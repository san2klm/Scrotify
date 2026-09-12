import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';

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

  factory Album.fromJson(Map<String, dynamic> json) {
    return Album(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      coverArtUrl: json['coverArtUrl'] as String?,
      trackCount: (json['trackCount'] as num?)?.toInt() ?? 0,
      year: (json['year'] as num?)?.toInt() ?? 0,
    );
  }
}

class NavidromeService with ChangeNotifier {
  String? _url;
  String? _user;
  String? _pass;
  bool _connected = false;
  late http.Client _client;

  bool get connected => _connected;

  String _randomSalt() {
    final rnd = Random.secure();
    return List.generate(16, (_) => rnd.nextInt(16).toRadixString(16)).join();
  }

  String _md5(String input) {
    return md5.convert(utf8.encode(input)).toString();
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

  Future<List<dynamic>> search(String query) async {
    if (!_connected) throw Exception('Not connected');
    final salt = _randomSalt();
    final token = _md5('$_pass$salt');

    final uri = Uri.parse('$_url/rest/search3.view').replace(queryParameters: {
      'query': query,
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
    });

    final response = await _client.get(uri);
    final data = jsonDecode(response.body);
    final results = data['subsonic-response']['searchResult3'] as List?;
    return results ?? [];
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
      final coverArtId = map['coverArt'] as String?;
      String? albumArtUrl;
      if (coverArtId != null) {
        albumArtUrl = '$_url/rest/getCoverArt.view'
            '?u=${Uri.encodeQueryComponent(_user!)}'
            '&s=$salt&t=$token&v=1.16.1&c=Psysonic&id=${Uri.encodeQueryComponent(coverArtId)}';
      }
      tracks.add(Track.fromJson(map, albumArtUrl: albumArtUrl));
    }

    tracks.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return tracks;
  }

  Future<Album> getAlbumInfo(String albumId) async {
    if (!_connected) throw Exception('Not connected');
    final salt = _randomSalt();
    final token = _md5('$_pass$salt');

    final uri = Uri.parse('$_url/rest/getAlbumInfo.view').replace(queryParameters: {
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
    final albumData = data['subsonic-response']['album'];

    if (albumData == null) throw Exception('Album not found');
    return Album.fromJson(albumData as Map<String, dynamic>);
  }

  Future<List<Album>> getAlbums({
    String? artist,
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_connected) throw Exception('Not connected');
    final salt = _randomSalt();
    final token = _md5('$_pass$salt');

    final uri = Uri.parse('$_url/rest/getAlbums.view').replace(queryParameters: {
      'u': _user!,
      's': salt,
      't': token,
      'v': '1.16.1',
      'c': 'Psysonic',
      'f': 'json',
      'limit': limit.toString(),
      'offset': offset.toString(),
      if (artist != null) 'artist': artist,
    });

    final response = await _client.get(uri);
    final data = jsonDecode(response.body);
    final albumsList = data['subsonic-response']['album'] as List?;

    if (albumsList == null) return [];

    final List<Album> albums = [];
    for (var albumJson in albumsList) {
      albums.add(Album.fromJson(albumJson as Map<String, dynamic>));
    }
    return albums;
  }

  String getStreamUrl(String trackId) {
    final salt = _randomSalt();
    final token = _md5('$_pass$salt');
    return '$_url/rest/stream.view'
        '?u=${Uri.encodeQueryComponent(_user!)}'
        '&s=$salt&t=$token&v=1.16.1&c=Psysonic'
        '&id=${Uri.encodeQueryComponent(trackId)}';
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