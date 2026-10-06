# TODO — Mejoras UI/UX Scrotify

## Fase 1 — Visuales puros

- [x] **1.1** `interactive_artist_text.dart` — Hover sobre nombre de artista: cursor mano + color accent + subrayado sólido; cada artista separado resaltado independientemente
- [x] **1.2** `persistent_player_bar.dart` — Eliminar `Icon(Icons.drag_handle_rounded)` izquierdo en desktop y mobile bar
- [x] **1.3** `playlist_detail_screen.dart` — Mover drag handle al centro de la fila; añadir ⋮ en trailing que abre `TrackContextMenu`

## Fase 2 — Lógica de ordenación y duplicados

- [x] **2.1** `home_screen.dart` + `navidrome_service.dart` — Playlists fijadas aparecen primero en la biblioteca, debajo de "Me gusta"; reordenamiento reactivo sin reinicios
- [x] **2.2** `track_context_menu.dart` — Detectar si canción ya está en playlist antes de añadir; mostrar "Ya está en Nombre" y no duplicar

## Fase 3 — Seguir artistas

- [x] **3.1** `navidrome_service.dart` — Añadir `_followedArtistIds` y `_excludedArtistIds` con persistencia en JSON local; getters y toggles con `notifyListeners()`
- [x] **3.2** `artist_screen.dart` — Botón Seguir/Siguiendo funcional; menú Dejar de seguir / No reproducir / Compartir con funcionalidad real
- [x] **3.3** `home_screen.dart` — Mostrar artistas seguidos en la biblioteca entre "Me gusta" y playlists

## Fase 4 — Compartir con comunidad (links)

- [x] **4.1** `track_context_menu.dart` + `server_activity_panel.dart` — "Compartir canción": envía `[TRACK:id:title:artist]` al chat; el chat renderiza tile navegable con portada y botón reproducir
- [x] **4.2** `artist_screen.dart` + `server_activity_panel.dart` — "Compartir artista": envía `[ARTIST:id:name]` al chat; el chat renderiza tile con foto y botón "Ver artista"

## Fase 5 — Refresco instantáneo

- [x] **5.1** `playlist_detail_screen.dart` + `track_context_menu.dart` — Al añadir/eliminar canciones de playlist, refresco inmediato sin salir y volver; `bumpPlaylists()` propaga cambios al Consumer

## Fase 6 — Correcciones pendientes (Jam, Artistas y Pantalla de Inicio)

- [x] **6.1** `Jam` — Revisar y arreglar detalles pendientes de la funcionalidad Jam (sincronización, UI o conexión). Verificado WSS seguro con TLS pinning sin downgrade, PRNG criptográfico en PINs, reconexión exponencial y tests verdes en jam-server.
- [x] **6.2** `Artistas (Seguir)` — Arreglar defectos visuales en la interfaz relacionados con la funcionalidad de seguir a los artistas: botones responsivos con LayoutBuilder en ArtistScreen sin overflow en pantallas estrechas, caché en memoria de Artist en NavidromeService para evitar flashes de IDs crudos y llamadas duplicadas, y soporte de artistas seguidos en la biblioteca de la app móvil.
- [x] **6.3** `Pantalla de Inicio` — Añadir cosas que faltan y pulir defectos visuales en la home (HomeScreen): manejo elegante de estados sin conexión en novedades/recientes tanto en escritorio como en móvil, y ordenamiento de playlists fijadas en la biblioteca móvil.

## Fase 7 — Mezcla Inteligente + Eliminación de Silencios (Ítems 12 y 17)

- [x] **7.1** `player_controller.dart` — Algoritmo de Mezcla Inteligente (Smart Shuffle): espaciado de artistas mediante ventana greedy M=2, evitando repetición consecutiva de pistas del mismo artista en modo aleatorio cuando existen alternativas en la cola; fallback seguro si domina un único artista.
- [x] **7.2** `player_controller.dart` + `waveform_service.dart` — Eliminación de Silencios (Skip Silence): cálculo de límites `usefulStart` y `usefulEnd` usando análisis de amplitud RMS (< -40 dBFS / 0.01) sobre forma de onda real; seek al inicio útil y transición suave sin cortar reverbs.
- [x] **7.3** `settings_controller.dart` + `settings_screen.dart` — Toggles configurables y persistentes para `Mezcla inteligente` y `Eliminar silencios` en Ajustes de reproducción.
- [x] **7.4** `smart_shuffle_and_silence_test.dart` — Suite completa de 9 tests unitarios para mezclas inteligentes y detección de silencios.

## Fase 8 — Rating 1-5 Estrellas (Ítem 13)

- [x] **8.1** `navidrome_service.dart` — Extensión de modelo canónico `Track` con `userRating` (0..5) y `copyWith`; integración con API Subsonic `setRating.view`, persistencia local JSON (`track_ratings.json`) y método `sortByRating(tracks)`.
- [x] **8.2** `rating_stars.dart` + `track_context_menu.dart` — Componente interactivo de 5 estrellas en el menú contextual de cada canción y Now Playing bar (`player_screen.dart`), permitiendo calificar de 1 a 5 o desmarcar al volver a tocar la estrella activa.
- [x] **8.3** `track_rating_test.dart` — 5 tests unitarios y de widgets verificando serialización, API Subsonic, ordenamiento descendente y reactividad visual.

## Fase 9 — Recientemente Agregados + Búsqueda por Género (Ítems 14 y 16)

- [x] **9.1** `genre_selector.dart` — Selector horizontal responsivo de géneros con chips interactivos, botón expandir/colapsar "Mostrar todos / Ocultar" y persistencia del último género seleccionado.
- [x] **9.2** `home_screen.dart` + `mobile_home_screen.dart` — Carruseles de pistas agregadas recientemente (`getRecentlyAddedTracks`) y filtrado instantáneo por género sobre listas locales y remotas.
- [x] **9.3** `genre_selector_test.dart` — 5 tests de widgets verificando renderizado, expansión/colapso y selección de géneros.

## Fase 10 — Ecualizador de 10 Bandas + Estadísticas de Escucha (Ítems 15 y 18)

- [x] **10.1** `equalizer_service.dart` + `equalizer_screen.dart` — Ecualizador estándar de 10 bandas (31 Hz a 16 kHz, -12 dB a +12 dB) con presets (Flat, Bass Boost, Vocal, Treble Boost), bypass, reset, persistencia local y aviso honesto sobre capacidades del backend de audio actual.
- [x] **10.2** `listening_stats_service.dart` + `stats_screen.dart` — Sistema de estadísticas locales "Spotify Wrapped" con tiempo total de reproducción, desglose temporal (diario, semanal, mensual), top artistas, top pistas y top géneros, filtrando reproducciones calificadas (>= 30s o >= 50% de duración).
- [x] **10.3** `equalizer_service_test.dart` + `listening_stats_service_test.dart` — 9 tests unitarios validando rangos de ganancia, persistencia, presets y agregación estadística.

## Jam 2.0 — Mejoras de Cola y Detección de Duplicados

- [x] **Jam.1** `jam_controller.dart` + `track_context_menu.dart` — Detección reactiva de canciones ya presentes en la cola de Jam (`isTrackInJamQueue`), advirtiendo al usuario en el menú contextual.
- [x] **Jam.2** `jam_queue_panel.dart` — Insignia visual `Repetida` en las filas de la cola tanto de Jam como de la reproducción local para pistas duplicadas.

## Fase 11 — Perfiles de Servidor y Cambio de Usuario en Caliente

- [x] **11.1** `navidrome_service.dart` — Aislamiento multi-usuario con `userScope` y `currentSessionKey` para evitar colisión de datos locales entre usuarios del mismo servidor. Limpieza de colecciones en memoria al reconectar (`_starredIds`, `_pinnedPlaylistIds`, `_followedArtistIds`, `_trackRatings`, `_cachedGenres`).
- [x] **11.2** `player_controller.dart` — Reset de reproducción y cola activa al cambiar de sesión/usuario. Historial de reproducción reciente persistido y aislado por sesión (`recently_played_$encoded.json`) con fallback compatible.
- [x] **11.3** `home_screen.dart` + `mobile_home_screen.dart` + `liked_songs_screen.dart` — Recarga reactiva en caliente de todos los `Future` (playlists, canciones, favoritos, géneros, novedades) al detectar cambio en `currentSessionKey` sin requerir cerrar ni reiniciar la aplicación.
- [x] **11.4** `test/user_profile_switching_test.dart` — Suite completa de 6 tests unitarios y de widgets verificando el aislamiento de credenciales, scopes, limpieza de colas y recarga visual inmediata al cambiar de usuario.

## Jam 3.0 — Auditoría Integral, Sincronización Remota y Resiliencia

- [x] **Jam.3** `jam_controller.dart` — Corrección de indexación de cola compartida (`_playerOrderIndexForQueueItem` y `_reorderQueueAsHost`): soporte para pistas no idénticas por referencia de memoria mediante comparación por `track.id`, y cálculo seguro de offset cuando el reproductor no tiene pista activa (`currentOrderPos < 0`).
- [x] **Jam.4** `jam_controller.dart` — Corrección de permisos de invitados remotos: validación estricta con operador lógico `&&` (`allowGuestControls && canControlPlayback` y `allowGuestQueueManage && canManageQueue`), impidiendo que invitados omitan las restricciones fijadas por el anfitrión.
- [x] **Jam.5** `jam-server/src/server.js` + `remote_jam_service.dart` — Normalización de duración (numérica y string) y soporte de actualizaciones de estado parciales (merge con `room.state`) en el servidor central. Propagación de errores reales (`lastError`) en lugar de fallos genéricos.
- [x] **Jam.6** `jam_controller.dart` — Sincronización completa de la cola de reproducción para invitados remotos (`JamQueueItem.toJson` / `fromJson` con trazabilidad de quién agregó la pista y portada) y actualización en caliente de permisos de participantes remotos.
- [x] **Jam.7** `jam_queue_panel.dart` — Corrección del contrato de arrastre en `ReorderableListView.builder` con ajuste de `newIndex` (`newIndex > oldIndex ? newIndex - 1 : newIndex`) para reordenar pistas hacia abajo y al final de la cola sin errores.
- [x] **Jam.8** `jam_dialog.dart` — Exposición de mensajes de error descriptivos (`lastJoinError`) al usuario al unirse por PIN, radar o QR.
- [x] **Jam.9** `test/jam_test.dart` + `jam-server/test/server.test.js` — Tests adicionales para deserialización remota de cola, permisos estrictos y actualizaciones de estado.

## Fase 12 — Autenticación Biométrica Móvil y Temporizador de Apagado Avanzado

- [x] **12.1** `android/app/src/main/kotlin/.../MainActivity.kt` + `AndroidManifest.xml` — Migración de `MainActivity` a `AudioServiceFragmentActivity` (requerido por `local_auth` para evitar excepciones `no_fragment_activity` en Android al abrir el prompt de huella), y permiso `android.permission.USE_BIOMETRIC`.
- [x] **12.2** `lib/services/biometric_auth_service.dart` — Servicio tipado y resiliente para biometría móvil compatible con `LocalAuthentication` 3.0, mapeando adecuadamente `LocalAuthException` (`temporaryLockout`, `biometricLockout`, `userCanceled`, `noBiometricsEnrolled`) y `PlatformException`.
- [x] **12.3** `lib/screens/mobile_login_screen.dart` — Integración con post-frame callback para auto-login seguro, botón táctil "Ingresar con huella digital" con icono de huella dactilar para reintento manual sin requerir reingresar credenciales, y feedback informativo de bloqueo temporal.
- [x] **12.4** `lib/services/player_controller.dart` + `lib/widgets/track_context_menu.dart` — Temporizador de apagado completo (Fase 5 de especificación): nueva opción "Fin de la canción" (`isSleepTimerEndOfTrack`, pausando automáticamente al finalizar la canción actual sin avanzar ni hacer crossfade), presets estándar y diálogo de minutos personalizados con fade out suave al vencer.
- [x] **12.5** `test/biometric_auth_test.dart` + `test/mobile_login_screen_test.dart` + `test/sleep_timer_test.dart` — Suites de pruebas unitarias y de widgets con cobertura total para biometría, interfaz móvil y temporizador de apagado.

## Jam 4.0 — Expulsión de Participantes (Kick) y Preferencia de Modo Sincronizado

- [x] **Jam.10** `jam_controller.dart` + `remote_jam_service.dart` + `jam_host_service.dart` — Corrección de expulsión de participantes (kick): `kickParticipant()` ahora remueve al usuario de `_remoteParticipants`, registra su nombre en `_kickedRemoteNames` para prevenir que `_syncHostState()` lo reinstaure, envía acción `'kick_guest'` por WebSocket, y en el servicio local LAN rechaza reconexiones de nombres expulsados.
- [x] **Jam.11** `jam-server/src/server.js` + `test/server.test.js` — Implementación en el servidor WebSocket de la acción `'kick_guest'`, notificando al invitado expulsado con evento `'kicked'` y cerrando su socket inmediatamente; test unitario `host can kick a guest from the room` pasando en Node.js.
- [x] **Jam.12** `jam_dialog.dart` + `jam_host_service.dart` + `jam_controller.dart` — Inversión del orden de modos para priorizar "Escucha sincronizada" / "Sincronizado" como la primera opción en dropdowns y modo por defecto en lugar de "Altavoz".
- [x] **Jam.13** `server_profiles_controller.dart` + `login_screen.dart` — Detección reactiva de perfiles persistidos (`ensureLoaded()`) para auto-login fluido en la app móvil y de escritorio sin requerir reingreso manual de credenciales en cada arranque.
- [x] **Jam.14** Verificación E2E en emulador Android (`mobile-mcp`) — Validación en vivo de inicio de sesión automático, reproducción de audio, apertura del diálogo Jam, selección por defecto de "Escucha sincronizada", unión de invitado y expulsión en tiempo real con remoción inmediata de la lista de participantes.



## Auditoría 2026-10-04 — Correcciones de seguridad y robustez

- [x] **Aud.1** `jam_models.dart` + `jam_controller.dart` + `jam_host_service.dart` + `jam-server/src/server.js` — Las URLs de carátula ya no viajan con `u/s/t` (token Subsonic reutilizable): `sanitizeArtUrl` en cliente y saneado de defensa en el servidor (estado y cola).
- [x] **Aud.2** `jam-server/src/server.js` — `/rooms` solo lista salas con `isPublic: true`; `host` público configurable (`PUBLIC_HOST`); allowlist y validación de `guest_action`; nombres duplicados rechazados; límite de intentos fallidos de PIN; ping/pong para limpiar sockets muertos; `check_room` sin cola; log de cierre corregido. 9 tests Node.
- [x] **Aud.3** `pairing_server.dart` — `/pair/status` ya no devuelve el código; 5 códigos erróneos invalidan la sesión (HTTP y relay); body de claim limitado a 4 KB; el código no se escribe en logs.
- [x] **Aud.4** `secure_storage.dart` — El archivo de respaldo se crea con `chmod 600` antes de escribir secretos.
- [x] **Aud.5** `navidrome_service.dart` — Salt/token de carátula estables por sesión (caché de imágenes efectiva); se eliminan logs de cuerpos de respuesta y del usuario.
- [x] **Aud.6** `player_controller.dart` — El watchdog de 200 ms se detiene en pausa/idle y se rearma al reproducir.
- [x] **Aud.7** `listening_stats_service.dart` — Guardado atómico y fusionado de escrituras concurrentes.
- [x] **Aud.8** `main.dart` + varios — Manejo global de errores; `catch (_) {}` clave ahora registran; `print` → `debugPrint`.
- [x] **Aud.9** `.gitignore` + `build.gradle.kts` — `pubspec.lock` versionable; firma de release vía `android/key.properties` (fallback debug); secretos de firma ignorados.
- Verificación: `flutter analyze` 0 issues, `flutter test` 267 OK, `node --test` 9 OK.

## Importar playlists — fix del cuelgue y mejoras (2026-10-04)

- [x] **Imp.1** `settings_screen.dart` — Causa del "se queda cargando": `_ImportingDialog` nunca esperaba el `Future` ni se cerraba. Reemplazado por `_ImportProgressDialog` (ejecuta la importación, muestra % real + contador encontradas/no encontradas, botón Cancelar y se cierra solo). Los errores ya no se pierden (`StateError` no lo captaba `on Exception`).
- [x] **Imp.2** `playlist_importer.dart` — Cada canción se busca con try/catch + timeout (15 s): si no aparece, falla o se cuelga, se salta y se sigue. Si ninguna coincide no se crea la playlist (antes lanzaba). Si TODAS fallan por red, error claro.
- [x] **Imp.3** Destino: playlist nueva o **existente** (sin duplicar canciones que ya tiene).
- [x] **Imp.4** Resultado final: cuántas importadas / cuántas no encontradas + CSV (`Titulo,Artista,Album`, con BOM, reimportable). En móvil (sin "Guardar como") se guarda en la carpeta de la app y se copia al portapapeles.
- [x] **Imp.5** Matching: lectura UTF-8 real (antes `String.fromCharCodes` rompía acentos/ñ), limpia "(feat…)/Remastered", varios artistas, cabeceras de Exportify (`Artist Name(s)`).
- Verificación: `flutter analyze` 0 issues; `test/playlist_importer_test.dart` 10 tests.

## UI adaptativa, widgets y espectro (2026-10-04)

- [x] **UI.1** `waveform_progress_bar.dart` — Espectro optimizado: barras rasterizadas una vez en `Picture` cacheadas y recortadas por progreso (2 draw calls/frame), progreso interpolado con `Ticker` (sin reconstruir el árbol), hover/arrastre/revelado/pulso solo repintan el `CustomPaint`. Animación de revelado y pulso del cabezal (respeta "reducir animaciones"), tiempo en hover (PC), arrastre solo horizontal (móvil), teclado ←/→, semántica de slider, alto adaptable y barras más gruesas en anchos grandes. Integrado en `player_screen.dart` y en la barra persistente de escritorio.
- [x] **UI.2** `utils/responsive.dart` + `home_shell.dart` — Breakpoints, histéresis al cruzar móvil↔escritorio (evita parpadeo y pérdida de estado al redimensionar).
- [x] **UI.3** `home_screen.dart` — Biblioteca auto-colapsable (<900 px, se abre como cajón), ancho proporcional, contenido centrado y limitado en monitores enormes.
- [x] **UI.4** `persistent_player_bar.dart` — Barra de escritorio adaptativa por tramos (antes desbordaba entre 700 y ~1000 px): oculta volumen/Jam/pantalla completa progresivamente, bloque de título acotado, progreso flexible.
- [x] **UI.5** `mobile_home_screen.dart` — Etiqueta de la barra inferior sin salto de línea (overflow a 320 px).
- [x] **W.1** `now_playing_panel.dart` — Panel lateral "Escuchando ahora" (≥1240 px): carátula, controles, cola y letra.
- [x] **W.2** `quick_actions_row.dart` — Acciones rápidas en el inicio del teléfono (Mezclar, Me gusta, Jam, Estadísticas).
- [x] **W.3** `mini_player_controller.dart` + `mini_player_view.dart` + `desktop_window_frame.dart` — Modo mini reproductor en PC (ventana pequeña siempre visible, con espectro); la UI normal conserva su estado.
- [x] **W.4** Android App Widget (`ScrotifyWidgetProvider.kt`, layout/xml/drawables, `home_widget_service.dart`) — carátula, título, artista y prev/play/siguiente en la pantalla de inicio. Verificado en emulador: aparece en el selector y se dibuja al añadirlo.
- Verificación: `flutter analyze` 0 issues; tests de espectro, responsive (anchos 320–2560) y widget.

## Ventana de escritorio: redimensionar, maximizar y pantalla completa (2026-10-04)

- [x] **Win.1** `desktop_window_frame.dart` — Bordes/esquinas arrastrables (`DragToResizeArea`) para redimensionar la ventana sin decoración nativa; `setResizable(true)` en `main.dart`.
- [x] **Win.2** Botón maximizar/restaurar con flecha arriba/abajo; pantalla completa real (botón, `F11`, `Esc` para salir); iconos sincronizados con el estado real vía `WindowListener`.
- [x] **Win.3** `persistent_player_bar.dart` — el botón de pantalla completa abre el reproductor grande y pone la ventana en pantalla completa real.
- [x] **Win.4** `services/window_controls.dart` — helpers compartidos.
- Verificación: analyze 0 issues, 309 tests, `flutter build linux --debug` OK. No se probó el arrastre en una ventana real (sesión Wayland sin herramienta para simular ratón).
- [x] **Win.5** Aclaración de diseño: la flecha ↑ de la barra inferior abre la **ventana completa** (reproductor con portada y letra dentro de la ventana, sin tocar el escritorio); dentro del reproductor, el botón de **pantalla completa** (o F11) ocupa toda la pantalla y Esc sale; al cerrar el reproductor se restaura si fue él quien la activó. La barra de título vuelve al icono clásico de maximizar/restaurar.

## Pendiente — Jam: el invitado no encuentra al host (2026-10-04, prioridad alta)

- [ ] **Jam.P1** Confirmar la causa real: escenario (lista/PIN/QR, LAN o remoto) y mensaje exacto en el teléfono.
- [ ] **Jam.P2** Revisar descubrimiento UDP 47623 con PC en Wi-Fi + cable (misma subred), firewall y aislamiento del AP; probar por QR.
- [x] `jam-server` revertido a `ae8dde3` (pedido del usuario); el cliente conserva `sanitizeArtUrl`.
- Referencia: versión anterior `ae8dde3` (descubrimiento LAN idéntico; solo difiere el servidor remoto).

- Nota: el commit `fc94ddc` (ya en el remoto) aún contiene el servidor Jam nuevo; el revert está sin commit.

- [x] **Jam.P3** (2026-10-04) Causa confirmada contra `jam.templo.cloud`: el servidor cierra el socket del anfitrión (1009) cuando un mensaje supera `MAX_MESSAGE_BYTES` (16 KB), o sea con colas de más de ~35 canciones; la sala remota desaparece y el invitado no la encuentra. Arreglo en el cliente: `RemoteJamService.fitStateToMessageLimit` recorta la cola al prefijo que cabe, y el anfitrión vuelve a registrar la sala con retroceso exponencial si pierde la conexión. Verificación: analyze 0 issues, 310 tests. Falta probar en dispositivos reales (hay que reinstalar la app en el anfitrión). Con colas largas el invitado remoto ve sólo las primeras ~34 canciones siguientes.

## Jam Roadmap — Fase 1 (2026-10-06): ajuste "Servidor Jam" + servidor administrable

- [x] **R1.1** Servidor: ajustes en SQLite (`node:sqlite`, sin dependencia nativa; desvío respecto a `better-sqlite3` del roadmap), panel `/admin` (login scrypt, cookie HttpOnly/SameSite=Strict, CSRF, rate limit de login por IP, pestañas Estado/Límites/Seguridad/Funciones/Persistentes*/Logs), `GET /api/capabilities`, límites en caliente (`maxRooms`, `maxQueueItems`, `publicListingEnabled`…), `/rooms` ya no hardcodea `jam.templo.cloud`. Dockerfile con volumen `/data` + HEALTHCHECK. 13 tests node verdes. (*pestaña de salas persistentes: placeholder hasta la Fase 7.)
- [x] **R1.2** Cliente: `jamServerUrl` en `SettingsController` (validación `JamServerEndpoint`: `wss://`, `ws://` solo host privado con aviso), `RemoteJamService`/radar/`JamController` usan el ajuste, UI en Ajustes (guardar, probar `/health`, restaurar). `flutter analyze` 0 issues; tests jam verdes.
- [ ] **R1.3** Pendiente: el cliente aún no lee `/api/capabilities` (se consumirá en las fases que habiliten funciones); no hay despliegue en el servidor real (faltan datos de la sección 1 del roadmap).

## Jam Roadmap — Fase 2 (2026-10-06): modos de cola
- [x] Modelos + `jam_queue_logic.dart` (11 tests), controlador host (aprobación, votos, fijado, modo en vivo), protocolo LAN/remoto, servidor relay (campos nuevos), UI (selector al crear, menú en vivo, ▲/▼, pin, bandeja de solicitudes). analyze 0, tests verdes.

## Jam Roadmap — Fase 3 (2026-10-06): historial + guardar como playlist
- [x] `jam_history.dart` (umbral 30 s / 50 %, resumen, filtro por participante; 5 tests), registro en el host, diálogo con "Guardar como playlist" (`createPlaylist` + `updatePlaylist`). Historial en RAM del host; se conserva tras finalizar hasta la siguiente Jam.
- [ ] No hecho: `history_snapshot` para invitados y "guardar mis aportaciones" del invitado (el historial solo vive en el host).

## Jam Roadmap — Fase 4 (2026-10-06): seguridad
- [x] Servidor: rate limit por IP (ventana + bloqueo progresivo 1 min→1 h) en `join_room`/`check_room`, IPs bloqueadas por admin (SQLite + panel), respuesta genérica PIN/contraseña, contraseña de sala (scrypt+sal en RAM; `check_room` no revela estado sin ella), baneo por nombre tras kick. 19 tests node.
- [x] Cliente: contraseña de sala (crear/unirse, LAN y nube), `JamFailureBlocker` en el host LAN, reconexión rechazada para IDs expulsados.
- Desvío: el relay recibe la contraseña en claro por TLS y guarda solo su hash (el roadmap decía que el host enviaba el hash; así no hay que compartir sal con los invitados).
- Límite documentado: el ban por nombre/ID es evadible; el ban por IP es solo del admin.

## Jam Roadmap — Fase 5 (2026-10-06): sincronización avanzada
- [x] 5.1 `jam_clock.dart` (`ClockOffsetEstimator`: mediana de las muestras de menor RTT; 9 tests). `time_ping`/`time_pong` en relay y host LAN; 5 muestras al unirse y re-medición cada 60 s. El host de nube sella `refTs` (hora del relay); el invitado convierte con su offset. Sin pong → cálculo anterior (clamp 0–5 s).
- [x] 5.2 Corrección suave: ≤50 ms nada, 50–450 ms `setPlaybackSpeed(1±0.02)` con histéresis, >450 ms seek (`kJamDrift*`). `PlayerController.setPlaybackSpeed` (A/B).
- [x] 5.3 `next_track_hint` (LAN op / remoto `nextHint`) ~10 s antes del final: el invitado precarga la pista siguiente tras la actual (el motor A/B la prepara). `startAtServerMs` se envía pero el arranque lo marca el fin natural de la pista (+ corrección de deriva), no un temporizador.
- [ ] Pendiente de prueba manual: 2 dispositivos, deriva media <100 ms en 10 min.

## Jam Roadmap — Fase 6 (2026-10-06): matching de pistas por metadatos
- [x] `Track` canónico ampliado (`mbid`, `isrc`, `trackNumber`; opcionales), `NavidromeService.getSong`, protocolo (`trackToJamJson`/`trackFromJamJson`, +`durationSec`), whitelist del relay.
- [x] `jam_track_matcher.dart` (normalización, MBID > ISRC > título+artista+duración ±3 s; live/remix no equivalen al estudio; sin falsos positivos por homónimos; 10 tests) y `JamTrackResolver` (caché incl. negativos, fast path por ID verificado, errores de red no cacheados, lotes que ceden el hilo; 7 tests).
- [x] Invitado en modo sincronizado reproduce la pista local equivalente; si no existe, la omite con aviso y la cola la muestra atenuada ("No disponible en tu biblioteca"). Error de red del resolver → comportamiento anterior.
- Nota: la precarga `next_track_hint` también resuelve la pista local antes de encolarla.
