import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/app_theme.dart';

List<int> _zip(Map<String, String> files) {
  final a = Archive();
  for (final e in files.entries) {
    final bytes = utf8.encode(e.value);
    a.addFile(ArchiveFile(e.key, bytes.length, bytes));
  }
  return ZipEncoder().encode(a);
}

void main() {
  group('AppTheme rango extendido', () {
    test('Resuelve var(--x) y usa waveform/player/sidebar', () {
      final bytes = _zip({
        't/manifest.json': jsonEncode({
          'id': 'demo',
          'name': 'Demo',
          'version': '1.0.0',
          'mode': 'dark',
        }),
        't/theme.css': '''
          [data-theme='demo'] {
            --accent: #ff0000;
            --bg-app: #111111;
            --text-primary: #eeeeee;
            --gw-accent-rgb: 255, 0, 0;
            --accent-dim: rgba(var(--gw-accent-rgb), 0.5);
            --bg-player: #222222;
            --bg-sidebar: #333333;
            --waveform-played: #00ff00;
            --player-title: #123456;
            --sidebar-item-active-text: #abcdef;
          }
        ''',
      });
      final t = AppTheme.fromZipBytes(bytes);
      expect(t, isNotNull);
      // rgba(255,0,0,0.5)
      expect(t!.accentDim, const Color.fromRGBO(255, 0, 0, 0.5));
      expect(t.bgPlayer, const Color(0xFF222222));
      expect(t.bgSidebar, const Color(0xFF333333));
      expect(t.waveformPlayed, const Color(0xFF00FF00));
      expect(t.playerTitle, const Color(0xFF123456));
      expect(t.sidebarActiveText, const Color(0xFFABCDEF));
      // Fallbacks derivados
      expect(t.waveformUnplayed.a, lessThan(1.0));
      expect(t.textOnAccent, isNotNull);
    });

    test('parseCssColor soporta hex corto, rgba y nombres', () {
      expect(AppTheme.parseCssColor('#fff'), const Color(0xFFFFFFFF));
      expect(AppTheme.parseCssColor('#000000'), const Color(0xFF000000));
      // Regresión: el hex de 6 dígitos no debe rotar canales.
      expect(AppTheme.parseCssColor('#123456'), const Color(0xFF123456));
      expect(AppTheme.parseCssColor('#A855F7'), const Color(0xFFA855F7));
      // CSS #rrggbbaa -> 0xaarrggbb.
      expect(AppTheme.parseCssColor('#12345678'), const Color(0x78123456));
      expect(AppTheme.parseCssColor('rgba(0, 0, 0, 0.5)'),
          const Color.fromRGBO(0, 0, 0, 0.5));
      expect(AppTheme.parseCssColor('transparent'), Colors.transparent);
    });
  });
}
