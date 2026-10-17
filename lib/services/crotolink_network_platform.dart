import 'dart:io';

import 'package:flutter/services.dart';

/// Mantiene abierto el acceso a paquetes multicast mientras CrotoLink está activo.
///
/// Android filtra broadcasts y multicast de Wi-Fi para ahorrar batería. El
/// permiso del manifiesto no basta por sí solo: hay que adquirir un
/// [WifiManager.MulticastLock] desde código nativo. El contador permite que el
/// host y un escaneo temporal lo compartan sin liberarlo prematuramente.
class CrotoLinkNetworkPlatform {
  static const _channel = MethodChannel('crotowave/crotolink_network');
  static int _multicastLeases = 0;

  static Future<void> acquireMulticastReception() async {
    if (!Platform.isAndroid) return;

    _multicastLeases++;
    if (_multicastLeases != 1) return;

    try {
      await _channel.invokeMethod<void>('acquireMulticastLock');
    } on MissingPluginException {
      // Permite ejecutar pruebas Dart o versiones anteriores de la app sin
      // convertir el radar en un error fatal.
    } on PlatformException {
      _multicastLeases = 0;
    }
  }

  static Future<void> releaseMulticastReception() async {
    if (!Platform.isAndroid || _multicastLeases == 0) return;

    _multicastLeases--;
    if (_multicastLeases != 0) return;

    try {
      await _channel.invokeMethod<void>('releaseMulticastLock');
    } on MissingPluginException {
      // Ver comentario en acquireMulticastReception.
    } on PlatformException {
      // No hay más recurso Dart que liberar.
    }
  }
}
