import 'dart:convert';
import 'package:http/http.dart' as http;

/// Busca carátulas en fuentes externas (iTunes y Deezer) cuando Navidrome
/// no tiene portada para una canción o álbum.
///
/// No requiere claves de API. Los resultados exitosos se cachean en memoria.
/// Los fallos de red NO se cachean para permitir reintentos.
class CoverFallbackService {
  CoverFallbackService._();
  static final CoverFallbackService instance = CoverFallbackService._();

  final Map<String, String?> _cache = {};
  final Map<String, Future<String?>> _pending = {};

  static const _timeout = Duration(seconds: 8);

  /// Devuelve la URL de una carátula externa o `null` si no se encontró.
  ///
  /// [size] es el lado deseado en píxeles.
  Future<String?> findCover({
    String? artist,
    String? album,
    String? title,
    int size = 600,
  }) {
    // Validar size
    final safeSize = size.clamp(100, 2000);

    final cleanArtist = _clean(artist);
    final cleanAlbum = _clean(album);
    final cleanTitle = _clean(title);
    if (cleanArtist.isEmpty && cleanAlbum.isEmpty && cleanTitle.isEmpty) {
      return Future.value(null);
    }

    final key = '$cleanArtist|$cleanAlbum|$cleanTitle|$safeSize';
    if (_cache.containsKey(key)) {
      return Future.value(_cache[key]);
    }
    if (_pending.containsKey(key)) {
      return _pending[key]!;
    }

    final future = _search(cleanArtist, cleanAlbum, cleanTitle, safeSize).then((url) {
      if (url != null && url.isNotEmpty) {
        _cache[key] = url;
      }
      // No cachear null: permitir reintento si falló la red o no hubo resultados
      return url;
    }).catchError((e) {
      // No cachear error: permitir reintento
      return null;
    }).whenComplete(() => _pending.remove(key));

    _pending[key] = future;
    return future;
  }

  /// Limpia la caché (útil para testing/debug).
  void clearCache() {
    _cache.clear();
    _pending.clear();
  }

  Future<String?> _search(
      String artist, String album, String title, int size) async {
    // 1) iTunes: búsqueda de álbum (la más fiable para portadas).
    if (artist.isNotEmpty && album.isNotEmpty) {
      final url = await _itunes('$artist $album', 'album', size);
      if (url != null) return url;
    }
    // 2) Deezer: búsqueda de álbum.
    if (artist.isNotEmpty && album.isNotEmpty) {
      final url = await _deezerAlbum('$artist $album', size);
      if (url != null) return url;
    }
    // 3) iTunes: búsqueda por canción (singles, temas sueltos).
    if (artist.isNotEmpty && title.isNotEmpty) {
      final url = await _itunes('$artist $title', 'song', size);
      if (url != null) return url;
    }
    // 4) Deezer: búsqueda por canción.
    if (artist.isNotEmpty && title.isNotEmpty) {
      final url = await _deezerTrack('$artist $title', size);
      if (url != null) return url;
    }
    // 5) Solo álbum (artista desconocido).
    if (album.isNotEmpty && artist.isEmpty) {
      final url = await _itunes(album, 'album', size) ??
          await _deezerAlbum(album, size);
      if (url != null) return url;
    }
    return null;
  }

  Future<String?> _itunes(String term, String entity, int size) async {
    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': term,
      'entity': entity,
      'limit': '1',
    });
    try {
      final res = await http.get(uri).timeout(_timeout);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final results = body['results'] as List?;
      if (results == null || results.isEmpty) return null;
      final art = results.first['artworkUrl100'] as String?;
      if (art == null) return null;
      // iTunes permite pedir el tamaño deseado cambiando 100x100bb.
      return art.replaceFirst('100x100bb', '${size}x${size}bb');
    } catch (_) {
      return null;
    }
  }

  Future<String?> _deezerAlbum(String query, int size) => _deezer(
        Uri.https('api.deezer.com', '/search/album', {'q': query, 'limit': '1'}),
        size,
      );

  Future<String?> _deezerTrack(String query, int size) => _deezer(
        Uri.https('api.deezer.com', '/search/track', {'q': query, 'limit': '1'}),
        size,
        albumKey: true,
      );

  Future<String?> _deezer(Uri uri, int size, {bool albumKey = false}) async {
    try {
      final res = await http.get(uri).timeout(_timeout);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final data = body['data'] as List?;
      if (data == null || data.isEmpty) return null;
      final first = data.first as Map<String, dynamic>;
      final container =
          albumKey ? (first['album'] as Map<String, dynamic>?) : first;
      if (container == null) return null;
      final field = size <= 250
          ? 'cover_medium'
          : size <= 500
              ? 'cover_big'
              : 'cover_xl';
      return (container[field] as String?) ??
          (container['cover_big'] as String?) ??
          (container['cover'] as String?);
    } catch (_) {
      return null;
    }
  }

  String _clean(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty || v.toLowerCase() == 'unknown') return '';
    return v;
  }
}