import 'package:flutter/material.dart';

/// Extrae un color de énfasis de una carátula.
///
/// Usa `ColorScheme.fromImageProvider` (cuantización de Material) y cachea el
/// resultado por clave (id de la pista o URL), porque decodificar la imagen
/// cuesta y la misma carátula se pide muchas veces.
class CoverPalette {
  CoverPalette({this.maxEntries = 64});

  final int maxEntries;
  final Map<String, Color?> _cache = {};

  /// Color de énfasis de [provider], o `null` si no se pudo decodificar.
  Future<Color?> accentFor(String key, ImageProvider provider,
      {Brightness brightness = Brightness.dark}) async {
    final cacheKey = '$key|${brightness.name}';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];
    Color? color;
    try {
      final scheme = await ColorScheme.fromImageProvider(
        provider: ResizeImage(provider, width: 96),
        brightness: brightness,
      );
      color = scheme.primary;
    } catch (_) {
      color = null; // imagen caída o no decodificable: se usa el tema
    }
    if (_cache.length >= maxEntries) _cache.remove(_cache.keys.first);
    _cache[cacheKey] = color;
    return color;
  }
}
