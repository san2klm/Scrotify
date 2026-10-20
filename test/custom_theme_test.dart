import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crotowave/services/theme_controller.dart';
import 'package:crotowave/widgets/theme_grid.dart';
import 'package:crotowave/widgets/app_theme_background.dart';
import 'package:crotowave/utils/app_colors.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> ready(ThemeController controller) async {
  var started = controller.loading;
  final done = Completer<void>();
  void listener() {
    started = started || controller.loading;
    if (started && !controller.loading && !done.isCompleted) done.complete();
  }

  controller.addListener(listener);
  await done.future.timeout(const Duration(seconds: 10));
  controller.removeListener(listener);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Personalizado queda último y conserva colores y selección al recargar',
      () async {
    final temp = await Directory.systemTemp.createTemp('custom-theme-test-');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(channel, (_) async => temp.path);
    addTearDown(() async {
      messenger.setMockMethodCallHandler(channel, null);
      await temp.delete(recursive: true);
    });
    await File('${temp.path}/themes.json').writeAsString(jsonEncode({
      'version': 2,
      'themesDir': temp.path,
      'selectedId': 'latte',
      'customColors': {'blur': 30},
    }));
    final imports = await Directory('${temp.path}/theme_imports').create();
    await File('${imports.path}/.bundled_installed_v2').writeAsString('v2');
    final controller = ThemeController();
    await ready(controller);
    expect(controller.themes.last.name, 'Personalizado');
    await controller.saveCustomTheme(
        background: Colors.white,
        accent: Colors.red,
        accent2: Colors.blue,
        transparency: 0.4);
    expect(controller.active.mode, 'light');
    final saved = await ThemeController.readInitial();
    expect(saved['selectedId'], ThemeController.customThemeId);
    expect((saved['customColors'] as Map).containsKey('blur'), isFalse);
    controller.dispose();
    final restored = ThemeController(initial: saved);
    await ready(restored);
    expect(restored.activeId, ThemeController.customThemeId);
    expect(restored.active.bgApp, Colors.white);
    expect(restored.active.accent.toARGB32(), Colors.red.toARGB32());
    expect(restored.active.accent2.toARGB32(), Colors.blue.toARGB32());
    expect(restored.themes.last.id, ThemeController.customThemeId);
    expect(restored.surfaceTransparency, 0.4);
    await restored.selectTheme('latte');
    expect(restored.surfaceTransparency, 0);
    restored.dispose();
  });
  testWidgets('Editor de efectos conserva cada casilla y permite cancelar',
      (tester) async {
    late Directory temp;
    late ThemeController controller;
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('rgb-theme-test-');
      messenger.setMockMethodCallHandler(channel, (_) async => temp.path);
      final imports = await Directory('${temp.path}/theme_imports').create();
      await File('${imports.path}/.bundled_installed_v2').writeAsString('v2');
      await File('${temp.path}/themes.json').writeAsString(jsonEncode({
        'version': 2,
        'themesDir': temp.path,
        'selectedId': ThemeController.customThemeId,
      }));
      controller = ThemeController();
      await ready(controller);
      await controller.saveCustomTheme(
          background: const Color(0xFF121212),
          accent: const Color(0xFFA855F7),
          accent2: const Color(0xFF38BDF8),
          transparency: 0.4);
    });
    addTearDown(() async {
      controller.dispose();
      messenger.setMockMethodCallHandler(channel, null);
      await temp.delete(recursive: true);
    });
    Color? sidebarColor;
    Color? playerColor;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(
        builder: (context, child) => AppThemeBackground(child: child!),
        home: Builder(builder: (context) {
          sidebarColor = context.bgSidebar;
          playerColor = context.bgPlayer;
          return Scaffold(
              backgroundColor: context.bgApp,
              body: const SingleChildScrollView(child: ThemesSection()));
        }),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(ImageFiltered), findsNothing);
    expect(sidebarColor!.toARGB32() >> 24, 153);
    expect(playerColor!.toARGB32() >> 24, 153);
    expect(
        tester
                .widget<Scaffold>(find.byType(Scaffold))
                .backgroundColor!
                .toARGB32() >>
            24,
        0);
    expect(
        find.byWidgetPredicate((w) =>
            w is Material &&
            w.color != null &&
            (w.color!.toARGB32() >> 24) == 153),
        findsWidgets);
    await tester.tap(find.byTooltip('Editar colores'));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNWidgets(3));
    expect(find.text('Color'), findsOneWidget);
    expect(find.text('Tonalidad'), findsOneWidget);
    expect(find.text('Luz'), findsOneWidget);
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();
    expect(find.text('Ajustar RGB'), findsNothing);
    expect(find.text('Blur de Windows'), findsNothing);
    expect(find.text('Blur'), findsNothing);
    expect(find.textContaining('RGB:'), findsNothing);
    expect(find.text('Transparencia'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Transparencia')).dy,
        greaterThan(tester.getTopLeft(find.text('Luz')).dy));
    expect(find.byType(Slider), findsNWidgets(4));
    final red = find.byType(Slider).first;
    await tester.ensureVisible(red);
    await tester.pumpAndSettle();
    final before = controller.customTheme;
    final originalRed = tester.widget<Slider>(red).value;
    await tester.drag(red, const Offset(-65, 0));
    await tester.pumpAndSettle();
    final changedRed = tester.widget<Slider>(red).value;
    expect(changedRed, isNot(originalRed));
    final firstChoice = find.byType(Checkbox).first;
    await tester.ensureVisible(firstChoice);
    await tester.tap(firstChoice);
    await tester.pumpAndSettle();
    expect(
        tester.widget<Slider>(red).value, HSLColor.fromColor(before.bgApp).hue);
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(red).value, changedRed);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(controller.customTheme.bgApp, before.bgApp);
    expect(controller.customTheme.accent.toARGB32(), before.accent.toARGB32());
    await tester.runAsync(() => controller.selectTheme('latte'));
    await tester.pumpAndSettle();
    expect(find.byType(ImageFiltered), findsNothing);
    expect(sidebarColor!.toARGB32() >> 24, 255);
    expect(playerColor!.toARGB32() >> 24, 255);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
