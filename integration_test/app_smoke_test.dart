// Arranque real de la app de escritorio: `main()` completo (ventana, tema,
// proveedores, mpv) hasta la pantalla de inicio de sesión, sin excepciones.
// Las pruebas unitarias montan pantallas sueltas y no ven fallos de arranque.
//
//   tool/run_linux_smoke.sh
//
// No inicia sesión ni toca la red. Las credenciales se aíslan en memoria y el
// script apunta los datos de la app a una carpeta temporal.

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:navidrome_client/main.dart' as app;
import 'package:navidrome_client/services/secure_storage.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('la app arranca y muestra el inicio de sesión', (tester) async {
    // Sin credenciales guardadas: no entra sola a ningún servidor.
    SecureStorage.inMemoryTestStore = {};
    addTearDown(() => SecureStorage.inMemoryTestStore = null);

    // `main` instala sus propios manejadores de errores (registran y siguen):
    // con ellos puestos el test ni vería los fallos ni podría informar de los
    // suyos, y se quedaría colgado. Se devuelven los del banco de pruebas.
    final errorBuilder = ErrorWidget.builder;
    final testOnError = FlutterError.onError;
    final testPlatformOnError = PlatformDispatcher.instance.onError;
    await app.main();
    FlutterError.onError = testOnError;
    PlatformDispatcher.instance.onError = testPlatformOnError;
    addTearDown(() => ErrorWidget.builder = errorBuilder);

    // Hay animaciones permanentes: se avanza por pasos en vez de esperar calma.
    final urlField = find.text('URL DEL SERVIDOR');
    for (var i = 0; i < 100 && urlField.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(urlField, findsOneWidget);
    expect(find.byType(TextFormField), findsWidgets);

    // Unos segundos más con la app viva: mpv y los servicios terminan de iniciar.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    // El framework exige dejar el constructor de errores como lo encontró.
    ErrorWidget.builder = errorBuilder;
  });
}
