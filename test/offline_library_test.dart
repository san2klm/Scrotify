import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:navidrome_client/screens/login_screen.dart';
import 'package:navidrome_client/screens/home_shell.dart';
import 'package:navidrome_client/models/server_profile.dart';
import 'package:navidrome_client/services/server_profiles_controller.dart';
import 'package:navidrome_client/services/local_music_service.dart';
import 'package:navidrome_client/services/connect/connect_service.dart';
import 'package:navidrome_client/services/jam_controller.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/offline_cache_service.dart';
import 'package:navidrome_client/services/player_controller.dart';
import 'package:navidrome_client/services/theme_controller.dart';
import 'package:path/path.dart' as p;

import 'support/app_fakes.dart';

class _CuentaGuardada extends ChangeNotifier
    implements ServerProfilesController {
  final ServerProfile profile = ServerProfile(
      url: 'https://musica.test', username: 'ana', password: 'clave-de-prueba');
  @override
  Future<void> ensureLoaded() async {}
  @override
  List<ServerProfile> get profiles => [profile];
  @override
  ServerProfile? get activeProfile => profile;
  @override
  String? get activeProfileId => profile.id;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late LocalMusicService music;
  late OfflineCacheService cache;
  late NavidromeService nav;
  late bool network;
  late int requests;
  const url = 'https://musica.test';
  const user = 'ana';
  final songs = [
    Track(
        id: '1',
        title: 'Primera',
        artist: 'Artista',
        album: 'Álbum',
        duration: '180',
        suffix: 'mp3'),
    Track(
        id: '2',
        title: 'Segunda',
        artist: 'Artista',
        album: 'Álbum',
        duration: '200',
        suffix: 'mp3'),
    Track(
        id: '3',
        title: 'Sin descargar',
        artist: 'Artista',
        album: 'Álbum',
        duration: '210',
        suffix: 'mp3'),
  ];
  Map<String, dynamic> songJson(Track track) => {
        'id': track.id,
        'title': track.title,
        'artist': track.artist,
        'album': track.album,
        'duration': int.parse(track.duration),
        'suffix': 'mp3'
      };

  OfflineCacheService newCache() => OfflineCacheService(
      cacheRootDir: Directory(p.join(temp.path, 'cache')),
      metadataStore: InMemoryOfflineCacheMetadataStore());
  LocalMusicService newMusic() => LocalMusicService(cache,
      stateFile: File(p.join(temp.path, 'biblioteca.json')),
      defaultRoot: Directory(p.join(temp.path, 'Música', 'CrotoWave')));
  NavidromeService newNav() {
    final client = MockClient((request) async {
      requests++;
      if (!network) throw const SocketException('Sin red');
      final data = <String, dynamic>{'status': 'ok'};
      switch (request.url.path) {
        case '/rest/getPlaylists.view':
          data['playlists'] = {
            'playlist': [
              {
                'id': 'rock',
                'name': 'Rock',
                'songCount': 3,
                'duration': 590,
                'owner': user,
                'coverArt': 'portada'
              }
            ]
          };
        case '/rest/getPlaylist.view':
          data['playlist'] = {
            'id': 'rock',
            'name': 'Rock',
            'songCount': 3,
            'duration': 590,
            'owner': user,
            'entry': [
              songJson(songs[1]),
              songJson(songs[2]),
              songJson(songs[0])
            ]
          };
        case '/rest/getStarred2.view':
          data['starred2'] = {
            'song': [songJson(songs[0]), songJson(songs[2])]
          };
        case '/rest/search3.view':
          data['searchResult3'] = {'song': songs.map(songJson).toList()};
      }
      return http.Response(jsonEncode({'subsonic-response': data}), 200);
    });
    return NavidromeService(httpClient: client)..localMusic = music;
  }

  Future<void> seed(Track track, {String? folder}) async {
    final dir = Directory(
        folder == null ? music.folderPath! : p.join(music.folderPath!, folder));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, '${track.title}.mp3'));
    await file.writeAsBytes([1, 2, 3, ...track.id.codeUnits]);
    final entry = await cache.registerFile(
        serverScope: nav.serverScope!,
        trackId: track.id,
        localPath: file.path,
        title: track.title,
        artist: track.artist,
        album: track.album,
        durationSeconds: int.parse(track.duration));
    await music.completed(entry);
  }

  Future<void> saveOnline() async {
    await nav.getPlaylists();
    await nav.getPlaylistTracks('rock');
    await nav.getStarred();
  }

  setUp(() async {
    temp =
        await Directory.systemTemp.createTemp('scrotify-biblioteca-offline-');
    network = true;
    requests = 0;
    cache = newCache();
    music = newMusic();
    await music.initialize();
    nav = newNav()
      ..setConnectedForTesting(
          url: url, username: user, password: 'clave-de-prueba');
  });
  tearDown(() async {
    // initialize() lanza un reescaneo en segundo plano que guarda el estado en
    // la carpeta temporal: hay que esperarlo antes de borrarla.
    // (En un testWidgets el escaneo vive en el reloj simulado y no avanza desde
    // aquí: el tope evita colgar ese caso; en los demás termina enseguida.)
    await music.settled().timeout(const Duration(seconds: 2), onTimeout: () {});
    nav.dispose();
    music.dispose();
    await cache.close();
    await temp.delete(recursive: true);
  });

  test(
      'Al perder internet las playlists y likes conservan orden y solo audio disponible',
      () async {
    await seed(songs[0]);
    await seed(songs[1]);
    await saveOnline();
    network = false;
    final playlists = await nav.getPlaylists();
    expect(playlists.single.name, 'Rock');
    expect(playlists.single.songCount, 2);
    expect(nav.offlineMode, isTrue);
    expect((await nav.getPlaylistTracks('rock')).map((track) => track.id),
        ['2', '1']);
    expect((await nav.getStarred()).map((track) => track.id), ['1']);
    expect((await nav.getTracks()).map((track) => track.id), ['1', '2']);
    expect((await nav.getRecentlyAddedTracks()).length, 2);
  });

  test(
      'Después de reiniciar sin internet abre la cuenta guardada y restaura colecciones',
      () async {
    await seed(songs[0]);
    await seed(songs[1]);
    await saveOnline();
    nav.dispose();
    music.dispose();
    await cache.close();
    network = false;
    cache = newCache();
    music = newMusic();
    nav = newNav();
    final before = requests;
    expect(await nav.openOfflineLibrary(url, user, 'clave-de-prueba'), isTrue);
    expect(nav.connected, isFalse);
    expect(nav.currentSessionKey, isNotNull);
    expect((await nav.getPlaylists()).single.id, 'rock');
    expect((await nav.getPlaylistTracks('rock')).map((track) => track.id),
        ['2', '1']);
    expect((await nav.getStarred()).single.id, '1');
    expect(await nav.getPlaylist('rock'), isNotNull);
    expect(requests, before);
    final stored =
        await File(p.join(temp.path, 'biblioteca.json')).readAsString();
    expect(stored, isNot(contains('clave-de-prueba')));
    expect(stored, isNot(contains('https://')));
    expect(stored, isNot(contains('token=')));
  });

  test(
      'Las descargas del índice anterior recuperan sus carpetas de playlist y likes',
      () async {
    await seed(songs[0], folder: 'playlist(Rock viejo)');
    await seed(songs[1], folder: 'likes');
    expect(await nav.openOfflineLibrary(url, user, 'clave-de-prueba'), isTrue);
    final localPlaylist = (await nav.getPlaylists()).single;
    expect(localPlaylist.name, 'Rock viejo');
    expect((await nav.getPlaylistTracks(localPlaylist.id)).single.id, '1');
    expect((await nav.getStarred()).single.id, '2');
  });

  test('Las playlists y likes guardados no se atribuyen a otro usuario',
      () async {
    await seed(songs[0], folder: 'playlist(Rock)');
    await seed(songs[1], folder: 'likes');
    await saveOnline();
    expect(
        await nav.openOfflineLibrary(url, 'otra-cuenta', 'otra-clave'), isTrue);
    expect(await nav.getPlaylists(), isEmpty);
    expect(await nav.getStarred(), isEmpty);
    expect(await nav.getPlaylistTracks('rock'), isEmpty);
  });

  test('Un audio borrado se omite al abrir una playlist sin red', () async {
    await seed(songs[0]);
    await seed(songs[1]);
    await saveOnline();
    await File(music.localPath(nav.serverScope!, '2')!).delete();
    network = false;
    await nav.getPlaylists();
    expect((await nav.getPlaylistTracks('rock')).single.id, '1');
  });

  test(
      'Colecciones vacías actualizadas no se reconstruyen con carpetas antiguas',
      () async {
    await seed(songs[0], folder: 'playlist(Rock)');
    await seed(songs[1], folder: 'likes');
    await music.bindLegacyCollections(nav.serverScope!, nav.userScope!);
    await music.rememberPlaylists(nav.userScope!, []);
    await music.rememberLikes(nav.userScope!, []);
    await nav.openOfflineLibrary(url, user, 'clave-de-prueba');
    expect(await nav.getPlaylists(), isEmpty);
    expect(await nav.getStarred(), isEmpty);
  });

  test(
      'La cuenta guardada sin esquema ni barra final recupera la misma biblioteca',
      () async {
    await seed(songs[0]);
    expect(
        await nav.openOfflineLibrary('musica.test/', user, 'clave-de-prueba'),
        isTrue);
    expect(nav.serverUrl, url);
    expect((await nav.getTracks()).single.id, '1');
  });

  test('Sin audio para ese servidor no entra en modo local', () async {
    expect(await nav.openOfflineLibrary('https://otro.test', user, 'clave'),
        isFalse);
    expect(nav.offlineMode, isFalse);
  });

  test('Volver a conectar restaura las listas completas del servidor',
      () async {
    await seed(songs[0]);
    await saveOnline();
    network = false;
    await nav.getTracks();
    expect(nav.offlineMode, isTrue);
    network = true;
    await nav.reconnect();
    expect(nav.connected, isTrue);
    expect(nav.offlineMode, isFalse);
    expect((await nav.getPlaylistTracks('rock')).length, 3);
  });

  test('El arranque local distingue fallos de red de errores de autenticación',
      () {
    expect(NavidromeService.isNetworkFailure(const SocketException('sin red')),
        isTrue);
    expect(
        NavidromeService.isNetworkFailure(Exception('Authentication failed')),
        isFalse);
  });

  testWidgets('El arranque sin internet entra en Inicio con la cuenta guardada',
      (tester) async {
    await tester.runAsync(() async {
      await seed(songs[0], folder: 'playlist(Rock guardado)');
      nav.dispose();
      network = false;
      nav = newNav();
    });
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<NavidromeService>.value(value: nav),
      ChangeNotifierProvider<LocalMusicService>.value(value: music),
      ChangeNotifierProvider<PlayerController>(create: (_) => IdlePlayer()),
      ChangeNotifierProvider<ConnectService>(
          create: (_) => idleConnectService()),
      ChangeNotifierProvider<JamController>(create: (_) => IdleJam()),
      ChangeNotifierProvider<ThemeController>(create: (_) => ThemeController()),
      ChangeNotifierProvider<ServerProfilesController>(
          create: (_) => _CuentaGuardada()),
    ], child: const MaterialApp(home: LoginScreen())));
    for (var frame = 0; frame < 40; frame++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 16));
      if (find.byType(HomeShell).evaluate().isNotEmpty) break;
    }
    await tester.pumpAndSettle();
    expect(nav.offlineMode, isTrue);
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.text('Descargadas'), findsNothing);
    expect(find.text('Sin conexión · Música del dispositivo'), findsOneWidget);
    expect(tester.takeException(), isNull);
    nav.disconnect(); // detiene el sondeo de reconexión automática
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
