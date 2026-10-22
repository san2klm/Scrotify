import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Composición del escritorio, sin volver transparentes el texto y los botones.
class WindowsWindowEffects {
  static const channel = MethodChannel('com.crotowave/window_effects');

  static Future<void> apply({
    required bool transparent,
    required bool dark,
    required Color background,
  }) async {
    // window_manager configura primero el fondo del host Flutter. El canal
    // nativo aplica después el material DWM, porque el plugin lo restablece.
    await windowManager
        .setBackgroundColor(transparent ? Colors.transparent : background);
    await channel.invokeMethod<void>('setEffects', {
      'transparent': transparent,
      'blur': false,
      'dark': dark,
    });
  }
}
