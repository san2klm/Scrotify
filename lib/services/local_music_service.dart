import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'navidrome_service.dart';
import 'offline_cache_service.dart';
import 'offline_download_manager.dart';

/// Biblioteca local con identidad independiente de la carpeta y huellas persistentes.
class LocalMusicService extends ChangeNotifier {
  LocalMusicService(this.cache, {this.stateFile, this.defaultRoot});

  final OfflineCacheService cache;
  final File? stateFile;
  final Directory? defaultRoot;
  Directory? _root;
  File? _state;
  Future<void>? _initializing;
  Future<void> _write = Future.value();
  final Map<String, Map<String, dynamic>> _records = {};
  final Map<String, String> _destinations = {};
  final Map<String, Future<void>> _requests = {};
  final Set<String> _roots = {};
  bool scanning = false;
  bool _disposed = false;
  String? get folderPath => _root?.path;

  String _key(String scope, String id) =>
      '${OfflineCacheService.safeScopeSegment(scope)}:$id';

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    _state = stateFile ?? File(p.join(
        (await getApplicationSupportDirectory()).path, 'local_music.json'));
    if (await _state!.exists()) {
      final data = jsonDecode(await _state!.readAsString()) as Map<String, dynamic>;
      _root = Directory(data['root'] as String);
      _roots.addAll((data['roots'] as List? ?? []).cast<String>());
      for (final item in (data['records'] as List? ?? [])) {
        final record = Map<String, dynamic>.from(item as Map);
        _records[_key(record['scope'] as String, record['id'] as String)] = record;
      }
      _destinations.addAll(Map<String, String>.from(data['destinations'] as Map? ?? {}));
    }
    _root ??= defaultRoot ?? await _platformRoot();
    await _root!.create(recursive: true);
    _roots.add(_root!.absolute.path);
    for (final path in _roots) {
      cache.allowMusicRoot(Directory(path));
    }
    await cache.initialize();
    // Conservar también las descargas de la caché anterior.
    for (final entry in await cache.getValidEntries()) {
      await _remember(entry);
    }
    await rescan();
  }

  static Future<Directory> _platformRoot() async {
    if (Platform.isAndroid) {
      final external = await getExternalStorageDirectory();
      return Directory(p.join((external ?? await getApplicationDocumentsDirectory()).path,
          'Music', 'Scrotify'));
    }
    if (Platform.isIOS) {
      return Directory(p.join((await getApplicationDocumentsDirectory()).path,
          'Music', 'Scrotify'));
    }
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null) {
      var music = p.join(home, Platform.isLinux ? 'Música' : 'Music');
      if (Platform.isLinux) {
        final config = Platform.environment['XDG_CONFIG_HOME'] ?? p.join(home, '.config');
        final file = File(p.join(config, 'user-dirs.dirs'));
        if (await file.exists()) {
          final match = RegExp(r'^XDG_MUSIC_DIR="([^"]+)"', multiLine: true)
              .firstMatch(await file.readAsString());
          if (match != null) music = match.group(1)!.replaceAll(r'$HOME', home);
        }
      }
      return Directory(p.join(music, 'Scrotify'));
    }
    return Directory(p.join((await getApplicationDocumentsDirectory()).path, 'Scrotify'));
  }

  static String safeName(String name) {
    final clean = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '').trim();
    final shortened = clean.runes.take(100).toList();
    final result = shortened.isEmpty ? 'Sin nombre' : String.fromCharCodes(shortened);
    return RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$', caseSensitive: false)
        .hasMatch(result) ? '_$result' : result;
  }

  String? localPath(String scope, String id) {
    final paths = (_records[_key(scope, id)]?['paths'] as List? ?? []).cast<String>();
    for (final path in paths) {
      if (FileSystemEntity.typeSync(path, followLinks: false) == FileSystemEntityType.file &&
          File(path).lengthSync() > 0) return path;
    }
    return null;
  }

  int count(String? scope) => scope == null ? 0 : _records.values.where((record) =>
      record['scope'] == OfflineCacheService.safeScopeSegment(scope) &&
      localPath(scope, record['id'] as String) != null).length;

  Future<void> changeFolder(String path) async {
    await initialize();
    final next = Directory(p.canonicalize(p.absolute(path)));
    await next.create(recursive: true);
    final probe = File(p.join(next.path, '.scrotify-probe-${DateTime.now().microsecondsSinceEpoch}'));
    await probe.writeAsString('');
    await probe.delete();
    _root = next;
    _roots.add(next.path);
    cache.allowMusicRoot(next);
    await _save();
    await rescan();
  }

  /// Serializar peticiones de la misma canción evita carreras entre colecciones.
  Future<void> download(OfflineDownloadManager manager, Track track, String scope,
      {String? collection}) {
    final key = _key(scope, track.id);
    return _requests.putIfAbsent(key, () => _download(manager, track, scope, collection)
        .whenComplete(() => _requests.remove(key)));
  }

  Future<void> _download(OfflineDownloadManager manager, Track track,
      String scope, String? collection) async {
    await initialize();
    final key = _key(scope, track.id);
    final path = localPath(scope, track.id);
    if (path != null) {
      await _registerRecord(_records[key]!, path);
      return;
    }
    final task = manager.getTask(scope, track.id);
    if (task != null && task.isNonTerminal) return;
    final extension = (track.suffix ?? 'audio').replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final folder = collection == null ? _root!.path : p.join(_root!.path, safeName(collection));
    var target = p.join(folder, '${safeName(track.title)}.${extension.isEmpty ? 'audio' : extension}');
    // Evitar sobrescribir canciones homónimas, incluso de otra cuenta.
    if (await File(target).exists() || _destinations.entries.any((e) => e.key != key && e.value == target)) {
      final tag = sha256.convert(utf8.encode(key)).toString().substring(0, 12);
      target = p.join(folder, '${safeName(track.title)} [$tag].${extension.isEmpty ? 'audio' : extension}');
      var index = 2;
      while (await File(target).exists()) {
        target = p.join(folder, '${safeName(track.title)} [$tag-${index++}].${extension.isEmpty ? 'audio' : extension}');
      }
    }
    _destinations[key] = target;
    await _save();
    await manager.queueTrack(track, serverScope: scope);
  }

  Future<String> destination(DownloadTask task) async {
    await initialize();
    final existing = _destinations[task.compoundKey];
    if (existing != null) return existing;
    // Las descargas iniciadas desde el menú contextual usan también Música local.
    final tag = sha256.convert(utf8.encode(task.compoundKey)).toString().substring(0, 12);
    final path = p.join(_root!.path, '${safeName(task.title)} [$tag].audio');
    _destinations[task.compoundKey] = path;
    await _save();
    return path;
  }

  Future<String> _fingerprint(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  Future<void> _remember(OfflineCacheEntry entry) async {
    final key = _key(entry.serverScope, entry.trackId);
    final previous = _records[key];
    final hash = await _fingerprint(File(entry.localPath));
    final paths = <String>{
      if (previous?['hash'] == hash) ...(previous?['paths'] as List? ?? []).cast<String>(),
      entry.localPath,
    };
    _records[key] = {
      'scope': entry.serverScope, 'id': entry.trackId,
      'title': entry.title, 'artist': entry.artist, 'album': entry.album,
      'duration': entry.durationSeconds, 'hash': hash, 'paths': paths.toList(),
    };
  }

  Future<void> completed(OfflineCacheEntry entry) async {
    await _remember(entry);
    await _save();
    _notify();
  }

  Future<void> _registerRecord(Map<String, dynamic> record, String path) async {
    await cache.registerFile(serverScope: record['scope'] as String,
      trackId: record['id'] as String, localPath: path,
      title: record['title'] as String, artist: record['artist'] as String,
      album: record['album'] as String, durationSeconds: record['duration'] as int);
  }

  Future<void> rescan() async {
    if (_root == null || scanning) return;
    scanning = true;
    _notify();
    try {
      final hashes = <String, List<String>>{};
      for (final path in _roots) {
        final dir = Directory(path);
        if (!await dir.exists()) continue;
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is! File || !{'mp3','flac','ogg','opus','m4a','aac','wav','wma','audio'}
              .contains(p.extension(entity.path).replaceFirst('.', '').toLowerCase())) continue;
          if (await entity.length() == 0) continue;
          final hash = await _fingerprint(entity);
          hashes.putIfAbsent(hash, () => []).add(entity.absolute.path);
        }
      }
      for (final record in _records.values) {
        final previous = (record['paths'] as List).cast<String>();
        final verified = <String>[];
        for (final path in previous) {
          if (FileSystemEntity.typeSync(path, followLinks: false) != FileSystemEntityType.file) continue;
          if (await _fingerprint(File(path)) == record['hash']) verified.add(path);
        }
        record['paths'] = <String>{...verified, ...?hashes[record['hash']]}.toList();
        final paths = (record['paths'] as List).cast<String>();
        if (paths.isNotEmpty) {
          await _registerRecord(record, paths.first);
        } else {
          // Purga los metadatos antiguos sin borrar otros archivos.
          await cache.lookup(record['scope'] as String, record['id'] as String);
        }
      }
      await _save();
    } finally {
      scanning = false;
      _notify();
    }
  }

  Future<void> _save() {
    final contents = jsonEncode({'root': _root!.path, 'roots': _roots.toList(),
      'records': _records.values.toList(), 'destinations': _destinations});
    final result = _write.catchError((Object _) {}).then((_) async {
      await _state!.parent.create(recursive: true);
      final temp = File('${_state!.path}.tmp');
      await temp.writeAsString(contents, flush: true);
      await temp.rename(_state!.path);
    });
    _write = result;
    return result;
  }

  void _notify() { if (!_disposed) notifyListeners(); }
  @override
  void dispose() { _disposed = true; super.dispose(); }
}
