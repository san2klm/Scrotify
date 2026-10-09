# Plan de mejoras — tanda 2 (2026-10-09)

Estado: `[ ]` pendiente · `[~]` en curso · `[x]` hecho (con commit) · `[!]` necesita decisión.

Base: `main` @ `d1ca483` (tanda 1 cerrada en `tasks/plan-mejoras.md`).

Reparto: coordina la sesión `scrotify-ff`; la sesión `Scrotify` implementa en
paralelo los ítems marcados (S). Mismo árbol de trabajo: commits con rutas
explícitas (`git commit -- rutas`), sin `add -A`, sin push sin confirmación.

Reglas de cada ítem (AGENTS.md §4): `flutter analyze` 0 issues, tests relevantes
en verde, un commit por ítem y una línea en `tasks/todo.md`.

## Fase 1 — Red de seguridad

### [x] 1. CI en GitHub Actions
- `.github/workflows/ci.yml`: `flutter analyze` + `flutter test` (con libmpv y ffmpeg) y `node --test` del jam-server.
- Sin verificar hasta el primer push (no se puede ejecutar en local).

### [~] 2. Eliminar tests intermitentes (S)
- Fallos aislados anotados en `offline_download_manager_test` y `local_music_service_test`.
- Hecho cuando: 20 corridas seguidas de la suite sin fallos, con causa raíz (sin reintentos ni skips).

### [ ] 3. Endurecer lints
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
- Sigue `com.example.navidrome_client`. Cambiarlo obliga a reinstalar y pierde los datos locales: decide el usuario.

### [x] 6. Acotar el tráfico en claro
- `usesCleartextTraffic="true"` global (necesario para Navidrome en LAN). Avisar en el login si la URL es `http://` hacia un host público.
- Auditar `pairing_client.dart` (`http://host:port/pair/claim`): confirmar que el contenido va cifrado.

### [x] 7. CORS del jam-server (auditado, sin cambios)
- `access-control-allow-origin: *` en varios endpoints de `server.js`: dejarlo solo donde haga falta.

## Fase 3 — Diagnóstico

### [x] 8. Log estructurado y «Exportar diagnóstico»
- 175 `debugPrint`/`print` sueltos. Buffer circular en memoria, exportable desde Ajustes, sin secretos.

## Fase 4 — Cobertura

### [~] 9. Tests de servicios sin cobertura directa (S)
- `replay_gain.dart`, `playlist_export_service.dart`, `connect/relay_transport.dart`, `connect/connect_mirror.dart`, `connect/player_connect_port.dart`.

### [ ] 10. Tests de widget de login, Inicio y reproductor

## Fase 5 — Rendimiento (medir antes de tocar)

### [ ] 11. Perfilar la APK de TV y decodificar portadas a tamaño real
### [x] 12. Revisar los `Timer.periodic` (23): que se pausen en segundo plano

## Fase 6 — Dependencias (una por commit)

### [ ] 13. `just_audio` 0.9 → 0.10 (riesgo alto: copia parcheada en `third_party/just_audio_media_kit`)
### [ ] 14. `mobile_scanner` 5 → 7
### [ ] 15. `web_socket_channel` 2 → 3, `rxdart` 0.27 → 0.28, `audio_session` 0.1 → 0.2

## Fase 7 — Limpieza

### [ ] 16. Partir los archivos que siguen por encima de 1200 líneas
- `pairing_panel.dart`, `jam_dialog.dart`, `track_context_menu.dart`, `mobile_home_screen.dart`.

### [x] 17. Ignorar `Scrotify-*.apk` en la raíz
### [!] 18. Cerrar tareas basura del Brain (`@file:Fase.md` ×2, `[CONTEXT COMPACTION…]`)
### [ ] 19. Localización (solo si se va a distribuir fuera)

## Bitácora

- **1** · workflow con dos jobs; YAML validado en local, jam-server 54/54 en local.
- **4** · aviso en `build.gradle.kts` y en `scripts/build_apks.sh`; `./gradlew help` evalúa bien.
- **17, 20** · `.gitignore` y archivos de build de Android añadidos al repo (sin secretos: `key.properties` y `local.properties` siguen ignorados).
- **6** · `isPublicCleartextUrl` (`lib/utils/cleartext_url.dart`) + `CleartextUrlWarning` bajo el campo de URL en login móvil, login de escritorio y edición de perfiles. No bloquea. LAN, loopback, link-local, CGNAT/Tailscale, ULA IPv6 y `.local`/`.lan`/`.home.arpa`/`.internal` no avisan. Auditoría del emparejamiento: `/pair/claim` va por HTTP pero las credenciales vuelven en sealed-box X25519 hacia una clave efímera del móvil, así que un observador pasivo no las lee; el código de emparejamiento sí viaja en claro (aceptable en LAN, queda anotado).
- **7** · los endpoints con `access-control-allow-origin: *` (`/api/capabilities`, `/health`, `/rooms`, lobby) son públicos y sin cookies; `/admin` no envía cabeceras CORS y usa cookie SameSite=Strict + CSRF. No hay nada que cerrar.
- **8** · `DiagnosticsLog` (`lib/services/diagnostics_log.dart`): buffer circular de 800 líneas enganchado a `debugPrint` desde `main` (los ~175 mensajes existentes entran sin tocarlos, y también los errores no controlados), con `redactSecrets` (parámetros Subsonic `u/p/t/s`, tokens, claves, `user:pass@`, `scrotify-sync://`, cabeceras y JSON). Ajustes → Diagnóstico: copiar, guardar en archivo y vaciar. Solo en memoria. Queda fuera: los 91 `catch (_) {}` siguen sin registrar nada (ítem 3).
- **12** · revisados los 23. Tres alimentaban interfaz con la app oculta: `ServerActivityPanel` (dos peticiones al servidor cada 5 s), el refresco de contadores de Inicio (cada 30 s, escritorio y móvil) y `PlayerPositionBuilder` (redibujo 4 veces por segundo). Ahora consultan `isAppVisible` (`lib/utils/app_visibility.dart`); la barra se re-ancla a la posición real al volver. Los de Jam, Connect, sincronización, reconexión y transiciones siguen en segundo plano a propósito. No medido en dispositivo: el ahorro de batería es por diseño, no por medición.
