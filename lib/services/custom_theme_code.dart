import 'package:flutter/painting.dart' show Color;

/// Código portátil de los colores y la transparencia del tema Personalizado.
final class CustomThemeCode {
  final Color background;
  final Color accent;
  final Color accent2;
  final double transparency;

  const CustomThemeCode({
    required this.background,
    required this.accent,
    required this.accent2,
    required this.transparency,
  });

  String encode() {
    _validateTransparency(transparency);
    final colors = [background, accent, accent2].map(_encodeColor).join('-');
    // One million steps preserve transparency to within 0.0000005 while
    // keeping its percentage to at most four decimal places.
    final units = (transparency * 1000000).round();
    final whole = units ~/ 10000;
    final fraction = (units % 10000)
        .toString()
        .padLeft(4, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    final percent = fraction.isEmpty ? '$whole' : '$whole.$fraction';
    return 'CWT1-$colors-$percent';
  }

  static CustomThemeCode decode(String source) {
    if (source.length > 128) {
      throw const FormatException('El código de tema es demasiado largo.');
    }
    final code = source.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (!code.startsWith('CWT1-')) {
      throw const FormatException(
          'El código de tema no es compatible. Usá un código CWT1.');
    }
    final match = RegExp(
      r'^CWT1-([0-9A-F]{6})-([0-9A-F]{6})-([0-9A-F]{6})-([0-9]+(?:\.[0-9]{1,4})?)$',
    ).firstMatch(code);
    if (match == null) {
      throw const FormatException(
          'El código de tema no es válido. Copialo completo e intentá de nuevo.');
    }
    final percent = double.tryParse(match.group(4)!);
    if (percent == null || !percent.isFinite || percent < 0 || percent > 100) {
      throw const FormatException(
          'La transparencia debe estar entre 0 y 100 %.');
    }
    Color color(int group) =>
        Color(int.parse('FF${match.group(group)}', radix: 16));
    return CustomThemeCode(
      background: color(1),
      accent: color(2),
      accent2: color(3),
      transparency: percent / 100,
    );
  }

  static String _encodeColor(Color color) {
    if (color.a != 1 ||
        !color.r.isFinite ||
        !color.g.isFinite ||
        !color.b.isFinite ||
        color.r < 0 ||
        color.r > 1 ||
        color.g < 0 ||
        color.g > 1 ||
        color.b < 0 ||
        color.b > 1) {
      throw const FormatException(
          'Los colores del tema deben ser RGB y opacos.');
    }
    return (color.toARGB32() & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0')
        .toUpperCase();
  }

  static void _validateTransparency(double value) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw const FormatException(
          'La transparencia debe estar entre 0 y 100 %.');
    }
  }
}
