import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'listening_stats_service.dart';
import 'local_music_service.dart';
import 'navidrome_service.dart';
import 'player_controller.dart';

/// Servicio de recomendaciones musicales personalizadas con descubrimiento externo.
///
/// Analiza los hábitos de escucha (reproducciones frecuentes, repeticiones, artistas favoritos)
/// y la biblioteca del usuario activo para sugerir canciones y artistas similares que
/// todavía NO posee en su colección.
class MusicRecommendationService extends ChangeNotifier {
  MusicRecommendationService({
    NavidromeService? nav,
    ListeningStatsService? stats,
    PlayerController? player,
    LocalMusicService? localMusic,
    http.Client? client,
  })  : _nav = nav,
        _stats = stats,
        _player = player,
        _localMusic = localMusic,
        _client = client ?? http.Client();

  static final MusicRecommendationService instance =
      MusicRecommendationService();

  NavidromeService? _nav;
  ListeningStatsService? _stats;
  PlayerController? _player;
  LocalMusicService? _localMusic;
  final http.Client _client;

  /// Caché en memoria de recomendaciones por cada usuario/ámbito (`userScope`).
  final Map<String, List<Track>> _recommendationsByUser = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final Map<String, Future<List<Track>>> _pendingFutures = {};

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Tiempo de vida de la caché antes de recalcular en segundo plano.
  static const _cacheDuration = Duration(minutes: 30);
  static const _requestTimeout = Duration(seconds: 6);

  /// Configura o actualiza las dependencias en tiempo de ejecución.
  void updateDependencies({
    NavidromeService? nav,
    ListeningStatsService? stats,
    PlayerController? player,
    LocalMusicService? localMusic,
  }) {
    if (nav != null) _nav = nav;
    if (stats != null) _stats = stats;
    if (player != null) _player = player;
    if (localMusic != null) _localMusic = localMusic;
  }

  /// Limpia la caché (útil en cambios de usuario o testing).
  void clearCache([String? userScope]) {
    if (userScope != null) {
      _recommendationsByUser.remove(userScope);
      _cacheTimestamps.remove(userScope);
      _pendingFutures.remove(userScope);
    } else {
      _recommendationsByUser.clear();
      _cacheTimestamps.clear();
      _pendingFutures.clear();
    }
    notifyListeners();
  }

  /// Obtiene recomendaciones para el usuario actual.
  ///
  /// Si [forceRefresh] es true, invalida la caché y recalcula de inmediato.
  Future<List<Track>> getRecommendations({
    NavidromeService? navOverride,
    ListeningStatsService? statsOverride,
    PlayerController? playerOverride,
    LocalMusicService? localMusicOverride,
    bool forceRefresh = false,
  }) async {
    final nav = navOverride ?? _nav;
    final stats = statsOverride ?? _stats;
    final player = playerOverride ?? _player;
    final localMusic = localMusicOverride ?? _localMusic;

    final userScope = nav?.userScope ?? nav?.serverScope ?? 'default_user';

    // Verificar caché válida
    if (!forceRefresh && _recommendationsByUser.containsKey(userScope)) {
      final timestamp = _cacheTimestamps[userScope];
      if (timestamp != null &&
          DateTime.now().difference(timestamp) < _cacheDuration) {
        return _recommendationsByUser[userScope]!;
      }
    }

    if (!forceRefresh && _pendingFutures.containsKey(userScope)) {
      return _pendingFutures[userScope]!;
    }

    final future = _computeRecommendations(
      userScope: userScope,
      nav: nav,
      stats: stats,
      player: player,
      localMusic: localMusic,
    ).then((result) {
      _recommendationsByUser[userScope] = result;
      _cacheTimestamps[userScope] = DateTime.now();
      notifyListeners();
      return result;
    }).whenComplete(() {
      _pendingFutures.remove(userScope);
    });

    _pendingFutures[userScope] = future;
    return future;
  }

  /// Invalida la caché y fuerza la recarga de recomendaciones.
  Future<List<Track>> refreshRecommendations({
    NavidromeService? navOverride,
    ListeningStatsService? statsOverride,
    PlayerController? playerOverride,
    LocalMusicService? localMusicOverride,
  }) =>
      getRecommendations(
        navOverride: navOverride,
        statsOverride: statsOverride,
        playerOverride: playerOverride,
        localMusicOverride: localMusicOverride,
        forceRefresh: true,
      );

  // ---------------------------------------------------------------------------
  // Lógica principal de análisis y recomendación
  // ---------------------------------------------------------------------------

  Future<List<Track>> _computeRecommendations({
    required String userScope,
    NavidromeService? nav,
    ListeningStatsService? stats,
    PlayerController? player,
    LocalMusicService? localMusic,
  }) async {
    _isLoading = true;
    try {
      // 1. ANÁLISIS DE LA BIBLIOTECA DEL USUARIO
      final libData = await _collectUserLibraryTracks(nav, localMusic, stats, player, userScope);
      final existingTrackKeys = <String>{};
      final existingTrackIds = <String>{};
      final existingArtistNames = <String>{};
      final existingAlbumTitles = <String>{};

      for (final t in libData.userCollection) {
        existingTrackIds.add(t.id);
        existingTrackKeys.add(createTrackKey(t.title, t.artist));
        existingArtistNames.add(normalizeArtist(t.artist));
        if (t.album.isNotEmpty) {
          existingAlbumTitles.add(normalizeTitle(t.album));
        }
      }

      // 2. ANÁLISIS DE HÁBITOS DE REPRODUCCIÓN
      final habitAnalysis = _analyzeListeningHabits(
        userScope: userScope,
        libraryTracks: libData.userCollection,
        stats: stats,
        player: player,
      );

      final isOffline = nav?.connected != true || (nav?.offlineMode ?? false);

      // 3. FUENTE DE DESCUBRIMIENTO
      List<Track> discoveredCandidates = [];
      if (!isOffline) {
        discoveredCandidates = await _fetchExternalDiscovery(
          favoriteArtists: habitAnalysis.favoriteArtists,
          favoriteGenres: habitAnalysis.favoriteGenres,
          existingArtistNames: existingArtistNames,
        );
      }

      // 4. EXCLUSIÓN DE MÚSICA EXISTENTE Y PRIORIZACIÓN
      final recommendations = _filterAndRankRecommendations(
        candidates: discoveredCandidates,
        existingTrackKeys: existingTrackKeys,
        existingTrackIds: existingTrackIds,
        existingArtistNames: existingArtistNames,
        favoriteArtists: habitAnalysis.favoriteArtists,
      );

      // 5. SI ESTÁ OFFLINE O NO SE ENCONTRARON RECOMENDACIONES EXTERNAS
      if (recommendations.isEmpty || isOffline) {
        final internalFallback = _getInternalLibraryDiscovery(
          catalogTracks: libData.catalog,
          existingKeys: {
            ...existingTrackKeys,
            ...recommendations.map((t) => createTrackKey(t.title, t.artist)),
          },
          existingIds: existingTrackIds,
          favoriteGenres: habitAnalysis.favoriteGenres,
          favoriteArtists: habitAnalysis.favoriteArtists,
        );
        recommendations.addAll(internalFallback);
      }

      return recommendations;
    } catch (e) {
      debugPrint('MusicRecommendationService error: $e');
      return [];
    } finally {
      _isLoading = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Normalización y detección de duplicados
  // ---------------------------------------------------------------------------

  /// Quita tildes y caracteres diacríticos para comparaciones fonéticas y textuales.
  static String removeDiacritics(String str) {
    const withDia =
        'ÀÁÂÃÄÅàáâãäåÒÓÔÕÕÖØòóôõöøÈÉÊËèéêëðÇçÐÌÍÎÏìíîïÙÚÛÜùúûüÑñŠšŸÿýŽž';
    const withoutDia =
        'AAAAAAaaaaaaOOOOOOOooooooEEEEeeeeeCcDIIIIiiiiUUUUuuuuNnSsYyyZz';
    var out = str;
    for (int i = 0; i < withDia.length; i++) {
      out = out.replaceAll(withDia[i], withoutDia[i]);
    }
    return out;
  }

  /// Limpia y normaliza el título eliminando sufijos como (Remastered), (Live),
  /// [feat. ...], versiones deluxe, puntuaciones, etc.
  static String normalizeTitle(String title) {
    var t = title.toLowerCase().trim();
    t = removeDiacritics(t);

    // Eliminar contenido entre paréntesis o corchetes que describa versión/remaster
    t = t.replaceAll(
      RegExp(
        r'\s*[\(\[](?:feat|ft|remaster|deluxe|live|version|edit|explicit|bonus|single|mix|mono|stereo|anniversary|edition|recording|radio)[^\)\]]*[\)\]]',
        caseSensitive: false,
      ),
      '',
    );

    // Eliminar sufijos con guion: " - Remastered 2020", " - Live", etc.
    t = t.replaceAll(
      RegExp(
        r'\s*[-–—]\s*(?:remaster|deluxe|live|version|edit|explicit|bonus|single|mix|mono|stereo|anniversary|edition|recording|radio).*$',
        caseSensitive: false,
      ),
      '',
    );

    // Eliminar colaboradores del título tipo "feat. X" o "ft. X"
    t = t.replaceAll(
      RegExp(r'\s*(?:feat\.|ft\.|featuring).*$', caseSensitive: false),
      '',
    );

    // Dejar solo letras, números y espacios
    t = t.replaceAll(RegExp(r'[^\w\s]'), '');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Normaliza el nombre del artista quedándose con el artista principal
  /// y eliminando colaboradores ("feat.", "&", ",", etc.).
  static String normalizeArtist(String artist) {
    var a = artist.toLowerCase().trim();
    a = removeDiacritics(a);
    a = a.replaceAll(
      RegExp(r'\s*(?:feat\.|ft\.|featuring|,|&|/|x\s).*$', caseSensitive: false),
      '',
    );
    a = a.replaceAll(RegExp(r'[^\w\s]'), '');
    return a.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Clave única compuesta para verificar duplicados e identificar canciones.
  static String createTrackKey(String title, String artist) {
    return '${normalizeTitle(title)}|${normalizeArtist(artist)}';
  }

  /// Comprueba si la canción ya existe en la biblioteca del usuario.
  static bool isAlreadyInLibrary(
    Track track,
    Set<String> existingKeys,
    Set<String> existingIds,
  ) {
    if (existingIds.contains(track.id)) return true;
    final key = createTrackKey(track.title, track.artist);
    if (existingKeys.contains(key)) return true;

    final normTitle = normalizeTitle(track.title);
    final normArtist = normalizeArtist(track.artist);
    if (normTitle.isEmpty) return true;

    // Comparación difusa: si alguna clave existente tiene el mismo título exacto
    // y comparte artista parcial
    for (final existing in existingKeys) {
      final parts = existing.split('|');
      if (parts.length == 2) {
        final exTitle = parts[0];
        final exArtist = parts[1];
        if (exTitle == normTitle) {
          if (exArtist == normArtist ||
              (exArtist.isNotEmpty && normArtist.contains(exArtist)) ||
              (normArtist.isNotEmpty && exArtist.contains(normArtist))) {
            return true;
          }
        }
      }
    }

    return false;
  }

  // ---------------------------------------------------------------------------
  // Recolección y hábitos
  // ---------------------------------------------------------------------------

  Future<_LibraryAnalysisData> _collectUserLibraryTracks(
    NavidromeService? nav,
    LocalMusicService? localMusic,
    ListeningStatsService? stats,
    PlayerController? player,
    String userScope,
  ) async {
    final userCollection = <Track>[];
    final catalog = <Track>[];
    final seen = <String>{};

    void addToUser(Iterable<Track>? items) {
      if (items == null) return;
      for (final t in items) {
        if (seen.add(t.id)) userCollection.add(t);
      }
    }

    if (nav != null) {
      try {
        final starred = await nav.getStarred();
        addToUser(starred);
      } catch (_) {}

      try {
        final recents = await nav.getRecentlyAddedTracks(limit: 50);
        addToUser(recents);
      } catch (_) {}

      try {
        final random = await nav.getRandomSongs(size: 60);
        if (random.isNotEmpty) {
          catalog.addAll(random);
        }
      } catch (_) {}
    }

    if (localMusic != null) {
      final scope = nav?.userScope ?? nav?.serverScope;
      if (scope != null) {
        addToUser(localMusic.downloadedTracks(scope));
      }
    }

    // Incluir canciones reproducidas en la colección del usuario para evitar recomendar lo ya escuchado
    if (player != null) {
      for (final item in player.mostPlayed) {
        if (item.type == MostPlayedItemType.track && item.track != null) {
          addToUser([item.track!]);
        }
      }
    }

    return _LibraryAnalysisData(
      userCollection: userCollection,
      catalog: catalog,
    );
  }

  _HabitAnalysis _analyzeListeningHabits({
    required String userScope,
    required List<Track> libraryTracks,
    ListeningStatsService? stats,
    PlayerController? player,
  }) {
    final artistScores = <String, int>{};
    final genreCounts = <String, int>{};

    // 1. Estadísticas duraderas de escucha
    if (stats != null) {
      final topArtists = stats.getTopArtists(limit: 15, serverScope: userScope);
      for (final a in topArtists) {
        final name = a.name.trim();
        if (name.isNotEmpty && name.toLowerCase() != 'desconocido') {
          artistScores[name] = (artistScores[name] ?? 0) + (a.playCount * 3);
        }
      }

      final topGenres = stats.getTopGenres(limit: 10, serverScope: userScope);
      for (final g in topGenres) {
        final name = g.name.trim();
        if (name.isNotEmpty && name.toLowerCase() != 'sin género') {
          genreCounts[name] = (genreCounts[name] ?? 0) + g.playCount;
        }
      }
    }

    // 2. Most played de PlayerController (repeticiones y frecuencia)
    if (player != null) {
      for (final item in player.mostPlayed) {
        if (item.type == MostPlayedItemType.track && item.track != null) {
          final t = item.track!;
          final artist = t.artist.trim();
          if (artist.isNotEmpty) {
            // Canciones repetidas frecuentemente tienen alto peso
            final weight = item.playCount > 3
                ? item.playCount * 4
                : item.playCount * 2;
            artistScores[artist] = (artistScores[artist] ?? 0) + weight;
          }
          if (t.genre != null && t.genre!.trim().isNotEmpty) {
            final g = t.genre!.trim();
            genreCounts[g] = (genreCounts[g] ?? 0) + item.playCount;
          }
        }
      }
    }

    // 3. Canciones con me gusta o de la biblioteca para usuarios nuevos
    for (final t in libraryTracks) {
      final a = t.artist.trim();
      if (a.isNotEmpty) {
        artistScores[a] = (artistScores[a] ?? 0) + 1;
      }
      if (t.genre != null && t.genre!.trim().isNotEmpty) {
        final g = t.genre!.trim();
        genreCounts[g] = (genreCounts[g] ?? 0) + 1;
      }
    }

    final sortedArtists = artistScores.keys.toList()
      ..sort((a, b) => artistScores[b]!.compareTo(artistScores[a]!));

    final sortedGenres = genreCounts.keys.toList()
      ..sort((a, b) => genreCounts[b]!.compareTo(genreCounts[a]!));

    return _HabitAnalysis(
      favoriteArtists: sortedArtists.take(8).toList(),
      favoriteGenres: sortedGenres.take(5).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Motor de Descubrimiento Externo (Deezer + iTunes)
  // ---------------------------------------------------------------------------

  Future<List<Track>> _fetchExternalDiscovery({
    required List<String> favoriteArtists,
    required List<String> favoriteGenres,
    required Set<String> existingArtistNames,
  }) async {
    final candidates = <Track>[];
    final seenCandidateKeys = <String>{};

    void addCandidate(Track track) {
      final key = createTrackKey(track.title, track.artist);
      if (seenCandidateKeys.add(key)) {
        candidates.add(track);
      }
    }

    // A) DESCUBRIMIENTO POR ARTISTAS SIMILARES Y RELACIONADOS
    for (final artist in favoriteArtists.take(4)) {
      try {
        final artistData = await _searchDeezerArtist(artist);
        if (artistData == null) continue;

        final artistId = artistData['id'];

        // 1. Obtener artistas relacionados (Deezer Related Artists)
        final relatedArtists = await _getDeezerRelatedArtists(artistId);

        // Priorizar artistas similares que el usuario aún NO tiene
        final newSimilarArtists = relatedArtists.where((r) {
          final norm = normalizeArtist(r['name'] as String? ?? '');
          return !existingArtistNames.contains(norm);
        }).toList();

        final targetSimilar = newSimilarArtists.isNotEmpty
            ? newSimilarArtists.take(3)
            : relatedArtists.take(2);

        for (final similar in targetSimilar) {
          final simId = similar['id'];
          final topTracks = await _getDeezerArtistTopTracks(simId);
          for (final t in topTracks.take(4)) {
            addCandidate(t);
          }
        }

        // 2. Obtener temas destacados del artista favorito (temas que no tenga)
        final ownTopTracks = await _getDeezerArtistTopTracks(artistId);
        for (final t in ownTopTracks.take(3)) {
          addCandidate(t);
        }
      } catch (_) {
        // Continuar con los siguientes artistas si falla alguno
      }
    }

    // B) DESCUBRIMIENTO POR GÉNEROS FAVORITOS
    for (final genre in favoriteGenres.take(2)) {
      try {
        final genreTracks = await _searchDeezerTracks(genre);
        for (final t in genreTracks.take(4)) {
          addCandidate(t);
        }
      } catch (_) {}
    }

    // C) FALLBACK ITUNES SI DEEZER NO ENTREGÓ SUFICIENTE
    if (candidates.length < 8 && favoriteArtists.isNotEmpty) {
      for (final artist in favoriteArtists.take(3)) {
        try {
          final itunesTracks = await _searchItunesTracks(artist);
          for (final t in itunesTracks.take(3)) {
            addCandidate(t);
          }
        } catch (_) {}
      }
    }

    return candidates;
  }

  Future<Map<String, dynamic>?> _searchDeezerArtist(String name) async {
    final uri = Uri.https('api.deezer.com', '/search/artist', {
      'q': name,
      'limit': '1',
    });
    final res = await _client.get(uri).timeout(_requestTimeout);
    if (res.statusCode != 200) return null;
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final data = json['data'] as List?;
    if (data == null || data.isEmpty) return null;
    return data.first as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> _getDeezerRelatedArtists(
      dynamic artistId) async {
    final uri = Uri.https('api.deezer.com', '/artist/$artistId/related', {
      'limit': '10',
    });
    final res = await _client.get(uri).timeout(_requestTimeout);
    if (res.statusCode != 200) return [];
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final data = json['data'] as List?;
    if (data == null) return [];
    return data.whereType<Map<String, dynamic>>().toList();
  }

  Future<List<Track>> _getDeezerArtistTopTracks(dynamic artistId) async {
    final uri = Uri.https('api.deezer.com', '/artist/$artistId/top', {
      'limit': '10',
    });
    final res = await _client.get(uri).timeout(_requestTimeout);
    if (res.statusCode != 200) return [];
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final data = json['data'] as List?;
    if (data == null) return [];
    return _parseDeezerTracks(data);
  }

  Future<List<Track>> _searchDeezerTracks(String query) async {
    final uri = Uri.https('api.deezer.com', '/search', {
      'q': query,
      'limit': '15',
    });
    final res = await _client.get(uri).timeout(_requestTimeout);
    if (res.statusCode != 200) return [];
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final data = json['data'] as List?;
    if (data == null) return [];
    return _parseDeezerTracks(data);
  }

  List<Track> _parseDeezerTracks(List list) {
    final results = <Track>[];
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final preview = item['preview'] as String?;
      final id = (preview != null && preview.isNotEmpty)
          ? preview
          : 'deezer_${item['id']}';
      final title = (item['title_short'] as String?) ??
          (item['title'] as String?) ??
          'Desconocido';
      final artistName = item['artist']?['name'] as String? ?? 'Desconocido';
      final albumName = item['album']?['title'] as String? ?? '';
      final coverUrl = (item['album']?['cover_big'] as String?) ??
          (item['album']?['cover_medium'] as String?) ??
          (item['album']?['cover'] as String?);
      final duration = (item['duration'] as num?)?.toString() ?? '180';

      results.add(Track(
        id: id,
        title: title,
        artist: artistName,
        album: albumName,
        duration: duration,
        albumArtUrl: coverUrl,
      ));
    }
    return results;
  }

  Future<List<Track>> _searchItunesTracks(String term) async {
    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': term,
      'entity': 'song',
      'limit': '15',
    });
    final res = await _client.get(uri).timeout(_requestTimeout);
    if (res.statusCode != 200) return [];
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final list = json['results'] as List?;
    if (list == null) return [];

    final results = <Track>[];
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final preview = item['previewUrl'] as String?;
      final id = (preview != null && preview.isNotEmpty)
          ? preview
          : 'itunes_${item['trackId']}';
      final title = item['trackName'] as String? ?? 'Desconocido';
      final artistName = item['artistName'] as String? ?? 'Desconocido';
      final albumName = item['collectionName'] as String? ?? '';
      var coverUrl = item['artworkUrl100'] as String?;
      if (coverUrl != null) {
        coverUrl = coverUrl.replaceFirst('100x100bb', '500x500bb');
      }
      final durationSec = (item['trackTimeMillis'] as num?) != null
          ? ((item['trackTimeMillis'] as num) / 1000).round().toString()
          : '180';

      results.add(Track(
        id: id,
        title: title,
        artist: artistName,
        album: albumName,
        duration: durationSec,
        albumArtUrl: coverUrl,
        genre: item['primaryGenreName'] as String?,
      ));
    }
    return results;
  }

  // ---------------------------------------------------------------------------
  // Filtrado, Deduplicación y Priorización
  // ---------------------------------------------------------------------------

  List<Track> _filterAndRankRecommendations({
    required List<Track> candidates,
    required Set<String> existingTrackKeys,
    required Set<String> existingTrackIds,
    required Set<String> existingArtistNames,
    required List<String> favoriteArtists,
  }) {
    final tier1NewArtists = <Track>[];
    final tier2KnownArtists = <Track>[];
    final artistTrackCounts = <String, int>{};

    for (final t in candidates) {
      // Regla estricta: NO recomendar canciones que el usuario ya tenga en su biblioteca
      if (isAlreadyInLibrary(t, existingTrackKeys, existingTrackIds)) {
        continue;
      }

      final normArtist = normalizeArtist(t.artist);
      final count = artistTrackCounts[normArtist] ?? 0;
      // Diversidad: máximo 2 canciones por artista en la lista de recomendaciones
      if (count >= 2) continue;

      artistTrackCounts[normArtist] = count + 1;

      // Priorizar artistas nuevos/similares que el usuario aún NO tiene en su colección
      if (!existingArtistNames.contains(normArtist)) {
        tier1NewArtists.add(t);
      } else {
        tier2KnownArtists.add(t);
      }
    }

    // Barajar ligeramente para evitar orden estático
    tier1NewArtists.shuffle(Random());
    tier2KnownArtists.shuffle(Random());

    final finalRecommendations = <Track>[
      ...tier1NewArtists,
      ...tier2KnownArtists,
    ];

    return finalRecommendations.take(15).toList();
  }

  // ---------------------------------------------------------------------------
  // Fallback interno cuando no hay conexión a servicios externos
  // ---------------------------------------------------------------------------

  List<Track> _getInternalLibraryDiscovery({
    required List<Track> catalogTracks,
    required Set<String> existingKeys,
    required Set<String> existingIds,
    required List<String> favoriteGenres,
    required List<String> favoriteArtists,
  }) {
    if (catalogTracks.isEmpty) return [];

    final unplayed = catalogTracks.where((t) {
      if (existingIds.contains(t.id)) return false;
      return !isAlreadyInLibrary(t, existingKeys, existingIds);
    }).toList();

    unplayed.shuffle(Random());
    return unplayed.take(10).toList();
  }
}

class _LibraryAnalysisData {
  final List<Track> userCollection;
  final List<Track> catalog;

  const _LibraryAnalysisData({
    required this.userCollection,
    required this.catalog,
  });
}

class _HabitAnalysis {
  final List<String> favoriteArtists;
  final List<String> favoriteGenres;

  const _HabitAnalysis({
    required this.favoriteArtists,
    required this.favoriteGenres,
  });
}
