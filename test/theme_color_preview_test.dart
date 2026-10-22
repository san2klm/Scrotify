import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crotowave/widgets/theme_color_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _width = 160;
const _height = 80;
const _accent = Color(0xFFFF0000);
const _accent2 = Color(0xFF00FF00);

Future<ByteData> _renderPreview(WidgetTester tester,
    {Color background = Colors.black}) async {
  final key = GlobalKey();
  await tester.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: SizedBox(
        width: _width.toDouble(),
        height: _height.toDouble(),
        child: RepaintBoundary(
          key: key,
          child: ThemeColorPreview(
            background: background,
            accent: _accent,
            accent2: _accent2,
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      expect(image.width, _width);
      expect(image.height, _height);
      return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    } finally {
      image.dispose();
    }
  });
  expect(bytes, isNotNull);
  return bytes!;
}

List<int> _rgba(ByteData image, int x, int y) {
  final offset = (y * _width + x) * 4;
  return List.generate(4, (channel) => image.getUint8(offset + channel));
}

Iterable<List<int>> _mainArea(ByteData image) sync* {
  // Keep clear of rounded corners and the two accent bands at the bottom.
  for (var y = 12; y < 56; y++) {
    for (var x = 12; x < _width - 12; x++) {
      yield _rgba(image, x, y);
    }
  }
}

void main() {
  testWidgets('El fondo negro conserva su color exacto con acentos vivos',
      (tester) async {
    final image = await _renderPreview(tester);
    expect(_mainArea(image).every((p) => p.join(',') == '0,0,0,255'), isTrue,
        reason: 'Los acentos no deben teñir el área del color de fondo.');
  });

  testWidgets('El fondo muestra el color elegido sin degradados ni damero',
      (tester) async {
    final image =
        await _renderPreview(tester, background: const Color(0xFF263D59));
    expect(
        _mainArea(image).every((p) => p.join(',') == '38,61,89,255'), isTrue);
  });

  testWidgets('Las dos franjas inferiores mantienen los acentos exactos',
      (tester) async {
    final image = await _renderPreview(tester);
    expect(_rgba(image, 80, 63), [0, 0, 0, 255]);
    for (var y = 64; y < 72; y++) {
      expect(_rgba(image, 80, y), [255, 0, 0, 255]);
    }
    for (var y = 72; y < 80; y++) {
      expect(_rgba(image, 80, y), [0, 255, 0, 255]);
    }
  });
}
