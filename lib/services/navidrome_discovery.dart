part of 'navidrome_service.dart';

/// Descubrimiento y continuidad: radio por artista/canción, cola guardada en
/// el servidor, biografía y similares, marcadores, radios de internet y
/// podcasts. Todo sobre la API Subsonic/OpenSubsonic estándar.
mixin _NavidromeDiscovery on _NavidromeBase {
  /// Llama a [endpoint] (`getX.view`) y devuelve el `subsonic-response` si el
  /// estado es `ok`; `null` si no hay conexión, falla la red o el servidor
  /// responde con error (p. ej. un servidor sin ese endpoint).
  Future<Map<String, dynamic>?> _subsonic(
    String endpoint,
    Map<String, String> params,
  ) async {
    if (!_connected || _url == null || _user == null) return null;
    final (salt, token) = _auth();
    final query = <String, String>{
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'CrotoWave',
      'f': 'json',
      ...params,
    };
    final uri =
        Uri.parse('$_url/rest/$endpoint.view').replace(queryParameters: query);
    try {
      final response = await _get(uri);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      final body = decoded is Map ? decoded['subsonic-response'] : null;
      if (body is! Map || body['status'] != 'ok') return null;
      return Map<String, dynamic>.from(body);
    } catch (_) {
      return null;
    }
  }

  List<Track> _tracksFrom(dynamic raw) {
    final (salt, token) = _auth();
    return NavidromeService._asList(raw)
        .whereType<Map>()
        .map((j) => Track.fromJson(Map<String, dynamic>.from(j),
            albumArtUrl: _coverArtUrl(j['coverArt'], salt, token)))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // 51. Radio por artista o canción
  // ---------------------------------------------------------------------------

  /// Canciones parecidas a [songId] (`getSimilarSongs2`), para una «radio».
  Future<List<Track>> getSimilarSongs(String songId, {int count = 50}) async {
    final body =
        await _subsonic('getSimilarSongs2', {'id': songId, 'count': '$count'});
    return _tracksFrom(body?['similarSongs2']?['song']);
  }

  /// Las canciones más escuchadas de un artista (`getTopSongs`, por nombre).
  Future<List<Track>> getTopSongs(String artistName, {int count = 50}) async {
    final body = await _subsonic(
        'getTopSongs', {'artist': artistName, 'count': '$count'});
    return _tracksFrom(body?['topSongs']?['song']);
  }

  /// Radio de un artista: sus temas más escuchados y los de artistas
  /// parecidos, sin repetidos y empezando por los del propio artista.
  Future<List<Track>> getArtistRadio(String artistId, String artistName,
      {int count = 50}) async {
    final results = await Future.wait([
      getTopSongs(artistName, count: count),
      getSimilarSongs(artistId, count: count),
    ]);
    final seen = <String>{};
    return [
      for (final track in [...results[0], ...results[1]])
        if (seen.add(track.id)) track,
    ].take(count).toList();
  }

  // ---------------------------------------------------------------------------
  // 52. Cola guardada en el servidor (continuar en otro dispositivo)
  // ---------------------------------------------------------------------------

  /// Guarda la cola y la pista actual en el servidor (`savePlayQueue`).
  /// [positionMs] es la posición dentro de [currentId].
  Future<bool> savePlayQueue(List<String> ids,
      {String? currentId, int positionMs = 0}) async {
    if (ids.isEmpty) return false;
    if (!_connected || _url == null || _user == null) return false;
    final (salt, token) = _auth();
    final buffer = StringBuffer('$_url/rest/savePlayQueue.view')
      ..write('?u=${Uri.encodeQueryComponent(_user!)}')
      ..write('&s=$salt&t=$token&v=1.16.1&c=CrotoWave&f=json');
    for (final id in ids) {
      buffer.write('&id=${Uri.encodeQueryComponent(id)}');
    }
    if (currentId != null) {
      buffer.write('&current=${Uri.encodeQueryComponent(currentId)}');
    }
    buffer.write('&position=$positionMs');
    try {
      final response = await _get(Uri.parse(buffer.toString()));
      if (response.statusCode != 200) return false;
      final body = jsonDecode(response.body)['subsonic-response'];
      return body is Map && body['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  /// Recupera la cola guardada (`getPlayQueue`) o `null` si no hay.
  Future<SavedPlayQueue?> getSavedPlayQueue() async {
    final body = await _subsonic('getPlayQueue', const {});
    final queue = body?['playQueue'];
    if (queue is! Map) return null;
    final tracks = _tracksFrom(queue['entry']);
    if (tracks.isEmpty) return null;
    return SavedPlayQueue(
      tracks: tracks,
      currentId: queue['current']?.toString(),
      positionMs: (queue['position'] as num?)?.toInt() ?? 0,
      changedBy: queue['changedBy'] as String?,
    );
  }

  // ---------------------------------------------------------------------------
  // 53. Biografía y artistas similares
  // ---------------------------------------------------------------------------

  /// Biografía, imagen y artistas similares de [artistId] (`getArtistInfo2`).
  Future<ArtistBio?> getArtistBio(String artistId, {int similar = 8}) async {
    final body = await _subsonic(
        'getArtistInfo2', {'id': artistId, 'count': '$similar'});
    final info = body?['artistInfo2'];
    if (info is! Map) return null;
    final (salt, token) = _auth();
    final similarArtists = NavidromeService._asList(info['similarArtist'])
        .whereType<Map>()
        .map((a) => Artist(
              id: a['id']?.toString() ?? '',
              name: a['name']?.toString() ?? '',
              coverArtUrl: _coverArtUrl(a['coverArt'], salt, token),
            ))
        .where((a) => a.id.isNotEmpty && a.name.isNotEmpty)
        .toList();
    final raw = (info['biography'] as String?) ?? '';
    return ArtistBio(
      // Last.fm incluye un enlace HTML al final: se quita para mostrar texto.
      biography: raw.replaceAll(RegExp(r'<[^>]*>'), '').trim(),
      imageUrl: (info['largeImageUrl'] ?? info['mediumImageUrl']) as String?,
      similarArtists: similarArtists,
    );
  }

  // ---------------------------------------------------------------------------
  // 55. Marcadores (pistas largas, podcasts, audiolibros)
  // ---------------------------------------------------------------------------

  Future<List<TrackBookmark>> getBookmarks() async {
    final body = await _subsonic('getBookmarks', const {});
    final result = <TrackBookmark>[];
    for (final raw
        in NavidromeService._asList(body?['bookmarks']?['bookmark'])) {
      if (raw is! Map) continue;
      final tracks = _tracksFrom(raw['entry']);
      if (tracks.isEmpty) continue;
      result.add(TrackBookmark(
        track: tracks.first,
        positionMs: (raw['position'] as num?)?.toInt() ?? 0,
        comment: raw['comment'] as String?,
      ));
    }
    return result;
  }

  Future<bool> createBookmark(String trackId, int positionMs,
      {String? comment}) async {
    final body = await _subsonic('createBookmark', {
      'id': trackId,
      'position': '$positionMs',
      if (comment != null && comment.isNotEmpty) 'comment': comment,
    });
    return body != null;
  }

  Future<bool> deleteBookmark(String trackId) async =>
      (await _subsonic('deleteBookmark', {'id': trackId})) != null;

  // ---------------------------------------------------------------------------
  // 61. Radios por internet y podcasts
  // ---------------------------------------------------------------------------

  Future<List<InternetRadioStation>> getInternetRadioStations() async {
    final body = await _subsonic('getInternetRadioStations', const {});
    return NavidromeService._asList(
            body?['internetRadioStations']?['internetRadioStation'])
        .whereType<Map>()
        .map((s) => InternetRadioStation(
              id: s['id']?.toString() ?? '',
              name: s['name']?.toString() ?? '',
              streamUrl: s['streamUrl']?.toString() ?? '',
              homePageUrl: s['homePageUrl'] as String?,
            ))
        .where((s) => s.id.isNotEmpty && s.streamUrl.isNotEmpty)
        .toList();
  }

  Future<List<PodcastChannel>> getPodcasts() async {
    final body = await _subsonic('getPodcasts', {'includeEpisodes': 'true'});
    return NavidromeService._asList(body?['podcasts']?['channel'])
        .whereType<Map>()
        .map((c) {
          // Un episodio se reproduce por su `streamId`, no por el id del episodio.
          final episodes = _tracksFrom([
            for (final e in NavidromeService._asList(c['episode']))
              if (e is Map)
                {
                  ...Map<String, dynamic>.from(e),
                  if (e['streamId'] != null) 'id': e['streamId'].toString(),
                },
          ]);
          return PodcastChannel(
            id: c['id']?.toString() ?? '',
            title: c['title']?.toString() ?? '',
            description: c['description'] as String?,
            coverArtUrl: c['coverArt'] != null
                ? _coverArtUrl(c['coverArt'], '', '')
                : c['originalImageUrl'] as String?,
            episodes: episodes,
          );
        })
        .where((c) => c.id.isNotEmpty)
        .toList();
  }
}

/// Cola de reproducción guardada en el servidor.
class SavedPlayQueue {
  final List<Track> tracks;
  final String? currentId;
  final int positionMs;
  final String? changedBy;

  const SavedPlayQueue({
    required this.tracks,
    this.currentId,
    this.positionMs = 0,
    this.changedBy,
  });

  int get currentIndex {
    final i = tracks.indexWhere((t) => t.id == currentId);
    return i < 0 ? 0 : i;
  }
}

/// Biografía e información de un artista.
class ArtistBio {
  final String biography;
  final String? imageUrl;
  final List<Artist> similarArtists;

  const ArtistBio({
    required this.biography,
    this.imageUrl,
    this.similarArtists = const [],
  });

  bool get isEmpty =>
      biography.isEmpty && imageUrl == null && similarArtists.isEmpty;
}

/// Posición guardada dentro de una pista.
class TrackBookmark {
  final Track track;
  final int positionMs;
  final String? comment;

  const TrackBookmark({
    required this.track,
    required this.positionMs,
    this.comment,
  });
}

class InternetRadioStation {
  final String id;
  final String name;
  final String streamUrl;
  final String? homePageUrl;

  const InternetRadioStation({
    required this.id,
    required this.name,
    required this.streamUrl,
    this.homePageUrl,
  });
}

class PodcastChannel {
  final String id;
  final String title;
  final String? description;
  final String? coverArtUrl;
  final List<Track> episodes;

  const PodcastChannel({
    required this.id,
    required this.title,
    this.description,
    this.coverArtUrl,
    this.episodes = const [],
  });
}
