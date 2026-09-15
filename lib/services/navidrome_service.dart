import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'settings_controller.dart';

class Track {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String duration;
  final String? albumArtUrl;

  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.albumArtUrl,
  });

  factory Track.fromJson(Map<String, dynamic> json, {String? albumArtUrl}) {
    final rawDuration = json['duration'];
    final duration = rawDuration is num
        ? rawDuration.toString()
        : (rawDuration as String? ?? '');

    final coverArt = albumArtUrl ?? json['coverArt'] as String?;

    return Track(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? 'Unknown',
      artist: (json['artist'] as String?) ?? 'Unknown',
      album: (json['album'] as String?) ?? 'Unknown',
      duration: duration,
      albumArtUrl: coverArt,
    );
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
      title: (json['name'] as String?) ?? (json['title'] as String?) ?? 'Unknown',
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

  Playlist({
    required this.id,
    required this.name,
    this.coverArtUrl,
    required this.songCount,
    required this.duration,
  });

  factory Playlist.fromJson(Map<String, dynamic> json, {String? coverArtUrl}) {
    return Playlist(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? 'Unknown',
      coverArtUrl: coverArtUrl ?? json['coverArt'] as String?,
      songCount: (json['songCount'] as num?)?.toInt() ?? 0,
      duration: (json['duration'] as num?)?.toInt() ?? 0,
    );
  }
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

class NavidromeService with ChangeNotifier {
  NavidromeService({SettingsController? settings}) {
    if (settings != null) {
      _settings = settings;
      _coverArtSize = settings.coverArtSize;
      settings.addListener(_syncFromSettings);
    }
  }

  String? _url;
  String? _user;
  String? _pass;
  bool _connected = false;
  late http.Client _client;

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
  bool get connected => _connected;

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

  String? _coverArtUrl(Object? coverArtId, String salt, String token,
      {int? size}) {
    if (coverArtId == null) return null;
    return '$_url/rest/getCoverArt.view'
        '?u=${Uri.encodeQueryComponent(_user!)}'
        '&s=$salt&t=$token&v=1.16.1&c=Psysonic'
        '&id=${Uri.encodeQueryComponent(coverArtId.toString())}'
        '&size=${size ?? _coverArtSize}';
  }

  Future<void> connectByUrl(String url, String user, String pass) async {
    var processedUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;

    if (!processedUrl.startsWith('http://') && !processedUrl.startsWith('https://')) {
      processedUrl = 'https://$processedUrl';
    }

    _url = processedUrl;
    _user = user;
    _pass = pass;

    debugPrint('Connecting to $_url with user: $user');

    _client = http.Client();

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

      final response = await _client.get(uri);

      debugPrint('Auth response status: ${response.statusCode}');
      debugPrint('Auth response body: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception('Server error: Status ${response.statusCode}. '
            'Check your Navidrome URL and make sure the API is accessible. '
            'Response: ${response.body.substring(0, min(50, response.body.length))}');
      }

      try {
        final data = jsonDecode(response.body);
        
        if (data['subsonic-response']['status'] == 'ok') {
          _connected = true;
          await _loadPins();
          notifyListeners();
        } else {
          throw Exception('Authentication failed: ${data['subsonic-response']['error']['message']}');
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

  Future<List<dynamic>> getMusicFolders() async {
    if (!_connected) throw Exception('Not connected');
    final salt = _randomSalt();
    final token = _md5('$_pass$salt');

    final uri = Uri.parse('$_url/rest/getMusicFolders.view').replace(queryParameters: {
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

    final uri = Uri.parse('$_url/rest/getArtists.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
    });

    final response = await _client.get(uri);
    debugPrint('getArtists response: ${response.body}');
    final data = jsonDecode(response.body);

    dynamic indexes = data['subsonic-response']['artists']?['index'];

    if (indexes == null) {
      return [];
    }

    final List<dynamic> allArtists = [];
    for (var idx in indexes) {
      final artistsList = idx['artist'] as List?;
      if (artistsList != null) {
        allArtists.addAll(artistsList);
      }
    }

    debugPrint('getArtists result count: ${allArtists.length}');
    return allArtists;
  }

  Future<List<dynamic>> getIndexes() async {
    if (!_connected) throw Exception('Not connected');
    final salt = _randomSalt();
    final token = _md5('$_pass$salt');

    final uri = Uri.parse('$_url/rest/getIndexes.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
    });

    final response = await _client.get(uri);
    debugPrint('getIndexes response: ${response.body}');
    final data = jsonDecode(response.body);

    dynamic indexes = data['subsonic-response']['indexes'];

    if (indexes == null) {
      return [];
    }

    if (indexes is Map && indexes.containsKey('index')) {
      final list = indexes['index'] as List?;
      debugPrint('getIndexes result (from index): $list');
      return list ?? [];
    }

    if (indexes is List) {
      debugPrint('getIndexes result: $indexes');
      return indexes;
    }

    debugPrint('getIndexes unknown format: $indexes');
    return [];
  }

  (String, String) _auth() {
    final salt = _randomSalt();
    return (salt, _md5('$_pass$salt'));
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
    final uri = Uri.parse('$_url/rest/search3.view').replace(queryParameters: params);

    final response = await _client.get(uri);
    final data = jsonDecode(response.body);
    final result = data['subsonic-response']?['searchResult3'] as Map<String, dynamic>?;
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
  Future<List<Playlist>> getPlaylists() async {
    if (!_connected) throw Exception('Not connected');
    final (salt, token) = _auth();

    final uri = Uri.parse('$_url/rest/getPlaylists.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
    });

    final response = await _client.get(uri);
    final data = jsonDecode(response.body);
    final list = data['subsonic-response']?['playlists']?['playlist'] as List?;
    if (list == null) return [];

    return list
        .map((j) => Playlist.fromJson(j as Map<String, dynamic>,
            coverArtUrl: _coverArtUrl(j['coverArt'], salt, token)))
        .toList();
  }

  Future<Playlist?> createPlaylist(String name) async {
    if (!_connected) throw Exception('Not connected');
    final (salt, token) = _auth();

    final uri = Uri.parse('$_url/rest/createPlaylist.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
      'name': name,
    });

    final response = await _client.get(uri);
    final data = jsonDecode(response.body);
    final p = data['subsonic-response']?['playlist'];
    if (p == null) return null;
    return Playlist.fromJson(p as Map<String, dynamic>,
        coverArtUrl: _coverArtUrl(p['coverArt'], salt, token));
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

    await _client.get(Uri.parse(buffer.toString()));
  }

  Future<void> deletePlaylist(String playlistId) async {
    if (!_connected) throw Exception('Not connected');
    final (salt, token) = _auth();
    final uri = Uri.parse('$_url/rest/deletePlaylist.view').replace(queryParameters: {
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

  Future<Playlist?> getPlaylist(String playlistId) async {
    if (!_connected) throw Exception('Not connected');
    final (salt, token) = _auth();
    final uri = Uri.parse('$_url/rest/getPlaylist.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
      'id': playlistId,
    });
    final response = await _client.get(uri);
    final data = jsonDecode(response.body);
    final p = data['subsonic-response']?['playlist'];
    if (p == null) return null;
    return Playlist.fromJson(p as Map<String, dynamic>,
        coverArtUrl: _coverArtUrl(p['coverArt'], salt, token));
  }

  Future<List<Track>> getPlaylistTracks(String playlistId) async {
    if (!_connected) throw Exception('Not connected');
    final (salt, token) = _auth();
    final uri = Uri.parse('$_url/rest/getPlaylist.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
      'id': playlistId,
    });
    final response = await _client.get(uri);
    final data = jsonDecode(response.body);
    final entries = data['subsonic-response']?['playlist']?['entry'] as List?;
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

    final uri = Uri.parse('$_url/rest/$endpoint').replace(queryParameters: params);
    await _client.get(uri);
  }

  Future<List<Track>> getStarred() async {
    if (!_connected) throw Exception('Not connected');
    final (salt, token) = _auth();
    final uri = Uri.parse('$_url/rest/getStarred2.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
    });
    final response = await _client.get(uri);
    final data = jsonDecode(response.body);
    final songs = data['subsonic-response']?['starred2']?['song'] as List?;
    if (songs == null) return [];
    final tracks = songs
        .map((j) => Track.fromJson(j as Map<String, dynamic>,
            albumArtUrl: _coverArtUrl(j['coverArt'], salt, token)))
        .toList();
    _starredIds
      ..clear()
      ..addAll(tracks.map((t) => t.id));
    return tracks;
  }

  final Set<String> _starredIds = {};

  bool isStarred(String id) => _starredIds.contains(id);

  // ---------------------------------------------------------------------------
  // Fijar (pin) playlists — persistido en disco vía path_provider
  // ---------------------------------------------------------------------------
  final Set<String> _pinnedPlaylistIds = {};

  bool isPinnedPlaylist(String id) => _pinnedPlaylistIds.contains(id);

  List<String> get pinnedPlaylistIds =>
      _pinnedPlaylistIds.toList()..sort();

  void togglePinPlaylist(String id) {
    if (_pinnedPlaylistIds.contains(id)) {
      _pinnedPlaylistIds.remove(id);
    } else {
      _pinnedPlaylistIds.add(id);
    }
    notifyListeners();
    _savePins();
  }

  Future<void> _loadPins() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/pinned_playlists.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final list = jsonDecode(content) as List;
        _pinnedPlaylistIds
          ..clear()
          ..addAll(list.cast<String>());
      }
    } catch (_) {
      // Silently ignore — pins are a convenience, not critical.
    }
  }

  Future<void> _savePins() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/pinned_playlists.json');
      await file.writeAsString(jsonEncode(_pinnedPlaylistIds.toList()));
    } catch (_) {}
  }

  Future<void> toggleStar(Track track) async {
    final wasStarred = _starredIds.contains(track.id);
    // Actualización optimista: reflejamos el cambio de inmediato para que la
    // UI no espere al round-trip de red, y revertimos si algo falla.
    if (wasStarred) {
      _starredIds.remove(track.id);
    } else {
      _starredIds.add(track.id);
    }
    notifyListeners();

    try {
      if (wasStarred) {
        await unstar(track.id);
      } else {
        await star(track.id);
      }
    } catch (_) {
      if (wasStarred) {
        _starredIds.add(track.id);
      } else {
        _starredIds.remove(track.id);
      }
      notifyListeners();
    }
  }

  Future<List<Track>> getTracks({
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
    debugPrint('getTracks search3 body: ${response.body}');

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

    tracks.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
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

    final uri = Uri.parse('$_url/rest/getAlbumList2.view').replace(queryParameters: {
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

  /// Devuelve los álbumes de un artista (getArtist.view).
  Future<List<Album>> getArtistAlbums(String artistId) async {
    if (!_connected) throw Exception('Not connected');
    final (salt, token) = _auth();
    final uri = Uri.parse('$_url/rest/getArtist.view').replace(queryParameters: {
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
    final artist = data['subsonic-response']?['artist'] as Map<String, dynamic>?;
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
    final uri = Uri.parse('$_url/rest/getArtist.view').replace(queryParameters: {
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
    final artist = data['subsonic-response']?['artist'] as Map<String, dynamic>?;
    if (artist == null) return [];
    final artistName = artist['name'] as String? ?? '';

    // Buscamos canciones del artista (search3 con query = nombre del artista).
    final searchUri = Uri.parse('$_url/rest/search3.view').replace(queryParameters: {
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
    final result = searchData['subsonic-response']?['searchResult3'] as Map<String, dynamic>?;
    if (result == null) return [];
    final songs = _asList(result['song']);
    return songs
        .map((j) => Track.fromJson(j as Map<String, dynamic>,
            albumArtUrl: _coverArtUrl(j['coverArt'], salt, token)))
        .toList();
  }

  String getStreamUrl(String trackId, {AudioQuality? quality}) {
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
    return url;
  }

  void disconnect() async {
    _connected = false;
    _url = null;
    _user = null;
    _pass = null;
    _client.close();
    notifyListeners();
  }
}