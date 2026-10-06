import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/local_music_service.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/offline_cache_service.dart';
import 'package:navidrome_client/services/offline_download_manager.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late OfflineCacheService cache;
  late LocalMusicService music;
  late OfflineDownloadManager manager;
  late int transfers;
  const scope = 'servidor-A';
  final track = Track(id: 'uno', title: 'Canción', artist: 'Artista',
      album: 'Álbum', duration: '180', suffix: 'mp3');

  OfflineCacheService newCache() => OfflineCacheService(
      cacheRootDir: Directory(p.join(temp.path, 'cache')),
      metadataStore: InMemoryOfflineCacheMetadataStore());

  LocalMusicService newMusic(OfflineCacheService cache) => LocalMusicService(cache,
      stateFile: File(p.join(temp.path, 'estado.json')),
      defaultRoot: Directory(p.join(temp.path, 'Música', 'Scrotify')));

  OfflineDownloadManager newManager(OfflineCacheService cache, LocalMusicService music) =>
      OfflineDownloadManager(cacheService: cache,
        persistenceFile: File(p.join(temp.path, 'tareas.json')),
        transport: FunctionalDownloadTransport(({
          required String serverScope, required String trackId,
          required File destinationFile, String? sourceMarker,
          void Function(int, int?)? onProgress, bool Function()? isCancelled,
        }) async {
          transfers++;
          await destinationFile.writeAsBytes([1, 2, 3, ...trackId.codeUnits]);
        }))
        ..beforeInitialize = music.initialize
        ..destinationResolver = music.destination
        ..onFileRegistered = music.completed;

  Future<void> complete(OfflineDownloadManager manager, String id, {String server = scope}) async {
    final done = Completer<void>();
    void listener() {
      final task = manager.getTask(server, id);
      if (task?.status == DownloadTaskStatus.failed && !done.isCompleted) {
        done.completeError(StateError('Descarga fallida: ${task?.failureCategory}'));
      }
      if (task?.status == DownloadTaskStatus.completed && !done.isCompleted) done.complete();
    }
    manager.addListener(listener);
    listener();
    try { await done.future.timeout(const Duration(seconds: 5)); }
    finally { manager.removeListener(listener); }
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('scrotify-local-test-');
    transfers = 0;
    cache = newCache(); music = newMusic(cache); manager = newManager(cache, music);
    await manager.initialize();
  });
  tearDown(() async {
    manager.dispose(); music.dispose(); await cache.close();
    await temp.delete(recursive: true);
  });

  test('Organiza playlist, likes y canciones sueltas con extensión original', () async {
    await music.download(manager, track, scope, collection: 'playlist(Rock)');
    await complete(manager, track.id);
    expect(music.localPath(scope, track.id), p.join(music.folderPath!, 'playlist(Rock)', 'Canción.mp3'));
    final liked = track.copyWith(id: 'dos', title: 'Favorita');
    await music.download(manager, liked, scope, collection: 'likes');
    await complete(manager, liked.id);
    expect(music.localPath(scope, liked.id), p.join(music.folderPath!, 'likes', 'Favorita.mp3'));
    final single = track.copyWith(id: 'tres', title: 'Suelta');
    await music.download(manager, single, scope);
    await complete(manager, single.id);
    expect(music.localPath(scope, single.id), p.join(music.folderPath!, 'Suelta.mp3'));
  });

  test('Peticiones simultáneas en varias colecciones transfieren una sola vez', () async {
    await Future.wait([
      music.download(manager, track, scope, collection: 'likes'),
      music.download(manager, track, scope, collection: 'playlist(Rock)'),
      music.download(manager, track, scope),
    ]);
    await complete(manager, track.id);
    await music.download(manager, track, scope, collection: 'playlist(Otra)');
    expect(transfers, 1);
    expect(music.count(scope), 1);
  });

  test('Reescaneo encuentra la canción movida y cuenta sus copias una sola vez', () async {
    await music.download(manager, track, scope, collection: 'likes');
    await complete(manager, track.id);
    final old = File(music.localPath(scope, track.id)!);
    final folder = Directory(p.join(music.folderPath!, 'otra carpeta'));
    await folder.create();
    final moved = await old.rename(p.join(folder.path, 'renombrada.mp3'));
    await moved.copy(p.join(music.folderPath!, 'copia.mp3'));
    await File(p.join(music.folderPath!, 'sin-extension')).writeAsString('desconocido');
    await music.rescan();
    await music.download(manager, track, scope);
    expect(transfers, 1);
    expect(music.count(scope), 1);
    expect(await cache.lookup(scope, track.id), isNotNull);
  });

  test('Reinicio restaura identidad sin las tareas ni metadatos en memoria', () async {
    await music.download(manager, track, scope);
    await complete(manager, track.id);
    manager.dispose(); music.dispose(); await cache.close();
    await File(p.join(temp.path, 'tareas.json')).delete();
    cache = newCache(); music = newMusic(cache); manager = newManager(cache, music);
    await manager.initialize();
    await manager.queueTrack(track, serverScope: scope);
    expect(transfers, 1);
    expect(manager.getTask(scope, track.id)?.status, DownloadTaskStatus.completed);
    expect(music.count(scope), 1);
  });

  test('Carpeta nueva conserva descargas anteriores sin volver a descargarlas', () async {
    await music.download(manager, track, scope);
    await complete(manager, track.id);
    final previous = music.localPath(scope, track.id);
    await music.changeFolder(p.join(temp.path, 'nueva'));
    await music.download(manager, track, scope, collection: 'likes');
    expect(music.localPath(scope, track.id), previous);
    expect(transfers, 1);
    final other = track.copyWith(id: 'dos');
    await music.download(manager, other, scope);
    await complete(manager, other.id);
    expect(p.isWithin(music.folderPath!, music.localPath(scope, other.id)!), isTrue);
  });

  test('Canción borrada vuelve a descargarse', () async {
    await music.download(manager, track, scope);
    await complete(manager, track.id);
    await File(music.localPath(scope, track.id)!).delete();
    await music.rescan();
    expect(music.count(scope), 0);
    await music.download(manager, track, scope);
    await complete(manager, track.id);
    expect(transfers, 2);
  });

  test('Archivo sustituido no conserva la identidad de la canción anterior', () async {
    await music.download(manager, track, scope);
    await complete(manager, track.id);
    final path = music.localPath(scope, track.id)!;
    await File(path).writeAsString('otro archivo ajeno');
    await music.rescan();
    await music.download(manager, track, scope);
    await complete(manager, track.id);
    expect(transfers, 2);
    expect(await File(path).readAsString(), 'otro archivo ajeno');
  });

  test('Homónimos y servidores distintos no sobrescriben archivos', () async {
    await music.download(manager, track, scope);
    await complete(manager, track.id);
    final first = music.localPath(scope, track.id);
    final other = track.copyWith(id: 'dos');
    await music.download(manager, other, scope);
    await complete(manager, other.id);
    await music.download(manager, track, 'servidor-B');
    await complete(manager, track.id, server: 'servidor-B');
    expect(music.localPath(scope, other.id), isNot(first));
    expect(music.localPath('servidor-B', track.id), isNot(first));
    expect(music.count(scope), 2);
    expect(music.count('servidor-B'), 1);
  });

  test('Carpeta con enlace simbólico exterior no recibe descargas', () async {
    final outside = Directory(p.join(temp.path, 'fuera'));
    await outside.create();
    await Link(p.join(music.folderPath!, 'likes')).create(outside.path);
    await music.download(manager, track, scope, collection: 'likes');
    await expectLater(complete(manager, track.id), throwsStateError);
    expect(await outside.list().isEmpty, isTrue);
  });

  test('Sanea rutas, caracteres reservados y nombres especiales', () {
    expect(LocalMusicService.safeName('../otra/playlist'), '.._otra_playlist');
    expect(LocalMusicService.safeName('CON'), '_CON');
    expect(LocalMusicService.safeName('...'), 'Sin nombre');
  });
}
