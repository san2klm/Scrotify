import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// Operaciones de ventana de escritorio compartidas por el marco de ventana
/// y el resto de la interfaz.
class WindowControls {
  WindowControls._();

  static bool get isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

  static Future<void> toggleMaximize() async {
    if (!isDesktop) return;
    if (await windowManager.isFullScreen()) return;
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  static Future<void> setFullScreen(bool value) async {
    if (!isDesktop) return;
    try {
      await windowManager.setFullScreen(value);
    } catch (e) {
      debugPrint('WindowControls.setFullScreen: $e');
    }
  }

  static Future<void> toggleFullScreen() async {
    if (!isDesktop) return;
    await setFullScreen(!await windowManager.isFullScreen());
  }
}
