import 'dart:io';

import 'package:flutter/services.dart';

/// Permiso necesario para la biblioteca compartida de Android.
class AndroidMusicStorage {
  static const _channel = MethodChannel('crotowave/music_storage');

  static Future<bool> ensureAccess({bool request = false}) async {
    if (!Platform.isAndroid) return true;
    return await _channel
            .invokeMethod<bool>(request ? 'requestAccess' : 'hasAccess') ??
        false;
  }

  static Future<void> requireAccess() async {
    if (!await ensureAccess(request: true)) {
      throw const FileSystemException(
          'Permite el acceso al almacenamiento para usar la carpeta Music.');
    }
  }
}
