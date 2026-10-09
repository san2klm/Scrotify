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

## Jam Roadmap — Fase 7 (2026-10-06): continuidad
- [x] 7.1 Relay: `hostToken` (128 bits, solo hash en memoria), `transfer_host`/`host_changed`, `resume_host`, failover automático al invitado más antiguo tras `hostFailoverMs` (opt-in del host con `failover`, configurable en `/admin`), `guestId` en `guest_joined`. Cliente: `RemoteJamService` unifica eventos (el rol cambia sin reabrir el socket), `JamController` asume/cede anfitrión (`_becomeRemoteHost`/`_demoteToRemoteGuest`), reanuda con `resume_host` antes de recrear. UI: "Transferir anfitrión", switch de failover.
- [x] 7.2 Salas persistentes: tabla SQLite (PIN reservado, `ownerToken` solo como hash scrypt, expiración por inactividad o nunca), solo con `persistentRoomsEnabled`; se persiste únicamente la configuración (permisos, modo de cola), nunca qué suena. Panel `/admin` (crear/borrar, token mostrado una sola vez). Cliente: PIN fijo + token en "Sala persistente (avanzado)".
- [x] 7.3 `GET /j/:code` (si `webLinkEnabled`), `/.well-known/assetlinks.json` y `apple-app-site-association` desde ajustes del panel. Cliente: `JamInviteLink` (`scrotify://join?code=…&server=…` y `https://host/j/PIN`), `app_links`, diálogo de unión, "Copiar enlace de invitación", pegar enlace en el campo PIN. AndroidManifest: filtro `scrotify://join` (el filtro https está comentado: pon tu dominio).
- [ ] No hecho: "migrar a la nube" desde LAN (`migrate_to_remote`); en LAN el host sigue siendo el servidor embebido (limitación documentada). iOS Universal Links/desktop no configurados.
- Probar a mano: matar la app del host con failover activado; abrir `https://<relay>/j/PIN` en el móvil.

## Jam Roadmap — Fase 8 (2026-10-06): extras sociales
- [x] Reacciones efímeras (whitelist de 8 emoji, 5/5 s por conexión) y chat ligero (≤280 car., sin historial, 5/10 s). Relay: flags `reactionsEnabled` (por defecto sí) y `chatEnabled` (por defecto NO) en `/api/capabilities` y panel; el host puede desactivar el chat de su sala (`set_chat`). LAN: ops `reaction`/`chat_message`. UI: barra de reacciones + chat en la vista de Jam activa. 3 tests node + 3 dart.
- [ ] No hecho (opcionales del roadmap): notificación persistente de Jam en Android, cast de letras a otra pantalla, proxy de stream opt-in (rompe el principio de no retransmitir audio; queda sin implementar a propósito).
- Limitación: los mensajes sociales no se reenvían entre invitados LAN y de nube de la misma sala (cada transporte ve los suyos + el host).

## Backlog de la app (sección 10 del roadmap): NO abordado en esta tanda.


## Instalación Android desde main (2026-10-06)

- [x] Regenerar la base Android omitida por Git y compilar APK release del commit `35ade76`.
- [x] Instalar por ADB (`install -r`) en Motorola edge 50 fusion: `Success`; versión `1.0.0+2002`.
- [x] Verificar arranque (`Status: ok`), proceso activo y registro sin errores graves. Análisis limpio y 497 pruebas aprobadas en esta sesión, sin cambios posteriores de código.

## Música local (2026-10-06)

- [x] Sustituir «Sesión» en Ajustes por carpeta configurable, cambiar carpeta, reescanear y contadores del servidor/locales.
- [x] Añadir descargas y estado visible a playlists, likes y canciones en biblioteca, álbumes, artistas y reproductor.
- [x] Guardar en raíz, `likes` y `playlist(Nombre)`; persistir identidad y huellas para saltar duplicados entre carpetas y tras reiniciar.
- [x] Reconocer archivos movidos/copias, permitir recuperar canciones borradas y conservar archivos ajenos; comprobar rutas antes de escribir.
- [x] Reproducción desde archivo local cuando está disponible; inicializar la biblioteca al arrancar.
- [x] Validación: 512 pruebas aprobadas y análisis sin problemas; 10 pruebas de biblioteca y 5 del total del servidor.
- [x] Compilación Linux release terminada correctamente; ejecutable actualizado en la ruta del acceso del escritorio.
- [ ] Verificar selección de carpeta y descargas en un dispositivo Android real; su ubicación predeterminada usa almacenamiento de la aplicación.

## Corrección de biblioteca sin internet (2026-10-06)

- [x] Persistir metadatos, orden y pertenencia de playlists/likes por cuenta; no guardar portadas autenticadas ni credenciales en el índice.
- [x] Recuperar canciones y colecciones desde disco al fallar la red, incluidas carpetas de descargas anteriores.
- [x] Restaurar la cuenta activa en modo local al arrancar sin internet con audio disponible; conservar el login para errores de autenticación y cierres de sesión.
- [x] Añadir «Descargadas» en Inicio y una pantalla para abrir y reproducir los archivos locales; ofrecer Reconectar.
- [x] Evitar mostrar el formulario de login durante la transición a Inicio tras restaurar la sesión.
- [x] Verificar pérdida de red, reinicio, orden, canciones borradas, separación de cuentas, colecciones vacías y recuperación de la conexión: 524 pruebas aprobadas y análisis limpio.
- [x] Compilación Linux release de la corrección terminada; el acceso del escritorio apunta al ejecutable actualizado.

## Ajuste de Inicio (2026-10-06)

- [x] Retirar la tarjeta «Descargadas» por preferencia del usuario; conservar el aviso de conexión y las canciones, likes y playlists sin internet.
- [x] Validar el ajuste: análisis limpio y 54 pruebas de biblioteca sin internet, Inicio y diseño adaptativo aprobadas.

## Carpeta predeterminada Android (2026-10-06)

- [x] Usar `/storage/emulated/0/Music` sin subcarpeta Scrotify; conservar descargas anteriores y rutas personalizadas.
- [x] Pedir acceso al almacenamiento compartido al descargar o reescanear; análisis limpio, pruebas aprobadas y APK release compilado.

## Portadas sin conexión (2026-10-06)

- [x] Persistir portadas y metadatos completos de las descargas; completar las anteriores al consultar la biblioteca con conexión.
- [x] Usar imágenes locales en canciones, playlists y reproductor, sin búsquedas de red en modo local.
- [x] Verificar reinicio, aislamiento, imágenes inválidas, deduplicación y continuidad de la descarga de audio; compilaciones Linux y Android release terminadas.

- [x] Verificación: 527 pruebas completas aprobadas; tras el último ajuste de descarga en paralelo, 68 pruebas relevantes aprobadas y análisis limpio.

## Zona fija de letras en el reproductor (2026-10-06)

- [x] Fijar el ancho del panel y el borde izquierdo durante los cambios de frase y la animación.
- [x] Reservar espacios estables para la línea anterior, actual y siguiente, adaptados a la escala de texto.
- [x] Validación: análisis sin problemas y 5 pruebas relevantes aprobadas.

## Entrega en GitHub (2026-10-06)

- [x] Preparar los cambios del proyecto para la rama `PC123` de `PC123PC123/Scrotify`; análisis limpio y 527 pruebas aprobadas en el estado actual.

## Ecualizador de tres niveles y modos Hi-Fi (2026-10-07)

Origen: carpeta `Eculiza/` (paquete `scrotify_eq` + `EQUALIZER.md`). Estado previo: el EQ de 10 bandas solo guardaba ajustes; no estaba conectado al reproductor.

- [x] **11.1** Incorporar modelos, matemática biquad, presets, import/export AutoEQ, backends, `EqualizerService` v2, curva y pantalla; retirar el EQ antiguo y sus pruebas; documentación en `docs/equalizer.md`.
- [x] **11.2** Android (conectado y compilado; falta confirmar el sonido en el teléfono): `AndroidEqualizer` en el `AudioPipeline` de los reproductores A y B del crossfade; verificar en el teléfono.
- [x] **11.3** Escritorio (verificado con libmpv real en `test/eq_mpv_integration_test.dart`): copia parcheada de `just_audio_media_kit` (acceso al `Player` de mpv) para aplicar el filtro `af`.
- [x] **11.4** Hi-Fi: `HifiPlanner`, plugin nativo Android (bit-perfect USB), ajuste de modo en Ajustes y `PlayerController.applyHifi`. Modo Estándar = comportamiento actual.
- [x] **11.5** Validación: `flutter analyze` limpio y 571 pruebas aprobadas. Pendiente: confirmar a oído en un teléfono Android.

## Datos ocultos y sincronización entre dispositivos (2026-10-07)

- [x] **12.1** Datos de escritorio en la carpeta oculta de soporte de la app (migración desde `~/Documentos/Scrotify`); la carpeta de temas por defecto muestra la real (carpeta de importados). Las descargas finales ya iban a la carpeta de música del usuario; solo los temporales quedan privados.
- [x] **12.2** `jam-server`: `/api/sync/v1` (bóvedas de blobs cifrados, last-write-wins, límites en `/admin`, desactivado por defecto). 43 pruebas del servidor.
- [x] **12.3** Cliente: `SyncCrypto` (HKDF + AES-GCM), `SyncService` (ciclo cada 5 min, push/pull por documento) y sección en Ajustes → Servidor Jam. Sincroniza temas importados, ajustes (sin `jamServerUrl`), seguidos/excluidos, playlists fijadas, orden de favoritos, valoraciones y ecualizador.
- [x] **12.4** `jam-server` redesplegado en 192.168.1.21 (backup previo de `data/` en `/root`) y `syncEnabled` activado (2026-10-07). Falta probar con dos dispositivos reales.
- [ ] **12.5** Pendiente/limitaciones: no se propagan borrados; solo `settings.json` y los temas se recargan al instante, el resto se aplica al reiniciar; vincular escaneando QR (hoy se escribe la clave).

## Scrotify Connect: controlar tus dispositivos (2026-10-07)

Como Spotify Connect: ver los dispositivos del usuario por LAN y por el servidor Jam, pasarles la reproducción y controlarlos a distancia. El "grupo" es la clave de sincronización (sección 12): solo se ven dispositivos con la misma clave y todo viaja cifrado de extremo a extremo.

- [x] **13.1** `jam-server`: `connect_join` / `connect_send` (presencia y relé de blobs cifrados, 16 dispositivos por grupo). 48 pruebas.
- [x] **13.2** Cliente: `ConnectService` (transferir, traer de vuelta, comandos, estado remoto, anti-repetición), `RelayTransport`, `LanTransport` (baliza UDP 47624 + WebSocket directo, saludo cifrado), `PlayerConnectPort`.
- [x] **13.3** UI: `ConnectPanel` (selector de dispositivos) y botón Connect en la barra en lugar del botón de la cola (escritorio y móvil); la barra muestra y controla el dispositivo remoto (play/pausa, siguiente, anterior, seek, volumen).
- [x] **13.4** Validación: relé probado contra el servidor Node real; `flutter analyze` limpio y 600 pruebas aprobadas.
- [x] **13.6** Sincronización completa: `PlayerController` en modo espejo (`RemotePlayback`/`ConnectMirror`). Mientras se controla otro dispositivo, la cola, la canción actual, el progreso, el volumen, mezcla y repetición son los del remoto y reproducir, encolar, reordenar o vaciar la cola se ejecutan allá (comandos `play_queue`, `queue_*`, `shuffle`, `repeat`). La cola viaja como ventana de 40 canciones solo cuando cambia. Pruebas en `test/player_mirror_test.dart` y `test/connect_service_test.dart`.
- [ ] **13.5** Pendiente: probar entre PC y teléfono reales (LAN y por internet); nombre de dispositivo editable; solo se transfieren las 40 canciones siguientes de la cola; solo entre dispositivos del mismo servidor Navidrome.

## Connect por usuario de Navidrome (2026-10-07)

Cambio: Connect ya no depende de la clave de sincronización. Cada usuario de Navidrome forma su grupo (admin solo ve a admin) y la detección ocurre directamente en el servidor Jam.

- [x] **14.1** `jam-server`: `connect_join` con `user` + token Subsonic; el servidor verifica con `ping` en el Navidrome fijado por `navidromeUrl` (ajuste de `/admin`, sin SSRF) y agrupa por usuario (sin distinguir mayúsculas). Caché de verificación de 5 min. 52 pruebas.
- [x] **14.2** Cliente: `ConnectAccount` (token Subsonic y clave E2E derivada con PBKDF2 de la clave del usuario). Connect arranca solo al iniciar sesión; el panel ya no pide sincronización. LAN y relé usan la misma clave derivada.
- [x] **14.3** Servidor de producción actualizado (backup previo de `data/`) con `navidromeUrl = https://navidrome.templo.cloud`; verificado el rechazo de claves falsas contra Navidrome real. APK instalado en el teléfono y AppImage regenerado.
- [x] **14.5** Corregido: el servidor cortaba el WebSocket (1009) con tramas de más de `maxMessageBytes` (16 KB) y los mensajes de Connect con la cola lo superaban; ahora la trama admite hasta 128 KB y solo las salas Jam siguen limitadas. Una instancia desplazada por otra con el mismo id de dispositivo ya no reintenta en bucle.
- [ ] **14.4** Pendiente: probar PC + teléfono con el mismo usuario. Cambiar la clave en Navidrome cambia la clave de cifrado: hay que volver a iniciar sesión en los demás dispositivos.

## Versión para Android TV (2026-10-07)

El mismo APK sirve para teléfono y tele. En una tele se activa un modo con la interfaz amplia, navegación con el control remoto y un anillo de foco visible.

- [x] **15.1** Manifiesto: `LEANBACK_LAUNCHER`, banner 320x180, y `uses-feature` sin exigir pantalla táctil, cámara, micrófono ni leanback (verificado con `aapt2 dump badging`).
- [x] **15.2** `TvMode` (canal `scrotify/device` → `UiModeManager`/`FEATURE_LEANBACK`; `--dart-define=FORCE_TV=true` para probar en un emulador). En TV: interfaz de escritorio siempre, login empieza en "Vincular" con el teléfono (sin cámara, sin botón de QR), tema con foco marcado y botón A de mandos de juego.
- [x] **15.3** `TvFocusRing`: borde visible alrededor del elemento enfocado (botones, tarjetas, listas, campos, sliders) y desplazamiento automático. Probado en emulador 1920x1080 con teclas direccionales: navegar, abrir álbum, reproducir, atrás, volumen y pausa con tecla multimedia.
- [x] **15.5** Corregido tras probar en un Chromecast HD (Google TV): los selectores de pestaña del login eran `GestureDetector` (no enfocables) y la flecha abajo/arriba dentro de un campo de texto movía el cursor (aserción `isValid`) en vez del foco. Ahora son `InkWell` y `TvTextFieldNavigation` mueve el foco desde los campos. Verificado recorriendo todo el formulario con las flechas.
- [x] **15.6** Teclado en pantalla propio para la tele (`showTvKeyboard`): OK/Enter en un campo lo abre (letras, mayúsculas, números, símbolos, `.com`, mostrar/ocultar clave, solo dígitos en campos numéricos); se desactiva el teclado del sistema (en Google TV pide conectar el teléfono) y un teclado físico sigue escribiendo.
- [ ] **15.4** Pendiente: probar en una tele real; el foco inicial al abrir una pantalla cae en la barra superior; no se tocó la pantalla completa del reproductor ni Ajustes con el control remoto; Jam (cámara/QR) no está pensado para tele. La tele funciona como destino de Connect (se controla desde el teléfono).

## Compatibilidad bit-perfect en esta PC Linux (2026-10-08)

- [x] Reproducir con un WAV silencioso: PipeWire exclusivo termina 3 s en 0,27 s y registra `no target node available`; salida normal funciona.
- [x] Conservar la salida del sistema sin exclusividad en Linux, mantener el modo sin procesado y aclarar sus límites en Ajustes.
- [x] Verificar el reloj y la salida real con libmpv y un WAV silencioso (1 integración), 30 pruebas unitarias, análisis limpio y compilación Linux release terminada.
- [ ] Reabrir Scrotify y comprobar una canción audible con los Galaxy Buds2 Pro.

## Recuperación de descargas antiguas (2026-10-08)

- [x] Reescanear la carpeta elegida y sus subcarpetas; recuperar archivos sin índice comparando título, artista, álbum y duración con el catálogo del servidor activo.
- [x] Conservar todas las copias de igual contenido como una sola canción y persistir la identidad para uso sin conexión y evitar descargas repetidas.
- [x] Leer etiquetas con MediaMetadataRetriever en Android y ffprobe en escritorio; mostrar recuperadas y archivos sin identificar, sin atribuir coincidencias ambiguas.
- [x] Validar 60 pruebas de recuperación, descargas, caché y biblioteca sin conexión (incluida lectura real de FLAC), análisis limpio, Linux release y APK Android debug compilados. Pendiente prueba en teléfono físico.


## Publicación del estado local en PC123 (2026-10-08)

- [x] Revisar los cambios locales y verificar análisis limpio, 616 pruebas Flutter aprobadas (2 integraciones omitidas) y 54 pruebas del servidor Jam aprobadas.
- [x] Preparar PC123 con los 25 commits posteriores de main y las correcciones locales de recuperación de descargas y salida Hi-Fi en Linux para publicar sin forzar el historial.

## Mejoras (plan en `tasks/plan-mejoras.md`)

- [x] **M2** Nombre de dispositivo editable en Connect (se guarda en ajustes y se reanuncia por LAN y relé).
