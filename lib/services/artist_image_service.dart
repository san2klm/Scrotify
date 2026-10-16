import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Busca una foto apaisada del artista, con caché en memoria.
///
/// Orden: 1) lo que dé el propio servidor ([serverLookup], p. ej.
/// `getArtistInfo2`); 2) TheAudioDB y 3) Deezer, **solo si**
/// [allowThirdParty] es `true`. Los terceros reciben el nombre del artista, por
/// eso el ajuste es opt-in.
class ArtistImageService {
  ArtistImageService(
      {http.Client? client, this.timeout = const Duration(seconds: 8)})
      : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  final Map<String, String?> _cache = {};
  final Map<String, Future<String?>> _inFlight = {};

  /// Para pruebas: vacía la caché.
  @visibleForTesting
  void clear() {
    _cache.clear();
    _inFlight.clear();
  }

  Future<String?> lookup(
    String artistName, {
    Future<String?> Function()? serverLookup,
    bool allowThirdParty = false,
  }) {
    final key = '${allowThirdParty ? 1 : 0}|${artistName.trim().toLowerCase()}';
    if (_cache.containsKey(key)) return Future.value(_cache[key]);
    return _inFlight[key] ??=
        _resolve(artistName, serverLookup, allowThirdParty).then((url) {
      _cache[key] = url;
      return url;
    }).whenComplete(() {
      // Bloque (no `=>`): devolver el propio Future haría que whenComplete
      // se esperara a sí mismo.
      _inFlight.remove(key);
    });
  }

  Future<String?> _resolve(String name,
      Future<String?> Function()? serverLookup, bool allowThirdParty) async {
    if (serverLookup != null) {
      try {
        final url = await serverLookup().timeout(timeout);
        if (url != null && url.trim().isNotEmpty) return url;
      } catch (e) {
        debugPrint('ArtistImageService: servidor sin imagen ($e)');
      }
    }
    if (!allowThirdParty) return null;
    return await _audioDb(name) ?? await _deezer(name);
  }

  Future<String?> _audioDb(String name) async {
    try {
      final uri = Uri.parse(
          'https://www.theaudiodb.com/api/v1/json/2/search.php?s=${Uri.encodeQueryComponent(name)}');
      final res = await _client.get(uri).timeout(timeout);
      if (res.statusCode != 200) return null;
      final artists = jsonDecode(res.body)['artists'];
      if (artists is List && artists.isNotEmpty) {
        final fanart = artists[0]['strArtistFanart']?.toString().trim();
        if (fanart != null && fanart.isNotEmpty) return fanart;
      }
    } catch (e) {
      debugPrint('ArtistImageService: TheAudioDB falló ($e)');
    }
    return null;
  }

  Future<String?> _deezer(String name) async {
    try {
      final uri = Uri.parse(
          'https://api.deezer.com/search/artist?q=${Uri.encodeQueryComponent(name)}');
      final res = await _client.get(uri).timeout(timeout);
      if (res.statusCode != 200) return null;
      final items = jsonDecode(res.body)['data'];
      if (items is List && items.isNotEmpty) {
        final img = (items[0]['picture_xl'] ?? items[0]['picture_big'])
            ?.toString()
            .trim();
        if (img != null && img.isNotEmpty) return img;
      }
    } catch (e) {
      debugPrint('ArtistImageService: Deezer falló ($e)');
    }
    return null;
  }
}
