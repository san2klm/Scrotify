import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:crotowave/screens/home_screen.dart';
import 'package:crotowave/screens/mobile_home_screen.dart';
import 'package:crotowave/services/connect/connect_service.dart';
import 'package:crotowave/services/crotolink_controller.dart';
import 'package:crotowave/services/home_navigation_controller.dart';
import 'package:crotowave/services/navidrome_service.dart';
import 'package:crotowave/services/player_controller.dart';
import 'package:crotowave/services/theme_controller.dart';
import 'package:crotowave/widgets/global_top_bar.dart';
import 'package:crotowave/widgets/search_explore_field.dart';

import 'support/app_fakes.dart';

const _url = 'http://192.168.1.50:4533';

http.Response _songs(String title) => http.Response(
    jsonEncode({
      'subsonic-response': {
        'status': 'ok',
        'searchResult3': {
          'song': [
            {
              'id': 'id-$title',
              'title': title,
              'artist': 'Artista',
              'album': 'Álbum',
              'duration': 100,
              'genre': 'rock',
            }
          ]
        }
      }
    }),
    200);

http.Response _json(Object body) => http.Response(jsonEncode(body), 200);

/// Escenario: una búsqueda de «rock» de ana queda en vuelo (compuerta) y el
/// usuario cambia a beto antes de que responda.
class _Scenario {
  final gates = <String, Completer<http.Response>>{};
  final homeNav = HomeNavigationController();
  late final NavidromeService nav;
  late final http.Client client;

  _Scenario() {
    client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('search3.view')) {
        final key = '${request.url.queryParameters['u']}:'
            '${request.url.queryParameters['query']}';
        final gate = gates[key];
        if (gate != null) return gate.future;
      }
      if (path.endsWith('getGenres.view')) {
        return _json({
          'subsonic-response': {
            'status': 'ok',
            'genres': {'genre': <Object>[]}
          }
        });
      }
      return _json({
        'subsonic-response': {
          'status': 'ok',
          'searchResult3': {'song': <Object>[]},
          'albumList2': {'album': <Object>[]},
          'playlists': {'playlist': <Object>[]},
        }
      });
    });
    nav = NavidromeService(httpClient: client);
    connect('ana');
  }

  void connect(String user) => nav.setConnectedForTesting(
      url: _url, username: user, password: 'clave-$user', client: client);

  Future<void> pump(WidgetTester tester, {required bool mobile}) async {
    tester.view.physicalSize =
        mobile ? const Size(400, 800) : const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<NavidromeService>.value(value: nav),
        ChangeNotifierProvider<PlayerController>.value(value: IdlePlayer()),
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider<HomeNavigationController>.value(value: homeNav),
        ChangeNotifierProvider<ConnectService>(
            create: (_) => idleConnectService()),
        ChangeNotifierProvider<CrotoLinkController>(
            create: (_) => IdleCrotoLink()),
      ],
      child: MaterialApp(
          home: mobile ? const MobileHomeScreen() : const HomeScreen()),
    ));
    await tester.pumpAndSettle();
  }

  /// Cambia de cuenta y deja que Home procese el cambio de sesión.
  Future<void> switchTo(WidgetTester tester, String user) async {
    connect(user);
    await tester.pump();
    await tester.pump();
  }
}

void main() {
  for (final mobile in [false, true]) {
    final screen = mobile ? 'móvil' : 'escritorio';

    group('Home $screen: búsquedas atadas a su sesión', () {
      testWidgets('control: el resultado de la sesión vigente se muestra',
          (tester) async {
        final s = _Scenario();
        s.gates['ana:rock'] = Completer();
        await s.pump(tester, mobile: mobile);

        s.homeNav.open(query: 'rock');
        await tester.pump();
        s.gates['ana:rock']!.complete(_songs('Canción de Ana'));
        await tester.pumpAndSettle();

        expect(find.text('Canción de Ana'), findsWidgets);
      });

      testWidgets('un resultado de texto de la sesión anterior no se aplica',
          (tester) async {
        final s = _Scenario();
        s.gates['ana:rock'] = Completer();
        await s.pump(tester, mobile: mobile);

        s.homeNav.open(query: 'rock');
        await tester.pump();
        await s.switchTo(tester, 'beto');
        s.gates['ana:rock']!.complete(_songs('Canción de Ana'));
        await tester.pumpAndSettle();

        expect(find.text('Canción de Ana'), findsNothing,
            reason: 'la búsqueda de ana no puede aparecer bajo beto');
      });

      testWidgets(
          'un error tardío de la sesión anterior no borra el resultado vigente',
          (tester) async {
        final s = _Scenario();
        s.gates['ana:rock'] = Completer();
        s.gates['beto:rock'] = Completer();
        await s.pump(tester, mobile: mobile);

        s.homeNav.open(query: 'rock');
        await tester.pump();
        await s.switchTo(tester, 'beto');
        s.homeNav.open(query: 'rock');
        await tester.pump();
        s.gates['beto:rock']!.complete(_songs('Canción de Beto'));
        await tester.pumpAndSettle();
        expect(find.text('Canción de Beto'), findsWidgets);

        // El fallo de ana llega cuando beto ya tiene resultados.
        s.gates['ana:rock']!.completeError(Exception('fallo de ana'));
        await tester.pumpAndSettle();

        expect(find.text('Canción de Beto'), findsWidgets,
            reason: 'el error de ana no puede vaciar la búsqueda de beto');
      });

      testWidgets('un resultado de género de la sesión anterior no se aplica',
          (tester) async {
        final s = _Scenario();
        s.gates['ana:rock'] = Completer();
        await s.pump(tester, mobile: mobile);

        if (mobile) {
          await tester.tap(find.text('Buscar').last);
          await tester.pumpAndSettle();
          tester
              .widget<SearchExploreField>(find.byType(SearchExploreField))
              .onGenreSelected!('rock');
        } else {
          tester
              .widget<GlobalTopBar>(find.byType(GlobalTopBar))
              .onGenreSelected!('rock');
        }
        await tester.pump();
        await s.switchTo(tester, 'beto');
        s.gates['ana:rock']!.complete(_songs('Canción de Ana'));
        await tester.pumpAndSettle();

        expect(find.text('Canción de Ana'), findsNothing,
            reason: 'el género buscado por ana no puede aparecer bajo beto');
      });
    });
  }
}
