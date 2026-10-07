import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:navidrome_client/screens/home_shell.dart';
import 'package:navidrome_client/services/home_navigation_controller.dart';
import 'package:navidrome_client/services/connect/connect_service.dart';
import 'package:navidrome_client/services/jam_controller.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/player_controller.dart';
import 'package:navidrome_client/services/theme_controller.dart';
import 'package:navidrome_client/widgets/explore_tracks_view.dart';
import 'package:navidrome_client/widgets/global_top_bar.dart';

import 'support/app_fakes.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('search and explore share working navigation on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        tester.view.physicalSize = platform == TargetPlatform.android
            ? const Size(390, 844)
            : const Size(1440, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final nav = FakeNavidrome();
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<NavidromeService>.value(value: nav),
            ChangeNotifierProvider(create: (_) => ThemeController()),
            ChangeNotifierProvider(create: (_) => HomeNavigationController()),
            ChangeNotifierProvider<PlayerController>.value(value: IdlePlayer()),
            ChangeNotifierProvider<ConnectService>(create: (_) => idleConnectService()),
            ChangeNotifierProvider<JamController>.value(value: IdleJam()),
          ],
          child: const MaterialApp(home: HomeShell()),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (platform == TargetPlatform.android) {
          await tester.tap(find.text('Buscar').last);
          await tester.pumpAndSettle();
        } else {
          expect(find.text('SCROTIFY'), findsNothing);
        }
        await tester.tap(find.byTooltip('Explorar'));
        await tester.pumpAndSettle();
        expect(find.byType(ExploreTracksView), findsOneWidget);
        expect(find.text('No hay canciones en tu biblioteca'), findsOneWidget);
        final field = find.byType(TextField).first;
        await tester.enterText(field, 'consulta');
        await tester.pumpAndSettle();
        expect(nav.queries.last, 'consulta');
        expect(find.byType(ExploreTracksView), findsNothing);

        if (platform == TargetPlatform.windows) {
          Navigator.of(tester.element(find.byType(HomeShell))).push(
            MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                      body: GlobalTopBar(title: 'Detalle'),
                    )),
          );
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), 'desde detalle');
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pumpAndSettle();
          expect(nav.queries.last, 'desde detalle');
          expect(find.byType(HomeShell), findsOneWidget);
          expect(
              tester
                  .widget<TextField>(find.byType(TextField).first)
                  .controller!
                  .text,
              'desde detalle');
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
