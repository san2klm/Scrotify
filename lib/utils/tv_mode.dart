import 'dart:io';

import 'package:flutter/services.dart';

/// ¿La app corre en un Android TV? (se maneja con control remoto: sin
/// pantalla táctil, sin cámara y con foco direccional.)
///
/// Para probar en un emulador normal: `--dart-define=FORCE_TV=true`.
class TvMode {
  TvMode._();

  static const _forced = bool.fromEnvironment('FORCE_TV');
  static const _channel = MethodChannel('scrotify/device');

  static bool _isTv = _forced;
  static bool get isTv => _isTv;

  /// Se llama una vez antes de `runApp`.
  static Future<void> init() async {
    if (_forced || !Platform.isAndroid) return;
    try {
      _isTv = await _channel.invokeMethod<bool>('isTelevision') ?? false;
    } on MissingPluginException {
      _isTv = false; // Versiones anteriores o pruebas sin plugin.
    } on PlatformException {
      _isTv = false;
    }
  }

  /// Solo para tests.
  static void debugSet(bool value) => _isTv = value;
}
