// Recuperación de descargas antiguas en un dispositivo Android real: usa el
// lector de etiquetas de verdad (MediaMetadataRetriever vía el canal
// `scrotify/music_storage`) y el almacenamiento compartido, que las pruebas
// unitarias de escritorio no pueden ejercitar.
//
// Requisitos (el script `tool/run_android_integration.sh` los prepara):
//  * un emulador o teléfono Android 11+ conectado;
//  * «Acceso a todos los archivos» concedido a la app:
//      adb shell appops set <paquete> MANAGE_EXTERNAL_STORAGE allow
//
//   flutter test integration_test/local_music_recovery_test.dart \
//       --flavor phone -d <dispositivo>

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:navidrome_client/services/android_music_storage.dart';
import 'package:navidrome_client/services/local_audio_metadata.dart';
import 'package:navidrome_client/services/local_music_service.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/offline_cache_service.dart';

import 'fixtures/tagged_flac.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;
  late Directory music;
  late LocalMusicService service;

  final matching = Track(
      id: 'it-1',
      title: 'Canción IT',
      artist: 'Artista IT',
      album: 'Álbum IT',
      duration: '1');

  setUpAll(() async {
    expect(await AndroidMusicStorage.ensureAccess(), isTrue,
        reason: 'Concede «Acceso a todos los archivos» a la app: '
            'adb shell appops set <paquete> MANAGE_EXTERNAL_STORAGE allow');
  });

  setUp(() async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    sandbox = Directory('/storage/emulated/0/Music/ScrotifyIT_$stamp');
    music = Directory('${sandbox.path}/Music');
    await music.create(recursive: true);
    final state = Directory.systemTemp.createTempSync('scrotify_it_state');
    addTearDown(() => state.deleteSync(recursive: true));
    service = LocalMusicService(
      OfflineCacheService(
          cacheRootDir: Directory('${state.path}/cache'),
          metadataStore: InMemoryOfflineCacheMetadataStore()),
      stateFile: File('${state.path}/estado.json'),
      defaultRoot: music,
    );
    await service.initialize();
  });

  tearDown(() async {
    service.dispose();
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  Future<void> scan(List<Track> catalog) => service.rescan(
      requestAccess: false,
      serverScope: 'it-server',
      catalogLoader: () async => catalog);

  testWidgets('el lector nativo devuelve título, artista, álbum y duración',
      (tester) async {
    final file = File('${music.path}/etiquetas.flac')
      ..writeAsBytesSync(taggedFlac());
    final tags = await readLocalAudioMetadata(file);
    expect(tags, isNotNull);
    expect(tags!['title'], 'Canción IT');
    expect(tags['artist'], 'Artista IT');
    expect(tags['album'], 'Álbum IT');
    expect(tags['duration'], closeTo(1.0, 0.2));
  });

  testWidgets('un archivo corrupto no devuelve etiquetas ni lanza',
      (tester) async {
    final file = File('${music.path}/roto.flac')
      ..writeAsBytesSync(List.filled(64, 7));
    expect(await readLocalAudioMetadata(file), isNull);
  });

  testWidgets(
      'recupera un archivo antiguo de una subcarpeta y junta las copias en una',
      (tester) async {
    Directory('${music.path}/Playlists/Vieja').createSync(recursive: true);
    Directory('${music.path}/likes').createSync(recursive: true);
    File('${music.path}/Playlists/Vieja/a.flac')
        .writeAsBytesSync(taggedFlac());
    File('${music.path}/likes/copia.flac').writeAsBytesSync(taggedFlac());

    await scan([matching]);

    expect(service.recoveredByLastScan, 1);
    expect(service.unidentifiedByLastScan, 0);
    expect(service.count('it-server'), 1,
        reason: 'dos copias del mismo contenido son una sola canción');
    expect(service.localPath('it-server', 'it-1'), isNotNull);
    expect(service.lastScanCancelled, isFalse);
  });

  testWidgets('etiquetas ambiguas en el catálogo no se atribuyen',
      (tester) async {
    File('${music.path}/a.flac').writeAsBytesSync(taggedFlac());
    final twin = Track(
        id: 'it-2',
        title: 'Canción IT',
        artist: 'Artista IT',
        album: 'Álbum IT',
        duration: '1');

    await scan([matching, twin]);

    expect(service.recoveredByLastScan, 0);
    expect(service.unidentifiedByLastScan, 1);
    expect(service.count('it-server'), 0);
  });

  testWidgets('un archivo corrupto cuenta como sin identificar y no frena',
      (tester) async {
    File('${music.path}/roto.flac').writeAsBytesSync(List.filled(64, 7));
    File('${music.path}/bien.flac').writeAsBytesSync(taggedFlac());

    await scan([matching]);

    expect(service.recoveredByLastScan, 1);
    expect(service.unidentifiedByLastScan, 1);
  });

  testWidgets('la recuperación sobrevive a reabrir el servicio',
      (tester) async {
    File('${music.path}/a.flac').writeAsBytesSync(taggedFlac());
    await scan([matching]);
    expect(service.count('it-server'), 1);

    final reopened = LocalMusicService(service.cache,
        stateFile: service.stateFile, defaultRoot: music);
    addTearDown(reopened.dispose);
    await reopened.initialize();
    expect(reopened.count('it-server'), 1);
    expect(reopened.localPath('it-server', 'it-1'), isNotNull);
  });

  testWidgets('cancelar a mitad conserva el índice anterior', (tester) async {
    File('${music.path}/a.flac').writeAsBytesSync(taggedFlac());
    await scan([matching]);
    expect(service.count('it-server'), 1);

    for (var i = 0; i < 5; i++) {
      File('${music.path}/extra$i.flac')
          .writeAsBytesSync([...taggedFlac(), i]); // contenido distinto
    }
    void cancel() {
      if (service.scanProgress?.phase == LocalScanPhase.files) {
        service.cancelScan();
      }
    }

    service.addListener(cancel);
    await scan([matching]);
    service.removeListener(cancel);

    expect(service.lastScanCancelled, isTrue);
    expect(service.count('it-server'), 1);
    expect(service.localPath('it-server', 'it-1'), isNotNull);
  });
}
