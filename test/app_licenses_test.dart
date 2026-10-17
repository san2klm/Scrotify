import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/utils/app_licenses.dart';

void main() {
  Future<List<LicenseEntry>> collect({required bool desktop, required bool linux}) =>
      AppLicenses.entries(
        appLicense: () async => 'texto de LICENSE',
        desktop: desktop,
        linux: linux,
      ).toList();

  List<String> names(List<LicenseEntry> entries) =>
      [for (final e in entries) ...e.packages];

  test('en móvil solo van CrotoWave y el servidor CrotoLink', () async {
    final entries = await collect(desktop: false, linux: false);
    expect(names(entries), ['CrotoWave', 'CrotoLink server']);
    expect(entries.first.paragraphs.map((p) => p.text).join(), 'texto de LICENSE');
  });

  test('en Windows se suman libmpv y FFmpeg', () async {
    final entries = await collect(desktop: true, linux: false);
    expect(names(entries), containsAll(['libmpv', 'FFmpeg', 'ffprobe']));
    expect(names(entries), isNot(contains('keybinder-3.0')));
  });

  test('en Linux también keybinder y las librerías del AppImage', () async {
    final entries = await collect(desktop: true, linux: true);
    expect(names(entries),
        containsAll(['libmpv', 'FFmpeg', 'keybinder-3.0', 'Librerías del AppImage']));
  });

  test('el LICENSE del repo es la GPLv3 con la excepción para tiendas', () {
    final text = File('LICENSE').readAsStringSync();
    expect(text, startsWith('                    GNU GENERAL PUBLIC LICENSE'));
    expect(text, contains('App Store & Platform Distribution Exception'));
    expect(text, contains('Excepción para tiendas y plataformas de distribución'));
  });
}
