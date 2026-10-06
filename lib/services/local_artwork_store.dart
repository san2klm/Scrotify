import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Portadas persistentes, separadas por servidor y sin URLs autenticadas en disco.
class LocalArtworkStore {
  LocalArtworkStore(this.directory, {http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final Directory directory;
  final http.Client _client;
  final bool _ownsClient;
  bool _disposed = false;
  final Map<String, Future<String?>> _pending = {};

  String _path(String scope, String id) => p.join(
      directory.path, '${sha256.convert(utf8.encode('$scope:$id'))}.image');

  String? path(String scope, String id) {
    final file = File(_path(scope, id));
    return FileSystemEntity.typeSync(file.path, followLinks: false) ==
                FileSystemEntityType.file &&
            file.lengthSync() > 0
        ? file.path
        : null;
  }

  Future<String?> cache(String scope, String id, String? source) {
    if (_disposed) return Future.value(null);
    final existing = path(scope, id);
    if (existing != null) return Future.value(existing);
    final uri = Uri.tryParse(source ?? '');
    if (uri == null || !{'https', 'http'}.contains(uri.scheme)) {
      return Future.value(null);
    }
    final key = _path(scope, id);
    return _pending.putIfAbsent(
        key,
        () => _fetch(key, uri).whenComplete(() {
              _pending.remove(key);
            }));
  }

  Future<String?> _fetch(String path, Uri uri) async {
    File? temporary;
    try {
      final response = await _client
          .send(http.Request('GET', uri))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        await response.stream.drain<void>().timeout(const Duration(seconds: 5));
        return null;
      }
      final bytes = <int>[];
      await for (final chunk
          in response.stream.timeout(const Duration(seconds: 5))) {
        bytes.addAll(chunk);
        if (bytes.length > 8 * 1024 * 1024) return null;
      }
      if (bytes.isEmpty) return null;
      // Una respuesta JSON/HTML o una imagen dañada no se guarda como portada.
      final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes),
          targetWidth: 1);
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      if (_disposed) return null;
      await directory.create(recursive: true);
      temporary = File('$path.${DateTime.now().microsecondsSinceEpoch}.tmp');
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(path);
      return path;
    } catch (_) {
      // La descarga de audio sigue siendo útil si no se consigue la portada.
      return null;
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  void dispose() {
    _disposed = true;
    if (_ownsClient) _client.close();
  }
}
