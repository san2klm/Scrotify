import 'dart:convert';
import 'dart:io';

import 'package:crotowave/screens/home_screen.dart';
import 'package:crotowave/screens/mobile_home_screen.dart';
import 'package:crotowave/services/connect/connect_service.dart';
import 'package:crotowave/services/crotolink_controller.dart';
import 'package:crotowave/services/home_navigation_controller.dart';
import 'package:crotowave/services/local_music_service.dart';
import 'package:crotowave/services/navidrome_service.dart';
import 'package:crotowave/services/offline_cache_service.dart';
import 'package:crotowave/services/player_controller.dart';
import 'package:crotowave/services/settings_controller.dart';
import 'package:crotowave/services/theme_controller.dart';
import 'package:crotowave/widgets/offline_connection_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'support/app_fakes.dart';

/// Home y el aviso de conexión ante un servidor vivo que responde con errores.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Modo de /rest/search3.view: ok | http503 | failed | malformed.
  var search = 'ok';
  late Directory temp;
  late OfflineCacheService cache;
  late LocalMusicService music;
  late NavidromeService nav;

  String envelope(Map<String, dynamic> data) => jsonEncode({
        'subsonic-response': {'status': 'ok', ...data}
      });

  http.Response reply(http.Request request) {
    final path = request.url.path;
    if (path == '/rest/search3.view') {
      switch (search) {
        case 'http503':
          return http.Response('<html>503</html>', 503);
        case 'failed':
          return http.Response(
              jsonEncode({
                'subsonic-response': {
                  'status': 'failed',
                  'error': {'code': 40, 'message': 'secreto-del-servidor'}
                }
              }),
              200);
        case 'malformed':
          return http.Response('esto no es json', 200);
      }
      return http.Response(
          envelope({
            'searchResult3': {
              'song': [
                {
                  'id': '1',
                  'title': 'Cancion Visible',
                  'artist': 'Artista',
                  'album': 'Album',
                  'duration': 120,
                }
              ]
            }
          }),
          200);
    }
    if (path == '/rest/getAlbumList2.view') {
      return http.Response(envelope({'albumList2': {}}), 200);
    }
    return http.Response(envelope({}), 200);
  }

  Future<void> prepare(WidgetTester tester) async {
    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('crotowave-home-estado-');
      cache = OfflineCacheService(
          cacheRootDir: Directory(p.join(temp.path, 'cache')),
          metadataStore: InMemoryOfflineCacheMetadataStore());
      music = LocalMusicService(cache,
          stateFile: File(p.join(temp.path, 'biblioteca.json')),
          defaultRoot: Directory(p.join(temp.path, 'Música', 'CrotoWave')));
      await music.initialize();
    });
    nav = NavidromeService(httpClient: MockClient((r) async => reply(r)))
      ..localMusic = music
      ..setConnectedForTesting(
          url: 'https://musica.test', username: 'ana', password: 'clave');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await music
            .settled()
            .timeout(const Duration(seconds: 2), onTimeout: () {});
        nav.disconnect();
        music.dispose();
        await cache.close();
        await temp.delete(recursive: true);
      });
    });
  }

  Widget app(Widget home) => MultiProvider(
        providers: [
          ChangeNotifierProvider<NavidromeService>.value(value: nav),
          ChangeNotifierProvider<LocalMusicService>.value(value: music),
          ChangeNotifierProvider<PlayerController>(create: (_) => IdlePlayer()),
          ChangeNotifierProvider<ThemeController>(
              create: (_) => ThemeController()),
          ChangeNotifierProvider<SettingsController>(
              create: (_) => SettingsController()),
          ChangeNotifierProvider<HomeNavigationController>(
              create: (_) => HomeNavigationController()),
          ChangeNotifierProvider<ConnectService>(
              create: (_) => idleConnectService()),
          ChangeNotifierProvider<CrotoLinkController>(
              create: (_) => IdleCrotoLink()),
        ],
        child: MaterialApp(home: home),
      );

  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 80 && !done(); i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  bool shown(Finder finder) => finder.evaluate().isNotEmpty;

  final screens = <String, (Size, Widget Function())>{
    'desktop': (const Size(1280, 800), () => const HomeScreen()),
    'móvil': (const Size(400, 800), () => const MobileHomeScreen()),
  };

  for (final entry in screens.entries) {
    final (size, home) = entry.value;

    group('Inicio ${entry.key}', () {
      setUp(() => search = 'ok');

      Future<void> open(WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await prepare(tester);
        await tester.pumpWidget(app(home()));
      }

      testWidgets('503 persistente: error útil y reintento que recarga',
          (tester) async {
        search = 'http503';
        await open(tester);
        await pumpUntil(tester, () => shown(find.byType(LibraryLoadError)));
        expect(find.text('El servidor respondió HTTP 503.'), findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);
        expect(nav.serverDegraded, isTrue);
        expect(nav.connected, isTrue);

        // Con el endpoint aún caído, reintentar no presenta un éxito.
        await tester.tap(find.text('Reintentar'));
        await pumpUntil(
            tester, () => shown(find.text('El servidor respondió HTTP 503.')));
        expect(find.byType(LibraryLoadError), findsOneWidget);

        // Recuperado: el mismo botón trae el catálogo y desaparece el aviso.
        search = 'ok';
        await tester.tap(find.text('Reintentar'));
        await pumpUntil(tester, () => !shown(find.byType(LibraryLoadError)));
        expect(find.byType(LibraryLoadError), findsNothing);
        expect(nav.serverDegraded, isFalse);
        expect(tester.takeException(), isNull);
      });

      testWidgets('credenciales rechazadas: mensaje sin texto del servidor',
          (tester) async {
        search = 'failed';
        await open(tester);
        await pumpUntil(tester, () => shown(find.byType(LibraryLoadError)));
        expect(find.text('El servidor rechazó las credenciales (código 40).'),
            findsOneWidget);
        expect(find.textContaining('secreto-del-servidor'), findsNothing);
        expect(nav.serverDegraded, isFalse); // no es transporte
        expect(tester.takeException(), isNull);
      });

      testWidgets('respuesta malformada: error visible y reintentable',
          (tester) async {
        search = 'malformed';
        await open(tester);
        await pumpUntil(tester, () => shown(find.byType(LibraryLoadError)));
        expect(find.textContaining('ilegible'), findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }

  group('OfflineConnectionBanner degradado', () {
    setUp(() => search = 'http503');

    testWidgets('mantiene el aviso mientras falle y se va al recuperar',
        (tester) async {
      await prepare(tester);
      await tester.runAsync(() async {
        await expectLater(
            nav.getTracks(), throwsA(isA<SubsonicHttpException>()));
      });
      await tester
          .pumpWidget(app(const Scaffold(body: OfflineConnectionBanner())));
      expect(find.textContaining('El servidor responde con errores'),
          findsOneWidget);

      // El endpoint principal sigue caído: el aviso persiste y se explica.
      await tester.tap(find.text('Reintentar'));
      await pumpUntil(tester, () => shown(find.byType(SnackBar)));
      expect(find.textContaining('sigue respondiendo con errores'),
          findsOneWidget);
      expect(nav.serverDegraded, isTrue);

      search = 'ok';
      await tester.pump(const Duration(seconds: 5)); // cierra el SnackBar
      await tester.tap(find.text('Reintentar'));
      await pumpUntil(tester, () => !nav.serverDegraded);
      await tester.pump(const Duration(milliseconds: 16));
      expect(nav.serverDegraded, isFalse);
      expect(find.textContaining('El servidor responde con errores'),
          findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
