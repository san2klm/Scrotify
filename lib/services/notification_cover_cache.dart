import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'navidrome_service.dart';

/// Guarda la carátula de cada pista en la caché de la app para publicarla en la
/// notificación de medios como `file://` (la URL remota lleva credenciales).
/// Conserva solo las últimas [keep] carátulas.
class NotificationCoverCache {
  NotificationCoverCache({this.keep = 12});

  final int keep;
  Directory? _dir;

  Future<String?> fetch(Track track) async {
    final url = track.albumArtUrl;
    if (url == null || url.isEmpty) return null;
    try {
      final dir = _dir ??= await _directory();
      final file = File('${dir.path}/${_safeName(track.id)}.img');
      if (!await file.exists() || await file.length() == 0) {
        final response =
            await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
        if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
          return null;
        }
        await file.writeAsBytes(response.bodyBytes, flush: true);
        await _prune(dir, file);
      }
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _directory() async {
    final base = await getApplicationCacheDirectory();
    return Directory('${base.path}/media_art').create(recursive: true);
  }

  static String _safeName(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  Future<void> _prune(Directory dir, File current) async {
    final files =
        await dir.list().where((e) => e is File).cast<File>().toList();
    if (files.length <= keep) return;
    files
        .sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
    for (final f in files.take(files.length - keep)) {
      if (f.path != current.path) await f.delete().catchError((_) => f);
    }
  }
}
