import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:navidrome_client/screens/home_screen.dart';
import 'package:navidrome_client/screens/home_shell.dart';
import 'package:navidrome_client/screens/mobile_home_screen.dart';
import 'package:navidrome_client/services/jam_controller.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/player_controller.dart';
import 'package:navidrome_client/services/settings_controller.dart';
import 'package:navidrome_client/services/theme_controller.dart';
import 'package:navidrome_client/utils/responsive.dart';
import 'package:navidrome_client/widgets/now_playing_panel.dart';

import 'support/app_fakes.dart';

Future<void> _pump(WidgetTester tester, Widget home, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final client = MockClient((request) async => http.Response(
      '{"subsonic-response":{"status":"ok","genres":{"genre":[]},"playlists":{}}}',
      200));
  final nav = NavidromeService();
  nav.setConnectedForTesting(
      url: 'http://192.168.1.50:4533',
      username: 'alice',
      password: 'pw',
      client: client);
  final settings = SettingsController();
  final player = PlayerController(nav, settings);

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<NavidromeService>.value(value: nav),
      ChangeNotifierProvider<PlayerController>.value(value: player),
      ChangeNotifierProvider<ThemeController>.value(value: ThemeController()),
      ChangeNotifierProvider<SettingsController>.value(value: settings),
      ChangeNotifierProvider<JamController>(create: (_) => IdleJam()),
    ],
    child: MaterialApp(home: home),
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Responsive (lógica)', () {
    test('clasifica los anchos', () {
      expect(Responsive.classify(360), ScreenSize.compact);
      expect(Responsive.classify(699), ScreenSize.compact);
      expect(Responsive.classify(700), ScreenSize.medium);
      expect(Responsive.classify(1000), ScreenSize.expanded);
      expect(Responsive.classify(1400), ScreenSize.large);
    });

    test('histéresis: no alterna móvil/escritorio cerca del límite', () {
      // Desde escritorio, cambia a móvil al bajar de 700.
      expect(Responsive.isMobileWidth(710, wasMobile: false), isFalse);
      expect(Responsive.isMobileWidth(699, wasMobile: false), isTrue);
      // Desde móvil, no vuelve a escritorio hasta superar 700 + histéresis.
      expect(Responsive.isMobileWidth(720, wasMobile: true), isTrue);
      expect(Responsive.isMobileWidth(739, wasMobile: true), isTrue);
      expect(Responsive.isMobileWidth(740, wasMobile: true), isFalse);
    });

    test('columnsFor respeta mínimos y máximos', () {
      expect(Responsive.columnsFor(100, minTileWidth: 220, min: 2, max: 4), 2);
      expect(Responsive.columnsFor(700, minTileWidth: 220, min: 2, max: 4), 3);
      expect(Responsive.columnsFor(3000, minTileWidth: 220, min: 2, max: 4), 4);
    });
  });

  group('HomeShell', () {
    testWidgets('móvil por debajo de 700 px, escritorio por encima',
        (tester) async {
      await _pump(tester, const HomeShell(), const Size(600, 900));
      expect(find.byType(MobileHomeScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('al redimensionar, la histéresis evita el parpadeo',
        (tester) async {
      await _pump(tester, const HomeShell(), const Size(900, 800));
      expect(find.byType(HomeScreen), findsOneWidget);

      // 720 px sigue siendo escritorio (venía de escritorio).
      tester.view.physicalSize = const Size(720, 800);
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);

      // Baja de 700: pasa a móvil.
      tester.view.physicalSize = const Size(600, 800);
      await tester.pumpAndSettle();
      expect(find.byType(MobileHomeScreen), findsOneWidget);

      // 720 px: todavía móvil (dentro de la banda de histéresis).
      tester.view.physicalSize = const Size(720, 800);
      await tester.pumpAndSettle();
      expect(find.byType(MobileHomeScreen), findsOneWidget);

      // 760 px: vuelve a escritorio.
      tester.view.physicalSize = const Size(760, 800);
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('HomeScreen adaptativo', () {
    testWidgets('estrecho: biblioteca colapsada que abre como cajón',
        (tester) async {
      await _pump(tester, const HomeScreen(), const Size(800, 700));
      expect(find.text('Tu Biblioteca'), findsNothing);
      expect(find.byType(NowPlayingSidePanel), findsNothing);

      await tester.tap(find.byIcon(Icons.library_music_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('Tu Biblioteca'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('estándar: biblioteca expandida sin panel lateral',
        (tester) async {
      await _pump(tester, const HomeScreen(), const Size(1100, 760));
      expect(find.text('Tu Biblioteca'), findsOneWidget);
      expect(find.byType(NowPlayingSidePanel), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ancho: aparece el panel lateral Escuchando ahora',
        (tester) async {
      await _pump(tester, const HomeScreen(), const Size(1500, 900));
      expect(find.text('Tu Biblioteca'), findsOneWidget);
      expect(find.byType(NowPlayingSidePanel), findsOneWidget);
      expect(find.text('No hay nada sonando'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final w in [720.0, 900.0, 1000.0, 1240.0, 1600.0, 2560.0]) {
      testWidgets('sin overflow a $w px de ancho', (tester) async {
        await _pump(tester, const HomeScreen(), Size(w, 800));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('MobileHomeScreen adaptativo', () {
    for (final w in [320.0, 360.0, 412.0, 600.0, 699.0]) {
      testWidgets('sin overflow a $w px de ancho', (tester) async {
        final errors = <String>[];
        final old = FlutterError.onError;
        FlutterError.onError = (d) => errors.add(d.toString());
        await _pump(tester, const MobileHomeScreen(), Size(w, 800));
        FlutterError.onError = old;
        expect(errors.join('\n---\n'), isEmpty);
      });
    }
  });
}
