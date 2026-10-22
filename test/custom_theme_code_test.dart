import 'dart:math';

import 'package:crotowave/services/custom_theme_code.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

CustomThemeCode _theme({
  Color background = const Color(0xFF000000),
  Color accent = const Color(0xFFA855F7),
  Color accent2 = const Color(0xFF38BDF8),
  double transparency = 0.75,
}) =>
    CustomThemeCode(
      background: background,
      accent: accent,
      accent2: accent2,
      transparency: transparency,
    );

void main() {
  test('El código canónico conserva RGB con ceros y hexadecimal en mayúsculas',
      () {
    expect(_theme().encode(), 'CWT1-000000-A855F7-38BDF8-75');
  });

  test('El porcentaje usa hasta cuatro decimales y elimina ceros sobrantes',
      () {
    for (final entry in <double, String>{
      0: '0',
      1: '100',
      0.1: '10',
      0.105: '10.5',
      0.123456789: '12.3457',
      0.000001: '0.0001',
      0.999999: '99.9999',
    }.entries) {
      expect(_theme(transparency: entry.key).encode(),
          'CWT1-000000-A855F7-38BDF8-${entry.value}');
    }
  });

  test('Pegar acepta espacios, saltos de línea y hexadecimal en minúsculas',
      () {
    final theme =
        CustomThemeCode.decode(' \n cwt1-00 0000-\n a855f7-38bdf8-\t75 \r\n');
    expect(theme.background.toARGB32(), 0xFF000000);
    expect(theme.accent.toARGB32(), 0xFFA855F7);
    expect(theme.accent2.toARGB32(), 0xFF38BDF8);
    expect(theme.transparency, 0.75);
    expect(theme.encode(), 'CWT1-000000-A855F7-38BDF8-75');
  });

  test('Leer porcentajes válidos los normaliza al volver a compartir', () {
    final theme = CustomThemeCode.decode('CWT1-FFFFFF-001122-ABCDEF-010.5000');
    expect(theme.background.toARGB32(), 0xFFFFFFFF);
    expect(theme.accent.toARGB32(), 0xFF001122);
    expect(theme.accent2.toARGB32(), 0xFFABCDEF);
    expect(theme.transparency, 0.105);
    expect(theme.encode(), 'CWT1-FFFFFF-001122-ABCDEF-10.5');
  });

  test('Compartir e importar conserva colores y precisión de transparencia',
      () {
    final random = Random(412);
    final values = [
      0.0,
      1.0,
      0.00000049,
      0.99999951,
      for (var i = 0; i < 200; i++) random.nextDouble()
    ];
    for (final value in values) {
      Color color() => Color(0xFF000000 | random.nextInt(0x1000000));
      final original = _theme(
          background: color(),
          accent: color(),
          accent2: color(),
          transparency: value);
      final restored = CustomThemeCode.decode(original.encode());
      expect(restored.background.toARGB32(), original.background.toARGB32());
      expect(restored.accent.toARGB32(), original.accent.toARGB32());
      expect(restored.accent2.toARGB32(), original.accent2.toARGB32());
      expect(restored.transparency, closeTo(value, 0.0000005));
    }
  });

  test('El límite de longitud se comprueba antes de quitar espacios', () {
    final source = '${' ' * 129}CWT1-000000-A855F7-38BDF8-75';
    expect(() => CustomThemeCode.decode(source), throwsFormatException);
  });

  test('Rechaza versiones, colores y estructura de código inválidos', () {
    for (final source in [
      '',
      'CWT2-000000-A855F7-38BDF8-75',
      'OTRO-000000-A855F7-38BDF8-75',
      'CWT1-#000000-A855F7-38BDF8-75',
      'CWT1-00000-A855F7-38BDF8-75',
      'CWT1-FF000000-A855F7-38BDF8-75',
      'CWT1-GG0000-A855F7-38BDF8-75',
      'CWT1-000000-Z855F7-38BDF8-75',
      'CWT1-000000-A855F7-38BDFZ-75',
      'CWT1-000000-A855F7-75',
      'CWT1-000000-A855F7-38BDF8-75-extra',
    ]) {
      expect(() => CustomThemeCode.decode(source), throwsFormatException,
          reason: source);
    }
  });

  test(
      'Rechaza porcentajes no finitos, negativos, fuera de rango o mal formados',
      () {
    for (final percent in [
      'NaN',
      'Infinity',
      '-Infinity',
      '-1',
      '-0',
      '101',
      '100.0001',
      '0.00001',
      '1e1',
      '+75',
      '75.',
      '.5',
      '10,5',
      '',
    ]) {
      final source = 'CWT1-000000-A855F7-38BDF8-$percent';
      expect(() => CustomThemeCode.decode(source), throwsFormatException,
          reason: percent);
    }
  });

  test('Compartir rechaza transparencias no finitas o fuera de rango', () {
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
      -0.001,
      1.00001
    ]) {
      expect(() => _theme(transparency: value).encode(), throwsFormatException);
    }
  });

  test('Compartir rechaza transparencia en cualquiera de los tres colores', () {
    const translucent = Color(0x80112233);
    for (final theme in [
      _theme(background: translucent),
      _theme(accent: translucent),
      _theme(accent2: translucent),
    ]) {
      expect(theme.encode, throwsFormatException);
    }
  });

  test('Los errores de formato incluyen un mensaje legible en español', () {
    expect(
      () => CustomThemeCode.decode('CWT1-000000-A855F7-38BDF8-101'),
      throwsA(isA<FormatException>().having(
          (error) => error.message, 'mensaje', contains('transparencia'))),
    );
  });
}
