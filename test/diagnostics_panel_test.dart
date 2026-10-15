import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/diagnostics_log.dart';
import 'package:navidrome_client/services/theme_controller.dart';
import 'package:navidrome_client/widgets/diagnostics_panel.dart';
import 'package:provider/provider.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('scrotify_diag_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Widget host(DiagnosticsLog log) => ChangeNotifierProvider(
        create: (_) => ThemeController(),
        child: MaterialApp(
          home: Scaffold(
            body: DiagnosticsPanel(log: log, directory: () async => tmp),
          ),
        ),
      );

  testWidgets('sin mensajes, los botones están desactivados', (tester) async {
    await tester.pumpWidget(host(DiagnosticsLog()));
    expect(find.text('Todavía no hay mensajes.'), findsOneWidget);
    final copy = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Copiar'));
    expect(copy.onPressed, isNull);
  });

  testWidgets('copiar deja el diagnóstico redactado en el portapapeles',
      (tester) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final log = DiagnosticsLog()..add('fallo https://x/rest?u=lau&t=abc123');
    await tester.pumpWidget(host(log));
    await tester.tap(find.text('Copiar'));
    await tester.pump();

    expect(clipboard, contains('fallo https://x/rest'));
    expect(clipboard, isNot(contains('abc123')));
    expect(find.text('Diagnóstico copiado'), findsOneWidget);
  });

  testWidgets('guardar escribe un archivo y vaciar limpia el registro',
      (tester) async {
    final log = DiagnosticsLog()..add('una línea');
    await tester.pumpWidget(host(log));

    await tester.runAsync(() async {
      await tester.tap(find.text('Guardar en archivo'));
      // Esperar la condición (el archivo escrito), no un tiempo fijo.
      for (var i = 0; i < 100; i++) {
        final written = tmp
            .listSync()
            .whereType<File>()
            .any((f) => f.readAsStringSync().contains('una línea'));
        if (written) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();

    final files = tmp.listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    expect(files.single.path, contains('diagnostico-'));
    expect(files.single.readAsStringSync(), contains('una línea'));

    await tester.tap(find.text('Vaciar'));
    await tester.pump();
    expect(find.text('Todavía no hay mensajes.'), findsOneWidget);
  });
}
