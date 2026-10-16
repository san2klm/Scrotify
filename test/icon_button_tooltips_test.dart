import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Todo `IconButton` debe llevar `tooltip` (es su etiqueta para lectores de
/// pantalla). Esta prueba lee el código: cualquier botón nuevo sin etiqueta
/// la rompe.
void main() {
  test('todos los IconButton de lib/ tienen tooltip', () {
    // Envueltos en un `Tooltip` propio.
    const allowed = {'desktop_window_frame.dart'};
    final offenders = <String>[];
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (allowed.any(file.path.endsWith)) continue;
      final src = file.readAsStringSync();
      for (final m in RegExp(r'IconButton\(').allMatches(src)) {
        var depth = 1;
        var i = m.end;
        while (depth > 0 && i < src.length) {
          final c = src[i++];
          if (c == '(') depth++;
          if (c == ')') depth--;
        }
        final body = src.substring(m.start, i);
        if (!body.contains('tooltip:')) {
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          offenders.add('${file.path}:$line');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
