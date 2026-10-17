import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/app_theme.dart';
import 'package:crotowave/services/theme_controller.dart';
import 'package:crotowave/utils/tv_mode.dart';
import 'package:crotowave/widgets/tv_focus_ring.dart';
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

  Widget app(Widget body) => ChangeNotifierProvider<ThemeController>.value(
        value: _Themes(),
        child: MaterialApp(
          home: TvTextFieldNavigation(child: Scaffold(body: body)),
        ),
      );

  testWidgets('OK en un campo abre el teclado en pantalla y escribe el texto',
      (tester) async {
    final controller = TextEditingController();
    String? changed;
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(TextField(
      controller: controller,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Usuario'),
      onChanged: (v) => changed = v,
    )));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Usuario'), findsWidgets);
    expect(find.text('Listo'), findsOneWidget);

    await tester.tap(find.text('h'));
    await tester.tap(find.text('ABC')); // mayúsculas
    await tester.pump();
    await tester.tap(find.text('I'));
    await tester.tap(find.text('.com'));
    await tester.tap(find.text('Borrar'));
    await tester.pump();
    await tester.tap(find.text('Listo'));
    await tester.pumpAndSettle();

    expect(controller.text, 'hI.co');
    expect(changed, 'hI.co');
    expect(find.text('Listo'), findsNothing);
  });

  testWidgets(
      'el teclado en pantalla parte del texto actual y se puede cancelar',
      (tester) async {
    final controller = TextEditingController(text: 'admin');
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(
        TextField(controller: controller, autofocus: true, obscureText: true)));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('•••••▏'), findsOneWidget); // clave oculta
    await tester.tap(find.text('Mostrar'));
    await tester.pump();
    expect(find.text('admin▏'), findsOneWidget);
    await tester.tap(find.text('x'));
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(controller.text, 'admin'); // cancelar no cambia nada
  });

  testWidgets('un campo numérico solo ofrece dígitos', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number)));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('q'), findsNothing);
    await tester.tap(find.text('4'));
    await tester.tap(find.text('2'));
    await tester.tap(find.text('Listo'));
    await tester.pumpAndSettle();
    expect(controller.text, '42');
  });

  testWidgets('un teclado físico sigue escribiendo sin teclado del sistema',
      (tester) async {
    final controller = TextEditingController(text: 'ab');
    addTearDown(controller.dispose);
    await tester
        .pumpWidget(app(TextField(controller: controller, autofocus: true)));
    await tester.pump();
    await simulateKeyDownEvent(LogicalKeyboardKey.keyZ, character: 'z');
    await simulateKeyUpEvent(LogicalKeyboardKey.keyZ);
    await tester.pump();
    expect(controller.text.contains('z'), isTrue);
  });
}
