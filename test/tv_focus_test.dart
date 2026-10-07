import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/app_theme.dart';
import 'package:navidrome_client/services/theme_controller.dart';
import 'package:navidrome_client/utils/tv_mode.dart';
import 'package:navidrome_client/widgets/tv_focus_ring.dart';
import 'package:provider/provider.dart';

class _Themes extends ThemeController {
  @override
  AppTheme get active => AppTheme.fixedThemes.first;
  @override
  bool get loading => false;
  @override
  Future<void> rescan() async {}
}

void main() {
  tearDown(() => TvMode.debugSet(false));

  test('fuera de una tele el modo TV está apagado', () {
    expect(TvMode.isTv, isFalse);
  });

  testWidgets('el marco sigue al elemento enfocado con las flechas',
      (tester) async {
    await tester.pumpWidget(ChangeNotifierProvider<ThemeController>.value(
      value: _Themes(),
      child: MaterialApp(
        home: TvFocusRing(
          child: Scaffold(
            body: Column(children: [
              TextButton(
                  onPressed: () {}, autofocus: true, child: const Text('Uno')),
              const SizedBox(height: 40),
              TextButton(onPressed: () {}, child: const Text('Dos')),
            ]),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    Finder ring() => find.byWidgetPredicate((w) =>
        w is DecoratedBox &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).border != null &&
        (w.decoration as BoxDecoration).boxShadow != null);

    expect(ring(), findsOneWidget);
    final first = tester.getRect(ring());
    expect(first.overlaps(tester.getRect(find.text('Uno'))), isTrue);

    // Flecha abajo: el foco (y el marco) pasan al segundo botón.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final second = tester.getRect(ring());
    expect(second.top, greaterThan(first.top));
    expect(second.overlaps(tester.getRect(find.text('Dos'))), isTrue);
  });

  testWidgets('en un formulario, abajo/arriba salen del campo de texto',
      (tester) async {
    final first = FocusNode();
    final second = FocusNode();
    final button = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    addTearDown(button.dispose);
    await tester.pumpWidget(MaterialApp(
      home: TvTextFieldNavigation(
        child: Scaffold(
          body: Column(children: [
            TextField(focusNode: first, autofocus: true),
            TextField(focusNode: second),
            TextButton(
                focusNode: button,
                onPressed: () {},
                child: const Text('Entrar')),
          ]),
        ),
      ),
    ));
    await tester.pump();
    expect(first.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(second.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(button.hasPrimaryFocus, isTrue);
    // Y se puede volver hacia arriba hasta el primer campo.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(first.hasPrimaryFocus, isTrue);
    expect(tester.takeException(), isNull);
  });
}
