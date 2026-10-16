import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/app_theme.dart';
import 'package:navidrome_client/services/cover_palette.dart';

Future<MemoryImage> solid(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
      .drawRect(const Rect.fromLTWH(0, 0, 32, 32), Paint()..color = color);
  final image = await recorder.endRecording().toImage(32, 32);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return MemoryImage(bytes!.buffer.asUint8List());
}

void main() {
  test('withAccent cambia el énfasis y conserva fondos y textos', () {
    final base = AppTheme.fixedThemes.first;
    const red = Color(0xFFD32F2F);
    final themed = base.withAccent(red);
    expect(themed.accent, red);
    expect(themed.volumeAccent, red);
    expect(themed.bgApp, base.bgApp);
    expect(themed.textPrimary, base.textPrimary);
    expect(themed.mode, base.mode);
  });

  testWidgets('CoverPalette extrae el tono dominante y lo cachea',
      (tester) async {
    final palette = CoverPalette();
    late Color? first;
    late Color? second;
    await tester.runAsync(() async {
      final image = await solid(const Color(0xFFD32F2F));
      first = await palette.accentFor('t1', image);
      second = await palette.accentFor('t1', image);
    });
    expect(first, isNotNull);
    final hue = HSLColor.fromColor(first!).hue;
    expect(hue < 20 || hue > 340, isTrue, reason: 'tono rojo, fue $hue');
    expect(second, first);
  });
}
