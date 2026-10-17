import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/utils/build_info.dart';

void main() {
  test('con commit y fecha los muestra', () {
    expect(BuildInfo.describe('1.0.0', '67abf4f', '2026-10-09'),
        'v1.0.0 (67abf4f · 2026-10-09)');
  });

  test('con un solo dato no deja separadores sueltos', () {
    expect(BuildInfo.describe('1.0.0', '67abf4f', ''), 'v1.0.0 (67abf4f)');
    expect(
        BuildInfo.describe('1.0.0', '', '2026-10-09'), 'v1.0.0 (2026-10-09)');
  });

  test('sin datos indica que es un build de desarrollo', () {
    expect(BuildInfo.describe('1.0.0', '', ''), 'v1.0.0 (desarrollo)');
    // En los tests no hay --dart-define.
    expect(BuildInfo.label, 'v1.0.0 (desarrollo)');
  });
}
