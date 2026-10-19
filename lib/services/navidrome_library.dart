part of 'navidrome_service.dart';

/// Biblioteca: totales, catálogo de recuperación, canciones, álbumes,
/// artistas, URLs de reproducción, descargas y scrobble.
mixin _NavidromeLibrary on _NavidromeBase {
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
      'c': 'CrotoWave',
      'f': 'json',
    });
    try {
      final response = await _get(uri).timeout(const Duration(seconds: 20));
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

  /// Catálogo completo para recuperar descargas; no usa el fallback sin conexión.
  ///
  /// Se guarda en memoria [NavidromeService.recoveryCatalogTtl] por sesión y las consultas
  /// simultáneas comparten una sola descarga. Una descarga cuyo escaneo se
  /// canceló sigue en segundo plano y deja el resultado listo para el
  /// siguiente. [forceRefresh] salta la caché.
  Future<List<Track>> getDownloadRecoveryCatalog(
      {bool forceRefresh = false}) async {
    final session = currentSessionKey;
    if (!connected || offlineMode) {
      throw StateError('Conecta el servidor para recuperar descargas.');
    }
    final cached = _recoveryCatalog;
    if (!forceRefresh &&
        cached != null &&
        cached.session == session &&
        recoveryClock().difference(cached.at) <
            NavidromeService.recoveryCatalogTtl) {
      return cached.tracks;
    }
    final inFlight = _recoveryInFlight;
    if (!forceRefresh && inFlight != null && inFlight.session == session) {
      return inFlight.future;
    }
    final future = _downloadRecoveryCatalog(session);
    final pending = (session: session, future: future);
    _recoveryInFlight = pending;
    try {
      return await future;
    } finally {
      if (identical(_recoveryInFlight, pending)) _recoveryInFlight = null;
    }
  }

  Future<List<Track>> _downloadRecoveryCatalog(String? session) async {
    final tracks = <Track>[];
    for (var offset = 0;; offset += 500) {
      final page = await _fetchTracks(limit: 500, offset: offset)
          .timeout(const Duration(seconds: 15));
      if (session != currentSessionKey || !connected || offlineMode) {
        throw StateError('La sesión cambió durante el escaneo.');
      }
      tracks.addAll(page);
      if (page.length < 500) break;
    }
    final frozen = List<Track>.unmodifiable(tracks);
    _recoveryCatalog = (session: session, at: recoveryClock(), tracks: frozen);
    return frozen;
  }

  @override
  Future<List<Track>> getTracks(
          {String? artist, String? album, int limit = 500, int offset = 0}) =>
      _readLibrary(
          key: 'tracks',
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
      'c': _clientName,
      'f': 'json',
      'songCount': limit.toString(),
      'songOffset': offset.toString(),
    });

    final subsonicResp = await _getEnvelope(uri);

    final songsList =
        NavidromeService._asListOrNull(subsonicResp['searchResult3']?['song']);
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
      'c': _clientName,
      'f': 'json',
      'id': albumId,
    });

    final data = await _getEnvelope(uri);
    final albumData = data['album'];

    if (albumData == null) throw Exception('Album not found');
    final map = albumData as Map<String, dynamic>;
    return Album.fromJson(map,
        coverArtUrl: _coverArtUrl(map['coverArt'], salt, token));
  }

  @override
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
      'c': _clientName,
      'f': 'json',
      'type': type,
      'size': limit.toString(),
      'offset': offset.toString(),
    });

    final data = await _getEnvelope(uri);
    final albumsList =
        NavidromeService._asListOrNull(data['albumList2']?['album']);

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
  @override
  Future<List<Track>> getAlbumTracks(String albumId) async {
    if (!_connected) throw Exception('Not connected');
    final (salt, token) = _auth();
    final uri = Uri.parse('$_url/rest/getAlbum.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': _clientName,
      'f': 'json',
      'id': albumId,
    });
    final data = await _getEnvelope(uri);
    final album = data['album'] as Map<String, dynamic>?;
    if (album == null) return [];
    final entries =
        NavidromeService._asListOrNull(album['song'] ?? album['entry']);
    if (entries == null) return [];
    return entries
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
    final failed = _artistFailedAt[artistId];
    if (failed != null &&
        DateTime.now().difference(failed) < const Duration(seconds: 30)) {
      return null;
    }
    return _artistInFlight[artistId] ??=
        _fetchArtist(artistId).whenComplete(() {
      // Bloque con llaves: devolver el Future quitado haría que se esperara a sí mismo.
      _artistInFlight.remove(artistId);
    });
  }

  Future<Artist?> _fetchArtist(String artistId) async {
    try {
      final (salt, token) = _auth();
      final uri =
          Uri.parse('$_url/rest/getArtist.view').replace(queryParameters: {
        'u': _user!,
        's': salt,
        't': token,
        'v': '1.16.1',
        'c': _clientName,
        'f': 'json',
        'id': artistId,
      });
      final data = await _getEnvelope(uri);
      final artistJson = data['artist'] as Map<String, dynamic>?;
      if (artistJson == null) return null;
      final artist = Artist.fromJson(
        artistJson,
        coverArtUrl: _coverArtUrl(artistJson['coverArt'], salt, token),
      );
      _artistCache[artistId] = artist;
      _artistFailedAt.remove(artistId);
      return artist;
    } catch (e) {
      debugPrint('NavidromeService.getArtist error: $e');
      _artistFailedAt[artistId] = DateTime.now();
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
      'c': _clientName,
      'f': 'json',
      'id': artistId,
    });
    final data = await _getEnvelope(uri);
    final artist = data['artist'] as Map<String, dynamic>?;
    if (artist == null) return [];
    final list = NavidromeService._asListOrNull(artist['album']);
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
      'c': _clientName,
      'f': 'json',
      'id': artistId,
    });
    final data = await _getEnvelope(uri);
    final artist = data['artist'] as Map<String, dynamic>?;
    if (artist == null) return [];
    final artistName = artist['name'] as String? ?? '';

    // Buscamos canciones del artista (search3 con query = nombre del artista).
    final searchUri =
        Uri.parse('$_url/rest/search3.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': _clientName,
      'f': 'json',
      'query': artistName,
      'songCount': '50',
      'albumCount': '0',
      'artistCount': '0',
    });
    final searchData = await _getEnvelope(searchUri);
    final result = searchData['searchResult3'] as Map<String, dynamic>?;
    if (result == null) return [];
    final songs = NavidromeService._asList(result['song']);
    return songs
        .map((j) => Track.fromJson(j as Map<String, dynamic>,
            albumArtUrl: _coverArtUrl(j['coverArt'], salt, token)))
        .toList();
  }

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
        '&s=$salt&t=$token&v=1.16.1&c=$_clientName'
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

    // Subsonic responde 200 con JSON/XML cuando falla (credenciales, id...):
    // eso no es audio y no debe guardarse como tal.
    final contentType = (response.headers['content-type'] ?? '').toLowerCase();
    if (contentType.contains('json') ||
        contentType.contains('xml') ||
        contentType.startsWith('text/')) {
      throw const DownloadException(
        'Server returned an error instead of audio',
        category: DownloadFailureCategory.serverError,
      );
    }

    final totalBytes = response.contentLength;
    int receivedBytes = 0;
    var checkedFirstChunk = false;

    IOSink? sink;
    StreamSubscription<List<int>>? subscription;
    try {
      if (!await destinationFile.parent.exists()) {
        await destinationFile.parent.create(recursive: true);
      }
      sink = destinationFile.openWrite();

      final completer = Completer<void>();

      // Timeout por inactividad (sin datos durante [timeout]), no de toda la
      // transferencia: un FLAC grande en una red lenta debe poder terminar.
      Timer? idleTimer;
      void armIdleTimer() {
        idleTimer?.cancel();
        idleTimer = Timer(timeout, () {
          subscription?.cancel();
          if (!completer.isCompleted) {
            completer.completeError(TimeoutException('idle', timeout));
          }
        });
      }

      armIdleTimer();
      subscription = response.stream.listen(
        (chunk) {
          armIdleTimer();
          if (!checkedFirstChunk && chunk.isNotEmpty) {
            checkedFirstChunk = true;
            // Ningún formato de audio empieza por `{` ni `<` (JSON/XML de error).
            var i = 0;
            while (i < chunk.length && (chunk[i] <= 0x20)) {
              i++;
            }
            if (i < chunk.length && (chunk[i] == 0x7B || chunk[i] == 0x3C)) {
              subscription?.cancel();
              if (!completer.isCompleted) {
                completer.completeError(const DownloadException(
                  'Server returned an error instead of audio',
                  category: DownloadFailureCategory.serverError,
                ));
              }
              return;
            }
          }
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

      try {
        await completer.future;
      } finally {
        idleTimer?.cancel();
      }
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
      await _get(Uri.parse('$_url/rest/scrobble.view').replace(
        queryParameters: {
          'u': _user!,
          's': salt,
          't': token,
          'v': '1.16.1',
          'c': 'CrotoWave',
          'f': 'json',
          'id': trackId,
          'submission': 'false',
        },
      ));
    } catch (_) {}
  }

  /// Colas persistentes por cuenta (`scrobble_queue_<scope>.json`). Se abren
  /// una sola vez por cuenta aunque varias operaciones las pidan a la vez.
  final Map<String, Future<ScrobbleQueue?>> _scrobbleQueues = {};

  /// Archivo de la cola en pruebas (sin path_provider).
  @visibleForTesting
  File? scrobbleQueueFileOverride;

  /// Cuenta de una operación de scrobble, fijada al empezarla: lo que se
  /// enviaba para A nunca sale con las credenciales de B.
  _ScrobbleSession? _pinScrobbleSession() {
    final url = _url, user = _user, pass = _pass;
    if (url == null || user == null || pass == null) return null;
    return (url: url, user: user, pass: pass);
  }

  bool _isCurrentScrobbleSession(_ScrobbleSession session) =>
      _connected &&
      _url == session.url &&
      _user == session.user &&
      _pass == session.pass;

  Future<ScrobbleQueue?> _scrobbleQueueFor(_ScrobbleSession session) async {
    final scope =
        OfflineCacheService.safeScopeSegment('${session.url}|${session.user}');
    final queue =
        await (_scrobbleQueues[scope] ??= _openScrobbleQueue(session));
    // Sin archivo (path_provider falló): no se recuerda el fallo, se reintenta.
    if (queue == null) unawaited(_scrobbleQueues.remove(scope));
    return queue;
  }

  /// Archivo de la cuenta de [session], no de la que esté activa al terminar la
  /// espera de path_provider. Mismo criterio que [_resolveScopedFile].
  Future<ScrobbleQueue?> _openScrobbleQueue(_ScrobbleSession session) async {
    final override = scrobbleQueueFileOverride;
    if (override != null) return ScrobbleQueue(override);
    try {
      final dir = await getAppDataDirectory();
      final userScope = OfflineCacheService.safeScopeSegment(
          '${session.url}|${session.user}');
      final byUser = File('${dir.path}/scrobble_queue_$userScope.json');
      if (await byUser.exists()) return ScrobbleQueue(byUser);
      final serverScope = OfflineCacheService.safeScopeSegment(session.url);
      final legacy = File('${dir.path}/scrobble_queue_$serverScope.json');
      return ScrobbleQueue(await legacy.exists() ? legacy : byUser);
    } catch (_) {
      return null;
    }
  }

  /// Envía una escucha con su hora original usando la cuenta fijada en
  /// [session]. `true` solo si el servidor respondió un envelope Subsonic con
  /// `status=ok`: un HTTP 2xx con `status=failed` es un rechazo.
  Future<bool> _sendScrobble(
      _ScrobbleSession session, String trackId, int timeMs) async {
    if (!_isCurrentScrobbleSession(session)) return false;
    try {
      final salt = _randomSalt();
      final uri = Uri.parse('${session.url}/rest/scrobble.view').replace(
        queryParameters: {
          'u': session.user,
          's': salt,
          't': _md5('${session.pass}$salt'),
          'v': '1.16.1',
          'c': 'CrotoWave',
          'f': 'json',
          'id': trackId,
          'time': timeMs.toString(),
          'submission': 'true',
        },
      );
      final response = await _get(uri, timeout: const Duration(seconds: 15));
      parseSubsonicEnvelope(response, requireOk: true);
      return true;
    } catch (_) {
      // Un fallo (de red o rechazado) al informar una escucha no debe cortar el
      // audio; el evento se conserva en la cola.
      return false;
    }
  }

  /// Informa una escucha. Si no hay conexión o falla, queda en cola y se envía
  /// al reconectar (con la hora en que ocurrió).
  Future<void> scrobble(String trackId) async {
    final timeMs = DateTime.now().millisecondsSinceEpoch;
    final session = _pinScrobbleSession();
    if (session == null) return;
    final queue = await _scrobbleQueueFor(session);
    if (queue != null && await queue.pendingCount() > 0) {
      // Mantener el orden: primero lo pendiente.
      await queue.add(trackId, timeMs);
      await _flushScrobbles(session, queue);
      return;
    }
    if (await _sendScrobble(session, trackId, timeMs)) return;
    await queue?.add(trackId, timeMs);
  }

  /// Vacía la cola de scrobbles pendientes (al reconectar).
  Future<int> flushScrobbles() async {
    if (!_connected) return 0;
    final session = _pinScrobbleSession();
    if (session == null) return 0;
    final queue = await _scrobbleQueueFor(session);
    if (queue == null) return 0;
    return _flushScrobbles(session, queue);
  }

  /// Si la cuenta cambia a mitad del vaciado, el siguiente envío devuelve
  /// `false` y la cola se detiene con lo pendiente intacto.
  Future<int> _flushScrobbles(_ScrobbleSession session, ScrobbleQueue queue) =>
      queue.flush((item) => _sendScrobble(session, item.trackId, item.timeMs));
}

typedef _ScrobbleSession = ({String url, String user, String pass});
