import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/local_music_service.dart';
import 'package:crotowave/services/navidrome_service.dart';
import 'package:crotowave/services/offline_cache_service.dart';

void main() {
  late Directory root;
  late LocalMusicService music;
  late OfflineCacheService cache;
  late List<Track> catalog;
  var titles = <String, String>{};
  (File, List<int>)? removed;

  Track song(String id) => Track(
      id: id,
      title: 'Canción $id',
      artist: 'Artista',
      album: 'Álbum',
      duration: '180');

  setUp(() async {
    root = await Directory.systemTemp.createTemp('escaneo-control-');
    cache = OfflineCacheService(
        cacheRootDir: Directory('${root.path}/cache'),
        metadataStore: InMemoryOfflineCacheMetadataStore());
    titles = {};
    music = LocalMusicService(cache,
        stateFile: File('${root.path}/estado.json'),
        defaultRoot: Directory('${root.path}/Music'),
        metadataReader: (file) async => {
              'title': titles[file.uri.pathSegments.last],
              'artist': 'Artista',
              'album': 'Álbum',
              'duration': 180.0,
            });
    catalog = [];
    await music.initialize();
    await music.rescan();
  });

  tearDown(() async {
    music.dispose();
    await root.delete(recursive: true);
  });

  Future<File> audio(String id, [int seed = 0]) async {
    final file = File('${root.path}/Music/$id.flac');
    await file.parent.create(recursive: true);
    titles['$id.flac'] = 'Canción $id';
    return file.writeAsBytes([...id.codeUnits, seed, 7, 7]);
  }

  Future<void> scan([Future<List<Track>> Function()? loader]) => music.rescan(
      serverScope: 'servidor', catalogLoader: loader ?? () async => catalog);

  test('informa el avance por archivos y se limpia al terminar', () async {
    for (final id in ['a', 'b', 'c']) {
      await audio(id);
      catalog.add(song(id));
    }
    final seen = <LocalScanProgress>[];
    music.addListener(() {
      final p = music.scanProgress;
      if (p != null) seen.add(p);
    });
    await scan();

    final hashing = seen.where((p) => p.phase == LocalScanPhase.files).toList();
    expect(hashing, isNotEmpty);
    expect(hashing.last.done, hashing.last.total);
    expect(hashing.map((p) => p.done),
        orderedEquals([...hashing.map((p) => p.done)]..sort()));
    expect(seen.any((p) => p.phase == LocalScanPhase.catalog), isTrue);
    expect(seen.any((p) => p.phase == LocalScanPhase.matching), isTrue);
    expect(music.scanProgress, isNull);
    expect(music.scanning, isFalse);
    expect(music.lastScanCancelled, isFalse);
    expect(music.recoveredByLastScan, 3);
  });

  Future<void> removeThenRecreate(File file) async {
    final bytes = await file.readAsBytes();
    await file.delete();
    for (final id in ['x', 'y', 'z']) {
      await audio(id);
    }
    removed = (file, bytes);
  }

  test('control: un escaneo completo sí purga la ruta de un archivo ausente',
      () async {
    final file = await audio('a');
    catalog.add(song('a'));
    await scan();
    expect(music.localPath('servidor', 'a'), isNotNull);

    await removeThenRecreate(file);
    await scan();
    await removed!.$1.writeAsBytes(removed!.$2); // el archivo vuelve
    expect(music.localPath('servidor', 'a'), isNull,
        reason: 'sin la cancelación, el registro olvida la ruta vieja');
  });

  test('cancelar mientras se leen archivos no borra nada del índice', () async {
    final file = await audio('a');
    catalog.add(song('a'));
    await scan();
    expect(music.localPath('servidor', 'a'), isNotNull);

    await removeThenRecreate(file);
    void cancelOnFirstFile() {
      if (music.scanProgress?.phase == LocalScanPhase.files) {
        music.cancelScan();
      }
    }

    music.addListener(cancelOnFirstFile);
    await scan();
    music.removeListener(cancelOnFirstFile);
    await removed!.$1.writeAsBytes(removed!.$2); // el archivo vuelve

    expect(music.lastScanCancelled, isTrue);
    expect(music.scanning, isFalse);
    expect(music.scanProgress, isNull);
    expect(music.recoveredByLastScan, 0);
    expect(music.localPath('servidor', 'a'), isNotNull,
        reason: 'un escaneo cortado no debe olvidar rutas');
  });

  test('cancelar mientras se identifican conserva lo ya recuperado', () async {
    for (final id in ['a', 'b', 'c']) {
      await audio(id);
      catalog.add(song(id));
    }
    void cancelAfterFirst() {
      if (music.scanProgress?.phase == LocalScanPhase.matching &&
          music.recoveredByLastScan >= 1) {
        music.cancelScan();
      }
    }

    music.addListener(cancelAfterFirst);
    await scan();
    music.removeListener(cancelAfterFirst);

    expect(music.lastScanCancelled, isTrue);
    expect(music.recoveredByLastScan, inInclusiveRange(1, 2));
    expect(music.count('servidor'), music.recoveredByLastScan);
    expect(music.unidentifiedByLastScan, 3 - music.recoveredByLastScan);

    // Y se persistió: un servicio nuevo ve lo mismo.
    final reloaded = LocalMusicService(cache,
        stateFile: File('${root.path}/estado.json'),
        defaultRoot: Directory('${root.path}/Music'));
    addTearDown(reloaded.dispose);
    await reloaded.initialize();
    expect(reloaded.count('servidor'), music.recoveredByLastScan);
  });

  test('cancelar mientras se espera el catálogo no cuelga el escaneo',
      () async {
    await audio('a');
    final never = Completer<List<Track>>();
    final done = scan(() => never.future);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(music.scanProgress?.phase, LocalScanPhase.catalog);
    music.cancelScan();
    await done.timeout(const Duration(seconds: 2));
    expect(music.lastScanCancelled, isTrue);
    expect(music.count('servidor'), 0);
    expect(music.scanning, isFalse);
  });

  test('cancelar sin escaneo en curso no afecta al siguiente', () async {
    music.cancelScan();
    await audio('a');
    catalog.add(song('a'));
    await scan();
    expect(music.lastScanCancelled, isFalse);
    expect(music.recoveredByLastScan, 1);
  });

  test('un escaneo nuevo olvida la cancelación del anterior', () async {
    await audio('a');
    catalog.add(song('a'));
    void cancel() => music.cancelScan();
    music.addListener(cancel);
    await scan();
    music.removeListener(cancel);
    expect(music.lastScanCancelled, isTrue);

    await scan();
    expect(music.lastScanCancelled, isFalse);
    expect(music.recoveredByLastScan, 1);
  });
}
