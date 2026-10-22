import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../utils/path_utils.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'android_music_storage.dart';
import 'local_artwork_store.dart';
import 'local_audio_metadata.dart';
import 'navidrome_service.dart';
import 'offline_cache_service.dart';
import 'offline_download_manager.dart';

/// Etapa de un escaneo de la carpeta de música.
enum LocalScanPhase { listing, files, catalog, matching }

/// Avance de un escaneo. [total] es 0 mientras se desconoce.
class LocalScanProgress {
  const LocalScanProgress(this.phase, this.done, [this.total = 0]);
  final LocalScanPhase phase;
  final int done;
  final int total;

  /// Fracción 0–1, o `null` si la etapa no tiene total conocido.
  double? get fraction => total > 0 ? (done / total).clamp(0.0, 1.0) : null;
}

/// Biblioteca local con identidad independiente de la carpeta y huellas persistentes.
class LocalMusicService extends ChangeNotifier {
  LocalMusicService(this.cache,
      {this.stateFile,
      this.defaultRoot,
      this.artworkClient,
      this.artworkFallback,
      this.metadataReader = readLocalAudioMetadata});

  final Future<Map<String, dynamic>?> Function(File) metadataReader;
  final OfflineCacheService cache;
  final File? stateFile;
  final Directory? defaultRoot;
  final http.Client? artworkClient;
  final Future<String?> Function(Track)? artworkFallback;
  LocalArtworkStore? _artwork;
  final Map<String, String> _artworkMetadata = {};
  Directory? _root;
  File? _state;
  Future<void>? _initializing;
  Future<void> _write = Future.value();
  final Map<String, Map<String, dynamic>> _records = {};
  final Map<String, String> _destinations = {};
  final Map<String, Future<void>> _requests = {};
  final Set<String> _roots = {};
  final Map<String, String> _legacyOwners = {};
  final Map<String, Map<String, dynamic>> _fingerprints = {};
  final Map<String, Map<String, dynamic>> _libraries = {};
  final Map<String, Map<String, dynamic>> _trackDetails = {};
  Future<void>? _scanFuture;
  int recoveredByLastScan = 0;
  int unidentifiedByLastScan = 0;
  bool recoveryUnavailable = false;
  bool scanning = false;

  /// Etapa y avance del escaneo en curso; `null` si no hay ninguno.
  LocalScanProgress? scanProgress;

  /// `true` si el último escaneo se interrumpió con [cancelScan].
  bool lastScanCancelled = false;
  bool _cancelRequested = false;
  Completer<void>? _cancelSignal;
  DateTime _lastProgressNotify = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;
  String? get folderPath => _root?.path;

  String _key(String scope, String id) =>
      '${OfflineCacheService.safeScopeSegment(scope)}:$id';

  /// Un fallo puntual no queda guardado: la siguiente llamada lo reintenta.
  Future<void> initialize() => _initializing ??=
          _initialize().catchError((Object error, StackTrace stack) {
        _initializing = null;
        Error.throwWithStackTrace(error, stack);
      });

  /// Espera a que termine la inicialización y el reescaneo en segundo plano que
  /// lanza, sin empezar otro. Útil antes de borrar la carpeta que usa el servicio.
  @visibleForTesting
  Future<void> settled() async {
    try {
      await _initializing;
      while (_scanFuture != null) {
        await _scanFuture;
      }
      await _write; // guardados de estado pendientes
    } catch (_) {
      // El error ya se informó donde se lanzó el escaneo.
    }
  }

  Future<void> _initialize() async {
    _state = stateFile ??
        File(p.join(
            (await getApplicationSupportDirectory()).path, 'local_music.json'));
    _artwork = LocalArtworkStore(
        Directory(p.join(_state!.parent.path, 'artwork')),
        client: artworkClient);
    if (await _state!.exists()) {
      final data =
          jsonDecode(await _state!.readAsString()) as Map<String, dynamic>;
      _root = Directory(data['root'] as String);
      _roots.addAll((data['roots'] as List? ?? []).cast<String>());
      for (final item in (data['records'] as List? ?? [])) {
        final record = Map<String, dynamic>.from(item as Map);
        _records[_key(record['scope'] as String, record['id'] as String)] =
            record;
      }
      _destinations
          .addAll(Map<String, String>.from(data['destinations'] as Map? ?? {}));
      _legacyOwners
          .addAll(Map<String, String>.from(data['legacyOwners'] as Map? ?? {}));
      final stored = data['fingerprints'];
      if (stored is Map) {
        for (final entry in stored.entries) {
          _fingerprints[entry.key as String] =
              Map<String, dynamic>.from(entry.value as Map);
        }
      }
      for (final field in ['libraries', 'details']) {
        final target = field == 'libraries' ? _libraries : _trackDetails;
        final stored = Map<String, dynamic>.from(data[field] as Map? ?? {});
        for (final entry in stored.entries) {
          target[entry.key] = Map<String, dynamic>.from(entry.value as Map);
        }
      }
    }
    if (Platform.isAndroid && defaultRoot == null) {
      final previous = await getExternalStorageDirectory();
      if (previous != null &&
          _root?.path == p.join(previous.path, 'Music', 'CrotoWave')) {
        _roots.add(_root!.path);
        _root = null;
      }
    }
    if (Platform.isIOS && defaultRoot == null) {
      final docs = await getApplicationDocumentsDirectory();
      final currentRoot = Directory(p.join(docs.path, 'Music', 'CrotoWave'));
      final oldPath = _root?.path;
      final canonDocs = OfflineCacheService.canonicalizePlatformPath(docs.path);
      final canonOld = oldPath != null
          ? OfflineCacheService.canonicalizePlatformPath(oldPath)
          : null;
      if (canonOld == null || !p.isWithin(canonDocs, canonOld)) {
        if (oldPath != null && oldPath != currentRoot.path) {
          _migrateIosContainerPaths(oldPath, currentRoot.path);
        }
        _root = currentRoot;
      }
      _roots.removeWhere((r) {
        final canonR = OfflineCacheService.canonicalizePlatformPath(r);
        return !p.isWithin(canonDocs, canonR) &&
            canonR.contains('/Documents/Music/CrotoWave');
      });
    }
    for (final entry in _trackDetails.entries) {
      final scope = entry.key.substring(0, entry.key.indexOf(':'));
      final track = Track.fromJson(entry.value);
      final path = _artwork!.path(scope, 'track:${track.id}');
      if (path != null) _artworkMetadata[_artworkKey(scope, track)] = path;
    }
    _root ??= defaultRoot ?? await _platformRoot();
    if (await AndroidMusicStorage.ensureAccess()) {
      await _root!.create(recursive: true);
    }
    _roots.add(_root!.absolute.path);
    for (final path in _roots) {
      cache.allowMusicRoot(Directory(path));
    }
    await cache.initialize();
    // Conservar también las descargas de la caché anterior.
    for (final entry in await cache.getValidEntries()) {
      if (!_records.containsKey(_key(entry.serverScope, entry.trackId))) {
        await _remember(entry);
      }
    }
    // Registro rápido (sin hashes) de lo ya descargado, para que una descarga
    // pedida justo al arrancar no se repita mientras el escaneo sigue en curso.
    for (final record in _records.values) {
      final path = (record['paths'] as List? ?? [])
          .cast<String>()
          .where((path) =>
              FileSystemEntity.typeSync(path, followLinks: false) ==
              FileSystemEntityType.file)
          .firstOrNull;
      if (path != null) await _registerRecord(record, path);
    }
    await _save();
    _notify();
    // El escaneo hashea cada archivo (GB en el móvil): no debe bloquear la
    // carga de la biblioteca, que espera a initialize().
    unawaited(rescan(requestAccess: false).catchError((Object error) {
      debugPrint('No se pudo reescanear la música local: $error');
    }));
  }

  void _migrateIosContainerPaths(String oldRootPath, String newRootPath) {
    const marker = '/Documents/Music/CrotoWave';
    String remap(String path) {
      if (path.contains(marker)) {
        final sub = path.substring(path.indexOf(marker) + marker.length);
        return p.join(
            newRootPath, sub.startsWith('/') ? sub.substring(1) : sub);
      }
      if (path.startsWith(oldRootPath)) {
        return path.replaceFirst(oldRootPath, newRootPath);
      }
      return path;
    }

    _roots.remove(oldRootPath);
    _roots.add(newRootPath);
    cache.allowMusicRoot(Directory(newRootPath));

    final updatedDestinations = <String, String>{};
    for (final entry in _destinations.entries) {
      updatedDestinations[entry.key] = remap(entry.value);
    }
    _destinations
      ..clear()
      ..addAll(updatedDestinations);

    for (final record in _records.values) {
      final paths = (record['paths'] as List? ?? []).cast<String>();
      record['paths'] = paths.map(remap).toList();
    }
  }

  static Future<Directory> _platformRoot() async {
    if (Platform.isAndroid) {
      return Directory('/storage/emulated/0/Music');
    }
    if (Platform.isIOS) {
      return Directory(p.join((await getApplicationDocumentsDirectory()).path,
          'Music', 'CrotoWave'));
    }
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null) {
      var music = p.join(home, Platform.isLinux ? 'Música' : 'Music');
      if (Platform.isLinux) {
        final config =
            Platform.environment['XDG_CONFIG_HOME'] ?? p.join(home, '.config');
        final file = File(p.join(config, 'user-dirs.dirs'));
        if (await file.exists()) {
          final match = RegExp(r'^XDG_MUSIC_DIR="([^"]+)"', multiLine: true)
              .firstMatch(await file.readAsString());
          if (match != null) music = match.group(1)!.replaceAll(r'$HOME', home);
        }
      }
      return Directory(p.join(music, 'CrotoWave'));
    }
    return Directory(
        p.join((await getApplicationDocumentsDirectory()).path, 'CrotoWave'));
  }

  static String safeName(String name) {
    final clean = name
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '')
        .trim();
    final shortened = clean.runes.take(100).toList();
    final result =
        shortened.isEmpty ? 'Sin nombre' : String.fromCharCodes(shortened);
    return RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$',
                caseSensitive: false)
            .hasMatch(result)
        ? '_$result'
        : result;
  }

  String? localPath(String scope, String id) {
    final paths =
        (_records[_key(scope, id)]?['paths'] as List? ?? []).cast<String>();
    for (final path in paths) {
      try {
        if (FileSystemEntity.typeSync(path, followLinks: false) ==
                FileSystemEntityType.file &&
            File(path).lengthSync() > 0) {
          return path;
        }
      } catch (_) {}
      if (Platform.isIOS && _root != null) {
        const marker = '/Documents/Music/CrotoWave';
        if (path.contains(marker)) {
          final sub = path.substring(path.indexOf(marker) + marker.length);
          final candidate =
              p.join(_root!.path, sub.startsWith('/') ? sub.substring(1) : sub);
          try {
            if (FileSystemEntity.typeSync(candidate, followLinks: false) ==
                    FileSystemEntityType.file &&
                File(candidate).lengthSync() > 0) {
              return candidate;
            }
          } catch (_) {}
        }
      }
    }
    return null;
  }

  int count(String? scope) => scope == null
      ? 0
      : _records.values
          .where((record) =>
              record['scope'] == OfflineCacheService.safeScopeSegment(scope) &&
              localPath(scope, record['id'] as String) != null)
          .length;

  // No persistimos portadas con tokens ni las credenciales del servidor.
  static Map<String, dynamic> _trackJson(Track track) => {
        'id': track.id,
        'title': track.title,
        'artist': track.artist,
        'album': track.album,
        'duration': track.duration,
        'suffix': track.suffix,
        'artistId': track.artistId,
        'albumId': track.albumId,
        'genre': track.genre,
        'userRating': track.userRating,
        'playCount': track.playCount,
        'createdAt': track.createdAt?.toIso8601String(),
        'replayGain': track.replayGain?.toJson(),
        'mbid': track.mbid,
        'isrc': track.isrc,
        'trackNumber': track.trackNumber,
      };

  String _artworkKey(String scope, Track track) =>
      '${OfflineCacheService.safeScopeSegment(scope)}:${jsonEncode([
            track.artist,
            track.album,
            track.title
          ])}';

  String? artworkForMetadata(String? scope,
      {String? artist, String? album, String? title}) {
    if (scope == null) return null;
    final key = '${OfflineCacheService.safeScopeSegment(scope)}:${jsonEncode([
          artist,
          album,
          title
        ])}';
    final path = _artworkMetadata[key];
    return path != null && File(path).existsSync() ? path : null;
  }

  String? artworkForTrack(String scope, Track track) => _artwork?.path(
      OfflineCacheService.safeScopeSegment(scope), 'track:${track.id}');

  Future<void> cacheTrackArtwork(String scope, Track track,
      {String? source}) async {
    await initialize();
    final safeScope = OfflineCacheService.safeScopeSegment(scope);
    var path = await _artwork!
        .cache(safeScope, 'track:${track.id}', source ?? track.albumArtUrl);
    if (path == null && artworkFallback != null && !_disposed) {
      final fallback = await artworkFallback!(track);
      path = await _artwork!.cache(safeScope, 'track:${track.id}', fallback);
    }
    if (path != null && !_disposed) {
      final key = _artworkKey(scope, track);
      if (_artworkMetadata[key] != path) {
        _artworkMetadata[key] = path;
        _notify();
      }
    }
  }

  Future<void> cacheDownloadedArtwork(String scope, List<Track> tracks) async {
    var changed = false;
    for (final track in tracks) {
      if (_disposed) return;
      if (localPath(scope, track.id) == null) continue;
      _trackDetails[_key(scope, track.id)] = _trackJson(track);
      changed = true;
      await cacheTrackArtwork(scope, track);
    }
    if (changed && !_disposed) await _save();
  }

  Future<void> cachePlaylistArtwork(String scope, Playlist playlist) async {
    await initialize();
    await _artwork!.cache(OfflineCacheService.safeScopeSegment(scope),
        'playlist:${playlist.id}', playlist.coverArtUrl);
  }

  Track _localTrack(String scope, Map<String, dynamic> data) {
    final track = Track.fromJson(data);
    final artwork = artworkForTrack(scope, track);
    return artwork == null
        ? track
        : track.copyWith(albumArtUrl: Uri.file(artwork).toString());
  }

  static Map<String, dynamic> _playlistJson(Playlist playlist) => {
        'id': playlist.id,
        'name': playlist.name,
        'owner': playlist.owner,
        'songCount': playlist.songCount,
        'duration': playlist.duration,
        'public': playlist.public,
      };

  Map<String, dynamic> _library(String userScope) => _libraries.putIfAbsent(
      userScope,
      () => {
            'playlists': <dynamic>[],
            'entries': <String, dynamic>{},
            'likes': <dynamic>[]
          });

  Future<void> bindLegacyCollections(String scope, String user) async {
    final safeScope = OfflineCacheService.safeScopeSegment(scope);
    if (_legacyOwners.containsKey(safeScope)) return;
    _legacyOwners[safeScope] = user;
    await _save();
  }

  List<Track> downloadedTracks(String? scope) {
    if (scope == null) return [];
    final safeScope = OfflineCacheService.safeScopeSegment(scope);
    return _records.values
        .where((record) =>
            record['scope'] == safeScope &&
            localPath(scope, record['id'] as String) != null)
        .map((record) {
      final id = record['id'] as String;
      return _localTrack(
          scope,
          _trackDetails[_key(scope, id)] ??
              {
                'id': id,
                'title': record['title'],
                'artist': record['artist'],
                'album': record['album'],
                'duration': record['duration'],
                'suffix':
                    p.extension(localPath(scope, id)!).replaceFirst('.', ''),
              });
    }).toList();
  }

  Future<void> rememberPlaylists(
      String userScope, List<Playlist> playlists) async {
    await initialize();
    _library(userScope)['playlists'] = playlists.map(_playlistJson).toList();
    _library(userScope)['playlistsKnown'] = true;
    await _save();
  }

  Future<void> rememberPlaylist(String userScope, Playlist playlist) async {
    await initialize();
    final library = _library(userScope);
    final playlists = (library['playlists'] as List? ?? []).toList();
    playlists.removeWhere((item) => (item is Map) && item['id'] == playlist.id);
    playlists.add(_playlistJson(playlist));
    library['playlists'] = playlists;
    library['playlistsKnown'] = true;
    await _save();
  }

  Future<void> rememberPlaylistTracks(
      String userScope, String id, List<Track> tracks) async {
    await initialize();
    final library = _library(userScope);
    final entries = (library['entries'] as Map?) != null
        ? Map<String, dynamic>.from(library['entries'] as Map)
        : <String, dynamic>{};
    entries[id] = tracks.map(_trackJson).toList();
    library['entries'] = entries;
    await _save();
  }

  Future<void> rememberLikes(String userScope, List<Track> tracks) async {
    await initialize();
    final library = _library(userScope);
    library['likes'] = tracks.map(_trackJson).toList();
    library['likesKnown'] = true;
    await _save();
  }

  List<Track> _available(String scope, List<dynamic> tracks) => tracks
      .map((item) => _localTrack(scope, Map<String, dynamic>.from(item as Map)))
      .where((track) => localPath(scope, track.id) != null)
      .toList();

  List<Track> _folderTracks(String scope, String folder) =>
      downloadedTracks(scope)
          .where((track) =>
              (_records[_key(scope, track.id)]?['paths'] as List? ?? []).any(
                  (path) => p.basename(p.dirname(path as String)) == folder))
          .toList();

  String _folderPlaylistId(String folder) =>
      'local_${sha256.convert(utf8.encode(folder)).toString().substring(0, 16)}';

  /// Las carpetas del índice anterior también aparecen sin conexión.
  List<Playlist> offlinePlaylists(String scope, String userScope) {
    final saved = (_libraries[userScope]?['playlists'] as List? ?? [])
        .map(
            (item) => Playlist.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    final folders = <String>{};
    for (final record in _records.values) {
      if (record['scope'] != OfflineCacheService.safeScopeSegment(scope)) {
        continue;
      }
      for (final path in (record['paths'] as List? ?? []).cast<String>()) {
        final folder = p.basename(p.dirname(path));
        if (folder.startsWith('playlist(') && folder.endsWith(')')) {
          folders.add(folder);
        }
      }
    }
    for (final folder in folders) {
      if (_libraries[userScope]?['playlistsKnown'] == true) continue;
      if (_legacyOwners[OfflineCacheService.safeScopeSegment(scope)] !=
          userScope) {
        continue;
      }
      if (saved.any(
          (playlist) => safeName('playlist(${playlist.name})') == folder)) {
        continue;
      }
      // Si otro usuario ya tiene la misma colección identificada, no se la atribuimos a esta cuenta.
      final belongsToOther = _libraries.entries.any((entry) =>
          entry.key != userScope &&
          (entry.value['playlists'] as List? ?? []).any((playlist) =>
              safeName('playlist(${playlist['name']})') == folder));
      if (belongsToOther) continue;
      final tracks = _folderTracks(scope, folder);
      if (tracks.isEmpty) continue;
      saved.add(Playlist(
          id: _folderPlaylistId(folder),
          name: folder.substring(9, folder.length - 1),
          songCount: tracks.length,
          duration: 0));
    }
    return saved
        .map((playlist) {
          final tracks = offlinePlaylistTracks(scope, userScope, playlist.id,
              playlist: playlist);
          return Playlist(
              id: playlist.id,
              name: playlist.name,
              owner: playlist.owner,
              public: playlist.public,
              coverArtUrl: () {
                final cover = _artwork?.path(
                    OfflineCacheService.safeScopeSegment(scope),
                    'playlist:${playlist.id}');
                return cover != null
                    ? Uri.file(cover).toString()
                    : tracks.firstOrNull?.albumArtUrl;
              }(),
              songCount: tracks.length,
              duration: tracks.fold<int>(
                  0,
                  (total, track) =>
                      total + (int.tryParse(track.duration) ?? 0)));
        })
        .where((playlist) => playlist.songCount > 0)
        .toList();
  }

  List<Track> offlinePlaylistTracks(String scope, String userScope, String id,
      {Playlist? playlist}) {
    final library = _libraries[userScope];
    final entries = library?['entries'] as Map?;
    // Una lista vacía guardada es un dato válido, no una señal para reconstruirla.
    if (entries?.containsKey(id) == true) {
      return _available(scope, (entries![id] as List? ?? []));
    }
    final saved = (library?['playlists'] as List? ?? []);
    for (final item in saved) {
      if (item['id'] == id) {
        playlist = Playlist.fromJson(Map<String, dynamic>.from(item as Map));
      }
    }
    if (_legacyOwners[OfflineCacheService.safeScopeSegment(scope)] !=
        userScope) {
      return [];
    }
    if (playlist != null) {
      return _folderTracks(scope, safeName('playlist(${playlist.name})'));
    }
    for (final track in downloadedTracks(scope)) {
      final paths = (_records[_key(scope, track.id)]?['paths'] as List? ?? [])
          .cast<String>();
      for (final path in paths) {
        final folder = p.basename(p.dirname(path));
        if (_folderPlaylistId(folder) == id) {
          return _folderTracks(scope, folder);
        }
      }
    }
    return [];
  }

  List<Track> offlineLikes(String scope, String userScope) {
    if (_libraries[userScope]?.containsKey('likesKnown') == true) {
      return _available(scope, (_libraries[userScope]!['likes'] as List? ?? []));
    }
    if (_legacyOwners[OfflineCacheService.safeScopeSegment(scope)] !=
        userScope) {
      return [];
    }
    return _folderTracks(scope, 'likes');
  }

  Future<void> changeFolder(String path) async {
    await initialize();
    await AndroidMusicStorage.requireAccess();
    final next = Directory(normalizePathKeepCase(path));
    await next.create(recursive: true);
    final probe = File(p.join(next.path,
        '.crotowave-probe-${DateTime.now().microsecondsSinceEpoch}'));
    await probe.writeAsString('');
    await probe.delete();
    _root = next;
    _roots.add(next.path);
    cache.allowMusicRoot(next);
    await _save();
    await rescan();
  }

  /// Serializar peticiones de la misma canción evita carreras entre colecciones.
  Future<void> download(
      OfflineDownloadManager manager, Track track, String scope,
      {String? collection}) {
    final key = _key(scope, track.id);
    return _requests.putIfAbsent(
        key,
        () => _download(manager, track, scope, collection).whenComplete(() {
              _requests.remove(key);
            }));
  }

  Future<void> _download(OfflineDownloadManager manager, Track track,
      String scope, String? collection) async {
    await initialize();
    // Obtener la imagen en paralelo evita retrasar el audio si falta la portada.
    unawaited(cacheTrackArtwork(scope, track).catchError((Object _) {}));
    final key = _key(scope, track.id);
    _trackDetails[key] = _trackJson(track);
    final path = localPath(scope, track.id);
    if (path != null) {
      await _registerRecord(_records[key]!, path);
      await _save();
      return;
    }
    await AndroidMusicStorage.requireAccess();
    final task = manager.getTask(scope, track.id);
    if (task != null && task.isNonTerminal) return;
    final extension =
        (track.suffix ?? 'audio').replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final folder = collection == null
        ? _root!.path
        : p.join(_root!.path, safeName(collection));
    var target = p.join(folder,
        '${safeName(track.title)}.${extension.isEmpty ? 'audio' : extension}');
    // Evitar sobrescribir canciones homónimas, incluso de otra cuenta.
    if (await File(target).exists() ||
        _destinations.entries.any((e) => e.key != key && e.value == target)) {
      final tag = sha256.convert(utf8.encode(key)).toString().substring(0, 12);
      target = p.join(folder,
          '${safeName(track.title)} [$tag].${extension.isEmpty ? 'audio' : extension}');
      var index = 2;
      while (await File(target).exists()) {
        target = p.join(folder,
            '${safeName(track.title)} [$tag-${index++}].${extension.isEmpty ? 'audio' : extension}');
      }
    }
    _destinations[key] = target;
    await _save();
    await manager.queueTrack(track, serverScope: scope);
  }

  Future<String> destination(DownloadTask task) async {
    await initialize();
    var path = _destinations[task.compoundKey];
    if (Platform.isIOS && path != null) {
      final canonRoot =
          OfflineCacheService.canonicalizePlatformPath(_root!.path);
      final canonPath =
          OfflineCacheService.canonicalizePlatformPath(path);
      if (!p.isWithin(canonRoot, canonPath)) {
        const marker = '/Documents/Music/CrotoWave';
        if (path.contains(marker)) {
          final sub = path.substring(path.indexOf(marker) + marker.length);
          path = p.join(
              _root!.path, sub.startsWith('/') ? sub.substring(1) : sub);
          _destinations[task.compoundKey] = path;
        }
      }
    }
    final tag = sha256
        .convert(utf8.encode(task.compoundKey))
        .toString()
        .substring(0, 12);
    path ??= p.join(_root!.path, '${safeName(task.title)} [$tag].audio');
    final parent = Directory(p.dirname(path));
    await parent.create(recursive: true);

    var safe = false;
    final canonParent =
        OfflineCacheService.canonicalizePlatformPath(parent.path);
    final canonPath =
        OfflineCacheService.canonicalizePlatformPath(path);

    for (final root in _roots) {
      final canonRoot = OfflineCacheService.canonicalizePlatformPath(root);
      if (canonParent == canonRoot ||
          p.isWithin(canonRoot, canonParent) ||
          p.isWithin(canonRoot, canonPath)) {
        safe = true;
        break;
      }
    }
    if (!safe && Platform.isIOS) {
      final docs = (await getApplicationDocumentsDirectory()).path;
      final canonDocs = OfflineCacheService.canonicalizePlatformPath(docs);
      if (p.isWithin(canonDocs, canonPath) ||
          p.isWithin(canonDocs, canonParent)) {
        safe = true;
      }
    }
    if (!safe) {
      throw const FileSystemException(
          'La carpeta está fuera de la biblioteca.');
    }
    // Si apareció un archivo después de encolar, no lo sobrescribimos.
    var counter = 2;
    final original = path;
    while (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      path = p.join(parent.path,
          '${p.basenameWithoutExtension(original)} [${counter++}]${p.extension(original)}');
    }
    _destinations[task.compoundKey] = path;
    await _save();
    return path;
  }

  /// SHA-256 del archivo. Se reutiliza el hash guardado mientras la ruta, el
  /// tamaño y la fecha de modificación no cambien, para no releer GB de música
  /// en cada arranque.
  Future<String> _fingerprint(File file) async {
    final stat = await file.stat();
    final cached = _fingerprints[file.absolute.path];
    if (cached != null &&
        cached['size'] == stat.size &&
        cached['mtime'] == stat.modified.millisecondsSinceEpoch) {
      return cached['hash'] as String;
    }
    final hash = (await sha256.bind(file.openRead()).first).toString();
    _fingerprints[file.absolute.path] = {
      'size': stat.size,
      'mtime': stat.modified.millisecondsSinceEpoch,
      'hash': hash,
    };
    return hash;
  }

  Future<void> _remember(OfflineCacheEntry entry) async {
    final key = _key(entry.serverScope, entry.trackId);
    final previous = _records[key];
    final hash = await _fingerprint(File(entry.localPath));
    final paths = <String>{
      if (previous?['hash'] == hash)
        ...(previous?['paths'] as List? ?? []).cast<String>(),
      entry.localPath,
    };
    _records[key] = {
      'scope': entry.serverScope,
      'id': entry.trackId,
      'title': entry.title,
      'artist': entry.artist,
      'album': entry.album,
      'duration': entry.durationSeconds,
      'hash': hash,
      'paths': paths.toList(),
    };
  }

  Future<void> completed(OfflineCacheEntry entry) async {
    await _remember(entry);
    await _save();
    _notify();
  }

  Future<void> _registerRecord(Map<String, dynamic> record, String path) async {
    await cache.registerFile(
        serverScope: record['scope'] as String,
        trackId: record['id'] as String,
        localPath: path,
        title: record['title'] as String,
        artist: record['artist'] as String,
        album: record['album'] as String,
        durationSeconds: record['duration'] as int);
  }

  /// Pide interrumpir el escaneo en curso. Si se corta antes de comparar con
  /// los archivos existentes no se toca el índice (no se sabe qué falta de
  /// verdad); si se corta al identificar, lo ya recuperado se conserva.
  void cancelScan() {
    if (!scanning) return;
    _cancelRequested = true;
    final signal = _cancelSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
  }

  void _progress(LocalScanPhase phase, int done, [int total = 0]) {
    scanProgress = LocalScanProgress(phase, done, total);
    final now = DateTime.now();
    final edge = done == 0 || done == 1 || (total > 0 && done >= total);
    if (!edge &&
        now.difference(_lastProgressNotify) <
            const Duration(milliseconds: 100)) {
      return;
    }
    _lastProgressNotify = now;
    _notify();
  }

  Future<void> rescan(
      {bool requestAccess = true,
      String? serverScope,
      Future<List<Track>> Function()? catalogLoader}) async {
    // Esperar el escaneo inicial antes de recuperar archivos del servidor activo.
    while (_scanFuture != null) {
      await _scanFuture;
    }
    final pending = _rescan(
        requestAccess: requestAccess,
        serverScope: serverScope,
        catalogLoader: catalogLoader);
    _scanFuture = pending;
    try {
      await pending;
    } finally {
      _scanFuture = null;
    }
  }

  Future<void> _rescan(
      {required bool requestAccess,
      String? serverScope,
      Future<List<Track>> Function()? catalogLoader}) async {
    if (_root == null) return;
    if (!await AndroidMusicStorage.ensureAccess(request: requestAccess)) {
      if (requestAccess) {
        throw const FileSystemException(
            'Permite el acceso al almacenamiento para usar la carpeta Music.');
      }
      return;
    }
    scanning = true;
    _cancelRequested = false;
    _cancelSignal = Completer<void>();
    lastScanCancelled = false;
    recoveredByLastScan = 0;
    unidentifiedByLastScan = 0;
    recoveryUnavailable = false;
    scanProgress = const LocalScanProgress(LocalScanPhase.listing, 0);
    _notify();
    try {
      const audioExtensions = {
        'mp3',
        'flac',
        'ogg',
        'opus',
        'm4a',
        'aac',
        'wav',
        'wma',
        'audio'
      };
      final files = <File>[];
      for (final path in _roots.toList()) {
        final dir = Directory(path);
        if (!await dir.exists()) continue;
        await for (final entity
            in dir.list(recursive: true, followLinks: false)) {
          if (_cancelRequested) {
            lastScanCancelled = true;
            return;
          }
          if (entity is! File ||
              !audioExtensions.contains(p
                  .extension(entity.path)
                  .replaceFirst('.', '')
                  .toLowerCase())) {
            continue;
          }
          if (await entity.length() == 0) {
            continue;
          }
          files.add(entity);
          _progress(LocalScanPhase.listing, files.length);
        }
      }
      final hashes = <String, List<String>>{};
      for (var i = 0; i < files.length; i++) {
        // Cortar aquí deja el índice intacto: aún no se sabe qué archivos
        // faltan de verdad, y purgar con una lista incompleta borraría
        // descargas válidas.
        if (_cancelRequested) {
          lastScanCancelled = true;
          return;
        }
        final hash = await _fingerprint(files[i]);
        hashes.putIfAbsent(hash, () => []).add(files[i].absolute.path);
        _progress(LocalScanPhase.files, i + 1, files.length);
      }
      for (final record in _records.values.toList()) {
        final previous = (record['paths'] as List).cast<String>();
        final verified = <String>[];
        for (final path in previous) {
          if (FileSystemEntity.typeSync(path, followLinks: false) !=
              FileSystemEntityType.file) {
            continue;
          }
          if (await _fingerprint(File(path)) == record['hash']) {
            verified.add(path);
          }
        }
        record['paths'] =
            <String>{...verified, ...?hashes[record['hash']]}.toList();
        final paths = (record['paths'] as List).cast<String>();
        if (paths.isNotEmpty) {
          await _registerRecord(record, paths.first);
        } else {
          // Purga los metadatos antiguos sin borrar otros archivos.
          await cache.forget(record['scope'] as String, record['id'] as String);
        }
      }
      final knownHashes = _records.values.map((r) => r['hash']).toSet();
      final unknown =
          hashes.entries.where((e) => !knownHashes.contains(e.key)).toList();
      unidentifiedByLastScan =
          unknown.fold<int>(0, (total, entry) => total + entry.value.length);
      if (unknown.isNotEmpty && serverScope != null && catalogLoader != null) {
        List<Track>? catalog;
        _progress(LocalScanPhase.catalog, 0);
        try {
          // Cancelar deja de esperar al servidor (la descarga sigue en segundo
          // plano y su resultado se ignora).
          catalog = await Future.any<List<Track>?>([
            catalogLoader(),
            _cancelSignal!.future.then<List<Track>?>((_) => null),
          ]);
        } catch (_) {
          recoveryUnavailable = true;
        }
        if (_cancelRequested) {
          catalog = null;
          lastScanCancelled = true;
        }
        if (catalog != null) {
          final byTags = <String, List<Track>>{};
          for (final track in catalog) {
            byTags
                .putIfAbsent(_tagKey(track.title, track.artist), () => [])
                .add(track);
          }
          var examined = 0;
          for (final entry in unknown) {
            if (_cancelRequested) {
              lastScanCancelled = true;
              break;
            }
            _progress(LocalScanPhase.matching, examined++, unknown.length);
            Map<String, dynamic>? tags;
            for (final path in entry.value) {
              tags = await metadataReader(File(path));
              if (tags != null) break;
            }
            if (tags == null) continue;
            final title = tags['title']?.toString() ?? '';
            final artist = tags['artist']?.toString() ?? '';
            final album = tags['album']?.toString() ?? '';
            final duration = double.tryParse('${tags['duration']}');
            if (title.trim().isEmpty ||
                artist.trim().isEmpty ||
                duration == null) {
              continue;
            }
            final matches =
                (byTags[_tagKey(title, artist)] ?? <Track>[]).where((track) {
              final seconds = double.tryParse(track.duration);
              return seconds != null &&
                  (seconds - duration).abs() <= 2 &&
                  (album.trim().isEmpty ||
                      _normalizeTag(album) == _normalizeTag(track.album));
            }).toList();
            // Un título ambiguo nunca debe marcar otra versión como descargada.
            if (matches.length != 1) continue;
            final track = matches.single;
            final key = _key(serverScope, track.id);
            final existing = _records[key];
            if (existing != null && (existing['paths'] as List).isNotEmpty) {
              continue;
            }
            final record = <String, dynamic>{
              'scope': OfflineCacheService.safeScopeSegment(serverScope),
              'id': track.id,
              'title': track.title,
              'artist': track.artist,
              'album': track.album,
              'duration': int.tryParse(track.duration) ?? 0,
              'hash': entry.key,
              'paths': entry.value,
            };
            await _registerRecord(record, entry.value.first);
            _records[key] = record;
            _trackDetails[key] = _trackJson(track);
            recoveredByLastScan++;
            unidentifiedByLastScan -= entry.value.length;
          }
        }
      } else if (unknown.isNotEmpty) {
        recoveryUnavailable = true;
      }
      // Descartar huellas de archivos que ya no existen.
      _fingerprints.removeWhere((path, _) =>
          FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.file);
      await _save();
    } finally {
      scanning = false;
      scanProgress = null;
      _cancelSignal = null;
      _notify();
    }
  }

  String _normalizeTag(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  String _tagKey(String title, String artist) =>
      jsonEncode([_normalizeTag(title), _normalizeTag(artist)]);

  Future<void> _save() {
    final contents = jsonEncode({
      'root': _root!.path,
      'roots': _roots.toList(),
      'records': _records.values.toList(),
      'legacyOwners': _legacyOwners,
      'libraries': _libraries,
      'details': _trackDetails,
      'destinations': _destinations,
      'fingerprints': _fingerprints,
    });
    final result = _write.catchError((Object _) {}).then((_) async {
      await _state!.parent.create(recursive: true);
      final temp = File('${_state!.path}.tmp');
      await temp.writeAsString(contents, flush: true);
      await temp.rename(_state!.path);
    });
    _write = result;
    return result;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    // Un reescaneo en segundo plano no debe seguir escribiendo el estado.
    _cancelRequested = true;
    _artwork?.dispose();
    super.dispose();
  }
}
