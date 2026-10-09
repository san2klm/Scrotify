import 'dart:io';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/local_music_service.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/offline_cache_service.dart';
import 'package:navidrome_client/services/offline_download_manager.dart';
import 'package:navidrome_client/services/local_audio_metadata.dart';

void main() {
  late Directory root;
  late LocalMusicService music;
  late OfflineCacheService cache;
  final track = Track(
      id: 'antigua',
      title: 'Canción',
      artist: 'Artista',
      album: 'Álbum',
      duration: '180');
  List<Track> catalog = [];
  Map<String, dynamic>? tags;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('recuperar-musica-');
    cache = OfflineCacheService(
        cacheRootDir: Directory('${root.path}/cache'),
        metadataStore: InMemoryOfflineCacheMetadataStore());
    music = LocalMusicService(cache,
        stateFile: File('${root.path}/estado.json'),
        defaultRoot: Directory('${root.path}/Music'),
        metadataReader: (_) async => tags);
    tags = {
      'title': ' canción ',
      'artist': 'ARTISTA',
      'album': 'Álbum',
      'duration': 180.5
    };
    catalog = [track];
    await music.initialize();
    await music.rescan();
  });
  tearDown(() async {
    music.dispose();
    await root.delete(recursive: true);
  });

  Future<File> oldFile(String path, [List<int> bytes = const [1, 2, 3]]) async {
    final file = File('${root.path}/Music/$path');
    await file.parent.create(recursive: true);
    return file.writeAsBytes(bytes);
  }

  Future<void> scan() =>
      music.rescan(serverScope: 'servidor', catalogLoader: () async => catalog);

  test(
      'Recupera etiquetas en subcarpetas y conserva todas las copias sin duplicar canciones',
      () async {
    final file = await oldFile('playlist(Vieja)/archivo.flac');
    await oldFile('likes/copia.flac');
    await scan();
    expect(music.count('servidor'), 1);
    expect(music.localPath('servidor', track.id), isNotNull);
    expect(music.recoveredByLastScan, 1);
    expect(music.unidentifiedByLastScan, 0);
    final manager = OfflineDownloadManager(
        cacheService: cache,
        transport: FunctionalDownloadTransport(({
          required String serverScope,
          required String trackId,
          required File destinationFile,
          String? sourceMarker,
          void Function(int, int?)? onProgress,
          bool Function()? isCancelled,
        }) async {
          fail('No debe volver a descargar un archivo recuperado.');
        }),
        persistenceFile: File('${root.path}/tareas.json'));
    await music.download(manager, track, 'servidor', collection: 'likes');
    expect(manager.getTask('servidor', track.id), isNull);
    manager.dispose();
    await file.delete();
    await music.rescan();
    expect(music.localPath('servidor', track.id), endsWith('copia.flac'));
    music.dispose();
    music =
        LocalMusicService(cache, stateFile: File('${root.path}/estado.json'));
    await music.initialize();
    await music.rescan();
    expect(music.count('servidor'), 1);
    expect(music.count('otro-servidor'), 0);
  });

  test('No atribuye canciones por nombre ni ante etiquetas ambiguas', () async {
    await oldFile('Canción.mp3');
    tags = null;
    await scan();
    expect(music.count('servidor'), 0);
    tags = {'title': 'Canción', 'artist': 'Artista', 'duration': 180};
    catalog.add(Track(
        id: 'otra',
        album: 'Álbum',
        title: 'Canción',
        artist: 'Artista',
        duration: '180'));
    await scan();
    expect(music.count('servidor'), 0);
    expect(music.unidentifiedByLastScan, 1);
  });

  test('La recuperación consulta todas las páginas del servidor', () async {
    final offsets = <int>[];
    final nav = NavidromeService(httpClient: MockClient((request) async {
      final offset = int.parse(request.url.queryParameters['songOffset']!);
      offsets.add(offset);
      return http.Response(
          jsonEncode({
            'subsonic-response': {
              'status': 'ok',
              'searchResult3': {
                'song': List.generate(
                    offset == 0 ? 500 : 1,
                    (i) => {
                          'id': '${offset + i}',
                          'title': 'Canción',
                          'artist': 'Artista',
                          'album': 'Álbum',
                          'duration': 180
                        })
              }
            }
          }),
          200);
    }))
      ..setConnectedForTesting(
          url: 'https://musica.test', username: 'ana', password: 'prueba');
    try {
      expect(await nav.getDownloadRecoveryCatalog(), hasLength(501));
      expect(offsets, [0, 500]);
    } finally {
      nav.dispose();
    }
  });

  test(
      'El catálogo de recuperación propaga la falta de red sin usar el fallback local',
      () async {
    final nav = NavidromeService(httpClient: MockClient((_) async {
      throw const SocketException('Sin red');
    }))
      ..setConnectedForTesting(
          url: 'https://musica.test', username: 'ana', password: 'prueba');
    try {
      await expectLater(
          nav.getDownloadRecoveryCatalog(), throwsA(isA<SocketException>()));
    } finally {
      nav.dispose();
    }
  });

  test('El lector real interpreta etiquetas FLAC en Linux', () async {
    if (!Platform.isLinux) return;
    final file = File('${root.path}/etiquetas.flac');
    final result = await Process.run('ffmpeg', [
      '-v',
      'error',
      '-f',
      'lavfi',
      '-i',
      'anullsrc',
      '-t',
      '1',
      '-metadata',
      'title=Canción',
      '-metadata',
      'artist=Artista',
      '-metadata',
      'album=Álbum',
      file.path
    ]);
    expect(result.exitCode, 0);
    final metadata = await readLocalAudioMetadata(file);
    expect(metadata?['title'], 'Canción');
    expect(metadata?['artist'], 'Artista');
    expect(metadata?['duration'], closeTo(1, 0.01));
  },
      skip: !Platform.isLinux ||
          Platform.environment['SCROTIFY_METADATA_INTEGRATION'] != '1');

  test('Rechaza otra versión y recupera al volver a conectarse', () async {
    await oldFile('likes/antigua.mp3');
    tags!['duration'] = 230;
    await scan();
    expect(music.count('servidor'), 0);
    tags!['duration'] = 180;
    await music.rescan(
        serverScope: 'servidor',
        catalogLoader: () async => throw const SocketException('Sin red'));
    expect(music.recoveryUnavailable, isTrue);
    expect(music.count('servidor'), 0);
    await scan();
    expect(music.count('servidor'), 1);
    await music.rescan();
    expect(music.count('servidor'), 1);
  });
}
