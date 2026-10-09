import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/utils/tv_mode.dart';
import 'package:navidrome_client/widgets/tv_initial_focus.dart';

void main() {
  tearDown(() => TvMode.debugSet(false));

  final topKey = GlobalKey();
  final aKey = GlobalKey();
  final bKey = GlobalKey();

  Widget app({Widget? content, VoidCallback? onTop, bool topFocused = true}) =>
      MaterialApp(
        home: Scaffold(
          body: Column(children: [
            TextButton(
                key: topKey,
                autofocus: topFocused,
                onPressed: onTop ?? () {},
                child: const Text('Barra superior')),
            Expanded(
              child: TvInitialFocus(
                child: content ??
                    Column(children: [
                      TextButton(
                          key: aKey,
                          onPressed: () {},
                          child: const Text('Contenido A')),
                      TextButton(
                          key: bKey,
                          onPressed: () {},
                          child: const Text('Contenido B')),
                    ]),
              ),
            ),
          ]),
        ),
      );

  bool focused(GlobalKey key) {
    final context = FocusManager.instance.primaryFocus?.context;
    return context != null && _isInside(context, key);
  }

  testWidgets('en una tele el foco inicial pasa del menú al contenido',
      (tester) async {
    TvMode.debugSet(true);
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 250));
    expect(focused(aKey), isTrue);
    expect(focused(topKey), isFalse);
  });

  testWidgets('fuera de una tele no mueve el foco', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 500));
    expect(focused(topKey), isTrue);
    expect(focused(aKey), isFalse);
  });

  testWidgets('espera al contenido que llega después', (tester) async {
    TvMode.debugSet(true);
    final ready = ValueNotifier(false);
    addTearDown(ready.dispose);
    await tester.pumpWidget(app(
      content: ValueListenableBuilder<bool>(
        valueListenable: ready,
        builder: (_, loaded, __) => loaded
            ? TextButton(
                key: aKey, onPressed: () {}, child: const Text('Cargado'))
            : const Center(child: CircularProgressIndicator()),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 250));
    expect(focused(topKey), isTrue, reason: 'aún no hay nada que enfocar');

    ready.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(focused(aKey), isTrue);
  });

  testWidgets('si el usuario ya pulsó una tecla no le quita el foco',
      (tester) async {
    TvMode.debugSet(true);
    await tester.pumpWidget(app());
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 500));
    expect(focused(aKey), isFalse);
  });

  testWidgets('no actúa si hay un diálogo encima', (tester) async {
    TvMode.debugSet(true);
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        ctx = context;
        return Scaffold(
          body: TvInitialFocus(
            child: TextButton(
                key: aKey, onPressed: () {}, child: const Text('Contenido')),
          ),
        );
      }),
    ));
    // Se abre un diálogo antes de que el temporizador dispare.
    unawaited(showDialog<void>(
        context: ctx,
        builder: (_) => AlertDialog(
              content: TextButton(
                  key: bKey, onPressed: () {}, child: const Text('Diálogo')),
            )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(focused(aKey), isFalse);
  });

  testWidgets('si el foco ya está dentro del contenido no lo mueve',
      (tester) async {
    TvMode.debugSet(true);
    await tester.pumpWidget(app(
      topFocused: false,
      content: Column(children: [
        TextButton(
            key: aKey, onPressed: () {}, child: const Text('Contenido A')),
        TextButton(
            key: bKey,
            autofocus: true,
            onPressed: () {},
            child: const Text('Contenido B')),
      ]),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    expect(focused(bKey), isTrue);
    expect(focused(aKey), isFalse);
  });

  testWidgets('deja de intentarlo cuando no hay nada enfocable',
      (tester) async {
    TvMode.debugSet(true);
    await tester.pumpWidget(app(content: const Text('Solo texto')));
    await tester.pump(const Duration(seconds: 10));
    // Sin temporizadores pendientes: el test termina sin quejarse.
    expect(focused(topKey), isTrue);
  });
}

bool _isInside(BuildContext inner, GlobalKey outer) {
  final target = outer.currentContext;
  if (target == null) return false;
  var found = false;
  inner.visitAncestorElements((e) {
    if (e == target) {
      found = true;
      return false;
    }
    return true;
  });
  return found || inner == target;
}
