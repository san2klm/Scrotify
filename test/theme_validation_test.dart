import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/theme_validation.dart';

List<int> _zip(Map<String, String> files) {
  final a = Archive();
  for (final e in files.entries) {
    final bytes = utf8.encode(e.value);
    a.addFile(ArchiveFile(e.key, bytes.length, bytes));
  }
  return ZipEncoder().encode(a);
}

Map<String, dynamic> _manifest({String id = 'demo-theme'}) => {
      'id': id,
      'name': 'Demo',
      'author': 'tester',
      'version': '1.2.3',
      'description': 'Tema de prueba.',
      'mode': 'dark',
    };

String _css({String id = 'demo-theme'}) =>
    "[data-theme='$id'] { --accent: #ff0000; --bg-app: #000000; }";

void main() {
  group('ThemeValidation manifest', () {
    test('manifiesto válido pasa', () {
      expect(
        ThemeValidation.validateManifest(
          _manifest(),
          reservedIds: {'mocha'},
        ),
        isNull,
      );
    });

    test('rechaza id malformado y colisión con fijos', () {
      expect(
        ThemeValidation.validateManifest(
          _manifest(id: 'Mal_Id!'),
          reservedIds: {'mocha'},
        ),
        isNotNull,
      );
      expect(
        ThemeValidation.validateManifest(
          _manifest(id: 'mocha'),
          reservedIds: {'mocha'},
        ),
        contains('fijo'),
      );
    });

    test('rechaza versión no SemVer y minAppVersion mayor', () {
      final bad = _manifest()..['version'] = '1.0';
      expect(
        ThemeValidation.validateManifest(bad, reservedIds: {}),
        isNotNull,
      );
      final future = _manifest()..['minAppVersion'] = '99.0.0';
      expect(
        ThemeValidation.validateManifest(future, reservedIds: {}),
        contains('Requiere app'),
      );
    });

    test('rechaza keys desconocidas y tags inválidos', () {
      final extra = _manifest()..['trampa'] = 1;
      expect(
        ThemeValidation.validateManifest(extra, reservedIds: {}),
        contains('desconocido'),
      );
      final tags = _manifest()..['tags'] = ['ok', 'MAL_TAG'];
      expect(
        ThemeValidation.validateManifest(tags, reservedIds: {}),
        isNotNull,
      );
    });
  });

  group('ThemeValidation CSS', () {
    test('CSS válido pasa', () {
      expect(ThemeValidation.validateCss(_css(), 'demo-theme'), isNull);
    });

    test('rechaza @import, javascript: y urls remotas', () {
      expect(
        ThemeValidation.validateCss("@import 'http://x/y.css';", 'demo-theme'),
        isNotNull,
      );
      expect(
        ThemeValidation.validateCss(
            'a{background:url(javascript:alert(1))}', 'demo-theme'),
        isNotNull,
      );
      expect(
        ThemeValidation.validateCss(
            'a{background:url(https://x/y.png)}', 'demo-theme'),
        isNotNull,
      );
    });

    test('acepta data: y assets/... válidos', () {
      expect(
        ThemeValidation.validateCss(
            'a{background:url(data:image/png;base64,AAA)}', 'demo-theme'),
        isNull,
      );
      expect(
        ThemeValidation.validateCss(
            'a{background:url("assets/bg.webp")}', 'demo-theme'),
        isNull,
      );
      expect(
        ThemeValidation.validateCss(
            'a{background:url(assets/../../x.png)}', 'demo-theme'),
        isNotNull,
      );
    });

    test('keyframes exige prefijo del id', () {
      expect(
        ThemeValidation.validateCss(
            '@keyframes demo-theme-glow {from{}to{}}', 'demo-theme'),
        isNull,
      );
      expect(
        ThemeValidation.validateCss(
            '@keyframes glow {from{}to{}}', 'demo-theme'),
        contains('@keyframes'),
      );
    });
  });

  group('ThemeValidation ZIP', () {
    test('zip completo válido pasa', () {
      final bytes = _zip({
        'demo-theme/manifest.json': jsonEncode(_manifest()),
        'demo-theme/theme.css': _css(),
      });
      expect(
        ThemeValidation.validateZipBytes(bytes, reservedIds: {'mocha'}),
        isNull,
      );
    });

    test('falta manifest o css', () {
      final sinManifest = _zip({'demo-theme/theme.css': _css()});
      expect(
        ThemeValidation.validateZipBytes(sinManifest, reservedIds: {}),
        contains('manifest'),
      );
      final sinCss =
          _zip({'demo-theme/manifest.json': jsonEncode(_manifest())});
      expect(
        ThemeValidation.validateZipBytes(sinCss, reservedIds: {}),
        contains('theme.css'),
      );
    });
  });

  group('SemVer', () {
    test('compara versiones', () {
      expect(ThemeValidation.compareVersions('1.0.0', '1.0.0'), 0);
      expect(ThemeValidation.compareVersions('1.2.0', '1.10.0'), lessThan(0));
      expect(ThemeValidation.compareVersions('2.0.0', '1.9.9'), greaterThan(0));
      expect(ThemeValidation.compareVersions('1.0.0-dev', '1.0.0'), 0);
    });
  });
}
