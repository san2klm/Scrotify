# Plan de mejoras — tanda 3 (2026-10-09)

Estado: `[ ]` pendiente · `[~]` en curso · `[x]` hecho · `[!]` necesita decisión del usuario.

Base: `main` @ `67abf4f`. Tanda 2 cerrada en `tasks/plan-mejoras-2.md`.

Origen: lo observado al ejecutar la tanda 2 y los dos fallos del mismo día
(Bit-perfect rompía Ajustes en Linux; el teléfono quedó con un build de 32 bits).
Los dos pasaron con 850 tests en verde: el hueco no es de tests unitarios, es de
comprobar la app armada y de saber qué build hay instalado.

## Fase 0 — Respaldo

### [!] 1. Push de `main`
- 45 commits solo existen en este equipo. Además es lo único que estrena el CI.

## Fase 1 — Que los fallos de hoy no se repitan

### [x] 2. Instalación segura en Android
- `tool/install_android.sh <id> phone|tv`: exige id, compila el sabor, comprueba que el APK trae la ABI del dispositivo, instala con `-r`, abre la app y falla si hay un cierre en los primeros segundos.
- Evidencia: con teléfono (arm64) y Chromecast HD (armv7) conectados, quedó en el teléfono un debug solo de 32 bits.

### [x] 3. Saber qué build está instalado
- `versionName` fijo en 1.0.0, `versionCode` 2003 sin tocar y «v1.0.0» escrito a mano en Ajustes. Hubo que deducir el build por la hora de instalación.
- Inyectar commit corto y fecha con `--dart-define`, mostrarlos en Ajustes y en la cabecera del diagnóstico, y subir `versionCode` en `scripts/build_apks.sh`.

### [x] 4. Pantalla de error propia
- Hoy un fallo de build muestra la pantalla roja (debug) o gris (release) a ventana completa.
- `ErrorWidget.builder` con un recuadro acotado y «copiar diagnóstico»; el error entra en `DiagnosticsLog`.

### [x] 5. Recorrido de humo de Ajustes (S)
- El test de Ajustes no monta `HifiCoordinator`, así que el selector ALSA nunca se ejercitó con dispositivos; el fallo de Bit-perfect venía de ahí.
- Test que abre cada subpantalla con todos los proveedores reales de `main.dart`, activa cada opción y vuelve atrás sin excepciones. Con una lista de salidas falsa (0, 1 y varias, y una elegida que ya no está).

### [ ] 6. Arranque real en CI
- `integration_test` mínimo en Linux (bajo `xvfb`): la app abre, llega al login y a Ajustes.

## Fase 2 — Publicación

### [!] 7. Keystore propio — en espera por indicación del usuario
- El APK del teléfono es debug-firmado. Crear keystore y `android/key.properties`.

### [!] 8. `applicationId` definitivo — en espera por indicación del usuario
- Sigue `com.example.navidrome_client`. Si se cambia, que sea junto con el 7: ambos obligan a reinstalar una sola vez.

### [x] 9. APK por arquitectura
- El APK universal pesa 85 MB; el de solo arm64 de un build anterior, 30 MB. `--split-per-abi` en `scripts/build_apks.sh` (arm64 para teléfono, armv7 para el Chromecast).

## Fase 3 — Robustez

### [ ] 10. Los `catch (_) {}` dejan rastro
- 91 en `lib/`. Revisarlos por archivo: los que ocultan fallos de red, disco o Jam pasan a registrar en `DiagnosticsLog`; los de limpieza se quedan con un comentario de por qué.

### [~] 11. La unión a una Jam espera el primer estado (S)
- `joinSession` termina con `join_response`; la sesión llega en el mensaje siguiente. Hoy funciona por el orden de entrega de `web_socket_channel` 2.
- Hacer que espere el `jam_state_snapshot` (con tope de tiempo) y después subir a `web_socket_channel` 3.

### [ ] 12. Partir `jam_host_service.dart` (1279 líneas) (S)

## Fase 4 — Dependencias que necesitan dispositivo

### [ ] 13. `just_audio` 0.10 + `audio_session` 0.2
- Reaplicar los tres cambios de `third_party/just_audio_media_kit`. Lista de comprobación manual: reproducción, crossfade, segundo plano, notificación, Bluetooth, ecualizador y Hi-Fi en Linux.

### [ ] 14. `mobile_scanner` 7
- Comprobar en el teléfono los tres escaneos: Jam, vincular teléfono y sincronización.

## Fase 5 — Arrastrado de tandas anteriores

### [ ] 15. Medir el lag en la tele antes de tocar imágenes
### [ ] 16. Test de `DesktopLoginScreen`
### [!] 17. Cerrar las tres tareas basura del Brain
### [ ] 18. Localización (solo si se distribuye fuera)

## Trabajo entre sesiones
- Dos sesiones sobre el mismo árbol funcionó con reparto de archivos y commits por ruta, pero hubo que frenar lints y dependencias para no invalidar corridas ajenas. Para la próxima: un `git worktree` por sesión.

## Orden
1 → 2, 3 → 5, 4 → 6 → 7+8 → 9 → 11 → 10 → 13, 14.

## Bitácora

- **3** · `BuildInfo` (`lib/utils/build_info.dart`): versión, commit y fecha por `--dart-define`; se ven al pie de Ajustes y en la cabecera del diagnóstico. `scripts/build_apks.sh` pone como número de build `10000 + nº de commits` (el instalado era 2003; así nunca es un «downgrade»). Con `flutter run` se lee «desarrollo».
- **9** · `scripts/build_apks.sh` genera un APK por arquitectura: teléfono arm64 (31 MB frente a 82 MB) y tele arm64 + armv7. `--universal` para emulador. Solo se compiló y probó el de teléfono.
- **2** · `tool/install_android.sh <id> phone|tv [--check]`. Probado en real: sin id lista los dispositivos; rechaza `phone` en el Chromecast y `tv` en el teléfono; avisa si falta el APK de esa arquitectura; instaló en el teléfono y comprobó el arranque (versionCode 12146). Sin probar: el camino en que la app se cierra tras instalar.
- Nota: una compilación de APK falló una vez porque `GeneratedPluginRegistrant.java` quedó con el plugin de `integration_test` mientras la otra sesión corría tests; al reintentar pasó. Otra razón para un `git worktree` por sesión.
- **5** (sesión `Scrotify`, `1e36ed5`, `9543465`, `835ae49`) · `test/settings_smoke_test.dart`, 20 tests con los proveedores de `main.dart`: abre las siete subpantallas, mueve cada interruptor, opción y deslizador, y vuelve. Destapó un bug real: dos salidas ALSA con el mismo nombre rompían el desplegable («exactly one item with value»); `directHardwareDevices` ahora quita repetidas. Límite: «Biblioteca y descargas» usa un `LocalMusicService` falso (el real se cuelga en `initialize()` dentro de `testWidgets`, sin investigar).
- **4** · `AppErrorBox` (`lib/widgets/app_error_box.dart`) instalado como `ErrorWidget.builder` en `main`: un fallo al construir un widget deja un recuadro en su hueco y el resto de la pantalla sigue visible; el texto técnico solo se ve en debug. No lleva botón de copiar: remite a Ajustes → Diagnóstico, donde ya queda el error.
