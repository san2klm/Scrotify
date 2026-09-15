import 'dart:math';

import 'navidrome_service.dart';

/// Una canción leída de un archivo de playlist importado.
///
/// [alternate] guarda la interpretación invertida (Artista-Título vs.
/// Título-Artista) cuando el campo vino separado por guion, porque no siempre
/// se sabe qué lado es el artista; el matcher probará ambas.
class ImportTrack {
  final String title;
  final String? artist;
  final String? album;
  final ImportTrack? alternate;

  const ImportTrack({
    required this.title,
    this.artist,
    this.album,
    this.alternate,
  });

  String get display => artist == null ? title : '$artist - $title';
}

/// Resultado del parseo de un archivo + nombre sugerido (p. ej. columna
/// "Playlist" de un CSV de Spotify).
class ParsedPlaylist {
  final String? suggestedName;
  final List<ImportTrack> tracks;

  const ParsedPlaylist({this.suggestedName, required this.tracks});
}

class PlaylistImportResult {
  final String playlistId;
  final String name;
  final int matched;
  final List<ImportTrack> unmatched;

  const PlaylistImportResult({
    required this.playlistId,
    required this.name,
    required this.matched,
    required this.unmatched,
  });

  bool get hasUnmatched => unmatched.isNotEmpty;
}

/// Importa playlists desde archivos CSV, M3U/M3U8, PLS o TXT.
///
/// Estrategia de matching: busca en el servidor (`search3.view`) canción por
/// canción en lugar de descargar toda la biblioteca. Escala mejor para
/// bibliotecas grandes.
class PlaylistImporter {
  static const int batchSize = 100;

  // ---------------------------------------------------------------------------
  // Parseo
  // ---------------------------------------------------------------------------

  static ParsedPlaylist parseFile(String fileName, String content) {
    final ext = fileName.contains('.')
        ? fileName.toLowerCase().split('.').last
        : '';
    return switch (ext) {
      'csv' => parseCsv(content),
      'm3u' || 'm3u8' => parseM3u(content),
      'pls' => parsePls(content),
      'txt' => parseTxt(content),
      _ => throw FormatException('Formato no soportado: .$ext'),
    };
  }

  /// CSV con encabezados flexibles: detecta columnas de título/artista/álbum
  /// por nombre, y el nombre de playlist si viene una columna "Playlist".
  static ParsedPlaylist parseCsv(String content) {
    final rows = _parseCsvRows(content);
    if (rows.isEmpty) return const ParsedPlaylist(tracks: []);

    const titleWords = {
      'title', 'track', 'track name', 'name', 'song',
      'titulo', 'título', 'cancion', 'canción',
    };
    const artistWords = {
      'artist', 'artist name', 'artista', 'interpret',
    };

    var titleIdx = 0;
    var artistIdx = 1;
    var albumIdx = 2;
    String? suggestedName;
    var hasHeader = false;

    final first = rows.first;
    for (var i = 0; i < first.length; i++) {
      final h = first[i].trim().toLowerCase();
      if (titleWords.contains(h)) {
        titleIdx = i;
        hasHeader = true;
      } else if (artistWords.contains(h)) {
        artistIdx = i;
        hasHeader = true;
      } else if (h == 'album' || h == 'album name') {
        albumIdx = i;
        hasHeader = true;
      } else if (h == 'playlist' || h == 'playlist name') {
        hasHeader = true;
      }
    }

    final tracks = <ImportTrack>[];
    for (var r = hasHeader ? 1 : 0; r < rows.length; r++) {
      final row = rows[r];
      final title = (titleIdx < row.length ? row[titleIdx] : '').trim();
      if (title.isEmpty) continue; // fila vacía / separador
      tracks.add(ImportTrack(
        title: title,
        artist: artistIdx < row.length ? row[artistIdx].trim() : null,
        album: albumIdx < row.length ? row[albumIdx].trim() : null,
      ));
      if (suggestedName == null && hasHeader) {
        final plIdx = first.indexWhere((h) =>
            h.trim().toLowerCase() == 'playlist' ||
            h.trim().toLowerCase() == 'playlist name');
        if (plIdx >= 0 && plIdx < row.length && row[plIdx].trim().isNotEmpty) {
          suggestedName = row[plIdx].trim();
        }
      }
    }
    return ParsedPlaylist(suggestedName: suggestedName, tracks: tracks);
  }

  static ParsedPlaylist parseM3u(String content) {
    final tracks = <ImportTrack>[];
    for (final raw in content.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXTINF:')) {
        final rest = line.substring('#EXTINF:'.length);
        final comma = rest.indexOf(',');
        final info = (comma >= 0 ? rest.substring(comma + 1) : rest).trim();
        if (info.isEmpty) continue;
        final parts = _splitSmart(info);
        if (parts != null) {
          tracks.add(_fromParts(parts));
        } else {
          tracks.add(ImportTrack(title: info));
        }
      } else if (!line.startsWith('#') && !_looksLikeMediaUrl(line)) {
        // Línea de ruta de archivo sin info (EXTINF ausente): usar el nombre.
        final name = _nameFromPath(line);
        if (name.isNotEmpty) tracks.add(ImportTrack(title: name));
      }
    }
    return ParsedPlaylist(tracks: tracks);
  }

  static ParsedPlaylist parsePls(String content) {
    final titles = <int, String>{};
    final artists = <int, String>{};
    final files = <int, String>{};
    final re = RegExp(r'^(Title|Artist|File)(\d+)=(.*)$');
    for (final raw in content.split('\n')) {
      final m = re.firstMatch(raw.trim());
      if (m == null) continue;
      final n = int.parse(m.group(2)!);
      final value = m.group(3)!.trim();
      switch (m.group(1)) {
        case 'Title':
          titles[n] = value;
        case 'Artist':
          artists[n] = value;
        case 'File':
          files[n] = value;
      }
    }
    final keys = {...titles.keys, ...files.keys}.toList()..sort();
    final tracks = <ImportTrack>[];
    for (final n in keys) {
      final title = (titles[n] ?? _nameFromPath(files[n] ?? '')).trim();
      if (title.isEmpty) continue;
      tracks.add(ImportTrack(title: title, artist: artists[n]));
    }
    return ParsedPlaylist(tracks: tracks);
  }

  static ParsedPlaylist parseTxt(String content) {
    final tracks = <ImportTrack>[];
    for (final raw in content.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final parts = _splitSmart(line);
      tracks.add(parts != null ? _fromParts(parts) : ImportTrack(title: line));
    }
    return ParsedPlaylist(tracks: tracks);
  }

  static ImportTrack _fromParts((String, String) parts) {
    final left = parts.$1;
    final right = parts.$2;
    // Artista - Título como interpretación primaria; alternativa invertida.
    return ImportTrack(
      title: right,
      artist: left,
      alternate: ImportTrack(title: left, artist: right),
    );
  }

  /// Separa "A - B", "A – B" o "A — B". Devuelve primer y segundo lado.
  static (String, String)? _splitSmart(String s) {
    for (final sep in [' — ', ' – ', ' - ']) {
      final idx = s.indexOf(sep);
      if (idx > 0) {
        final a = s.substring(0, idx).trim();
        final b = s.substring(idx + sep.length).trim();
        if (a.isNotEmpty && b.isNotEmpty) return (a, b);
      }
    }
    return null;
  }

  static bool _looksLikeMediaUrl(String s) =>
      s.startsWith('http://') || s.startsWith('https://');

  static String _nameFromPath(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    return name
        .replaceAll(RegExp(r'\.(mp3|flac|m4a|aac|ogg|oga|opus|wav|wma)$'), '')
        .trim();
  }

  /// Parser CSV manual: soporta comillas y comas dentro de valores.
  static List<List<String>> _parseCsvRows(String content) {
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < content.length; i++) {
      final c = content[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < content.length && content[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          cell.write(c);
        }
      } else {
        if (c == '"') {
          inQuotes = true;
        } else if (c == ',') {
          row.add(cell.toString().trim());
          cell.clear();
        } else if (c == '\n' || c == '\r') {
          if (c == '\r' && i + 1 < content.length && content[i + 1] == '\n') {
            i++;
          }
          row.add(cell.toString().trim());
          cell.clear();
          rows.add(row);
          row = <String>[];
        } else {
          cell.write(c);
        }
      }
    }
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString().trim());
      rows.add(row);
    }
    return rows.where((r) => r.any((c) => c.isNotEmpty)).toList();
  }

  // ---------------------------------------------------------------------------
  // Matching contra la biblioteca (busca en el servidor, no descarga todo)
  // ---------------------------------------------------------------------------

  /// Normaliza texto para comparar: minúsculas, sin acentos, sin puntuación.
  static String _fold(String s) {
    const accents = {
      'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'ā': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ė': 'e', 'ę': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', 'į': 'i',
      'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o', 'ō': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u',
      'ñ': 'n', 'ç': 'c', 'ć': 'c', 'č': 'c', 'š': 's', 'ș': 's', 'ş': 's',
      'ž': 'z', 'ý': 'y', 'ÿ': 'y', 'æ': 'ae', 'œ': 'oe', 'ß': 'ss',
    };
    final out = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      out.write(accents[ch] ?? ch);
    }
    return out
        .toString()
        .replaceAll(RegExp(r"[^a-z0-9 ]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Busca una canción en Navidrome por título (+ artista opcional).
  /// Usa `search3.view` del servidor, que está optimizado e indexado.
  static Future<Track?> _searchTrack(
      NavidromeService nav,
      String title, {
        String? artist,
      }) async {
    // Consulta: "title artist" si hay artista, si no solo título.
    final query = artist != null ? '$title $artist' : title;
    final results = await nav.search(query);
    final tracks = results.songs;
    if (tracks.isEmpty) return null;

    // Filtrado local ligero sobre los resultados del servidor (máx ~50).
    final titleF = _fold(title);
    final artistF = artist == null ? null : _fold(artist);

    Track? exact;
    Track? fallback;

    for (final t in tracks) {
      final lt = _fold(t.title);
      final la = _fold(t.artist);
      if (lt == titleF && (artistF == null || la == artistF)) {
        return t; // match exacto título+artista
      }
      if (exact == null && lt == titleF) {
        exact = t; // match exacto solo título
      }
      if (fallback == null && artistF != null && la == artistF && lt.contains(titleF)) {
        fallback = t; // mismo artista, título contenido
      }
    }
    return exact ?? fallback;
  }

  /// Match principal: intenta la canción y su alternativa invertida.
  static Future<Track?> _match(
      NavidromeService nav,
      ImportTrack t) async {
    for (final cand in [t, if (t.alternate != null) t.alternate!]) {
      final hit = await _searchTrack(nav, cand.title, artist: cand.artist);
      if (hit != null) return hit;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Importación
  // ---------------------------------------------------------------------------

  static Future<PlaylistImportResult> import({
    required String name,
    required List<ImportTrack> tracks,
    required NavidromeService nav,
  }) async {
    final matched = <Track>[];
    final unmatched = <ImportTrack>[];
    final seen = <String>{};

    // Buscar canción por canción en el servidor (paralelismo limitado para no saturar).
    const concurrency = 4;
    for (var i = 0; i < tracks.length; i += concurrency) {
      final batch = tracks.sublist(i, min(i + concurrency, tracks.length));
      final futures = batch.map((t) => _match(nav, t));
      final results = await Future.wait(futures);

      for (var j = 0; j < batch.length; j++) {
        final hit = results[j];
        if (hit != null) {
          if (seen.add(hit.id)) matched.add(hit);
        } else {
          unmatched.add(batch[j]);
        }
      }
    }

    if (matched.isEmpty) {
      throw StateError(
          'Ninguna de las ${tracks.length} canciones coincide con tu biblioteca.');
    }

    final playlist = await nav.createPlaylist(name);
    final playlistId = playlist?.id ?? '';
    if (playlistId.isEmpty) {
      throw Exception('No se pudo crear la playlist en el servidor.');
    }

    // Agregar de a lotes para no construir una URL gigantesca.
    for (var i = 0; i < matched.length; i += batchSize) {
      final ids = matched
          .sublist(i, min(i + batchSize, matched.length))
          .map((t) => t.id)
          .toList();
      await nav.updatePlaylist(playlistId: playlistId, songIdsToAdd: ids);
    }

    nav.bumpPlaylists();
    return PlaylistImportResult(
      playlistId: playlistId,
      name: name,
      matched: matched.length,
      unmatched: unmatched,
    );
  }
}