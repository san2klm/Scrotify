part of 'navidrome_service.dart';

/// Favoritos, valoraciones, fijados y artistas seguidos o excluidos.
mixin _NavidromeFavorites on _NavidromeBase {
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
}
