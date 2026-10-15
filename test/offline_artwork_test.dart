import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:navidrome_client/services/local_artwork_store.dart';
import 'package:navidrome_client/services/local_music_service.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/offline_cache_service.dart';
import 'package:navidrome_client/services/offline_download_manager.dart';
import 'package:navidrome_client/widgets/cover_art.dart';
import 'package:navidrome_client/services/theme_controller.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC');
  const scope = 'https://musica.test';
  const user = 'ana';
  final track = Track(
      id: '1',
      title: 'Canción',
      artist: 'Artista',
      album: 'Álbum',
      duration: '180',
      albumArtUrl:
          '$scope/rest/getCoverArt.view?id=album&u=ana&t=secreto&s=sal',
      suffix: 'mp3',
      genre: 'Rock',
      trackNumber: 3,
      mbid: 'mbid-1',
      isrc: 'isrc-1');

  OfflineCacheService newCache() => OfflineCacheService(
      cacheRootDir: Directory(p.join(temp.path, 'cache')),
      metadataStore: InMemoryOfflineCacheMetadataStore());
  final created = <LocalMusicService>[];
  LocalMusicService newMusic(OfflineCacheService cache, http.Client client) {
    final music = LocalMusicService(cache,
        stateFile: File(p.join(temp.path, 'biblioteca.json')),
        defaultRoot: Directory(p.join(temp.path, 'Music')),
        artworkClient: client);
    created.add(music);
    return music;
  }

  Future<void> seed(LocalMusicService music, OfflineCacheService cache) async {
    await music.initialize();
    final audio = File(p.join(music.folderPath!, 'Canción.mp3'));
    await audio.writeAsBytes([1, 2, 3]);
    final entry = await cache.registerFile(
        serverScope: scope,
        trackId: track.id,
        localPath: audio.path,
        title: track.title,
        artist: track.artist,
        album: track.album,
        durationSeconds: 180);
    await music.completed(entry);
  }

  setUp(() async =>
      temp = await Directory.systemTemp.createTemp('scrotify-artwork-'));
  tearDown(() async {
    // Esperar el reescaneo en segundo plano antes de borrar la carpeta.
    for (final music in created) {
      await music.settled();
    }
    created.clear();
    // En Windows el decodificador de imágenes suelta el archivo un poco
    // después de que el widget desaparece: reintentar el borrado.
    for (var attempt = 0;; attempt++) {
      try {
        await temp.delete(recursive: true);
        break;
      } on FileSystemException {
        if (attempt >= 5) {
          // Limpieza de mejor esfuerzo: la carpeta está en el temporal del sistema.
          if (Platform.isWindows) break;
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  test(
      'Reiniciar sin internet conserva portadas y metadatos en canciones, likes y playlists',
      () async {
    var calls = 0;
    final online = MockClient((_) async {
      calls++;
      return http.Response.bytes(png, 200);
    });
    var cache = newCache();
    var music = newMusic(cache, online);
    await seed(music, cache);
    await music.cacheDownloadedArtwork(scope, [track]);
    final nav = NavidromeService(
        httpClient:
            MockClient((_) async => throw const SocketException('Sin red')))
      ..localMusic = music;
    expect(await nav.openOfflineLibrary(scope, user, 'clave'), isTrue);
    final account = nav.userScope!;
    final playlist = Playlist(
        id: 'p1',
        name: 'Rock',
        songCount: 1,
        duration: 180,
        coverArtUrl: track.albumArtUrl);
    await music.rememberLikes(account, [track]);
    await music.rememberPlaylist(account, playlist);
    await music.rememberPlaylistTracks(account, playlist.id, [track]);
    await music.cachePlaylistArtwork(scope, playlist);
    expect(calls, 2);
    final contents =
        await File(p.join(temp.path, 'biblioteca.json')).readAsString();
    expect(contents, isNot(contains('secreto')));
    expect(contents, isNot(contains('getCoverArt')));
    nav.dispose();
    music.dispose();
    await cache.close();

    var offlineCalls = 0;
    cache = newCache();
    music = newMusic(cache, MockClient((_) async {
      offlineCalls++;
      throw const SocketException('Sin red');
    }));
    await music.initialize();
    final restored = music.downloadedTracks(scope).single;
    expect(restored.genre, 'Rock');
    expect(restored.trackNumber, 3);
    expect(restored.mbid, 'mbid-1');
    expect(restored.isrc, 'isrc-1');
    final cover = Uri.parse(restored.albumArtUrl!);
    expect(cover.scheme, 'file');
    expect(await File.fromUri(cover).readAsBytes(), png);
    expect(music.offlineLikes(scope, account).single.albumArtUrl,
        restored.albumArtUrl);
    expect(music.offlinePlaylistTracks(scope, account, 'p1').single.albumArtUrl,
        restored.albumArtUrl);
    expect(
        Uri.parse(music.offlinePlaylists(scope, account).single.coverArtUrl!)
            .scheme,
        'file');
    await music.cacheDownloadedArtwork(scope, [restored]);
    expect(offlineCalls, 0);
    music.dispose();
    await cache.close();
  });

  test(
      'Portadas inválidas se reintentan; peticiones simultáneas se deduplican y los servidores se separan',
      () async {
    var invalid = true;
    var calls = 0;
    final store = LocalArtworkStore(Directory(p.join(temp.path, 'artwork')),
        client: MockClient((_) async {
      calls++;
      return invalid
          ? http.Response('{"error":"sin portada"}', 200)
          : http.Response.bytes(png, 200);
    }));
    expect(await store.cache(scope, 'track:1', track.albumArtUrl), isNull);
    expect(store.path(scope, 'track:1'), isNull);
    invalid = false;
    final paths = await Future.wait([
      store.cache(scope, 'track:1', track.albumArtUrl),
      store.cache(scope, 'track:1', track.albumArtUrl)
    ]);
    expect(paths[0], isNotNull);
    expect(paths[0], paths[1]);
    expect(calls, 2);
    final other =
        await store.cache('otro servidor', 'track:1', track.albumArtUrl);
    expect(other, isNot(paths[0]));
    expect(calls, 3);
    store.dispose();
  });

  test('Un fallo al obtener la portada no impide descargar el audio', () async {
    final cache = newCache();
    final music = newMusic(
        cache, MockClient((_) async => http.Response('Sin portada', 503)));
    final manager = OfflineDownloadManager(
        cacheService: cache,
        persistenceFile: File(p.join(temp.path, 'tareas.json')),
        transport: FunctionalDownloadTransport(({
          required String serverScope,
          required String trackId,
          required File destinationFile,
          String? sourceMarker,
          void Function(int, int?)? onProgress,
          bool Function()? isCancelled,
        }) async {
          await destinationFile.writeAsBytes([1, 2, 3]);
        }))
      ..beforeInitialize = music.initialize
      ..destinationResolver = music.destination
      ..onFileRegistered = music.completed;
    final done = Completer<void>();
    manager.addListener(() {
      final task = manager.getTask(scope, track.id);
      if (!done.isCompleted && task?.status == DownloadTaskStatus.completed) {
        done.complete();
      }
      if (!done.isCompleted && task?.status == DownloadTaskStatus.failed) {
        done.completeError(StateError('Falló el audio'));
      }
    });
    await music.download(manager, track, scope);
    await done.future.timeout(const Duration(seconds: 5));
    expect(music.count(scope), 1);
    expect(music.artworkForTrack(scope, track), isNull);
    await manager.flushPersistence();
    manager.dispose();
    music.dispose();
    await cache.close();
  });

  testWidgets(
      'La carátula usa el archivo local sin conexión aunque la cola conserve una URL remota',
      (tester) async {
    late OfflineCacheService cache;
    late LocalMusicService music;
    late NavidromeService nav;
    await tester.runAsync(() async {
      cache = newCache();
      music = newMusic(
          cache, MockClient((_) async => http.Response.bytes(png, 200)));
      nav = NavidromeService(
          httpClient:
              MockClient((_) async => throw const SocketException('Sin red')))
        ..localMusic = music;
      await seed(music, cache);
      await music.cacheDownloadedArtwork(scope, [track]);
      await nav.openOfflineLibrary(scope, user, 'clave');
    });
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>(
              create: (_) => ThemeController()),
          ChangeNotifierProvider<NavidromeService>.value(value: nav),
          ChangeNotifierProvider<LocalMusicService>.value(value: music),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: CoverArt(
                    url: track.albumArtUrl,
                    artist: track.artist,
                    album: track.album,
                    title: track.title,
                    width: 80,
                    height: 80)))));
    await tester.runAsync(() async =>
        await Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
    final provider = tester.widget<Image>(find.byType(Image)).image;
    expect(provider, isA<ResizeImage>());
    expect((provider as ResizeImage).imageProvider, isA<FileImage>());
    expect(find.byIcon(Icons.music_note), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    nav.dispose();
    music.dispose();
    await tester.runAsync(cache.close);
    // Windows no borra la carpeta mientras la imagen decodificada la usa.
    imageCache.clear();
    imageCache.clearLiveImages();
    await tester.runAsync(() async =>
        await Future<void>.delayed(const Duration(milliseconds: 50)));
  });
}
