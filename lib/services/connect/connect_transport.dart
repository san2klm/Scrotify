import 'dart:async';

import 'connect_protocol.dart';

/// Camino por el que se descubren dispositivos y viajan los mensajes cifrados.
/// Hay uno por LAN y otro por el servidor Jam; `ConnectService` los combina.
abstract class ConnectTransport {
  /// Dispositivos visibles por este camino (sin incluir el propio).
  Stream<List<ConnectDevice>> get devices;

  /// Blobs cifrados recibidos: `(deviceId emisor, blob)`.
  Stream<({String from, String blob})> get messages;

  /// Estado legible para la UI (p. ej. por qué no conecta).
  String? get problem;

  /// `true` si puede entregar a [deviceId] ahora mismo.
  bool canReach(String deviceId);

  Future<void> start();
  Future<void> stop();

  /// Envía a un dispositivo concreto o, con `null`, a todos los visibles.
  Future<void> send(String? deviceId, String blob);
}
