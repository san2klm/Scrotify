# Plan de mejoras — tanda 2 (2026-10-09)

Estado: `[ ]` pendiente · `[~]` en curso · `[x]` hecho (con commit) · `[!]` necesita decisión.

Base: `main` @ `d1ca483` (tanda 1 cerrada en `tasks/plan-mejoras.md`).

Reparto: coordina la sesión `crotowave-ff`; la sesión `CrotoWave` implementa en
paralelo los ítems marcados (S). Mismo árbol de trabajo: commits con rutas
explícitas (`git commit -- rutas`), sin `add -A`, sin push sin confirmación.

Reglas de cada ítem (AGENTS.md §4): `flutter analyze` 0 issues, tests relevantes
en verde, un commit por ítem y una línea en `tasks/todo.md`.

## Fase 1 — Red de seguridad

### [x] 1. CI en GitHub Actions
- `.github/workflows/ci.yml`: `flutter analyze` + `flutter test` (con libmpv y ffmpeg) y `node --test` del crotolink-server.
- Sin verificar hasta el primer push (no se puede ejecutar en local).

### [x] 2. Eliminar tests intermitentes (S)
- Fallos aislados anotados en `offline_download_manager_test` y `local_music_service_test`.
- Hecho cuando: 20 corridas seguidas de la suite sin fallos, con causa raíz (sin reintentos ni skips).

### [x] 3. Endurecer lints
- `flutter_lints` 3.0.1 sin reglas extra; 91 `catch (_) {}` vacíos en `lib/`.
- Activar `unawaited_futures`, `cancel_subscriptions`, `close_sinks`; analyze en 0.
- Va después de los ítems 2 y 9 para no pisar a la otra sesión.

## Fase 2 — Seguridad y release

### [x] 4. Firma debug silenciosa en release
- Sin `android/key.properties` el release cae a la clave debug (a propósito, para desarrollo). Ahora Gradle y `scripts/build_apks.sh` lo avisan.
- [!] Pendiente del usuario: crear un keystore propio si se va a distribuir.

### [x] 20. Versionar la configuración de build de Android
- `android/app/build.gradle.kts` (sabores phone/tv), los manifiestos de `src/phone` y `src/tv`, `settings.gradle.kts` y el wrapper no estaban en git: un clon limpio no podía generar los APK.

### [!] 5. `applicationId` definitivo
- Sigue `el id de la plantilla de Flutter`. Cambiarlo obliga a reinstalar y pierde los datos locales: decide el usuario.

### [x] 6. Acotar el tráfico en claro
- `usesCleartextTraffic="true"` global (necesario para Navidrome en LAN). Avisar en el login si la URL es `http://` hacia un host público.
- Auditar `pairing_client.dart` (`http://host:port/pair/claim`): confirmar que el contenido va cifrado.

### [x] 7. CORS del crotolink-server (auditado, sin cambios)
- `access-control-allow-origin: *` en varios endpoints de `server.js`: dejarlo solo donde haga falta.

## Fase 3 — Diagnóstico

### [x] 8. Log estructurado y «Exportar diagnóstico»
- 175 `debugPrint`/`print` sueltos. Buffer circular en memoria, exportable desde Ajustes, sin secretos.

## Fase 4 — Cobertura

### [x] 9. Tests de servicios sin cobertura directa (S)
- `replay_gain.dart`, `playlist_export_service.dart`, `connect/relay_transport.dart`, `connect/connect_mirror.dart`, `connect/player_connect_port.dart`.

### [ ] 10. Tests de widget de login, Inicio y reproductor
- Revisado: ya hay tests que montan `MobileLoginScreen`, `HomeScreen`/`MobileHomeScreen` y `PlayerScreen`. Falta `DesktopLoginScreen`; prioridad baja.

## Fase 5 — Rendimiento (medir antes de tocar)

### [ ] 11. Perfilar la APK de TV y decodificar portadas a tamaño real
- Revisado: `CoverArt` ya decodifica al tamaño en pantalla (`ResizeImage`). Quedan 8 usos directos de `NetworkImage`/`Image.network` (cabeceras de artista y álbum, avatares). No se toca sin medir en la tele.
### [x] 12. Revisar los `Timer.periodic` (23): que se pausen en segundo plano

## Fase 6 — Dependencias (una por commit)

### [ ] 13. `just_audio` 0.9 → 0.10 (riesgo alto: copia parcheada en `third_party/just_audio_media_kit`)
### [ ] 14. `mobile_scanner` 5 → 7
### [~] 15. `web_socket_channel` 2 → 3, `rxdart` 0.27 → 0.28, `audio_session` 0.1 → 0.2
- [x] `rxdart` 0.28.
- [!] `web_socket_channel` 3: revertido, cambia el orden de entrega en la unión a una CrotoLink (ver bitácora).
- [ ] `audio_session` 0.2: bloqueado por `just_audio` 0.9 (va junto con el ítem 13).

## Fase 7 — Limpieza

### [x] 16. Partir los archivos que siguen por encima de 1200 líneas (S)
- `pairing_panel.dart`, `crotolink_dialog.dart`, `track_context_menu.dart`, `mobile_home_screen.dart`.

### [x] 17. Ignorar `CrotoWave-*.apk` en la raíz
### [!] 18. Cerrar tareas basura del Brain (`@file:Fase.md` ×2, `[CONTEXT COMPACTION…]`)
### [ ] 19. Localización (solo si se va a distribuir fuera)

## Bitácora

- **1** · workflow con dos jobs; YAML validado en local, crotolink-server 54/54 en local.
- **4** · aviso en `build.gradle.kts` y en `scripts/build_apks.sh`; `./gradlew help` evalúa bien.
- **17, 20** · `.gitignore` y archivos de build de Android añadidos al repo (sin secretos: `key.properties` y `local.properties` siguen ignorados).
- **6** · `isPublicCleartextUrl` (`lib/utils/cleartext_url.dart`) + `CleartextUrlWarning` bajo el campo de URL en login móvil, login de escritorio y edición de perfiles. No bloquea. LAN, loopback, link-local, CGNAT/Tailscale, ULA IPv6 y `.local`/`.lan`/`.home.arpa`/`.internal` no avisan. Auditoría del emparejamiento: `/pair/claim` va por HTTP pero las credenciales vuelven en sealed-box X25519 hacia una clave efímera del móvil, así que un observador pasivo no las lee; el código de emparejamiento sí viaja en claro (aceptable en LAN, queda anotado).
- **7** · los endpoints con `access-control-allow-origin: *` (`/api/capabilities`, `/health`, `/rooms`, lobby) son públicos y sin cookies; `/admin` no envía cabeceras CORS y usa cookie SameSite=Strict + CSRF. No hay nada que cerrar.
- **8** · `DiagnosticsLog` (`lib/services/diagnostics_log.dart`): buffer circular de 800 líneas enganchado a `debugPrint` desde `main` (los ~175 mensajes existentes entran sin tocarlos, y también los errores no controlados), con `redactSecrets` (parámetros Subsonic `u/p/t/s`, tokens, claves, `user:pass@`, `crotowave-sync://`, cabeceras y JSON). Ajustes → Diagnóstico: copiar, guardar en archivo y vaciar. Solo en memoria. Queda fuera: los 91 `catch (_) {}` siguen sin registrar nada (ítem 3).
- **12** · revisados los 23. Tres alimentaban interfaz con la app oculta: `ServerActivityPanel` (dos peticiones al servidor cada 5 s), el refresco de contadores de Inicio (cada 30 s, escritorio y móvil) y `PlayerPositionBuilder` (redibujo 4 veces por segundo). Ahora consultan `isAppVisible` (`lib/utils/app_visibility.dart`); la barra se re-ancla a la posición real al volver. Los de CrotoLink, Connect, sincronización, reconexión y transiciones siguen en segundo plano a propósito. No medido en dispositivo: el ahorro de batería es por diseño, no por medición.
- **2** (sesión `CrotoWave`, `7b6c820`) · 20/20 corridas completas sin fallos (antes 7 de 20). Causas: esperas de tiempo fijo en `offline_download_manager_test` (ahora por condición) y un reescaneo en segundo plano que escribía en la carpeta temporal mientras el `tearDown` la borraba (`LocalMusicService.settled()`, solo para tests). Verificado solo en Linux.
- **3** · `unawaited_futures` y `cancel_subscriptions` activos. 22 llamadas asíncronas sin esperar, todas intencionales, ahora marcadas con `unawaited(...)` (sin cambio de comportamiento); `cancel_subscriptions` no encontró nada. `close_sinks` descartado: sus 8 avisos eran falsos positivos (sockets y controladores que se cierran en otro método). Los 91 `catch (_) {}` no se tocaron: ningún lint estándar los cubre y revisarlos uno por uno es otro ítem. Suite completa: 801 tests en verde.
- **15** · `rxdart` 0.28: analyze limpio y 825 tests en verde; `lib/` no lo importa directamente, lo usan `just_audio` y `audio_service`, así que falta oírlo en un dispositivo. `web_socket_channel` 3 **revertido**: `crotolink_guest_history_test` («notificationInfo describe la sala…») falla siempre con la v3 y pasa con la v2. `joinSession` termina al llegar `join_response`, y con la v3 el `crotolink_state_snapshot` que crea la sesión se entrega un turno después, así que justo tras unirse `session` es `null`. Para subir de versión, antes hay que hacer que la unión espere al primer snapshot.
- **9** (sesión `CrotoWave`, `4796705`) · 75 tests nuevos en 5 archivos (`replay_gain_model`, `playlist_export_service`, `relay_transport`, `connect_mirror`, `player_connect_port`); suite en 852. `replay_gain.dart` ya tenía cobertura indirecta; los otros cuatro, ninguna. Comprobado por mutación. No destapó bugs. Solo Linux; el selector de archivos de Windows/macOS no se probó.
- **16** (sesión `CrotoWave`, `5fc2814`, `747a943`, `c787b96`, `f60383b`) · `pairing_panel` 1661 → 516, `crotolink_dialog` 1632 → 176, `track_context_menu` 1607 → 1090, `mobile_home_screen` 1597 → 606, solo moviendo código a `part`. Único archivo que sigue por encima de 1200: `crotolink_host_service.dart` (1279), fuera de este ítem.

## Cierre de la tanda (2026-10-09)
- Verificado por la sesión coordinadora tras el último commit: `flutter analyze` 0 issues, `flutter test` 852 en verde (3 omitidos), crotolink-server 54/54.
- Abierto: 5 (`applicationId`), 13 y 14 (`just_audio` 0.10, `mobile_scanner` 7: necesitan dispositivo real), 15 parcial (`web_socket_channel` 3, `audio_session` 0.2), 10 (login de escritorio), 11 (medir en la tele), 18, 19.
- Sin push: el CI (ítem 1) sigue sin ejecutarse por primera vez.
