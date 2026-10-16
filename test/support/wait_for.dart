import 'dart:async';

/// Espera a que se cumpla [condition] en vez de dormir un tiempo fijo.
///
/// Falla (con [reason]) si no se cumple en [timeout]. Es la forma de esperar
/// trabajo asíncrono real en las pruebas: no depende de la velocidad de la
/// máquina ni añade latencia cuando ya está listo.
Future<void> waitFor(
  FutureOr<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  Duration step = const Duration(milliseconds: 10),
  String reason = 'la condición no se cumplió a tiempo',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(reason, timeout);
    }
    await Future<void>.delayed(step);
  }
}
