import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'navidrome_service.dart';

/// Línea de letra con tiempo de inicio.
class LyricLine {
  final Duration start;
  final String text;

  const LyricLine({required this.start, required this.text});
}

/// Resultado unificado de letra, venga de Navidrome local o de LRCLIB.
class LyricsResult {
  /// Líneas ordenadas por [LyricLine.start].
  final List<LyricLine> lines;

  /// `true` si tiene tiempos (sincronizada), `false` si es texto plano.
  final bool synced;

  /// Origen: 'Navidrome' o 'LRCLIB'.
  final String source;

  /// `true` si la pista es instrumental (sin letra cantada).
  final bool instrumental;

  const LyricsResult({
    required this.lines,
    required this.synced,
    required this.source,
    this.instrumental = false,
  });

  String get plainText => lines.map((l) => l.text).join('\n');
}

/// Servicio de letras con prioridad: local de Navidrome > LRCLIB.
///
/// 1. Intenta `getLyricsBySongId` del servidor (embebidas o .lrc escaneados).
///    Si lo local es plano (sin tiempos), no se devuelve todavía: se sigue
///    buscando una versión sincronizada.
/// 2. Cae a `https://lrclib.net/api/get` (coincidencia exacta).
/// 3. Si sigue sin tiempos, busca en `https://lrclib.net/api/search`
///    una versión sincronizada del mismo tema.
/// 4. Como último recurso devuelve la mejor plana encontrada (o null).
class LyricsService {
  static final Map<String, Future<LyricsResult?>> _cache = {};

  static const _lrclibHeaders = {
    'Lrclib-Client': 'CrotoWave/1.0 (+https://github.com/Dante0Q/CrotoWave)',
    'User-Agent': 'CrotoWave/1.0',
    'Accept': 'application/json',
  };

  /// Devuelve la letra para [track] o `null` si no se encontró en ningún lado.
  /// El resultado se cachea por `track.id` en memoria.
  static Future<LyricsResult?> fetch({
    required NavidromeService nav,
    required Track track,
  }) {
    return _cache.putIfAbsent(track.id, () async {
      LyricsResult? plainFallback;

      // 1) Local de Navidrome (prioridad). Si es sincronizada, listo.
      try {
        final blocks = await nav.getLyricsBySongId(track.id);
        final synced = _pickSyncedBlock(blocks);
        if (synced != null) {
          debugPrint(
              'LyricsService: letra local Navidrome sincronizada (${synced.lines.length} líneas)');
          return LyricsResult(
            lines: _toLines(synced),
            synced: true,
            source: 'Navidrome',
          );
        }
        final first = _pickFirstBlock(blocks);
        if (first != null) {
          plainFallback = LyricsResult(
            lines: _toLines(first),
            synced: false,
            source: 'Navidrome',
          );
        }
      } catch (e) {
        debugPrint('LyricsService: error Navidrome local: $e');
      }

      // 2) LRCLIB exacto. Si trae tiempos, listo; si es instrumental, listo.
      try {
        final remote = await _fetchFromLrclib(track);
        if (remote != null) {
          if (remote.synced || remote.instrumental) {
            debugPrint(
                'LyricsService: letra LRCLIB exacta (${remote.lines.length} líneas, synced=${remote.synced})');
            return remote;
          }
          plainFallback ??= remote;
        }
      } catch (e) {
        debugPrint('LyricsService: error LRCLIB: $e');
      }

      // 3) La plana no sirve para seguir: buscar versión sincronizada.
      try {
        final synced = await _searchSyncedFromLrclib(track);
        if (synced != null) {
          debugPrint(
              'LyricsService: letra LRCLIB sincronizada vía búsqueda (${synced.lines.length} líneas)');
          return synced;
        }
      } catch (e) {
        debugPrint('LyricsService: error LRCLIB búsqueda: $e');
      }

      // 4) Último recurso: la mejor plana (local primero).
      if (plainFallback != null) {
        debugPrint(
            'LyricsService: letra plana sin sincronizar (${plainFallback.source})');
      }
      return plainFallback;
    });
  }

  /// Limpia la caché en memoria (p. ej. al cambiar de servidor).
  static void clearCache() => _cache.clear();

  static List<LyricLine> _toLines(StructuredLyricBlock block) {
    final lines = block.lines
        .map((l) => LyricLine(
            start: Duration(milliseconds: l.startMs), text: l.text))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return lines;
  }

  static StructuredLyricBlock? _pickSyncedBlock(
      List<StructuredLyricBlock> blocks) {
    for (final b in blocks) {
      if (b.synced && b.lines.isNotEmpty) return b;
    }
    return null;
  }

  static StructuredLyricBlock? _pickFirstBlock(
      List<StructuredLyricBlock> blocks) {
    for (final b in blocks) {
      if (b.lines.isNotEmpty) return b;
    }
    return null;
  }

  static Future<LyricsResult?> _fetchFromLrclib(Track track) async {
    final durationSec = int.tryParse(track.duration) ?? 0;
    final params = <String, String>{
      'artist_name': track.artist,
      'track_name': track.title,
      'album_name': track.album,
      if (durationSec > 0) 'duration': durationSec.toString(),
    };
    final uri = Uri.https('lrclib.net', '/api/get', params);
    final response = await http.get(uri, headers: _lrclibHeaders);

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['instrumental'] == true) {
      return const LyricsResult(
          lines: [], synced: false, source: 'LRCLIB', instrumental: true);
    }

    final syncedRaw = data['syncedLyrics'] as String?;
    if (syncedRaw != null && syncedRaw.trim().isNotEmpty) {
      final lines = parseLrc(syncedRaw);
      if (lines.isNotEmpty) {
        return LyricsResult(lines: lines, synced: true, source: 'LRCLIB');
      }
    }

    final plainRaw = data['plainLyrics'] as String?;
    if (plainRaw != null && plainRaw.trim().isNotEmpty) {
      final lines = plainRaw
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .map((s) => LyricLine(start: Duration.zero, text: s))
          .toList();
      if (lines.isNotEmpty) {
        return LyricsResult(lines: lines, synced: false, source: 'LRCLIB');
      }
    }

    return null;
  }

  /// Búsqueda amplia en LRCLIB para rescatar una versión sincronizada cuando
  /// la coincidencia exacta (o lo local) solo dio texto plano.
  ///
  /// Ordena candidatos por cercanía de duración para evitar llevarse la letra
  /// de otro tema con mismo título.
  static Future<LyricsResult?> _searchSyncedFromLrclib(Track track) async {
    final durationSec = int.tryParse(track.duration) ?? 0;
    final uri = Uri.https('lrclib.net', '/api/search', {
      'track_name': track.title,
      'artist_name': track.artist,
      'album_name': track.album,
    });
    final response = await http.get(uri, headers: _lrclibHeaders);
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body);
    if (data is! List || data.isEmpty) return null;

    final candidates = <Map<String, dynamic>>[];
    for (final e in data) {
      if (e is! Map<String, dynamic>) continue;
      final syncedRaw = e['syncedLyrics'] as String?;
      if (syncedRaw == null || syncedRaw.trim().isEmpty) continue;
      if (e['instrumental'] == true) continue;
      candidates.add(e);
    }
    if (candidates.isEmpty) return null;

    if (durationSec > 0) {
      candidates.sort((a, b) {
        final da = ((a['duration'] as num?)?.toDouble() ?? 0) - durationSec;
        final db = ((b['duration'] as num?)?.toDouble() ?? 0) - durationSec;
        return da.abs().compareTo(db.abs());
      });
    }

    for (final c in candidates) {
      final lines = parseLrc((c['syncedLyrics'] as String?) ?? '');
      if (lines.isNotEmpty) {
        return LyricsResult(lines: lines, synced: true, source: 'LRCLIB');
      }
    }
    return null;
  }

  /// Parsea un LRC (`[mm:ss.xx] texto`) a líneas ordenadas.
  /// Soporta varias etiquetas de tiempo por línea.
  @visibleForTesting
  static List<LyricLine> parseLrc(String lrc) {
    final stamp = RegExp(r'\[(\d+):(\d+)(?:[.:](\d+))?\]');
    final lines = <LyricLine>[];
    for (final raw in lrc.split('\n')) {
      final matches = stamp.allMatches(raw).toList();
      if (matches.isEmpty) continue;
      final text = raw.replaceAll(stamp, '').trim();
      if (text.isEmpty) continue;
      for (final m in matches) {
        final min = int.tryParse(m.group(1) ?? '0') ?? 0;
        final sec = int.tryParse(m.group(2) ?? '0') ?? 0;
        final fracRaw = m.group(3) ?? '0';
        // centésimas (2 dígitos) o milisegundos (3 dígitos).
        int millis;
        if (fracRaw.length == 2) {
          millis = (int.tryParse(fracRaw) ?? 0) * 10;
        } else if (fracRaw.length == 3) {
          millis = int.tryParse(fracRaw) ?? 0;
        } else if (fracRaw.isEmpty) {
          millis = 0;
        } else {
          // Normaliza a milisegundos.
          final padded = '${fracRaw}000'.substring(0, 3);
          millis = int.tryParse(padded) ?? 0;
        }
        lines.add(LyricLine(
          start: Duration(
              minutes: min, seconds: sec, milliseconds: millis),
          text: text,
        ));
      }
    }
    lines.sort((a, b) => a.start.compareTo(b.start));
    return lines;
  }
}
