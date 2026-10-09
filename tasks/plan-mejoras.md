# Plan de mejoras (2026-10-09)

Estado: `[ ]` pendiente · `[~]` en curso · `[x]` hecho (con commit) · `[!]` bloqueado/necesita decisión.

Reglas de cada ítem (AGENTS.md §4): TDD donde haya lógica, `flutter analyze` 0 issues,
tests relevantes en verde, un commit por ítem, `git status --porcelain` tras cada
cambio, y una línea de avance en `tasks/todo.md`.

Base: `main` @ `0718f17` (merge de `origin/PC123`), 625 tests OK.

## Orden de ejecución y dependencias

Primero lo pequeño y aislado, luego lo medio, y al final el refactor grande
(para no provocar conflictos con el resto).

| Fase | Ítems | Motivo del orden |
|------|-------|------------------|
| A. Rápidos | 2, 3, 7, 11, 12 | Pequeños, sin dependencias entre sí |
| B. Medios | 1, 4, 6, 8, 13 | Tocan plataforma o UI nueva |
| C. Sensible | 5 | Riesgo de pérdida de datos: diseño con tombstones y tests primero |
| D. Pruebas | 10 | Depende de que 11 y 12 estén hechos |
| E. Refactor | 9 | Al final, sin cambio de comportamiento, con toda la batería como red |

---

## Fase A — Rápidos

### [x] 2. Nombre de dispositivo editable en Connect
- Dónde: `lib/services/connect/connect_service.dart`, `lan_transport.dart` (`selfName`), `relay_transport.dart`, `lib/widgets/connect_panel.dart`.
- Plan: persistir el nombre en `settings.json` (clave `connectDeviceName`); campo editable en el panel; al cambiarlo, reanunciar a LAN y relé. Valor por defecto = el actual.
- Tests: guardar/leer, reanuncio, nombre vacío o >40 caracteres se normaliza.
- Hecho cuando: renombrar se ve en otro dispositivo sin reiniciar.

### [x] 3. Transferir toda la cola en Connect
- Dónde: `player_connect_port.dart` (`maxTransferTracks = 40`, líneas 53/78/103), `connect_mirror.dart:80`, límite de trama de 128 KB del servidor.
- Plan: enviar la cola en trozos (lotes de N pistas, calculados por tamaño codificado y no por cantidad) con mensaje `queue_chunk` (índice, total). El receptor ensambla y aplica al completar; si falta un trozo, descarta y mantiene la cola previa. Sin romper clientes viejos: si el receptor no declara soporte, se mantiene el tope de 40.
- Tests: cola de 500 pistas llega completa; trozo perdido no deja cola a medias; compatibilidad con el tope antiguo.

### [x] 7. El cliente lee `/api/capabilities` del servidor Jam
- Dónde: `jam-server/src/server.js:273` (endpoint ya existe), `lib/services/remote_jam_service.dart`, `jam_controller.dart`.
- Plan: `JamCapabilities` (modelo tipado con valores por defecto conservadores), cargado al conectar al relé; las funciones opcionales (historial, matching, etc.) se habilitan solo si el servidor las declara. Fallo de red o 404 → capacidades mínimas, sin error visible.
- Tests: parser con campos desconocidos y ausentes; servidor viejo sin endpoint.

### [x] 11. Progreso y cancelación del escaneo de descargas
- Dónde: `local_music_service.dart` (`rescan`/`_rescan`, línea 663+), `local_music_settings.dart`, `navidrome_service.getDownloadRecoveryCatalog`.
- Plan: `ValueNotifier<ScanProgress>` (fase: catálogo / archivos, hechos/total) y token de cancelación; botón "Cancelar" en Ajustes. Cancelar deja el índice consistente (no escribe a medias).
- Tests: cancelar a mitad conserva el índice anterior; el progreso es monótono.

### [x] 12. Caché del catálogo de recuperación
- Dónde: `navidrome_service.dart:1762`.
- Plan: caché en memoria por `serverScope` con TTL de 10 min e invalidación al cambiar de sesión o tras forzar "Reescanear". Mantiene la comprobación de sesión actual.
- Tests: segunda llamada no vuelve a paginar; otra sesión no reutiliza; el forzado sí refresca.

---

## Fase B — Medios

### [x] 1. Selector de salida ALSA `hw:` en Linux (bit-perfect real)
- Dónde: `hifi_profiles.dart` (rama Linux), `hifi_coordinator.dart`, `settings_screen.dart` (Salida), `docs/equalizer.md`.
- Plan: enumerar dispositivos con mpv (`audio-device-list`) filtrando `alsa/hw:` y mostrar PipeWire/sistema como opción por defecto; guardar la elección; con `hw:` aplicar `ao=alsa` + `audio-device`, y volver a la salida del sistema si el dispositivo desaparece. Mantener el aviso de que Bluetooth/PipeWire no es bit-perfect.
- Cuidado: no reintroducir el bug de `bc53fca` (exclusividad que deja el stream sin destino). Por defecto sigue `audio-exclusive=no`.
- Tests: planner por plataforma; dispositivo ausente → fallback; prueba de integración con libmpv y WAV silencioso (ya existe `linux_hifi_output_test.dart`).

### [x] 4. Vincular sincronización escaneando QR
- Dónde: `sync_service.dart` (`link`, `enableNew`), `sync_settings.dart`, `pairing_qr_code.dart`, `QrScannerSheet` (`mobile_scanner`, ya en pubspec).
- Plan: en el dispositivo origen, mostrar QR con la clave (`scrotify-sync://<clave>`) tras confirmación explícita (biometría si está disponible) y con aviso de que es un secreto; en el destino, botón "Escanear QR" que llama a `link`. Nunca se registra la clave en logs.
- Tests: formato y validación del URI; clave inválida rechazada; el QR no se genera sin confirmar.

### [x] 6. Control remoto en Android TV: foco inicial, reproductor y Ajustes
- Dónde: `tv_focus_ring.dart`, `home_shell.dart`, `player_screen.dart`, `settings_screen.dart`, `global_top_bar.dart`.
- Plan: `FocusTraversalGroup` por pantalla con `autofocus` en el primer contenido (no en la barra superior); reproductor completo con foco/atajos (play/pausa, ±10 s, siguiente/anterior); Ajustes navegable con flechas y OK.
- Tests de widget con `FORCE_TV`; verificar en emulador TV 1920x1080 con `adb input keyevent`.

### [x] 8. Historial de Jam para invitados y "guardar mis aportaciones"
- Dónde: `jam_history.dart`, `jam_guest_service.dart`, `jam_host_service.dart`, `jam_history_dialog.dart`, y el esquema de mensajes (`jam_security.dart` para validar).
- Plan: mensaje `history_snapshot` host→invitado (solo las últimas N entradas, validado con esquema estricto); el invitado guarda localmente sus propias aportaciones; acción "Guardar mis aportaciones" como playlist en Navidrome. Respeta los límites de tamaño de trama.
- Tests: esquema rechaza campos inválidos; el invitado solo ve su historial permitido; snapshot grande se trunca.

### [x] 13. Notificación persistente de Jam en Android
- Dónde: `scrotify_audio_handler.dart`, `MainActivity.kt`/servicio, `jam_controller.dart`.
- Plan: mientras haya sala Jam activa, mostrar en la notificación de medios el nombre de la sala y los participantes, con acción "Salir". Reutiliza el servicio de `audio_service` (sin crear un segundo foreground service). Se retira al salir de la sala.
- Verificación: emulador Android con `mobile-mcp` (crashes/logs).

---

## Fase C — Sensible

### [x] 5. Propagar borrados en la sincronización
- Dónde: `sync_service.dart` (`_cycle`, `_listRemote`, `_localDocs`), `sync_crypto.dart`.
- Riesgo: pérdida de datos en todos los dispositivos si un borrado es erróneo.
- Plan (con diseño primero):
  1. Tombstones cifrados `{name, deletedAt}` en lugar de borrar remoto; retención de 30 días.
  2. Borrado local solo si el tombstone es **posterior** al último cambio local (no resucita ni borra ediciones más nuevas).
  3. Sin red o fallo parcial → nunca se interpreta "ausente" como "borrado".
  4. Papelera local de 30 días antes de borrar de verdad.
- Tests primero: archivo editado después del borrado se conserva; borrado + recreación; ciclo interrumpido; dos dispositivos con relojes desfasados (usar versión monótona en el estado, no solo la hora).
- Se pedirá confirmación antes de activar por defecto.

---

## Fase D — Pruebas

### [x] 10. Integración de recuperación de descargas en Android
- Dónde: nuevo `integration_test/local_music_recovery_test.dart`, `MainActivity.kt` (`readAudioMetadata`).
- Plan: sembrar archivos de audio de prueba en el almacenamiento de la app, ejecutar `rescan` real con `MediaMetadataRetriever`, comprobar recuperadas / sin identificar / ambiguas. Correr en el emulador (`/opt/android-sdk/emulator/emulator`, adb de `/opt/android-sdk/platform-tools/adb`).
- Depende de: 11 y 12 (usar el mismo API).

---

## Fase E — Refactor sin cambio de comportamiento

### [x] 9. Partir archivos grandes
Objetivo: ninguno por encima de ~1200 líneas, **sin cambiar API pública** ni comportamiento.

| Archivo | Líneas | Corte propuesto |
|---------|--------|-----------------|
| `navidrome_service.dart` | 2869 | Cliente HTTP Subsonic / caché de biblioteca / sesión y perfiles |
| `jam_controller.dart` | 2379 | Cola Jam / sincronización de reloj / sala y roles |
| `player_controller.dart` | 2210 | Cola / crossfade / persistencia de estado |
| `home_screen.dart` | 1783 | Secciones de Home como widgets propios |

- Método: un archivo por vez, mover por clases cohesivas, exportar desde el archivo original para no tocar imports; `flutter analyze` y toda la batería (`flutter test`) tras **cada** movimiento; commit por archivo.
- Los modelos canónicos `Track`/`Album`/`Artist` siguen en `navidrome_service.dart` (invariante §3.1): se reexportan, no se duplican.

---

## Verificación final
- [x] `flutter analyze`: 0 issues
- [x] `flutter test`: todo verde
- [x] `jam-server`: `node --test` verde
- [x] APK teléfono y TV compilan
- [x] `tasks/todo.md` actualizado
- [ ] Push solo con confirmación expresa

## Fuera de alcance (necesita dispositivo físico del usuario)
Pruebas en TV real, teléfono físico, auriculares Bluetooth, deriva de reloj entre dos equipos.

## Bitácora
(Se rellena al cerrar cada ítem: commit, tests, notas.)

- **2** · nombre de dispositivo editable: `SettingsController.connectDeviceName` + `ConnectService.rename` (recrea transportes y reanuncia) + lápiz en el panel. 7 tests nuevos; 632 en total, analyze limpio.
- **3** · cola completa en Connect: `ConnectQueueChunks` (40 + trozos de 80, tope 1000), `ConnectQueueReceiver` (orden estricto, sin huecos, caduca a los 5 min), comando `queue_append`, `PlayerController.addAllToQueue`. Compatible con clientes viejos (ignoran `queue_append` y reciben los 40 de siempre). 647 tests, analyze limpio. Nota: `sync_service_test` es intermitente por carrera con directorios temporales (preexistente, pasa aislado).
- **7** · `JamCapabilities` tipado (`lib/models/jam_capabilities.dart`) reemplaza el registro `(reactions, chat)`; `JamController.cloudCapabilities`/`refreshCloudCapabilities()` (se invalida al cambiar de relé); el diálogo oculta "Sesión pública" y "Sala persistente" solo si el relé declara que no las ofrece (relé antiguo = todo visible, sin cambios). 653 tests, analyze limpio.
- **11** · progreso y cancelación del escaneo: `LocalScanProgress`/`LocalScanPhase`, `LocalMusicService.cancelScan()`, `ScanProgressView` en Ajustes. Decisión de seguridad: cancelar antes de comparar con el disco **no toca el índice** (purgar con una lista incompleta borraría descargas válidas; hay un test de control que demuestra que un escaneo completo sí purga); cancelar al identificar conserva lo ya recuperado y lo guarda.
- **12** · caché del catálogo: `getDownloadRecoveryCatalog({forceRefresh})` con validez de 3 min por sesión, descargas simultáneas compartidas, resultado inmutable; un escaneo cancelado deja la descarga lista para el siguiente. 670 tests, analyze limpio.
- **1** · selector ALSA `hw:` (Linux, Bit-perfect): `audio_output_devices.dart` (parser de `audio-device-list` + validación estricta del nombre), `HifiPlanner(outputDevice)`, `HifiCoordinator` (lista, comprobación de presencia, `outputDeviceMissing`, restauración a `auto`), `SettingsController.audioOutputDevice`, selector en Ajustes y doc. `audio-device` se cambia sin recrear el player. Verificado con libmpv real (`SCROTIFY_AUDIO_INTEGRATION=1`). Pendiente de tu lado: probar con un DAC USB real.
- **4** · QR de sincronización: `SyncKeyLink` (`scrotify-sync://<clave>`, parser estricto), botón «Mostrar QR» (aviso de secreto + biometría si existe, inyectable para tests) y «Escanear QR» en el diálogo de vinculación (solo móvil; reutiliza `QrScannerSheet`, ahora con `prefix`/`hint`). Bugs hallados por los tests y corregidos: `AlertDialog` + `LayoutBuilder` del QR (ancho fijo) y `TextEditingController` liberado con el diálogo aún animándose en `_link` (ahora `_LinkDialog` con estado). 698 tests. Pendiente de tu lado: probar el escaneo con la cámara real.
- **6** · Android TV: `TvInitialFocus` (foco inicial en el contenido con reintentos cada 100 ms hasta 3 s; se rinde si el usuario ya pulsó una tecla, si hay un diálogo encima o si el foco ya está dentro; ambas guardas verificadas por mutación) aplicado a Inicio, álbum, artista, playlist, favoritos y Ajustes (raíz y subpáginas); el reproductor completo enfoca pausa/reproducir y salta de 10 s con el mando (la barra de onda ya respondía a ←/→). Tests: recorrido de Ajustes con las flechas (7 categorías, ida y vuelta), OK/Atrás, subpáginas, Inicio y reproductor. Pendiente de tu lado: probar en una tele/emulador TV reales (no lo hice).
- **Test inestable corregido** · `sync_service_test` tenía una carrera latente (`link()` lanza un `syncNow()` en segundo plano y el `syncNow()` del test se ignoraba si ya había uno): ahora espera a que termine (`fullSync`). 0 fallos en 10 ejecuciones seguidas de la suite (antes, ~1 de cada 4 con mis tests añadidos). Dos fallos aislados de `offline_download_manager_test` y `local_music_service_test` no se han vuelto a reproducir en 13 ejecuciones.
- **8** · historial para invitados. **Cambio de diseño respecto al plan**: no hay mensaje `history_snapshot`. Cada invitado reconstruye su historial observando el estado sincronizado (`JamGuestHistoryTracker`: mismo umbral 30 s / 50 %, solo cuenta lo oído desde que entró, recuerda quién añadió cada pista a partir de la cola, memoria acotada a 300). Ventajas: sin cambios de protocolo ni de servidor relay, funciona igual en LAN y nube, y no hay que confiar en datos que mande el host. Coste: no ve lo anterior a su entrada. «Guardar mis aportaciones» crea la playlist «Mis aportaciones a la Jam <fecha>» con lo que añadió él (se identifica por nombre: si el host le cambia el nombre por duplicado, no se reconoce). Test de integración real (host LAN por loopback + `JamController` invitado + diálogo).
- **13** · notificación de Jam en Android: se reutiliza la notificación de medios de `audio_service` (sin segundo servicio en primer plano). `ScrotifyAudioHandler.setJam(JamNotificationInfo)` añade «<artista> · Jam de <anfitrión>» / «Tu Jam», «N personas» (solo si se conoce: el invitado conectado por el servidor central no recibe la lista, así que no se inventa) y un botón «Salir de la Jam»/«Terminar la Jam» (`drawable/audio_service_leave_jam`, con nombre `audio_service_*` para que `res/raw/keep.xml` lo salve de R8). El nombre del anfitrión (lo elige otra persona) se limpia y se recorta. Verificado: tests del handler, `notificationInfo` con host LAN real y el recurso presente en `app-phone-debug.apk` y `app-tv-debug.apk`. **Limitación**: aparece solo mientras haya una pista (es la notificación de reproducción); sin pista no hay notificación. Pendiente de tu lado: verlo en un teléfono con una Jam real.
- **10** · `integration_test/local_music_recovery_test.dart` (7 pruebas) + fixture FLAC con etiquetas + `tool/run_android_integration.sh <id>`. Ejecutado en el emulador `pixel_test` (Android 14): lector nativo `MediaMetadataRetriever` (título/artista/álbum/duración), archivo corrupto, recuperación desde subcarpetas con copias que cuentan como una, etiquetas ambiguas, persistencia al reabrir y cancelación. 7/7. Añade `integration_test` (SDK) como dependencia de desarrollo: solo suma paquetes transitivos de desarrollo, no cambia versiones existentes. **Seguridad**: el script exige el id del dispositivo y rechaza los que no sean `emulator-*` (hay un teléfono real conectado por Wi-Fi; escribe en `/storage/emulated/0/Music` y concede «todos los archivos»). Solo se usó `emulator-5554`; el emulador quedó apagado y su carpeta Music vacía.
- **5** · borrados en la sincronización (solo **temas .zip**; los JSON se reescriben, nunca se borran). Diseño: aviso de borrado (tombstone) cifrado bajo la clave `x-<hash del documento>` (derivada de la clave del documento, sin revelar nombres); su contenido se **autentica** (descifra y comprueba que habla de ese tema) antes de actuar; el nombre del aviso acaba en `.deleted`, así un cliente antiguo lo descarta en vez de escribir un archivo. Reglas: lo editado en un dispositivo gana al borrado (y se devuelve a los demás); un dispositivo que nunca sincronizó ese tema no lo pierde; un borrado local solo se infiere si la carpeta de temas existe y el tema falta en **dos ciclos seguidos**; si desaparecen ≥3 temas y más de la mitad de los conocidos de golpe, no se propaga, se restauran y se avisa; los temas borrados por un aviso van a una **papelera local** (`sync_trash/`, 30 días) y los avisos de más de 30 días se eliminan del servidor. Sin cambios en `jam-server` (ya admitía DELETE). 18 tests nuevos; **6 mutaciones** de las guardas (confirmación en 2 ciclos, borrado masivo, autenticidad, editar-gana, carpeta no listada, JSON borrable) detectadas por los tests. Limitaciones: un dispositivo desconectado >30 días puede devolver un tema ya borrado (preferible a perder uno); clientes antiguos descargan cada aviso en cada ciclo sin usarlo (una GET diminuta). Falta probar entre dos dispositivos reales.
- **9** · archivos grandes partidos **sin cambiar comportamiento ni API pública**. Método: la clase pasa a `abstract class _XBase` (con todos los campos) + `mixin`s en archivos `part` por área; los miembros que un mixin usa y viven en otro sitio se declaran abstractos en la base. Verificado por **comparación de líneas** (multiconjunto de líneas del original frente a la suma de los archivos nuevos): solo difieren cabeceras, firmas abstractas, `@override` y los pocos estáticos calificados con el nombre de la clase. Un primer intento perdió comentarios de sección; se detectó con esa misma comparación, se corrigió el generador y se repitió.

  | Archivo | Antes | Ahora |
  |---|---|---|
  | `navidrome_service.dart` | 2911 | 850 (+ `navidrome_models` 354, `_playlists` 303, `_favorites` 373, `_library` 590, `_extras` 541) |
  | `player_controller.dart` | 2221 | 1076 (+ 7 áreas de 120–359) |
  | `jam_controller.dart` | 2464 | 689 (+ 6 áreas de 103–507) |
  | `home_screen.dart` | 1786 | 354 (+ biblioteca 617, contenido 834) |

  Los modelos canónicos `Track`/`Album`/`Artist` siguen en la biblioteca `navidrome_service.dart` (son un `part` de ella), así que el invariante §3.1 de AGENTS.md se cumple. 754 tests, analyze limpio, compilan Linux debug y Android phone/TV debug; con `SCROTIFY_AUDIO_INTEGRATION=1` pasan los tests con libmpv. Siguen por encima de 1200 líneas y no estaban en el alcance: `pairing_panel` (1661), `jam_dialog` (1632), `track_context_menu` (1606), `mobile_home_screen` (1594), `jam_host_service` (1279).
