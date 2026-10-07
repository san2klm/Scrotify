import '../utils/app_data_dir.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';

import '../models/jam_models.dart';
import '../models/server_profile.dart';
import 'offline_cache_service.dart';
import 'local_music_service.dart';
import 'offline_download_manager.dart';
import 'hifi/hifi_profiles.dart' show StreamQuality;
import 'replay_gain.dart';
import 'server_profiles_controller.dart';
import 'settings_controller.dart';

export 'replay_gain.dart';

class Track {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String duration;
  final String? albumArtUrl;
  final int playCount;
  final String? suffix;
  final String? artistId;
  final String? albumId;
  final String? genre;
  final DateTime? createdAt;
  final ReplayGainMetadata? replayGain;
  final int userRating;

  /// Identificadores/metadatos para emparejar la pista entre servidores
  /// distintos (Jam). Opcionales: OpenSubsonic los expone si están etiquetados.
  final String? mbid;
  final String? isrc;
  final int? trackNumber;

  /// Frecuencia (Hz) y profundidad (bits) del archivo original, si el servidor
  /// las informa (OpenSubsonic). El modo Bit-perfect las necesita.
  final int? samplingRate;
  final int? bitDepth;

  int get rating => userRating;

  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.albumArtUrl,
    this.playCount = 0,
    this.suffix,
    this.artistId,
    this.albumId,
    this.genre,
    this.createdAt,
    this.replayGain,
    this.userRating = 0,
    this.mbid,
    this.isrc,
    this.trackNumber,
    this.samplingRate,
    this.bitDepth,
  });

  Track copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? duration,
    String? albumArtUrl,
    int? playCount,
    String? suffix,
    String? artistId,
    String? albumId,
    String? genre,
    DateTime? createdAt,
    ReplayGainMetadata? replayGain,
    int? userRating,
    String? mbid,
    String? isrc,
    int? trackNumber,
    int? samplingRate,
    int? bitDepth,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      albumArtUrl: albumArtUrl ?? this.albumArtUrl,
      playCount: playCount ?? this.playCount,
      suffix: suffix ?? this.suffix,
      artistId: artistId ?? this.artistId,
      albumId: albumId ?? this.albumId,
      genre: genre ?? this.genre,
      createdAt: createdAt ?? this.createdAt,
      replayGain: replayGain ?? this.replayGain,
      userRating: userRating ?? this.userRating,
      mbid: mbid ?? this.mbid,
      isrc: isrc ?? this.isrc,
      trackNumber: trackNumber ?? this.trackNumber,
      samplingRate: samplingRate ?? this.samplingRate,
      bitDepth: bitDepth ?? this.bitDepth,
    );
  }

  factory Track.fromJson(Map<String, dynamic> json, {String? albumArtUrl}) {
    final rawDuration = json['duration'];
    final duration = rawDuration is num
        ? rawDuration.toString()
        : (rawDuration as String? ?? '');

    final coverArt = albumArtUrl ?? json['coverArt'] as String?;

    DateTime? createdAt;
    final rawCreated = json['created'] ?? json['createdAt'];
    if (rawCreated != null) {
      createdAt = DateTime.tryParse(rawCreated.toString());
    }

    ReplayGainMetadata? replayGain;
    final rawRg = json['replayGain'];
    if (rawRg is Map) {
      final parsed = ReplayGainMetadata.fromJson(rawRg.cast<String, dynamic>());
      if (!parsed.isEmpty) {
        replayGain = parsed;
      }
    } else if (json.containsKey('trackGain') ||
        json.containsKey('albumGain') ||
        json.containsKey('trackPeak') ||
        json.containsKey('albumPeak') ||
        json.containsKey('baseGain') ||
        json.containsKey('fallbackGain')) {
      final parsed = ReplayGainMetadata.fromJson(json);
      if (!parsed.isEmpty) {
        replayGain = parsed;
      }
    }

    final rating = (json['userRating'] as num?)?.toInt() ??
        (json['rating'] as num?)?.toInt() ??
        0;

    return Track(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? 'Unknown',
      artist: (json['artist'] as String?) ?? 'Unknown',
      album: (json['album'] as String?) ?? 'Unknown',
      duration: duration,
      albumArtUrl: coverArt,
      playCount: (json['playCount'] as num?)?.toInt() ?? 0,
      suffix: json['suffix'] as String?,
      artistId: json['artistId'] as String?,
      albumId: json['albumId'] as String?,
      genre: json['genre'] as String?,
      createdAt: createdAt,
      replayGain: replayGain,
      userRating: rating,
      mbid: (json['musicBrainzId'] ?? json['mbid']) as String?,
      isrc: _firstIsrc(json['isrc']),
      trackNumber: (json['track'] ?? json['trackNumber']) is num
          ? ((json['track'] ?? json['trackNumber']) as num).toInt()
          : null,
      samplingRate: (json['samplingRate'] as num?)?.toInt(),
      bitDepth: (json['bitDepth'] as num?)?.toInt(),
    );
  }

  /// OpenSubsonic devuelve `isrc` como lista; nuestro protocolo, como texto.
  static String? _firstIsrc(dynamic raw) {
    if (raw is String && raw.isNotEmpty) return raw;
    if (raw is List && raw.isNotEmpty && raw.first is String) {
      return raw.first as String;
    }
    return null;
  }
}

class Album {
  final String id;
  final String title;
  final String artist;
  final String? coverArtUrl;
  final int trackCount;
  final int year;

  Album({
    required this.id,
    required this.title,
    required this.artist,
    this.coverArtUrl,
    required this.trackCount,
    required this.year,
  });

  factory Album.fromJson(Map<String, dynamic> json, {String? coverArtUrl}) {
    return Album(
      id: (json['id'] as String?) ?? '',
      title:
          (json['name'] as String?) ?? (json['title'] as String?) ?? 'Unknown',
      artist: (json['artist'] as String?) ?? 'Unknown',
      coverArtUrl: coverArtUrl ?? json['coverArt'] as String?,
      trackCount: (json['songCount'] as num?)?.toInt() ??
          (json['trackCount'] as num?)?.toInt() ??
          0,
      year: (json['year'] as num?)?.toInt() ?? 0,
    );
  }
}

class Artist {
  final String id;
  final String name;
  final String? coverArtUrl;

  Artist({required this.id, required this.name, this.coverArtUrl});

  factory Artist.fromJson(Map<String, dynamic> json, {String? coverArtUrl}) {
    return Artist(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? 'Unknown',
      coverArtUrl: coverArtUrl ?? json['coverArt'] as String?,
    );
  }
}

class Playlist {
  final String id;
  final String name;
  final String? coverArtUrl;
  final int songCount;
  final int duration;
  final String? owner;
  final bool public;

  Playlist({
    required this.id,
    required this.name,
    this.coverArtUrl,
    required this.songCount,
    required this.duration,
    this.owner,
    this.public = false,
  });

  factory Playlist.fromJson(Map<String, dynamic> json, {String? coverArtUrl}) {
    return Playlist(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? 'Unknown',
      coverArtUrl: coverArtUrl ?? json['coverArt'] as String?,
      songCount: (json['songCount'] as num?)?.toInt() ?? 0,
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      owner: json['owner'] as String?,
      public: json['public'] == true,
    );
  }
}

/// La playlist ya existe aunque su portada no haya podido guardarse.
class PlaylistCoverUploadException implements Exception {
  final Playlist playlist;
  final Object cause;

  PlaylistCoverUploadException(this.playlist, this.cause);

  @override
  String toString() => 'La playlist se creó, pero la portada no se guardó. '
      '${cause.toString().replaceFirst('Exception: ', '')}';
}

class SearchResults {
  final List<Track> songs;
  final List<Album> albums;
  final List<Artist> artists;

  SearchResults({
    required this.songs,
    required this.albums,
    required this.artists,
  });

  bool get isEmpty => songs.isEmpty && albums.isEmpty && artists.isEmpty;
}

/// Registro de lo que un usuario está escuchando en el servidor Navidrome en tiempo real.
class NowPlayingEntry {
  final String username;
  final Track track;
  final int minutesAgo;
  final int? playerId;

  NowPlayingEntry({
    required this.username,
    required this.track,
    required this.minutesAgo,
    this.playerId,
  });

  factory NowPlayingEntry.fromJson(
      Map<String, dynamic> json, String? albumArtUrl) {
    return NowPlayingEntry(
      username: (json['username'] as String?) ?? 'Usuario',
      track: Track.fromJson(json, albumArtUrl: albumArtUrl),
      minutesAgo: (json['minutesAgo'] as num?)?.toInt() ?? 0,
      playerId: (json['playerId'] as num?)?.toInt(),
    );
  }
}

/// Mensaje en el chat comunitario del servidor Navidrome.
class ChatMessage {
  final String username;
  final DateTime time;
  final String message;

  ChatMessage({
    required this.username,
    required this.time,
    required this.message,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawTime = json['time'];
    DateTime time;
    if (rawTime is num) {
      time = DateTime.fromMillisecondsSinceEpoch(rawTime.toInt());
    } else if (rawTime is String) {
      final parsed = int.tryParse(rawTime);
      time = parsed != null
          ? DateTime.fromMillisecondsSinceEpoch(parsed)
          : (DateTime.tryParse(rawTime) ?? DateTime.now());
    } else {
      time = DateTime.now();
    }

    return ChatMessage(
      username: (json['username'] as String?) ?? 'Usuario',
      time: time,
      message: (json['message'] as String?) ?? '',
    );
  }
}

/// Línea de letra estructurada (OpenSubsonic).
class LyricLineData {
  final int startMs;
  final String text;

  const LyricLineData({required this.startMs, required this.text});
}

/// Bloque de letra estructurada devuelto por `getLyricsBySongId`.
class StructuredLyricBlock {
  final bool synced;
  final String lang;
  final List<LyricLineData> lines;

  const StructuredLyricBlock({
    required this.synced,
    required this.lang,
    required this.lines,
  });
}

class NavidromeService with ChangeNotifier {
  NavidromeService(
      {SettingsController? settings,
      http.Client? httpClient,
      ServerProfilesController? profilesController}) {
    _injectedClient = httpClient;
    _client = httpClient ?? http.Client();
    if (settings != null) {
      _settings = settings;
      _coverArtSize = settings.coverArtSize;
      settings.addListener(_syncFromSettings);
    }

    // Listen to profile changes for automatic reconnection
    if (profilesController != null) {
      _profilesController = profilesController;
      _profilesController!.addListener(_onActiveProfileChanged);
      // Load initial profile if exists
      // Wait until end of frame to avoid notifying during build
      Future.microtask(() => _loadInitialProfile());
    }

    loadLastSelectedGenre();
  }

  ServerProfilesController? _profilesController;

  void _onActiveProfileChanged() {
    // When active profile changes, reconnect with new credentials
    final activeProfile = _profilesController?.activeProfile;
    if (activeProfile != null &&
        (activeProfile.url != _url ||
            activeProfile.username != _user ||
            activeProfile.password != _pass)) {
      debugPrint(
          'Active profile changed, reconnecting to ${activeProfile.url} as ${activeProfile.username}');
      unawaited(_disconnectAndReconnect(activeProfile));
    } else if (activeProfile == null && (_connected || _offlineMode)) {
      // No active profile, disconnect
      debugPrint('No active profile, disconnecting');
      disconnect();
    }
  }

  void _loadInitialProfile() {
    final activeProfile = _profilesController?.activeProfile;
    if (activeProfile != null) {
      debugPrint('Loading initial profile: ${activeProfile.url}');
      connectByUrl(
              activeProfile.url, activeProfile.username, activeProfile.password)
          .catchError((Object _) {});
    }
  }

  Future<void> _disconnectAndReconnect(ServerProfile profile) async {
    if (_connected || _offlineMode) {
      disconnect();
    }
    try {
      await connectByUrl(profile.url, profile.username, profile.password);
    } catch (e) {
      if (isNetworkFailure(e)) {
        await openOfflineLibrary(
            profile.url, profile.username, profile.password);
      }
      debugPrint('No se pudo reconectar con el servidor.');
    }
  }

  String? _url;
  String? _user;
  String? _pass;
  LocalMusicService? localMusic;
  bool _offlineMode = false;
  bool get offlineMode => _offlineMode;
  bool _connected = false;
  http.Client? _injectedClient;
  late http.Client _client;

  int _sessionVersion = 0;
  int get sessionVersion => _sessionVersion;

  /// Clave única representativa de la sesión y usuario actual conectado.
  String? get currentSessionKey =>
      (_connected || _offlineMode) && _url != null && _user != null
          ? '$_url|$_user#$_sessionVersion'
          : null;

  /// Opaque cache scope segment identifying the current connected server.
  /// Never exposes URLs, usernames, passwords, or tokens.
  String? get serverScope {
    if (_url == null || _url!.isEmpty) return null;
    return OfflineCacheService.safeScopeSegment(_url!);
  }

  /// Retorna un segmento de ámbito seguro específico para el usuario y servidor actual.
  String? get userScope {
    if (_url == null || _url!.isEmpty) return null;
    final u = _user ?? '';
    if (u.isEmpty) return serverScope;
    return OfflineCacheService.safeScopeSegment('$_url|$u');
  }

  String _scopedName(String name) {
    final scope = userScope ?? serverScope;
    if (scope == null) return name;
    final parts = name.split('.');
    final ext = parts.length > 1 ? '.${parts.last}' : '';
    final base =
        parts.length > 1 ? parts.sublist(0, parts.length - 1).join('.') : name;
    return '${base}_$scope$ext';
  }

  Future<File?> _resolveScopedFile(String name) async {
    try {
      final dir = await getAppDataDirectory();
      final userScopedFile = File('${dir.path}/${_scopedName(name)}');
      if (await userScopedFile.exists()) {
        return userScopedFile;
      }
      final sScope = serverScope;
      if (sScope != null) {
        final parts = name.split('.');
        final ext = parts.length > 1 ? '.${parts.last}' : '';
        final base = parts.length > 1
            ? parts.sublist(0, parts.length - 1).join('.')
            : name;
        final legacyFile = File('${dir.path}/${base}_$sScope$ext');
        if (await legacyFile.exists()) {
          return legacyFile;
        }
      }
      return userScopedFile;
    } catch (_) {
      return null;
    }
  }

  SettingsController? _settings;

  // Tamaño de portadas y una versión que sube cada vez que cambia, para que
  // las pantallas puedan refrescar su contenido con la nueva resolución.
  int _coverArtSize = 600;
  int _coverArtVersion = 0;

  // Versión de playlists: sube tras una importación/creación/borrado para que
  // las pantallas vuelvan a cargar la lista de playlists.
  int _playlistVersion = 0;

  int get coverArtVersion => _coverArtVersion;
  int get playlistVersion => _playlistVersion;

  void bumpPlaylists() {
    _playlistVersion++;
    notifyListeners();
  }

  String? get serverUrl => _url;
  String? get username => _user;
  bool get connected => _connected;

  /// Sets connected state directly for isolated testing without credentials or network.
  @visibleForTesting
  void setConnectedForTesting({
    required String url,
    required String username,
    required String password,
    http.Client? client,
  }) {
    _url = url;
    _user = username;
    _pass = password;
    _resetCoverAuth();
    _connected = true;
    _offlineMode = false;
    _sessionVersion++;
    _starredIds.clear();
    _starredSongOrder.clear();
    _pinnedPlaylistIds.clear();
    _followedArtistIds.clear();
    _excludedArtistIds.clear();
    _artistCache.clear();
    _trackRatings.clear();
    _cachedGenres = null;
    if (client != null) {
      _injectedClient = client;
      _client = client;
    }
    notifyListeners();
  }

  /// Retorna las credenciales actuales si la sesión está conectada,
  /// útil para compartirlas con el teléfono mediante emparejamiento.
  ({String url, String username, String password})? get currentCredentials {
    if (!_connected || _url == null || _user == null || _pass == null) {
      return null;
    }
    return (url: _url!, username: _user!, password: _pass!);
  }

  void _syncFromSettings() {
    final size = _settings!.coverArtSize;
    if (size != _coverArtSize) {
      _coverArtSize = size;
      _coverArtVersion++;
      notifyListeners();
    }
  }

  String _randomSalt() {
    final rnd = Random.secure();
    return List.generate(16, (_) => rnd.nextInt(16).toRadixString(16)).join();
  }

  String _md5(String input) {
    return md5.convert(utf8.encode(input)).toString();
  }

  // Salt/token fijos durante la sesión: con un salt aleatorio por petición, la
  // misma carátula tenía una URL distinta cada vez y la caché de imágenes
  // (indexada por URL) nunca acertaba.
  String? _coverSalt;
  String? _coverToken;

  void _resetCoverAuth() {
    _coverSalt = null;
    _coverToken = null;
  }

  /// Los parámetros `salt`/`token` se mantienen por compatibilidad de firma;
  /// la URL usa credenciales estables de sesión.
  String? _coverArtUrl(Object? coverArtId, String salt, String token,
      {int? size}) {
    if (coverArtId == null) return null;
    _coverSalt ??= _randomSalt();
    _coverToken ??= _md5('$_pass$_coverSalt');
    return '$_url/rest/getCoverArt.view'
        '?u=${Uri.encodeQueryComponent(_user!)}'
        '&s=$_coverSalt&t=$_coverToken&v=1.16.1&c=Psysonic'
        '&id=${Uri.encodeQueryComponent(coverArtId.toString())}'
        '&size=${size ?? _coverArtSize}';
  }

  Future<void> connectByUrl(String url, String user, String pass) async {
    var processedUrl =
        url.endsWith('/') ? url.substring(0, url.length - 1) : url;

    if (!processedUrl.startsWith('http://') &&
        !processedUrl.startsWith('https://')) {
      processedUrl = 'https://$processedUrl';
    }

    _url = processedUrl;
    _user = user;
    _pass = pass;
    _resetCoverAuth();

    debugPrint('Connecting to $_url');

    _client = _injectedClient ?? http.Client();

    try {
      final salt = _randomSalt();
      final token = _md5('$pass$salt');

      final uri = Uri.parse('$_url/rest/ping.view').replace(queryParameters: {
        'u': user,
        's': salt,
        't': token,
        'v': '1.16.1',
        'c': 'Psysonic',
        'f': 'json',
      });

      final response =
          await _client.get(uri).timeout(const Duration(seconds: 8));

      debugPrint('Auth response status: ${response.statusCode}');

      if (response.statusCode != 200) {
        throw Exception('Server error: Status ${response.statusCode}. '
            'Check your Navidrome URL and make sure the API is accessible. '
            'Response: ${response.body.substring(0, min(50, response.body.length))}');
      }

      try {
        final data = jsonDecode(response.body);

        if (data['subsonic-response']['status'] == 'ok') {
          _connected = true;
          _offlineMode = false;
          _stopAutoReconnect();
          _sessionVersion++;
          _starredIds.clear();
          _starredSongOrder.clear();
          _pinnedPlaylistIds.clear();
          _followedArtistIds.clear();
          _excludedArtistIds.clear();
          _artistCache.clear();
          _trackRatings.clear();
          _cachedGenres = null;
          await _loadPins();
          await _loadStarredOrder();
          await loadLastSelectedGenre();
          notifyListeners();
        } else {
          throw Exception(
              'Authentication failed: ${data['subsonic-response']['error']['message']}');
        }
      } catch (e) {
        if (e.toString().contains('Unexpected character')) {
          throw Exception('Invalid response from server. '
              'The server may not be a Navidrome instance or the API endpoint is incorrect. '
              'Make sure you are using the correct Navidrome URL with /rest/ endpoints.');
        }
        rethrow;
      }
    } catch (e) {
      rethrow;
    }
  }

  static bool isNetworkFailure(Object error) =>
      error is SocketException ||
      error is TimeoutException ||
      error is http.ClientException;

  /// Solo restaura una cuenta guardada con audio disponible; no autentica contra el servidor.
  Future<bool> openOfflineLibrary(
      String url, String username, String password) async {
    final music = localMusic;
    if (music == null) return false;
    await music.initialize();
    var normalized = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'https://$normalized';
    }
    final scope = OfflineCacheService.safeScopeSegment(normalized);
    if (music.count(scope) == 0) return false;
    _url = normalized;
    _user = username;
    _pass = password;
    _connected = false;
    _offlineMode = true;
    _startAutoReconnect();
    _sessionVersion++;
    _resetCoverAuth();
    _starredIds.clear();
    _starredSongOrder.clear();
    _pinnedPlaylistIds.clear();
    _followedArtistIds.clear();
    _excludedArtistIds.clear();
    _artistCache.clear();
    _trackRatings.clear();
    _cachedGenres = null;
    await music.bindLegacyCollections(scope, userScope!);
    await _loadPins();
    await _loadStarredOrder();
    _starredIds
        .addAll(music.offlineLikes(scope, userScope!).map((track) => track.id));
    notifyListeners();
    return true;
  }

  Future<void> reconnect() async {
    if (_url == null || _user == null || _pass == null) return;
    await connectByUrl(_url!, _user!, _pass!);
  }

  Timer? _reconnectTimer;
  bool _autoReconnecting = false;

  /// Un fallo de red puntual no debe dejar la app en modo sin conexión para
  /// siempre: mientras esté offline se sondea el servidor y, en cuanto
  /// responde, se vuelve a conectar sin intervención del usuario.
  void _startAutoReconnect() {
    _reconnectTimer ??= Timer.periodic(
        const Duration(seconds: 15), (_) => unawaited(_tryAutoReconnect()));
  }

  void _stopAutoReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  Future<void> _tryAutoReconnect() async {
    if (!_offlineMode || _url == null || _user == null || _pass == null) {
      _stopAutoReconnect();
      return;
    }
    if (_autoReconnecting) return;
    _autoReconnecting = true;
    final session = currentSessionKey;
    try {
      final salt = _randomSalt();
      final uri = Uri.parse('$_url/rest/ping.view').replace(queryParameters: {
        'u': _user!,
        's': salt,
        't': _md5('$_pass$salt'),
        'v': '1.16.1',
        'c': 'Psysonic',
        'f': 'json',
      });
      final probe = _injectedClient ?? http.Client();
      try {
        final response =
            await probe.get(uri).timeout(const Duration(seconds: 6));
        if (response.statusCode != 200) return;
      } finally {
        if (_injectedClient == null) probe.close();
      }
      if (!_offlineMode || currentSessionKey != session) return;
      await reconnect();
      debugPrint('Conexión con el servidor restablecida automáticamente.');
    } catch (_) {
      // Sigue sin red: se reintenta en el próximo ciclo.
    } finally {
      _autoReconnecting = false;
    }
  }

  @override
  void dispose() {
    _stopAutoReconnect();
    super.dispose();
  }

  /// Conserva datos por cuenta y recurre a los archivos locales al perder la red.
  Future<T> _readLibrary<T>(Future<T> Function() fetch,
      T Function(LocalMusicService music, String scope, String user) fallback,
      {Future<void> Function(LocalMusicService music, String user, T data)?
          remember}) async {
    final music = localMusic;
    final scope = serverScope;
    final user = userScope;
    if (music == null || scope == null || user == null) return fetch();
    try {
      await music.initialize();
    } catch (_) {
      if (_connected && !_offlineMode) return fetch();
      rethrow;
    }
    await music.bindLegacyCollections(scope, user);
    if (!_connected || _offlineMode) return fallback(music, scope, user);
    final session = currentSessionKey;
    T data;
    try {
      data = await fetch().timeout(const Duration(seconds: 8));
    } catch (error) {
      if (currentSessionKey != session) rethrow;
      if (isNetworkFailure(error)) {
        _connected = false;
        _offlineMode = true;
        _startAutoReconnect();
        notifyListeners();
      }
      return fallback(music, scope, user);
    }
    // Una respuesta atrasada no debe guardarse bajo una cuenta nueva.
    if (currentSessionKey == session && remember != null) {
      try {
        await remember(music, user, data);
      } catch (_) {
        debugPrint('No se pudo guardar la biblioteca sin conexión.');
      }
    }
    if (currentSessionKey == session) {
      Future<void> cacheArtwork() async {
        if (data is List<Track>) {
          await music.cacheDownloadedArtwork(scope, data);
        } else if (data is List<Playlist>) {
          for (final playlist in data) {
            await music.cachePlaylistArtwork(scope, playlist);
          }
        } else if (data is Playlist) {
          await music.cachePlaylistArtwork(scope, data);
        }
      }

      // Las portadas se completan sin bloquear la apertura de la biblioteca.
      unawaited(cacheArtwork().catchError((Object _) {}));
    }
    return data;
  }

  Future<List<dynamic>> getMusicFolders() async {
    if (!_connected) throw Exception('Not connected');
    final salt = _randomSalt();
    final token = _md5('$_pass$salt');

    final uri =
        Uri.parse('$_url/rest/getMusicFolders.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
    });

    final response = await _client.get(uri);
    final data = jsonDecode(response.body);
    final folders = data['subsonic-response']['musicFolder'] as List?;
    return folders ?? [];
  }

  Future<List<dynamic>> getArtists() async {
    if (!_connected) throw Exception('Not connected');
    final salt = _randomSalt();
    final token = _md5('$_pass$salt');

    final uri =
        Uri.parse('$_url/rest/getArtists.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
    });

    final response = await _client.get(uri);
    final data = jsonDecode(response.body);

    dynamic indexes = data['subsonic-response']['artists']?['index'];

    if (indexes == null) {
      return [];
    }

    // getArtists devuelve el id de coverArt, no una URL. Normalizarlo aquí
    // para que los consumidores de este método puedan cargar la imagen igual
    // que los álbumes y resultados de búsqueda.
    final List<dynamic> allArtists = [];
    for (final index in _asList(indexes)) {
      if (index is! Map) continue;

      for (final rawArtist in _asList(index['artist'])) {
        if (rawArtist is! Map) continue;

        final artist = Map<String, dynamic>.from(rawArtist);
        artist['coverArt'] = _coverArtUrl(artist['coverArt'], salt, token);
        allArtists.add(artist);
        try {
          final model = Artist.fromJson(artist,
              coverArtUrl: artist['coverArt'] as String?);
          _artistCache[model.id] = model;
        } catch (err) {
          debugPrint('navidrome_service:688 ignorado: $err');
        }
      }
    }

    debugPrint('getArtists result count: ${allArtists.length}');
    return allArtists;
  }

  Future<List<dynamic>> getIndexes() async {
    if (!_connected) throw Exception('Not connected');
    final salt = _randomSalt();
    final token = _md5('$_pass$salt');

    final uri =
        Uri.parse('$_url/rest/getIndexes.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
    });

    final response = await _client.get(uri);
    final data = jsonDecode(response.body);

    dynamic indexes = data['subsonic-response']['indexes'];

    if (indexes == null) {
      return [];
    }

    if (indexes is Map && indexes.containsKey('index')) {
      final list = indexes['index'] as List?;
      return list ?? [];
    }

    if (indexes is List) {
      return indexes;
    }

    debugPrint('getIndexes unknown format: $indexes');
    return [];
  }

  (String, String) _auth() {
    final salt = _randomSalt();
    return (salt, _md5('$_pass$salt'));
  }

  /// Una canción por ID (`getSong.view`); `null` si no existe en este servidor.
  Future<Track?> getSong(String id) async {
    if (!_connected) throw Exception('Not connected');
    final (salt, token) = _auth();
    final uri = Uri.parse('$_url/rest/getSong.view').replace(queryParameters: {
      'id': id,
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
    });
    final response = await _client.get(uri);
    final resp = jsonDecode(response.body)['subsonic-response'];
    final song = resp?['song'];
    if (resp?['status'] == 'failed' || song is! Map<String, dynamic>) {
      return null;
    }
    return Track.fromJson(song,
        albumArtUrl: _coverArtUrl(song['coverArt'], salt, token));
  }

  Future<SearchResults> search(String query) async {
    if (!_connected) throw Exception('Not connected');
    final (salt, token) = _auth();

    final params = <String, String>{
      'query': query,
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
      'songCount': '100',
      'albumCount': '24',
      'artistCount': '24',
    };
    final uri =
        Uri.parse('$_url/rest/search3.view').replace(queryParameters: params);

    final response = await _client.get(uri);
    final data = jsonDecode(response.body);
    final result =
        data['subsonic-response']?['searchResult3'] as Map<String, dynamic>?;
    if (result == null) {
      return SearchResults(songs: [], albums: [], artists: []);
    }

    Track mapSong(dynamic j) => Track.fromJson(
          j as Map<String, dynamic>,
          albumArtUrl: _coverArtUrl(j['coverArt'], salt, token),
        );
    Album mapAlbum(dynamic j) => Album.fromJson(
          j as Map<String, dynamic>,
          coverArtUrl: _coverArtUrl(j['coverArt'], salt, token),
        );
    Artist mapArtist(dynamic j) => Artist.fromJson(
          j as Map<String, dynamic>,
          coverArtUrl: _coverArtUrl(j['coverArt'], salt, token),
        );

    return SearchResults(
      songs: _asList(result['song']).map(mapSong).toList(),
      albums: _asList(result['album']).map(mapAlbum).toList(),
      artists: _asList(result['artist']).map(mapArtist).toList(),
    );
  }

  static List<dynamic> _asList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value;
    return [value];
  }

  // ---------------------------------------------------------------------------
  // Playlists
  // ---------------------------------------------------------------------------
  Future<List<Playlist>> getPlaylists() => _readLibrary(_fetchPlaylists,
      (music, scope, user) => music.offlinePlaylists(scope, user),
      remember: (music, user, data) => music.rememberPlaylists(user, data));

  Future<List<Playlist>> _fetchPlaylists() async {
    if (!_connected) throw Exception('Not connected');
    final (salt, token) = _auth();

    final uri =
        Uri.parse('$_url/rest/getPlaylists.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
    });

    final response = await _client.get(uri);
    final body = _playlistResponse(response);
    final list = body['playlists']?['playlist'] as List?;

    if (list == null) return [];

    final playlists = list
        .map((j) => Playlist.fromJson(j as Map<String, dynamic>,
            coverArtUrl: _coverArtUrl(j['coverArt'], salt, token)))
        .toList();

    // Filtramos las playlists para mostrar solo las creadas por el usuario actual.
    // Si 'owner' no viene en la API (es nulo), por precaución la mostramos.
    final currentUser = _user?.toLowerCase() ?? '';
    return playlists.where((p) {
      if (p.owner == null || p.owner!.isEmpty) return true;
      return p.owner?.toLowerCase() == currentUser;
    }).toList();
  }

  /// Crea primero la playlist mediante Subsonic y sube la portada por la API
  /// nativa de Navidrome, que es la que admite imágenes de playlists.
  Future<Playlist?> createPlaylist(
    String name, {
    List<int>? coverBytes,
    String? coverFileName,
  }) async {
    if (!_connected) throw Exception('Not connected');
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'El nombre es obligatorio.');
    }
    if (coverBytes != null) _playlistCoverType(coverBytes);
    final (salt, token) = _auth();
    final uri =
        Uri.parse('$_url/rest/createPlaylist.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
      'name': cleanName,
    });
    final data = _playlistResponse(await _client.get(uri));
    final p = data['playlist'] as Map<String, dynamic>?;
    if (p == null || (p['id'] as String? ?? '').isEmpty) {
      throw Exception('El servidor no devolvió la playlist creada.');
    }
    final playlist = Playlist.fromJson(p,
        coverArtUrl: _coverArtUrl(p['coverArt'], salt, token));
    if (coverBytes == null) return playlist;
    try {
      return await uploadPlaylistCover(playlist.id, coverBytes,
          fileName: coverFileName);
    } catch (e) {
      throw PlaylistCoverUploadException(playlist, e);
    }
  }

  Map<String, dynamic> _playlistResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('No se pudo actualizar o cargar la playlist '
          '(HTTP ${response.statusCode}).');
    }
    final data = jsonDecode(response.body)['subsonic-response'];
    if (data is! Map<String, dynamic>) {
      throw Exception(
          'El servidor devolvió una respuesta de playlist inválida.');
    }
    if (data['status'] != 'ok') {
      throw Exception(data['error']?['message'] ??
          'El servidor rechazó la operación de playlist.');
    }
    return data;
  }

  MediaType _playlistCoverType(List<int> bytes) {
    if (bytes.length > 10 * 1024 * 1024) {
      throw ArgumentError('La portada supera el máximo de 10 MB.');
    }
    bool startsWith(List<int> signature) =>
        bytes.length >= signature.length &&
        List.generate(signature.length, (i) => bytes[i] == signature[i])
            .every((match) => match);
    if (startsWith([137, 80, 78, 71, 13, 10, 26, 10])) {
      return MediaType('image', 'png');
    }
    if (startsWith([255, 216, 255])) return MediaType('image', 'jpeg');
    if (bytes.length >= 12 &&
        startsWith([82, 73, 70, 70]) &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return MediaType('image', 'webp');
    }
    throw ArgumentError('Selecciona una imagen PNG, JPG o WebP válida.');
  }

  Future<Playlist> uploadPlaylistCover(String playlistId, List<int> bytes,
      {String? fileName}) async {
    if (!_connected) throw Exception('Not connected');
    final type = _playlistCoverType(bytes);
    final login = await _client.post(
      Uri.parse('$_url/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': _user, 'password': _pass}),
    );
    if (login.statusCode != 200) {
      throw Exception('No se pudo autorizar la carga de portada '
          '(HTTP ${login.statusCode}).');
    }
    final nativeToken = jsonDecode(login.body)['token'];
    if (nativeToken is! String || nativeToken.isEmpty) {
      throw Exception('El servidor no permite cargar portadas desde esta app.');
    }
    // Mismo endpoint y campo que la interfaz web de Navidrome. Subsonic
    // createPlaylist no admite el antiguo multipart "coverArt".
    final request = http.MultipartRequest(
        'POST',
        Uri.parse(
            '$_url/api/playlist/${Uri.encodeComponent(playlistId)}/image'))
      ..headers['X-ND-Authorization'] = 'Bearer $nativeToken'
      ..files.add(http.MultipartFile.fromBytes('image', bytes,
          filename: fileName ?? 'playlist-cover.${type.subtype}',
          contentType: type));
    final response =
        await http.Response.fromStream(await _client.send(request));
    if (response.statusCode == 404 || response.statusCode == 405) {
      throw Exception('Esta versión de Navidrome no admite cargar portadas.');
    }
    if (response.statusCode == 403) {
      throw Exception('El servidor no permite cambiar esta portada. '
          'Comprueba los permisos de la playlist y de carga de imágenes.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('No se pudo guardar la portada '
          '(HTTP ${response.statusCode}).');
    }
    if (jsonDecode(response.body)['status'] != 'ok') {
      throw Exception('El servidor no confirmó la carga de la portada.');
    }
    final updated = await getPlaylist(playlistId);
    if (updated == null) {
      throw Exception('No se pudo recargar la playlist después de la portada.');
    }
    return updated;
  }

  Future<void> updatePlaylist({
    required String playlistId,
    String? name,
    List<String>? songIdsToAdd,
    List<int>? songIndexesToRemove,
  }) async {
    if (!_connected) throw Exception('Not connected');
    final (salt, token) = _auth();

    // Subsonic espera `songIdToAdd` (y `songIndexToRemove`) REPETIDOS en la
    // query string, uno por canción. Un Map no permite claves duplicadas, así
    // que la URL se construye manualmente.
    final buffer = StringBuffer('$_url/rest/updatePlaylist.view');
    buffer.write('?u=${Uri.encodeQueryComponent(_user!)}');
    buffer.write('&s=$salt&t=$token&v=1.16.1&c=Psysonic&f=json');
    buffer.write('&playlistId=${Uri.encodeQueryComponent(playlistId)}');
    if (name != null && name.isNotEmpty) {
      buffer.write('&name=${Uri.encodeQueryComponent(name)}');
    }
    for (final id in songIdsToAdd ?? const <String>[]) {
      buffer.write('&songIdToAdd=${Uri.encodeQueryComponent(id)}');
    }
    for (final index in songIndexesToRemove ?? const <int>[]) {
      buffer.write('&songIndexToRemove=$index');
    }

    _playlistResponse(await _client.get(Uri.parse(buffer.toString())));
    bumpPlaylists();
  }

  /// Reemplaza el contenido de una playlist en el orden indicado.
  ///
  /// `createPlaylist` con el ID de una lista existente es la operación
  /// Subsonic destinada a actualizarla por completo. Así el orden se conserva
  /// también con temas repetidos, sin depender de cómo el servidor procese
  /// índices eliminados y canciones añadidas en una misma petición.
  Future<void> reorderPlaylistTracks({
    required String playlistId,
    required List<String> orderedSongIds,
  }) async {
    if (orderedSongIds.length < 2) return;
    if (!_connected) throw Exception('Not connected');
    final (salt, token) = _auth();
    final buffer = StringBuffer('$_url/rest/createPlaylist.view');
    buffer.write('?u=${Uri.encodeQueryComponent(_user!)}');
    buffer.write('&s=$salt&t=$token&v=1.16.1&c=Psysonic&f=json');
    buffer.write('&playlistId=${Uri.encodeQueryComponent(playlistId)}');
    for (final id in orderedSongIds) {
      buffer.write('&songId=${Uri.encodeQueryComponent(id)}');
    }
    _playlistResponse(await _client.get(Uri.parse(buffer.toString())));
    bumpPlaylists();
  }

  Future<void> deletePlaylist(String playlistId) async {
    if (!_connected) throw Exception('Not connected');
    final (salt, token) = _auth();
    final uri =
        Uri.parse('$_url/rest/deletePlaylist.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
      'id': playlistId,
    });
    await _client.get(uri);
  }

  Future<Playlist?> getPlaylist(String playlistId) => _readLibrary(
      () => _fetchPlaylist(playlistId),
      (music, scope, user) => music
          .offlinePlaylists(scope, user)
          .where((playlist) => playlist.id == playlistId)
          .firstOrNull,
      remember: (music, user, data) =>
          data == null ? Future.value() : music.rememberPlaylist(user, data));

  Future<Playlist?> _fetchPlaylist(String playlistId) async {
    if (!_connected) throw Exception('Not connected');
    final (salt, token) = _auth();
    final uri =
        Uri.parse('$_url/rest/getPlaylist.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
      'id': playlistId,
    });
    final response = await _client.get(uri);
    final data = _playlistResponse(response);
    final p = data['playlist'];
    if (p == null) return null;
    return Playlist.fromJson(p as Map<String, dynamic>,
        coverArtUrl: _coverArtUrl(p['coverArt'], salt, token));
  }

  Future<List<Track>> getPlaylistTracks(String playlistId) => _readLibrary(
      () => _fetchPlaylistTracks(playlistId),
      (music, scope, user) =>
          music.offlinePlaylistTracks(scope, user, playlistId),
      remember: (music, user, data) =>
          music.rememberPlaylistTracks(user, playlistId, data));

  Future<List<Track>> _fetchPlaylistTracks(String playlistId) async {
    if (!_connected) throw Exception('Not connected');
    final (salt, token) = _auth();
    final uri =
        Uri.parse('$_url/rest/getPlaylist.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
      'id': playlistId,
    });
    final response = await _client.get(uri);
    final data = _playlistResponse(response);
    final entries = data['playlist']?['entry'] as List?;
    if (entries == null) return [];
    return entries
        .map((j) => Track.fromJson(j as Map<String, dynamic>,
            albumArtUrl: _coverArtUrl(j['coverArt'], salt, token)))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Favoritos (star / unstar)
  // ---------------------------------------------------------------------------
  Future<void> star(String id, {String? albumId, String? artistId}) async {
    if (!_connected) throw Exception('Not connected');
    await _setStar(id: id, albumId: albumId, artistId: artistId, star: true);
  }

  Future<void> unstar(String id, {String? albumId, String? artistId}) async {
    if (!_connected) throw Exception('Not connected');
    await _setStar(id: id, albumId: albumId, artistId: artistId, star: false);
  }

  Future<void> _setStar({
    required String id,
    String? albumId,
    String? artistId,
    required bool star,
  }) async {
    final (salt, token) = _auth();
    final endpoint = star ? 'star.view' : 'unstar.view';
    final params = <String, String>{
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
    };
    if (id.isNotEmpty) params['id'] = id;
    if (albumId != null) params['albumId'] = albumId;
    if (artistId != null) params['artistId'] = artistId;

    final uri =
        Uri.parse('$_url/rest/$endpoint').replace(queryParameters: params);
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed request (HTTP ${response.statusCode})');
    }
  }

  Future<List<Track>> getStarred() => _readLibrary(_fetchStarred,
      (music, scope, user) => _offlineStarred(music, scope, user),
      remember: (music, user, data) => music.rememberLikes(user, data));

  Future<List<Track>> _fetchStarred() async {
    if (!_connected) throw Exception('Not connected');
    final (salt, token) = _auth();
    final uri =
        Uri.parse('$_url/rest/getStarred2.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
    });
    final response = await _client.get(uri);
    final body = _playlistResponse(response);
    final songs = body['starred2']?['song'] as List?;
    if (songs == null) return [];
    final tracks = songs
        .map((j) => Track.fromJson(j as Map<String, dynamic>,
            albumArtUrl: _coverArtUrl(j['coverArt'], salt, token)))
        .toList();
    _starredIds
      ..clear()
      ..addAll(tracks.map((t) => t.id));
    return _applyStarredOrder(tracks);
  }

  List<Track> _offlineStarred(
      LocalMusicService music, String scope, String user) {
    final tracks = music.offlineLikes(scope, user);
    _starredIds
      ..clear()
      ..addAll(tracks.map((track) => track.id));
    return _applyStarredOrder(tracks);
  }

  final Set<String> _starredIds = {};
  final List<String> _starredSongOrder = [];

  bool isStarred(String id) => _starredIds.contains(id);

  /// Conserva el orden manual de "Me gustas" en este dispositivo. El
  /// protocolo Subsonic sólo expone favoritos, no un orden de favoritos que se
  /// pueda modificar en el servidor.
  void reorderStarredTracks(List<Track> tracks) {
    _starredSongOrder
      ..clear()
      ..addAll(tracks.map((track) => track.id));
    notifyListeners();
    _saveStarredOrder();
  }

  List<Track> _applyStarredOrder(List<Track> tracks) {
    var changed = false;
    final activeIds = tracks.map((track) => track.id).toSet();
    final originalLength = _starredSongOrder.length;
    _starredSongOrder.removeWhere((id) => !activeIds.contains(id));
    changed = _starredSongOrder.length != originalLength;
    for (final track in tracks) {
      if (!_starredSongOrder.contains(track.id)) {
        _starredSongOrder.add(track.id);
        changed = true;
      }
    }
    if (changed) _saveStarredOrder();

    final positions = <String, int>{
      for (var index = 0; index < _starredSongOrder.length; index++)
        _starredSongOrder[index]: index,
    };
    return [...tracks]..sort((a, b) => (positions[a.id] ?? tracks.length)
        .compareTo(positions[b.id] ?? tracks.length));
  }

  Future<void> _loadStarredOrder() async {
    try {
      final file = await _resolveScopedFile("starred_track_order.json");
      if (file != null && await file.exists()) {
        final content = await file.readAsString();
        final list = jsonDecode(content) as List;
        _starredSongOrder
          ..clear()
          ..addAll(list.cast<String>());
      }
    } catch (_) {
      // El orden manual es una preferencia local; no bloquea los favoritos.
    }
  }

  Future<void> _saveStarredOrder() async {
    try {
      final dir = await getAppDataDirectory();
      final file =
          File('${dir.path}/${_scopedName("starred_track_order.json")}');
      await file.writeAsString(jsonEncode(_starredSongOrder));
    } catch (_) {
      // El cambio ya está aplicado en memoria aunque no pueda persistirse.
    }
  }

  // ---------------------------------------------------------------------------
  // Fijar (pin) playlists, artistas seguidos y excluidos
  // ---------------------------------------------------------------------------
  final Set<String> _pinnedPlaylistIds = {};
  final Set<String> _followedArtistIds = {};
  final Set<String> _excludedArtistIds = {};
  final Map<String, Artist> _artistCache = {};

  Artist? getCachedArtist(String id) => _artistCache[id];

  void cacheArtist(Artist artist) {
    _artistCache[artist.id] = artist;
  }

  bool isPinnedPlaylist(String id) => _pinnedPlaylistIds.contains(id);
  bool isFollowingArtist(String id) => _followedArtistIds.contains(id);
  bool isArtistExcluded(String id) => _excludedArtistIds.contains(id);

  List<String> get pinnedPlaylistIds => _pinnedPlaylistIds.toList()..sort();
  List<String> get followedArtistIds => _followedArtistIds.toList();

  void togglePinPlaylist(String id) {
    if (_pinnedPlaylistIds.contains(id)) {
      _pinnedPlaylistIds.remove(id);
    } else {
      _pinnedPlaylistIds.add(id);
    }
    notifyListeners();
    _savePins();
  }

  void toggleFollowArtist(String id) {
    if (_followedArtistIds.contains(id)) {
      _followedArtistIds.remove(id);
    } else {
      _followedArtistIds.add(id);
    }
    notifyListeners();
    _saveFollowedArtists();
  }

  void toggleExcludeArtist(String id) {
    if (_excludedArtistIds.contains(id)) {
      _excludedArtistIds.remove(id);
    } else {
      _excludedArtistIds.add(id);
    }
    notifyListeners();
    _saveExcludedArtists();
  }

  Future<void> _loadPins() async {
    try {
      // Load Pins
      final pinFile = await _resolveScopedFile("pinned_playlists.json");
      if (pinFile != null && await pinFile.exists()) {
        final content = await pinFile.readAsString();
        final list = jsonDecode(content) as List;
        _pinnedPlaylistIds
          ..clear()
          ..addAll(list.cast<String>());
      }

      // Load Followed
      final followFile = await _resolveScopedFile("followed_artists.json");
      if (followFile != null && await followFile.exists()) {
        final content = await followFile.readAsString();
        final list = jsonDecode(content) as List;
        _followedArtistIds
          ..clear()
          ..addAll(list.cast<String>());
      }

      // Load Excluded
      final excludeFile = await _resolveScopedFile("excluded_artists.json");
      if (excludeFile != null && await excludeFile.exists()) {
        final content = await excludeFile.readAsString();
        final list = jsonDecode(content) as List;
        _excludedArtistIds
          ..clear()
          ..addAll(list.cast<String>());
      }

      // Load Ratings
      await _loadTrackRatings();
    } catch (err) {
      debugPrint('navidrome_service:1284 ignorado: $err');
    }
  }

  Future<void> _savePins() async {
    try {
      final dir = await getAppDataDirectory();
      final file = File('${dir.path}/${_scopedName("pinned_playlists.json")}');
      await file.writeAsString(jsonEncode(_pinnedPlaylistIds.toList()));
    } catch (err) {
      debugPrint('navidrome_service:1292 ignorado: $err');
    }
  }

  Future<void> _saveFollowedArtists() async {
    try {
      final dir = await getAppDataDirectory();
      final file = File('${dir.path}/${_scopedName("followed_artists.json")}');
      await file.writeAsString(jsonEncode(_followedArtistIds.toList()));
    } catch (err) {
      debugPrint('navidrome_service:1300 ignorado: $err');
    }
  }

  Future<void> _saveExcludedArtists() async {
    try {
      final dir = await getAppDataDirectory();
      final file = File('${dir.path}/${_scopedName("excluded_artists.json")}');
      await file.writeAsString(jsonEncode(_excludedArtistIds.toList()));
    } catch (err) {
      debugPrint('navidrome_service:1308 ignorado: $err');
    }
  }

  // ---------------------------------------------------------------------------
  // Rating 1-5 estrellas (Fase 8)
  // ---------------------------------------------------------------------------
  final Map<String, int> _trackRatings = {};

  /// Devuelve la puntuación en estrellas (0 a 5) de una canción.
  int getTrackRating(String trackId) => _trackRatings[trackId] ?? 0;

  /// Establece o limpia la puntuación de una canción en Subsonic API (setRating.view).
  /// Si [rating] es 0, quita la puntuación. Los valores se restringen entre 0 y 5.
  Future<void> setRating(String trackId, int rating) async {
    final clampedRating = rating.clamp(0, 5);
    if (clampedRating == 0) {
      _trackRatings.remove(trackId);
    } else {
      _trackRatings[trackId] = clampedRating;
    }
    notifyListeners();
    unawaited(_saveTrackRatings());

    if (!_connected) return;
    try {
      final (salt, token) = _auth();
      final uri =
          Uri.parse('$_url/rest/setRating.view').replace(queryParameters: {
        'u': _user!,
        's': salt,
        't': token,
        'v': '1.16.1',
        'c': 'Psysonic',
        'f': 'json',
        'id': trackId,
        'rating': clampedRating.toString(),
      });
      await _client.get(uri);
    } catch (e) {
      debugPrint('NavidromeService.setRating error: $e');
    }
  }

  /// Ordena una lista de pistas por calificación descendente (5 estrellas primero).
  List<Track> sortByRating(List<Track> tracks) {
    final sorted = List<Track>.from(tracks);
    sorted.sort((a, b) {
      final ratingA =
          getTrackRating(a.id) != 0 ? getTrackRating(a.id) : a.userRating;
      final ratingB =
          getTrackRating(b.id) != 0 ? getTrackRating(b.id) : b.userRating;
      return ratingB.compareTo(ratingA);
    });
    return sorted;
  }

  Future<void> _loadTrackRatings() async {
    try {
      final file = await _resolveScopedFile("track_ratings.json");
      if (file != null && await file.exists()) {
        final content = await file.readAsString();
        final map = jsonDecode(content) as Map<String, dynamic>;
        _trackRatings.clear();
        map.forEach((k, v) {
          if (v is num) _trackRatings[k] = v.toInt();
        });
      }
    } catch (err) {
      debugPrint('navidrome_service:1373 ignorado: $err');
    }
  }

  Future<void> _saveTrackRatings() async {
    try {
      final dir = await getAppDataDirectory();
      final file = File('${dir.path}/${_scopedName("track_ratings.json")}');
      await file.writeAsString(jsonEncode(_trackRatings));
    } catch (err) {
      debugPrint('navidrome_service:1381 ignorado: $err');
    }
  }

  Future<void> toggleStar(Track track) async {
    final wasStarred = _starredIds.contains(track.id);
    final previousOrderIndex = _starredSongOrder.indexOf(track.id);
    // Actualización optimista: reflejamos el cambio de inmediato para que la
    // UI no espere al round-trip de red, y revertimos si algo falla.
    if (wasStarred) {
      _starredIds.remove(track.id);
      _starredSongOrder.remove(track.id);
    } else {
      _starredIds.add(track.id);
      _starredSongOrder.add(track.id);
    }
    notifyListeners();
    _saveStarredOrder();

    try {
      if (wasStarred) {
        await unstar(track.id);
      } else {
        await star(track.id);
      }
    } catch (_) {
      if (wasStarred) {
        _starredIds.add(track.id);
        _starredSongOrder.insert(
          previousOrderIndex < 0
              ? _starredSongOrder.length
              : previousOrderIndex,
          track.id,
        );
      } else {
        _starredIds.remove(track.id);
        _starredSongOrder.remove(track.id);
      }
      notifyListeners();
      _saveStarredOrder();
    }
  }

  /// Total exacto reportado por el servidor, independiente de la paginación.
  Future<int?> getServerSongCount() async {
    if (!_connected) return null;
    final salt = _randomSalt();
    final token = _md5('$_pass$salt');
    final uri =
        Uri.parse('$_url/rest/getScanStatus.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Scrotify',
      'f': 'json',
    });
    try {
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body)['subsonic-response'];
      if (body?['status'] != 'ok' || body?['scanStatus']?['scanning'] == true) {
        return null;
      }
      final count = (body?['scanStatus']?['count'] as num?)?.toInt();
      return count != null && count >= 0 ? count : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<Track>> getTracks(
          {String? artist, String? album, int limit = 500, int offset = 0}) =>
      _readLibrary(
          () => _fetchTracks(
              artist: artist,
              album: album,
              limit: limit,
              offset: offset), (music, scope, user) {
        final tracks = music
            .downloadedTracks(scope)
            .where((track) =>
                (artist == null || track.artist == artist) &&
                (album == null || track.album == album))
            .toList()
          ..sort(
              (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        return tracks.skip(offset).take(limit).toList();
      });

  Future<List<Track>> _fetchTracks({
    String? artist,
    String? album,
    int limit = 500,
    int offset = 0,
  }) async {
    if (!_connected) throw Exception('Not connected');
    final salt = _randomSalt();
    final token = _md5('$_pass$salt');

    final uri = Uri.parse('$_url/rest/search3.view').replace(queryParameters: {
      'query': '',
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
      'songCount': limit.toString(),
      'songOffset': offset.toString(),
    });

    final response = await _client.get(uri);
    debugPrint('getTracks search3 status: ${response.statusCode}');

    final String raw = response.body;
    dynamic data;
    try {
      data = jsonDecode(raw);
    } catch (e) {
      throw Exception('No se pudo parsear la respuesta del servidor.\n'
          'Status: ${response.statusCode}\n'
          'Body (${raw.length} chars): ${raw.length > 200 ? raw.substring(0, 200) : raw}');
    }

    final subsonicResp = data['subsonic-response'];
    if (subsonicResp == null) return [];

    if (subsonicResp['status'] == 'failed') {
      final err = subsonicResp['error'];
      throw Exception('Server error: ${err?['message'] ?? err}');
    }

    final songsList = subsonicResp['searchResult3']?['song'] as List?;
    if (songsList == null) return [];

    final List<Track> tracks = [];
    for (var songJson in songsList) {
      final map = songJson as Map<String, dynamic>;
      tracks.add(Track.fromJson(map,
          albumArtUrl: _coverArtUrl(map['coverArt'], salt, token)));
    }

    tracks
        .sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return tracks;
  }

  Future<Album> getAlbumInfo(String albumId) async {
    if (!_connected) throw Exception('Not connected');
    final salt = _randomSalt();
    final token = _md5('$_pass$salt');

    final uri = Uri.parse('$_url/rest/getAlbum.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
      'id': albumId,
    });

    final response = await _client.get(uri);
    final data = jsonDecode(response.body);
    final albumData = data['subsonic-response']?['album'];

    if (albumData == null) throw Exception('Album not found');
    final map = albumData as Map<String, dynamic>;
    return Album.fromJson(map,
        coverArtUrl: _coverArtUrl(map['coverArt'], salt, token));
  }

  Future<List<Album>> getAlbums({
    String type = 'newest',
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_connected) throw Exception('Not connected');
    final salt = _randomSalt();
    final token = _md5('$_pass$salt');

    final uri =
        Uri.parse('$_url/rest/getAlbumList2.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
      'type': type,
      'size': limit.toString(),
      'offset': offset.toString(),
    });

    final response = await _client.get(uri);
    final data = jsonDecode(response.body);
    final albumsList =
        data['subsonic-response']?['albumList2']?['album'] as List?;

    if (albumsList == null) return [];

    final List<Album> albums = [];
    for (var albumJson in albumsList) {
      final map = albumJson as Map<String, dynamic>;
      albums.add(Album.fromJson(map,
          coverArtUrl: _coverArtUrl(map['coverArt'], salt, token)));
    }
    return albums;
  }

  /// Devuelve las canciones de un álbum (getAlbum.view).
  Future<List<Track>> getAlbumTracks(String albumId) async {
    if (!_connected) throw Exception('Not connected');
    final (salt, token) = _auth();
    final uri = Uri.parse('$_url/rest/getAlbum.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
      'id': albumId,
    });
    final response = await _client.get(uri);
    final data = jsonDecode(response.body);
    final album = data['subsonic-response']?['album'] as Map<String, dynamic>?;
    if (album == null) return [];
    final entries = album['song'] ?? album['entry'] as List?;
    if (entries == null) return [];
    return (entries as List)
        .map((j) => Track.fromJson(j as Map<String, dynamic>,
            albumArtUrl: _coverArtUrl(j['coverArt'], salt, token)))
        .toList();
  }

  /// Devuelve los detalles de un artista (getArtist.view), aprovechando caché en memoria.
  Future<Artist?> getArtist(String artistId) async {
    if (_artistCache.containsKey(artistId)) {
      return _artistCache[artistId];
    }
    if (!_connected) return null;
    try {
      final (salt, token) = _auth();
      final uri =
          Uri.parse('$_url/rest/getArtist.view').replace(queryParameters: {
        'u': _user!,
        's': salt,
        't': token,
        'v': '1.16.1',
        'c': 'Psysonic',
        'f': 'json',
        'id': artistId,
      });
      final response = await _client.get(uri);
      final data = jsonDecode(response.body);
      final artistJson =
          data['subsonic-response']?['artist'] as Map<String, dynamic>?;
      if (artistJson == null) return null;
      final artist = Artist.fromJson(
        artistJson,
        coverArtUrl: _coverArtUrl(artistJson['coverArt'], salt, token),
      );
      _artistCache[artistId] = artist;
      return artist;
    } catch (e) {
      debugPrint('NavidromeService.getArtist error: $e');
      return null;
    }
  }

  /// Devuelve los álbumes de un artista (getArtist.view).
  Future<List<Album>> getArtistAlbums(String artistId) async {
    if (!_connected) throw Exception('Not connected');
    final (salt, token) = _auth();
    final uri =
        Uri.parse('$_url/rest/getArtist.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
      'id': artistId,
    });
    final response = await _client.get(uri);
    final data = jsonDecode(response.body);
    final artist =
        data['subsonic-response']?['artist'] as Map<String, dynamic>?;
    if (artist == null) return [];
    final list = artist['album'] as List?;
    if (list == null) return [];
    return list
        .map((j) => Album.fromJson(j as Map<String, dynamic>,
            coverArtUrl: _coverArtUrl(j['coverArt'], salt, token)))
        .toList();
  }

  /// Devuelve las canciones de un artista (vía search3 filtrado por artista).
  Future<List<Track>> getArtistTracks(String artistId) async {
    if (!_connected) throw Exception('Not connected');
    // Primero obtenemos el nombre del artista para buscar sus canciones.
    final (salt, token) = _auth();
    final uri =
        Uri.parse('$_url/rest/getArtist.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
      'id': artistId,
    });
    final response = await _client.get(uri);
    final data = jsonDecode(response.body);
    final artist =
        data['subsonic-response']?['artist'] as Map<String, dynamic>?;
    if (artist == null) return [];
    final artistName = artist['name'] as String? ?? '';

    // Buscamos canciones del artista (search3 con query = nombre del artista).
    final searchUri =
        Uri.parse('$_url/rest/search3.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
      'query': artistName,
      'songCount': '50',
      'albumCount': '0',
      'artistCount': '0',
    });
    final searchResponse = await _client.get(searchUri);
    final searchData = jsonDecode(searchResponse.body);
    final result = searchData['subsonic-response']?['searchResult3']
        as Map<String, dynamic>?;
    if (result == null) return [];
    final songs = _asList(result['song']);
    return songs
        .map((j) => Track.fromJson(j as Map<String, dynamic>,
            albumArtUrl: _coverArtUrl(j['coverArt'], salt, token)))
        .toList();
  }

  /// Calidad de reproducción impuesta por el modo de fidelidad (Alta fidelidad
  /// o Bit-perfect). `null` = la calidad elegida en los ajustes. No afecta a
  /// las descargas.
  StreamQuality? hifiStream;

  /// URL de reproducción: igual que [getStreamUrl] salvo que el modo de
  /// fidelidad imponga el archivo original (`format=raw`).
  String getPlaybackStreamUrl(String trackId, {AudioQuality? quality}) {
    final override = hifiStream;
    if (override == null) return getStreamUrl(trackId, quality: quality);
    return getStreamUrl(trackId,
        quality: AudioQuality.lossless, extraQuery: override.toQuery());
  }

  String getStreamUrl(String trackId,
      {AudioQuality? quality, Map<String, String>? extraQuery}) {
    final salt = _randomSalt();
    final token = _md5('$_pass$salt');
    var url = '$_url/rest/stream.view'
        '?u=${Uri.encodeQueryComponent(_user!)}'
        '&s=$salt&t=$token&v=1.16.1&c=Psysonic'
        '&id=${Uri.encodeQueryComponent(trackId)}';
    // Sin pérdida = sin parámetros (el servidor manda el archivo original).
    // Con bitrate definido, Navidrome transcodifica a MP3.
    final q = quality;
    if (q != null && q != AudioQuality.lossless) {
      url += '&format=mp3&maxBitRate=${q.kbps}';
    }
    if (extraQuery != null) {
      for (final e in extraQuery.entries) {
        url += '&${Uri.encodeQueryComponent(e.key)}='
            '${Uri.encodeQueryComponent(e.value)}';
      }
    }
    return url;
  }

  /// Downloads track audio bytes via authenticated HTTP streaming into [destinationFile].
  /// Never exposes or logs the authenticated URL or credentials.
  /// Throws sanitized [DownloadException] on error.
  Future<void> downloadTrackStream({
    required String trackId,
    required File destinationFile,
    AudioQuality? quality,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    bool Function()? isCancelled,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!_connected || _url == null || _user == null || _pass == null) {
      throw const DownloadException(
        'Server not connected',
        category: DownloadFailureCategory.notConnected,
      );
    }

    if (isCancelled != null && isCancelled()) {
      throw const DownloadException(
        'Download cancelled',
        category: DownloadFailureCategory.cancelled,
      );
    }

    final streamUrl = getStreamUrl(trackId, quality: quality);
    final uri = Uri.parse(streamUrl);

    http.StreamedResponse response;
    try {
      final request = http.Request('GET', uri);
      final streamedFuture = _client.send(request);
      response = await streamedFuture.timeout(timeout);
    } on TimeoutException {
      throw const DownloadException(
        'Connection timed out',
        category: DownloadFailureCategory.timeout,
      );
    } on SocketException {
      throw const DownloadException(
        'Network connection failed',
        category: DownloadFailureCategory.network,
      );
    } on HttpException {
      throw const DownloadException(
        'HTTP transport error',
        category: DownloadFailureCategory.network,
      );
    } catch (e) {
      if (e is DownloadException) rethrow;
      throw const DownloadException(
        'Network connection failed',
        category: DownloadFailureCategory.network,
      );
    }

    if (response.statusCode != 200) {
      final category = switch (response.statusCode) {
        401 || 403 => DownloadFailureCategory.auth,
        404 => DownloadFailureCategory.notFound,
        >= 500 => DownloadFailureCategory.serverError,
        _ => DownloadFailureCategory.unknown,
      };
      throw DownloadException(
        'Server returned HTTP ${response.statusCode}',
        category: category,
      );
    }

    final totalBytes = response.contentLength;
    int receivedBytes = 0;

    IOSink? sink;
    StreamSubscription<List<int>>? subscription;
    try {
      if (!await destinationFile.parent.exists()) {
        await destinationFile.parent.create(recursive: true);
      }
      sink = destinationFile.openWrite();

      final completer = Completer<void>();

      subscription = response.stream.listen(
        (chunk) {
          if (isCancelled != null && isCancelled()) {
            subscription?.cancel();
            if (!completer.isCompleted) {
              completer.completeError(const DownloadException(
                'Download cancelled',
                category: DownloadFailureCategory.cancelled,
              ));
            }
            return;
          }
          try {
            sink!.add(chunk);
            receivedBytes += chunk.length;
            onProgress?.call(receivedBytes, totalBytes);
          } catch (_) {
            subscription?.cancel();
            if (!completer.isCompleted) {
              completer.completeError(const DownloadException(
                'Filesystem write error',
                category: DownloadFailureCategory.storage,
              ));
            }
          }
        },
        onError: (Object error) {
          if (!completer.isCompleted) {
            final category = error is TimeoutException
                ? DownloadFailureCategory.timeout
                : DownloadFailureCategory.network;
            completer.completeError(DownloadException(
              error is TimeoutException
                  ? 'Download timed out'
                  : 'Download stream failed',
              category: category,
            ));
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
        cancelOnError: true,
      );

      await completer.future.timeout(timeout);
      await sink.flush();
    } on TimeoutException {
      throw const DownloadException(
        'Download transfer timed out',
        category: DownloadFailureCategory.timeout,
      );
    } on FileSystemException {
      throw const DownloadException(
        'Filesystem write error',
        category: DownloadFailureCategory.storage,
      );
    } finally {
      await subscription?.cancel();
      try {
        await sink?.close();
      } catch (err) {
        debugPrint('navidrome_service:1840 ignorado: $err');
      }
    }
  }

  /// Registra una reproducción para el usuario conectado. Navidrome solo
  /// actualiza su contador al recibir este evento, nunca solo por `stream`.
  /// Informa a Navidrome de lo que suena ahora (`submission=false`); es lo que
  /// alimenta "Ahora sonando" para los demás usuarios.
  Future<void> reportNowPlaying(String trackId) async {
    if (!_connected) return;
    try {
      final (salt, token) = _auth();
      await _client.get(Uri.parse('$_url/rest/scrobble.view').replace(
        queryParameters: {
          'u': _user!,
          's': salt,
          't': token,
          'v': '1.16.1',
          'c': 'Scrotify',
          'f': 'json',
          'id': trackId,
          'submission': 'false',
        },
      ));
    } catch (_) {}
  }

  Future<void> scrobble(String trackId) async {
    if (!_connected) return;
    try {
      final (salt, token) = _auth();
      final uri = Uri.parse('$_url/rest/scrobble.view').replace(
        queryParameters: {
          'u': _user!,
          's': salt,
          't': token,
          'v': '1.16.1',
          'c': 'Scrotify',
          'f': 'json',
          'id': trackId,
          'time': DateTime.now().millisecondsSinceEpoch.toString(),
          'submission': 'true',
        },
      );
      await _client.get(uri);
    } catch (_) {
      // Un fallo de red al informar una escucha no debe cortar el audio.
    }
  }

  // ---------------------------------------------------------------------------
  // Letras locales (prioridad 1): getLyricsBySongId de Navidrome/OpenSubsonic.
  // Usa letras embebidas o .lrc externos ya escaneados por el servidor.
  // ---------------------------------------------------------------------------

  /// Devuelve los bloques de letra estructurada para una canción.
  /// Lista vacía si el servidor no tiene letra para ese `songId`.
  Future<List<StructuredLyricBlock>> getLyricsBySongId(String songId) async {
    if (!_connected) return [];
    final (salt, token) = _auth();
    final uri = Uri.parse('$_url/rest/getLyricsBySongId.view')
        .replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
      'id': songId,
    });

    try {
      final response = await _client.get(uri);
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body);
      final lyricsList =
          data['subsonic-response']?['lyricsList'] as Map<String, dynamic>?;
      if (lyricsList == null) return [];
      final rawBlocks = lyricsList['structuredLyrics'];
      if (rawBlocks == null) return [];
      final blocks = _asList(rawBlocks);
      final result = <StructuredLyricBlock>[];
      for (final b in blocks) {
        if (b is! Map) continue;
        final map = b as Map<String, dynamic>;
        final synced = map['synced'] == true;
        final lang = (map['lang'] as String?) ?? '';
        final rawLines = _asList(map['line']);
        final lines = <LyricLineData>[];
        for (final l in rawLines) {
          if (l is! Map) continue;
          final lm = l as Map<String, dynamic>;
          final value = (lm['value'] as String?) ?? '';
          if (value.trim().isEmpty) continue;
          final start = (lm['start'] as num?)?.toInt() ?? 0;
          lines.add(LyricLineData(startMs: start, text: value));
        }
        if (lines.isNotEmpty) {
          result.add(
              StructuredLyricBlock(synced: synced, lang: lang, lines: lines));
        }
      }
      return result;
    } catch (e) {
      debugPrint('NavidromeService.getLyricsBySongId error: $e');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Descubrimiento y Filtrado (Fase 9)
  // ---------------------------------------------------------------------------

  List<String>? _cachedGenres;
  String? _lastSelectedGenreSuggestion;

  /// Sugerencia del último género seleccionado (solo sugerencia; no bloquea al usuario al volver).
  String? get lastSelectedGenreSuggestion => _lastSelectedGenreSuggestion;

  /// Lista en memoria de los géneros cargados previamente.
  List<String> get cachedGenres => _cachedGenres ?? const [];

  /// Guarda el último género seleccionado únicamente como sugerencia futura.
  Future<void> saveLastSelectedGenre(String genre) async {
    _lastSelectedGenreSuggestion = genre;
    try {
      final dir = await getAppDataDirectory();
      final file =
          File('${dir.path}/${_scopedName("last_genre_suggestion.json")}');
      await file.writeAsString(jsonEncode({'genre': genre}));
    } catch (err) {
      debugPrint('navidrome_service:1948 ignorado: $err');
    }
  }

  /// Carga la sugerencia persistida del último género seleccionado.
  Future<String?> loadLastSelectedGenre() async {
    try {
      final file = await _resolveScopedFile("last_genre_suggestion.json");
      if (file != null && await file.exists()) {
        final data =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _lastSelectedGenreSuggestion = data['genre'] as String?;
        return _lastSelectedGenreSuggestion;
      }
    } catch (err) {
      debugPrint('navidrome_service:1961 ignorado: $err');
    }
    return null;
  }

  /// Filtra localmente una lista de pistas por género de forma exacta (insensible a mayúsculas).
  List<Track> filterByGenre(List<Track> tracks, String genre) {
    if (genre.isEmpty ||
        genre.toLowerCase() == 'todos' ||
        genre.toLowerCase() == 'all') {
      return List<Track>.from(tracks);
    }
    final target = genre.trim().toLowerCase();
    return tracks.where((t) {
      final g = t.genre;
      if (g == null || g.trim().isEmpty) return false;
      final gl = g.trim().toLowerCase();
      if (gl == target) return true;
      final parts = gl.split(RegExp(r'[,;/]')).map((s) => s.trim());
      return parts.contains(target);
    }).toList();
  }

  /// Obtiene pistas de los álbumes más nuevos del servidor.
  ///
  /// `getAlbumList2(type=newest)` es el endpoint Subsonic soportado para esta
  /// consulta. Se expanden álbumes en orden y se detiene al alcanzar [limit].
  /// Protegido contra desconexiones para mantener seguro el montaje de Home.
  Future<List<Track>> getRecentlyAddedTracks({int limit = 20}) async {
    if (limit <= 0) return [];
    if (!_connected || _offlineMode) {
      await localMusic?.initialize();
      return (localMusic?.downloadedTracks(serverScope) ?? [])
          .take(limit)
          .toList();
    }
    try {
      final albums = await getAlbums(type: 'newest', limit: limit);
      final tracks = <Track>[];
      for (final album in albums) {
        if (tracks.length >= limit) break;
        final albumTracks = await getAlbumTracks(album.id);
        tracks.addAll(albumTracks.take(limit - tracks.length));
      }
      return tracks;
    } catch (e) {
      debugPrint('NavidromeService.getRecentlyAddedTracks error: $e');
      await localMusic?.initialize();
      return (localMusic?.downloadedTracks(serverScope) ?? [])
          .take(limit)
          .toList();
    }
  }

  /// Busca pistas que pertenezcan exactamente a un género específico.
  ///
  /// Recurre a `search3.view` aplicando filtrado local estricto para asegurar que las canciones coincidan.
  /// Si no hay coincidencias o falla, recurre a pistas de la biblioteca localmente con filtrado exacto.
  /// Seguro ante desconexiones.
  Future<List<Track>> searchByGenre(String genre, {int limit = 50}) async {
    if (!_connected || genre.trim().isEmpty) return const [];
    final (salt, token) = _auth();

    // 1. Búsqueda con search3 y filtrado exacto
    try {
      final uri =
          Uri.parse('$_url/rest/search3.view').replace(queryParameters: {
        'query': genre,
        'u': _user!,
        's': salt,
        't': token,
        'v': '1.16.1',
        'c': 'Psysonic',
        'f': 'json',
        'songCount': (limit * 2).toString(),
        'albumCount': '0',
        'artistCount': '0',
      });

      final response = await _client.get(uri);
      final data = jsonDecode(response.body);
      final result =
          data['subsonic-response']?['searchResult3'] as Map<String, dynamic>?;
      if (result != null) {
        final rawTracks = _asList(result['song'])
            .map((j) => Track.fromJson(
                  j as Map<String, dynamic>,
                  albumArtUrl: _coverArtUrl(j['coverArt'], salt, token),
                ))
            .toList();

        final exactMatches = filterByGenre(rawTracks, genre);
        if (exactMatches.isNotEmpty) {
          return exactMatches.take(limit).toList();
        }
      }
    } catch (err) {
      debugPrint('navidrome_service:2047 ignorado: $err');
    }

    // 2. Fallback: comprobar pistas de biblioteca localmente con filtrado exacto
    try {
      final libraryTracks = await getTracks(limit: 500);
      final libraryMatches = filterByGenre(libraryTracks, genre);
      if (libraryMatches.isNotEmpty) {
        return libraryMatches.take(limit).toList();
      }
    } catch (err) {
      debugPrint('navidrome_service:2056 ignorado: $err');
    }

    return const [];
  }

  /// Obtiene una lista de géneros disponibles en la biblioteca.
  /// Protegido contra desconexiones y cacheado en memoria para evitar
  /// peticiones redundantes.
  Future<List<String>> getGenres() async {
    if (!_connected) return _cachedGenres ?? [];

    // 1. Intentar endpoint getGenres.view
    try {
      final (salt, token) = _auth();
      final uri =
          Uri.parse('$_url/rest/getGenres.view').replace(queryParameters: {
        'u': _user!,
        's': salt,
        't': token,
        'v': '1.16.1',
        'c': 'Psysonic',
        'f': 'json',
      });

      final response = await _client.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final genresList = data['subsonic-response']?['genres']?['genre'];
        if (genresList != null) {
          final set = <String>{};
          for (final item in _asList(genresList)) {
            if (item is Map<String, dynamic>) {
              final val = item['value'] ?? item['name'];
              if (val is String && val.trim().isNotEmpty) {
                set.add(val.trim());
              }
            } else if (item is String && item.trim().isNotEmpty) {
              set.add(item.trim());
            }
          }
          if (set.isNotEmpty) {
            final sorted = set.toList()..sort();
            _cachedGenres = sorted;
            return sorted;
          }
        }
      }
    } catch (err) {
      debugPrint('navidrome_service:2103 ignorado: $err');
    }

    // 2. Muestra de biblioteca
    try {
      final tracks = await getTracks(limit: 500);
      final genres = tracks
          .map((track) => track.genre)
          .whereType<String>()
          .where((genre) => genre.trim().isNotEmpty)
          .toSet()
          .toList();

      genres.sort();
      _cachedGenres = genres;
      return genres;
    } catch (e) {
      debugPrint('NavidromeService.getGenres error: $e');
      return _cachedGenres ?? [];
    }
  }
  // ---------------------------------------------------------------------------

  /// Obtiene lo que otros usuarios están escuchando en este servidor en tiempo real.
  Future<List<NowPlayingEntry>> getNowPlaying() async {
    if (!_connected) return [];
    final (salt, token) = _auth();
    final uri =
        Uri.parse('$_url/rest/getNowPlaying.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
    });

    try {
      final response = await _client.get(uri);
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body);
      final entries =
          data['subsonic-response']?['nowPlaying']?['entry'] as List?;
      if (entries == null) return [];

      return entries
          .map((j) => NowPlayingEntry.fromJson(
                j as Map<String, dynamic>,
                _coverArtUrl(j['coverArt'], salt, token),
              ))
          .toList();
    } catch (e) {
      debugPrint('NavidromeService.getNowPlaying error: $e');
      return [];
    }
  }

  /// Base HTTP del relay Jam usada para el chat comunitario. Navidrome no
  /// implementa el chat de Subsonic (responde 410), así que se hospeda allí.
  Uri? lobbyBaseUrl;

  /// Canal del chat: el host de este servidor Navidrome.
  String? get _lobbyChannel {
    final host = Uri.tryParse(_url ?? '')?.host.toLowerCase();
    return host == null || host.isEmpty ? null : host;
  }

  Future<List<ChatMessage>> _getLobbyMessages() async {
    final channel = _lobbyChannel;
    final base = lobbyBaseUrl;
    if (channel == null || base == null) return [];
    try {
      final res = await _client
          .get(base.replace(
              path: '/api/lobby/messages',
              queryParameters: {'channel': channel}))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return [];
      final list = (jsonDecode(res.body)['messages'] as List?) ?? const [];
      return [
        for (final m in list)
          if (m is Map<String, dynamic>) ChatMessage.fromJson(m),
      ];
    } catch (e) {
      debugPrint('NavidromeService.lobby get error: $e');
      return [];
    }
  }

  Future<bool> _addLobbyMessage(String message) async {
    final channel = _lobbyChannel;
    final base = lobbyBaseUrl;
    if (channel == null || base == null || _user == null) return false;
    try {
      final res = await _client
          .post(
            base.replace(path: '/api/lobby/messages', queryParameters: null),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(
                {'channel': channel, 'username': _user, 'message': message}),
          )
          .timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('NavidromeService.lobby post error: $e');
      return false;
    }
  }

  /// Obtiene los mensajes del chat comunitario del servidor.
  Future<List<ChatMessage>> getChatMessages({int? since}) async {
    if (!_connected) return [];
    if (lobbyBaseUrl != null) return _getLobbyMessages();
    final (salt, token) = _auth();
    final params = <String, String>{
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
      if (since != null) 'since': since.toString(),
    };

    final uri = Uri.parse('$_url/rest/getChatMessages.view')
        .replace(queryParameters: params);

    try {
      final response = await _client.get(uri);
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body);
      final rawList =
          data['subsonic-response']?['chatMessages']?['chatMessage'] as List?;
      if (rawList == null) return [];

      return rawList
          .map((j) => ChatMessage.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('NavidromeService.getChatMessages error: $e');
      return [];
    }
  }

  /// Envía un mensaje al chat comunitario del servidor.
  Future<bool> addChatMessage(String message) async {
    if (!_connected || message.trim().isEmpty) return false;
    if (lobbyBaseUrl != null) return _addLobbyMessage(message.trim());
    final (salt, token) = _auth();
    final uri =
        Uri.parse('$_url/rest/addChatMessage.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
      'message': message.trim(),
    });

    try {
      final response = await _client.get(uri);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('NavidromeService.addChatMessage error: $e');
      return false;
    }
  }

  /// Publica o anuncia una sesión Jam activa en el servidor Navidrome para que
  /// cualquier usuario conectado a la misma instancia pueda descubrirla y unirse.
  DateTime? _lastJamAnnounce;

  Future<void> publishServerJam(JamSessionState session) async {
    if (!_connected || !session.isPublic) return;
    // Se llama en cada cambio de estado: máximo un anuncio cada 30 s.
    final last = _lastJamAnnounce;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 30)) {
      return;
    }
    _lastJamAnnounce = DateTime.now();
    try {
      final payload = jsonEncode({
        'tag': 'SCROTIFY_JAM',
        'sessionId': session.sessionId,
        'pin': session.pinCode,
        'host': session.hostIp,
        'port': session.port,
        'hostName': session.hostName,
        'title': 'Jam de ${session.hostName}',
        'trackTitle': session.currentTrack?.title,
        'trackArtist': session.currentTrack?.artist,
        'albumArtUrl': session.currentTrack?.albumArtUrl,
        'mode': session.mode.name,
        'participantCount': session.participants.length,
        'isPublic': session.isPublic,
        if (session.remoteHost != null) 'remoteHost': session.remoteHost,
        if (session.remotePort != null) 'remotePort': session.remotePort,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      await addChatMessage('[JAM_LIVE]:$payload');
    } catch (e) {
      debugPrint('NavidromeService.publishServerJam error: $e');
    }
  }

  /// Retira el anuncio de una Jam que terminó de forma ordenada.
  Future<void> publishServerJamEnded(JamSessionState session) async {
    if (!_connected || !session.isPublic) return;
    _lastJamAnnounce = null;
    try {
      await addChatMessage('[JAM_END]:${jsonEncode({
            'tag': 'SCROTIFY_JAM',
            'sessionId': session.sessionId,
            'pin': session.pinCode,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          })}');
    } catch (e) {
      debugPrint('NavidromeService.publishServerJamEnded error: $e');
    }
  }

  /// Descubre sesiones Jam activas anunciadas en este servidor Navidrome.
  Future<List<DiscoveredJamSession>> getServerActiveJams() async {
    if (!_connected) return [];
    final discovered = <String, DiscoveredJamSession>{};

    try {
      // 1. Buscar en mensajes de chat recientes
      final messages = await getChatMessages();
      final now = DateTime.now().millisecondsSinceEpoch;

      // PIN -> momento en que el anfitrión cerró la sala.
      final endedAt = <String, int>{};
      for (final msg in messages) {
        if (!msg.message.startsWith('[JAM_END]:')) continue;
        try {
          final data = jsonDecode(msg.message.substring('[JAM_END]:'.length))
              as Map<String, dynamic>;
          final pin = (data['pin'] as String?) ?? '';
          final ts = (data['timestamp'] as num?)?.toInt() ?? 0;
          if (pin.isNotEmpty && ts > (endedAt[pin] ?? 0)) endedAt[pin] = ts;
        } catch (_) {}
      }

      for (final msg in messages.reversed) {
        if (msg.message.startsWith('[JAM_LIVE]:')) {
          try {
            final jsonStr = msg.message.substring('[JAM_LIVE]:'.length);
            final data = jsonDecode(jsonStr) as Map<String, dynamic>;
            final ts = (data['timestamp'] as num?)?.toInt() ?? 0;

            final closedAt = endedAt[(data['pin'] as String?) ?? ''];
            final closed = closedAt != null && closedAt >= ts;

            // Ignorar sesiones cerradas o con más de 25 minutos sin actualización
            if (!closed &&
                data['isPublic'] != false &&
                now - ts < 25 * 60 * 1000) {
              final host = (data['host'] as String?) ?? '127.0.0.1';
              final port = (data['port'] as num?)?.toInt() ?? 0;
              final pin = (data['pin'] as String?) ?? '';
              final key = '$host:$port:$pin';

              if (pin.isNotEmpty) {
                final modeName =
                    data['mode'] as String? ?? JamMode.partySpeaker.name;
                final mode = JamMode.values.firstWhere(
                  (m) => m.name == modeName,
                  orElse: () => JamMode.partySpeaker,
                );

                discovered[key] = DiscoveredJamSession(
                  host: host,
                  port: port,
                  pin: pin,
                  sessionTitle: (data['title'] as String?) ??
                      'Jam de ${data['hostName'] ?? "Comunidad"}',
                  hostName: (data['hostName'] as String?) ?? msg.username,
                  participantCount:
                      (data['participantCount'] as num?)?.toInt() ?? 1,
                  currentTrackTitle: data['trackTitle'] as String?,
                  currentTrackArtist: data['trackArtist'] as String?,
                  albumArtUrl: data['albumArtUrl'] as String?,
                  mode: mode,
                  remoteHost: data['remoteHost'] as String?,
                  remotePort: (data['remotePort'] as num?)?.toInt(),
                );
              }
            }
          } catch (err) {
            debugPrint('navidrome_service:2297 ignorado: $err');
          }
        }
      }
    } catch (e) {
      debugPrint('NavidromeService.getServerActiveJams error: $e');
    }

    return discovered.values.toList();
  }

  void disconnect() {
    _stopAutoReconnect();
    _connected = false;
    _offlineMode = false;
    _url = null;
    _user = null;
    _pass = null;
    _resetCoverAuth();
    _client.close();
    _client = _injectedClient ?? http.Client();

    // Clear state
    _starredIds.clear();
    _starredSongOrder.clear();
    _pinnedPlaylistIds.clear();
    _followedArtistIds.clear();
    _excludedArtistIds.clear();
    _artistCache.clear();
    _trackRatings.clear();
    _cachedGenres = null;

    notifyListeners();
  }
}
