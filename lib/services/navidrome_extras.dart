part of 'navidrome_service.dart';

/// Letras, géneros, "escuchando ahora", chat del lobby y Jams del servidor.
mixin _NavidromeExtras on _NavidromeBase {
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
      final blocks = NavidromeService._asList(rawBlocks);
      final result = <StructuredLyricBlock>[];
      for (final b in blocks) {
        if (b is! Map) continue;
        final map = b as Map<String, dynamic>;
        final synced = map['synced'] == true;
        final lang = (map['lang'] as String?) ?? '';
        final rawLines = NavidromeService._asList(map['line']);
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
        final rawTracks = NavidromeService._asList(result['song'])
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
          for (final item in NavidromeService._asList(genresList)) {
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
}
