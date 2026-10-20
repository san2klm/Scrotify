import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crotowave/services/custom_theme_code.dart';
import 'package:crotowave/services/theme_controller.dart';
import 'package:crotowave/widgets/theme_color_preview.dart';
import 'package:crotowave/widgets/theme_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Comparte el borrador e importa con vista previa sin guardar al cancelar',
      (tester) async {
    late Directory temp;
    late ThemeController themes;
    String? clipboard;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
      }
      if (call.method == 'Clipboard.getData') return {'text': clipboard};
      return null;
    });
    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('share-theme-test-');
      messenger.setMockMethodCallHandler(paths, (_) async => temp.path);
      final imports = await Directory('${temp.path}/theme_imports').create();
      await File('${imports.path}/.bundled_installed_v2').writeAsString('v2');
      await File('${temp.path}/themes.json').writeAsString(jsonEncode({
        'version': 2,
        'themesDir': temp.path,
        'selectedId': ThemeController.customThemeId,
      }));
      themes = ThemeController();
      final done = Completer<void>();
      var started = false;
      void loaded() {
        started = started || themes.loading;
        if (started && !themes.loading && !done.isCompleted) done.complete();
      }

      themes.addListener(loaded);
      await done.future.timeout(const Duration(seconds: 10));
      themes.removeListener(loaded);
    });
    addTearDown(() async {
      themes.dispose();
      messenger.setMockMethodCallHandler(paths, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      await temp.delete(recursive: true);
    });
    final before = themes.customTheme;
    final beforeTransparency = themes.customTransparency;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: themes,
      child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: ThemesSection()))),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Editar colores'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Código del tema'));
    await tester.tap(find.text('Código del tema'));
    await tester.pumpAndSettle();
    final code = find.byKey(const ValueKey('custom-theme-code'));
    String currentCode() => tester.widget<SelectableText>(code).data!;
    final original = currentCode();
    expect(CustomThemeCode.decode(original).background, before.bgApp);
    await tester.ensureVisible(find.text('Copiar código'));
    await tester.tap(find.text('Copiar código'));
    await tester.pumpAndSettle();
    expect(clipboard, original);

    const imported = CustomThemeCode(
        background: Color(0xFFFAFAFA),
        accent: Color(0xFF225588),
        accent2: Color(0xFFCC7700),
        transparency: 0.75);
    clipboard = imported.encode();
    await tester.ensureVisible(find.byTooltip('Pegar del portapapeles'));
    await tester.tap(find.byTooltip('Pegar del portapapeles'));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('custom-theme-code-input'));
    expect(tester.widget<TextField>(input).controller!.text, clipboard);
    await tester.ensureVisible(find.text('Cargar código'));
    await tester.tap(find.text('Cargar código'));
    await tester.pumpAndSettle();
    expect(currentCode(), imported.encode());
    final preview =
        tester.widget<ThemeColorPreview>(find.byType(ThemeColorPreview));
    expect(preview.background.toARGB32(), imported.background.toARGB32());
    expect(preview.accent.toARGB32(), imported.accent.toARGB32());
    expect(tester.widget<Slider>(find.byType(Slider).last).value, 75);

    await tester.ensureVisible(input);
    await tester.enterText(input, 'esto no es un tema');
    await tester.ensureVisible(find.text('Cargar código'));
    await tester.tap(find.text('Cargar código'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).decoration!.errorText, isNotNull);
    expect(currentCode(), imported.encode());
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(themes.customTheme.bgApp, before.bgApp);
    expect(themes.customTransparency, beforeTransparency);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
