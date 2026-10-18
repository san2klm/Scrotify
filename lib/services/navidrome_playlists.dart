part of 'navidrome_service.dart';

/// Playlists: consulta, creación, edición, portada y orden.
mixin _NavidromePlaylists on _NavidromeBase {
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
      'c': _clientName,
      'f': 'json',
    });

    final response = await _get(uri);
    final body = _playlistResponse(response);
    final list = NavidromeService._asListOrNull(body['playlists']?['playlist']);

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
      'c': _clientName,
      'f': 'json',
      'name': cleanName,
    });
    final data = _playlistResponse(await _get(uri));
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

  @override
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
    buffer.write('&s=$salt&t=$token&v=1.16.1&c=$_clientName&f=json');
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

    _playlistResponse(await _get(Uri.parse(buffer.toString())));
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
    // `createPlaylist` reemplaza la lista entera: si la pantalla mostraba una
    // copia parcial (p. ej. solo lo descargado tras un timeout), reordenarla
    // borraría del servidor las canciones que no se veían.
    if (!_sameSongs(await _fetchPlaylistTracks(playlistId), orderedSongIds)) {
      throw Exception('La playlist cambió o no se cargó completa. '
          'Recárgala antes de reordenar.');
    }
    final (salt, token) = _auth();
    final buffer = StringBuffer('$_url/rest/createPlaylist.view');
    buffer.write('?u=${Uri.encodeQueryComponent(_user!)}');
    buffer.write('&s=$salt&t=$token&v=1.16.1&c=$_clientName&f=json');
    buffer.write('&playlistId=${Uri.encodeQueryComponent(playlistId)}');
    for (final id in orderedSongIds) {
      buffer.write('&songId=${Uri.encodeQueryComponent(id)}');
    }
    _playlistResponse(await _get(Uri.parse(buffer.toString())));
    bumpPlaylists();
  }

  static bool _sameSongs(List<Track> server, List<String> ids) {
    if (server.length != ids.length) return false;
    final counts = <String, int>{};
    for (final track in server) {
      counts[track.id] = (counts[track.id] ?? 0) + 1;
    }
    for (final id in ids) {
      final left = (counts[id] ?? 0) - 1;
      if (left < 0) return false;
      counts[id] = left;
    }
    return true;
  }

  /// Quita la primera aparición de [trackId] de la playlist. El índice se
  /// calcula sobre la lista real del servidor, nunca sobre una copia local
  /// que podría estar incompleta y apuntar a otra canción.
  Future<bool> removeTrackFromPlaylist({
    required String playlistId,
    required String trackId,
  }) async {
    final index = (await _fetchPlaylistTracks(playlistId))
        .indexWhere((track) => track.id == trackId);
    if (index < 0) return false;
    await updatePlaylist(playlistId: playlistId, songIndexesToRemove: [index]);
    return true;
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
      'c': _clientName,
      'f': 'json',
      'id': playlistId,
    });
    await _get(uri);
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
      'c': _clientName,
      'f': 'json',
      'id': playlistId,
    });
    final response = await _get(uri);
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
      'c': _clientName,
      'f': 'json',
      'id': playlistId,
    });
    final response = await _get(uri);
    final data = _playlistResponse(response);
    final entries = NavidromeService._asListOrNull(data['playlist']?['entry']);
    if (entries == null) return [];
    return entries
        .map((j) => Track.fromJson(j as Map<String, dynamic>,
            albumArtUrl: _coverArtUrl(j['coverArt'], salt, token)))
        .toList();
  }
}
