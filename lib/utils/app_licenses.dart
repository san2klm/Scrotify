import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'build_info.dart';

/// Avisos legales para «Licencias de código abierto» (ver LICENSING.md).
///
/// Flutter ya junta solo las licencias de todos los paquetes de Dart (también
/// `third_party/just_audio_media_kit`). Aquí se agrega lo que no ve: la
/// licencia de CrotoWave y las librerías nativas que van con el escritorio.
class AppLicenses {
  const AppLicenses._();

  static const legalese = '© 2026 Lautaro (Dante0Q) y los colaboradores de '
      'CrotoWave.\nSoftware libre bajo GPL-3.0-or-later, con una excepción '
      'para tiendas de aplicaciones.';

  static bool _registered = false;

  static void register() {
    if (_registered) return;
    _registered = true;
    final desktop = !kIsWeb && (Platform.isLinux || Platform.isWindows);
    final linux = !kIsWeb && Platform.isLinux;
    LicenseRegistry.addLicense(() => entries(
          appLicense: () => rootBundle.loadString('LICENSE'),
          desktop: desktop,
          linux: linux,
        ));
  }

  static void show(BuildContext context) => showLicensePage(
        context: context,
        applicationName: 'CrotoWave',
        applicationVersion: BuildInfo.label,
        applicationLegalese: legalese,
      );

  @visibleForTesting
  static Stream<LicenseEntry> entries({
    required Future<String> Function() appLicense,
    required bool desktop,
    required bool linux,
  }) async* {
    yield LicenseEntryWithLineBreaks(['CrotoWave'], await appLicense());
    yield const LicenseEntryWithLineBreaks(['CrotoLink server'], _jamServer);
    if (desktop) {
      yield const LicenseEntryWithLineBreaks(['libmpv'], _libmpv);
      yield const LicenseEntryWithLineBreaks(['FFmpeg', 'ffprobe'], _ffmpeg);
    }
    if (linux) {
      yield const LicenseEntryWithLineBreaks(['keybinder-3.0'], _keybinder);
      yield const LicenseEntryWithLineBreaks(
          ['Librerías del AppImage'], _appImageLibs);
    }
  }

  static const _jamServer = '''
CrotoLink server
Copyright (C) 2026 Lautaro (Dante0Q) and the CrotoWave contributors

The Jam server is a separate program, licensed under the GNU Affero General Public License version 3 or (at your option) any later version (AGPL-3.0-or-later). The app only talks to it over the network. Anyone may run their own server; whoever modifies it and lets others use it over a network must offer them its source code (AGPL section 13). Each server publishes its source at GET /source.

Full text: https://www.gnu.org/licenses/agpl-3.0.html''';

  static const _libmpv = '''
libmpv (mpv media player) — https://mpv.io
Copyright (C) the mpv developers

The copy distributed with CrotoWave for desktop is built with its GPL parts and is licensed under the GNU General Public License version 2 or later (GPL-2.0-or-later). Builds without those parts are available under the GNU Lesser General Public License version 2.1 or later.

Source code: https://github.com/mpv-player/mpv
GPL: https://www.gnu.org/licenses/gpl-2.0.html''';

  static const _ffmpeg = '''
FFmpeg and ffprobe — https://ffmpeg.org
Copyright (C) the FFmpeg developers

FFmpeg is licensed under the GNU Lesser General Public License version 2.1 or later. The copy distributed with CrotoWave for desktop enables optional GPL parts, so as a whole it is licensed under the GNU General Public License version 2 or later (GPL-2.0-or-later).

Source code: https://ffmpeg.org/download.html
Legal: https://ffmpeg.org/legal.html''';

  static const _keybinder = '''
keybinder-3.0 — https://github.com/kupferlauncher/keybinder
Copyright (C) 2008 Alex Graveley
Copyright (C) 2010 Ulrik Sverdrup <ulrik.sverdrup@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.''';

  static const _appImageLibs = '''
The Linux AppImage also bundles shared libraries taken from Debian 12 (codecs, audio, image and network libraries) so that it runs without installing anything. Each one keeps its own license (LGPL, MIT, BSD, zlib and others).

Inside the AppImage, usr/share/doc/<package>/copyright holds the copyright notice and license of every bundled package, and THIRD_PARTY_SOURCES.txt lists each package with its exact version and where to download its source code.''';
}
