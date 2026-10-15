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
      'c': 'Scrotify',
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

    final response = await _get(uri);
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
      'c': 'Psysonic',
      'f': 'json',
      'id': albumId,
    });

    final response = await _get(uri);
    final data = jsonDecode(response.body);
    final albumData = data['subsonic-response']?['album'];

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
      'c': 'Psysonic',
      'f': 'json',
      'type': type,
      'size': limit.toString(),
      'offset': offset.toString(),
    });

    final response = await _get(uri);
    final data = jsonDecode(response.body);
    final albumsList = NavidromeService._asListOrNull(
        data['subsonic-response']?['albumList2']?['album']);

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
      'c': 'Psysonic',
      'f': 'json',
      'id': albumId,
    });
    final response = await _get(uri);
    final data = jsonDecode(response.body);
    final album = data['subsonic-response']?['album'] as Map<String, dynamic>?;
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
      final response = await _get(uri);
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
    final response = await _get(uri);
    final data = jsonDecode(response.body);
    final artist =
        data['subsonic-response']?['artist'] as Map<String, dynamic>?;
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
      'c': 'Psysonic',
      'f': 'json',
      'id': artistId,
    });
    final response = await _get(uri);
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
    final searchResponse = await _get(searchUri);
    final searchData = jsonDecode(searchResponse.body);
    final result = searchData['subsonic-response']?['searchResult3']
        as Map<String, dynamic>?;
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
          'c': 'Scrotify',
          'f': 'json',
          'id': trackId,
          'submission': 'false',
        },
      ));
    } catch (_) {}
  }

  /// Cola persistente por perfil (`scrobble_queue_<scope>.json`).
  ScrobbleQueue? _scrobbleQueue;
  String? _scrobbleQueueScope;

  /// Archivo de la cola en pruebas (sin path_provider).
  @visibleForTesting
  File? scrobbleQueueFileOverride;

  Future<ScrobbleQueue?> _scrobbleQueueFor() async {
    final scope = _scopedName('scrobble_queue.json');
    if (_scrobbleQueue != null && _scrobbleQueueScope == scope) {
      return _scrobbleQueue;
    }
    final file = scrobbleQueueFileOverride ??
        await _resolveScopedFile('scrobble_queue.json');
    if (file == null) return null;
    _scrobbleQueueScope = scope;
    return _scrobbleQueue = ScrobbleQueue(file);
  }

  /// Envía una escucha con su hora original. `true` si el servidor la aceptó.
  Future<bool> _sendScrobble(String trackId, int timeMs) async {
    if (!_connected) return false;
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
          'time': timeMs.toString(),
          'submission': 'true',
        },
      );
      final response = await _get(uri).timeout(const Duration(seconds: 15));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      // Un fallo de red al informar una escucha no debe cortar el audio.
      return false;
    }
  }

  /// Informa una escucha. Si no hay conexión o falla, queda en cola y se envía
  /// al reconectar (con la hora en que ocurrió).
  Future<void> scrobble(String trackId) async {
    final timeMs = DateTime.now().millisecondsSinceEpoch;
    final queue = await _scrobbleQueueFor();
    if (queue != null && queue.length > 0) {
      // Mantener el orden: primero lo pendiente.
      await queue.add(trackId, timeMs);
      await flushScrobbles();
      return;
    }
    if (await _sendScrobble(trackId, timeMs)) return;
    await queue?.add(trackId, timeMs);
  }

  /// Vacía la cola de scrobbles pendientes (al reconectar).
  Future<int> flushScrobbles() async {
    if (!_connected) return 0;
    final queue = await _scrobbleQueueFor();
    if (queue == null) return 0;
    return queue.flush((item) => _sendScrobble(item.trackId, item.timeMs));
  }
}
