# TODO — Mejoras UI/UX CrotoWave

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

## Fase 6 — Correcciones pendientes (CrotoLink, Artistas y Pantalla de Inicio)

- [x] **6.1** `CrotoLink` — Revisar y arreglar detalles pendientes de la funcionalidad CrotoLink (sincronización, UI o conexión). Verificado WSS seguro con TLS pinning sin downgrade, PRNG criptográfico en PINs, reconexión exponencial y tests verdes en crotolink-server.
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

## CrotoLink 2.0 — Mejoras de Cola y Detección de Duplicados

- [x] **CrotoLink.1** `crotolink_controller.dart` + `track_context_menu.dart` — Detección reactiva de canciones ya presentes en la cola de CrotoLink (`isTrackInCrotoLinkQueue`), advirtiendo al usuario en el menú contextual.
- [x] **CrotoLink.2** `crotolink_queue_panel.dart` — Insignia visual `Repetida` en las filas de la cola tanto de CrotoLink como de la reproducción local para pistas duplicadas.

## Fase 11 — Perfiles de Servidor y Cambio de Usuario en Caliente

- [x] **11.1** `navidrome_service.dart` — Aislamiento multi-usuario con `userScope` y `currentSessionKey` para evitar colisión de datos locales entre usuarios del mismo servidor. Limpieza de colecciones en memoria al reconectar (`_starredIds`, `_pinnedPlaylistIds`, `_followedArtistIds`, `_trackRatings`, `_cachedGenres`).
- [x] **11.2** `player_controller.dart` — Reset de reproducción y cola activa al cambiar de sesión/usuario. Historial de reproducción reciente persistido y aislado por sesión (`recently_played_$encoded.json`) con fallback compatible.
- [x] **11.3** `home_screen.dart` + `mobile_home_screen.dart` + `liked_songs_screen.dart` — Recarga reactiva en caliente de todos los `Future` (playlists, canciones, favoritos, géneros, novedades) al detectar cambio en `currentSessionKey` sin requerir cerrar ni reiniciar la aplicación.
- [x] **11.4** `test/user_profile_switching_test.dart` — Suite completa de 6 tests unitarios y de widgets verificando el aislamiento de credenciales, scopes, limpieza de colas y recarga visual inmediata al cambiar de usuario.

## CrotoLink 3.0 — Auditoría Integral, Sincronización Remota y Resiliencia

- [x] **CrotoLink.3** `crotolink_controller.dart` — Corrección de indexación de cola compartida (`_playerOrderIndexForQueueItem` y `_reorderQueueAsHost`): soporte para pistas no idénticas por referencia de memoria mediante comparación por `track.id`, y cálculo seguro de offset cuando el reproductor no tiene pista activa (`currentOrderPos < 0`).
- [x] **CrotoLink.4** `crotolink_controller.dart` — Corrección de permisos de invitados remotos: validación estricta con operador lógico `&&` (`allowGuestControls && canControlPlayback` y `allowGuestQueueManage && canManageQueue`), impidiendo que invitados omitan las restricciones fijadas por el anfitrión.
- [x] **CrotoLink.5** `crotolink-server/src/server.js` + `remote_crotolink_service.dart` — Normalización de duración (numérica y string) y soporte de actualizaciones de estado parciales (merge con `room.state`) en el servidor central. Propagación de errores reales (`lastError`) en lugar de fallos genéricos.
- [x] **CrotoLink.6** `crotolink_controller.dart` — Sincronización completa de la cola de reproducción para invitados remotos (`CrotoLinkQueueItem.toJson` / `fromJson` con trazabilidad de quién agregó la pista y portada) y actualización en caliente de permisos de participantes remotos.
- [x] **CrotoLink.7** `crotolink_queue_panel.dart` — Corrección del contrato de arrastre en `ReorderableListView.builder` con ajuste de `newIndex` (`newIndex > oldIndex ? newIndex - 1 : newIndex`) para reordenar pistas hacia abajo y al final de la cola sin errores.
- [x] **CrotoLink.8** `crotolink_dialog.dart` — Exposición de mensajes de error descriptivos (`lastJoinError`) al usuario al unirse por PIN, radar o QR.
- [x] **CrotoLink.9** `test/crotolink_test.dart` + `crotolink-server/test/server.test.js` — Tests adicionales para deserialización remota de cola, permisos estrictos y actualizaciones de estado.

## Fase 12 — Autenticación Biométrica Móvil y Temporizador de Apagado Avanzado

- [x] **12.1** `android/app/src/main/kotlin/.../MainActivity.kt` + `AndroidManifest.xml` — Migración de `MainActivity` a `AudioServiceFragmentActivity` (requerido por `local_auth` para evitar excepciones `no_fragment_activity` en Android al abrir el prompt de huella), y permiso `android.permission.USE_BIOMETRIC`.
- [x] **12.2** `lib/services/biometric_auth_service.dart` — Servicio tipado y resiliente para biometría móvil compatible con `LocalAuthentication` 3.0, mapeando adecuadamente `LocalAuthException` (`temporaryLockout`, `biometricLockout`, `userCanceled`, `noBiometricsEnrolled`) y `PlatformException`.
- [x] **12.3** `lib/screens/mobile_login_screen.dart` — Integración con post-frame callback para auto-login seguro, botón táctil "Ingresar con huella digital" con icono de huella dactilar para reintento manual sin requerir reingresar credenciales, y feedback informativo de bloqueo temporal.
- [x] **12.4** `lib/services/player_controller.dart` + `lib/widgets/track_context_menu.dart` — Temporizador de apagado completo (Fase 5 de especificación): nueva opción "Fin de la canción" (`isSleepTimerEndOfTrack`, pausando automáticamente al finalizar la canción actual sin avanzar ni hacer crossfade), presets estándar y diálogo de minutos personalizados con fade out suave al vencer.
- [x] **12.5** `test/biometric_auth_test.dart` + `test/mobile_login_screen_test.dart` + `test/sleep_timer_test.dart` — Suites de pruebas unitarias y de widgets con cobertura total para biometría, interfaz móvil y temporizador de apagado.

## CrotoLink 4.0 — Expulsión de Participantes (Kick) y Preferencia de Modo Sincronizado

- [x] **CrotoLink.10** `crotolink_controller.dart` + `remote_crotolink_service.dart` + `crotolink_host_service.dart` — Corrección de expulsión de participantes (kick): `kickParticipant()` ahora remueve al usuario de `_remoteParticipants`, registra su nombre en `_kickedRemoteNames` para prevenir que `_syncHostState()` lo reinstaure, envía acción `'kick_guest'` por WebSocket, y en el servicio local LAN rechaza reconexiones de nombres expulsados.
- [x] **CrotoLink.11** `crotolink-server/src/server.js` + `test/server.test.js` — Implementación en el servidor WebSocket de la acción `'kick_guest'`, notificando al invitado expulsado con evento `'kicked'` y cerrando su socket inmediatamente; test unitario `host can kick a guest from the room` pasando en Node.js.
- [x] **CrotoLink.12** `crotolink_dialog.dart` + `crotolink_host_service.dart` + `crotolink_controller.dart` — Inversión del orden de modos para priorizar "Escucha sincronizada" / "Sincronizado" como la primera opción en dropdowns y modo por defecto en lugar de "Altavoz".
- [x] **CrotoLink.13** `server_profiles_controller.dart` + `login_screen.dart` — Detección reactiva de perfiles persistidos (`ensureLoaded()`) para auto-login fluido en la app móvil y de escritorio sin requerir reingreso manual de credenciales en cada arranque.
- [x] **CrotoLink.14** Verificación E2E en emulador Android (`mobile-mcp`) — Validación en vivo de inicio de sesión automático, reproducción de audio, apertura del diálogo CrotoLink, selección por defecto de "Escucha sincronizada", unión de invitado y expulsión en tiempo real con remoción inmediata de la lista de participantes.



## Auditoría 2026-10-04 — Correcciones de seguridad y robustez

- [x] **Aud.1** `crotolink_models.dart` + `crotolink_controller.dart` + `crotolink_host_service.dart` + `crotolink-server/src/server.js` — Las URLs de carátula ya no viajan con `u/s/t` (token Subsonic reutilizable): `sanitizeArtUrl` en cliente y saneado de defensa en el servidor (estado y cola).
- [x] **Aud.2** `crotolink-server/src/server.js` — `/rooms` solo lista salas con `isPublic: true`; `host` público configurable (`PUBLIC_HOST`); allowlist y validación de `guest_action`; nombres duplicados rechazados; límite de intentos fallidos de PIN; ping/pong para limpiar sockets muertos; `check_room` sin cola; log de cierre corregido. 9 tests Node.
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
- [x] **UI.4** `persistent_player_bar.dart` — Barra de escritorio adaptativa por tramos (antes desbordaba entre 700 y ~1000 px): oculta volumen/CrotoLink/pantalla completa progresivamente, bloque de título acotado, progreso flexible.
- [x] **UI.5** `mobile_home_screen.dart` — Etiqueta de la barra inferior sin salto de línea (overflow a 320 px).
- [x] **W.1** `now_playing_panel.dart` — Panel lateral "Escuchando ahora" (≥1240 px): carátula, controles, cola y letra.
- [x] **W.2** `quick_actions_row.dart` — Acciones rápidas en el inicio del teléfono (Mezclar, Me gusta, CrotoLink, Estadísticas).
- [x] **W.3** `mini_player_controller.dart` + `mini_player_view.dart` + `desktop_window_frame.dart` — Modo mini reproductor en PC (ventana pequeña siempre visible, con espectro); la UI normal conserva su estado.
- [x] **W.4** Android App Widget (`CrotoWaveWidgetProvider.kt`, layout/xml/drawables, `home_widget_service.dart`) — carátula, título, artista y prev/play/siguiente en la pantalla de inicio. Verificado en emulador: aparece en el selector y se dibuja al añadirlo.
- Verificación: `flutter analyze` 0 issues; tests de espectro, responsive (anchos 320–2560) y widget.

## Ventana de escritorio: redimensionar, maximizar y pantalla completa (2026-10-04)

- [x] **Win.1** `desktop_window_frame.dart` — Bordes/esquinas arrastrables (`DragToResizeArea`) para redimensionar la ventana sin decoración nativa; `setResizable(true)` en `main.dart`.
- [x] **Win.2** Botón maximizar/restaurar con flecha arriba/abajo; pantalla completa real (botón, `F11`, `Esc` para salir); iconos sincronizados con el estado real vía `WindowListener`.
- [x] **Win.3** `persistent_player_bar.dart` — el botón de pantalla completa abre el reproductor grande y pone la ventana en pantalla completa real.
- [x] **Win.4** `services/window_controls.dart` — helpers compartidos.
- Verificación: analyze 0 issues, 309 tests, `flutter build linux --debug` OK. No se probó el arrastre en una ventana real (sesión Wayland sin herramienta para simular ratón).
- [x] **Win.5** Aclaración de diseño: la flecha ↑ de la barra inferior abre la **ventana completa** (reproductor con portada y letra dentro de la ventana, sin tocar el escritorio); dentro del reproductor, el botón de **pantalla completa** (o F11) ocupa toda la pantalla y Esc sale; al cerrar el reproductor se restaura si fue él quien la activó. La barra de título vuelve al icono clásico de maximizar/restaurar.

## Pendiente — CrotoLink: el invitado no encuentra al host (2026-10-04, prioridad alta)

- [ ] **CrotoLink.P1** Confirmar la causa real: escenario (lista/PIN/QR, LAN o remoto) y mensaje exacto en el teléfono.
- [ ] **CrotoLink.P2** Revisar descubrimiento UDP 47623 con PC en Wi-Fi + cable (misma subred), firewall y aislamiento del AP; probar por QR.
- [x] `crotolink-server` revertido a `ae8dde3` (pedido del usuario); el cliente conserva `sanitizeArtUrl`.
- Referencia: versión anterior `ae8dde3` (descubrimiento LAN idéntico; solo difiere el servidor remoto).

- Nota: el commit `fc94ddc` (ya en el remoto) aún contiene el servidor CrotoLink nuevo; el revert está sin commit.

- [x] **CrotoLink.P3** (2026-10-04) Causa confirmada contra `jam.templo.cloud`: el servidor cierra el socket del anfitrión (1009) cuando un mensaje supera `MAX_MESSAGE_BYTES` (16 KB), o sea con colas de más de ~35 canciones; la sala remota desaparece y el invitado no la encuentra. Arreglo en el cliente: `RemoteCrotoLinkService.fitStateToMessageLimit` recorta la cola al prefijo que cabe, y el anfitrión vuelve a registrar la sala con retroceso exponencial si pierde la conexión. Verificación: analyze 0 issues, 310 tests. Falta probar en dispositivos reales (hay que reinstalar la app en el anfitrión). Con colas largas el invitado remoto ve sólo las primeras ~34 canciones siguientes.

## CrotoLink Roadmap — Fase 1 (2026-10-06): ajuste "Servidor CrotoLink" + servidor administrable

- [x] **R1.1** Servidor: ajustes en SQLite (`node:sqlite`, sin dependencia nativa; desvío respecto a `better-sqlite3` del roadmap), panel `/admin` (login scrypt, cookie HttpOnly/SameSite=Strict, CSRF, rate limit de login por IP, pestañas Estado/Límites/Seguridad/Funciones/Persistentes*/Logs), `GET /api/capabilities`, límites en caliente (`maxRooms`, `maxQueueItems`, `publicListingEnabled`…), `/rooms` ya no hardcodea `jam.templo.cloud`. Dockerfile con volumen `/data` + HEALTHCHECK. 13 tests node verdes. (*pestaña de salas persistentes: placeholder hasta la Fase 7.)
- [x] **R1.2** Cliente: `crotoLinkServerUrl` en `SettingsController` (validación `CrotoLinkServerEndpoint`: `wss://`, `ws://` solo host privado con aviso), `RemoteCrotoLinkService`/radar/`CrotoLinkController` usan el ajuste, UI en Ajustes (guardar, probar `/health`, restaurar). `flutter analyze` 0 issues; tests jam verdes.
- [ ] **R1.3** Pendiente: el cliente aún no lee `/api/capabilities` (se consumirá en las fases que habiliten funciones); no hay despliegue en el servidor real (faltan datos de la sección 1 del roadmap).

## CrotoLink Roadmap — Fase 2 (2026-10-06): modos de cola
- [x] Modelos + `crotolink_queue_logic.dart` (11 tests), controlador host (aprobación, votos, fijado, modo en vivo), protocolo LAN/remoto, servidor relay (campos nuevos), UI (selector al crear, menú en vivo, ▲/▼, pin, bandeja de solicitudes). analyze 0, tests verdes.

## CrotoLink Roadmap — Fase 3 (2026-10-06): historial + guardar como playlist
- [x] `crotolink_history.dart` (umbral 30 s / 50 %, resumen, filtro por participante; 5 tests), registro en el host, diálogo con "Guardar como playlist" (`createPlaylist` + `updatePlaylist`). Historial en RAM del host; se conserva tras finalizar hasta la siguiente CrotoLink.
- [ ] No hecho: `history_snapshot` para invitados y "guardar mis aportaciones" del invitado (el historial solo vive en el host).

## CrotoLink Roadmap — Fase 4 (2026-10-06): seguridad
- [x] Servidor: rate limit por IP (ventana + bloqueo progresivo 1 min→1 h) en `join_room`/`check_room`, IPs bloqueadas por admin (SQLite + panel), respuesta genérica PIN/contraseña, contraseña de sala (scrypt+sal en RAM; `check_room` no revela estado sin ella), baneo por nombre tras kick. 19 tests node.
- [x] Cliente: contraseña de sala (crear/unirse, LAN y nube), `CrotoLinkFailureBlocker` en el host LAN, reconexión rechazada para IDs expulsados.
- Desvío: el relay recibe la contraseña en claro por TLS y guarda solo su hash (el roadmap decía que el host enviaba el hash; así no hay que compartir sal con los invitados).
- Límite documentado: el ban por nombre/ID es evadible; el ban por IP es solo del admin.

## CrotoLink Roadmap — Fase 5 (2026-10-06): sincronización avanzada
- [x] 5.1 `crotolink_clock.dart` (`ClockOffsetEstimator`: mediana de las muestras de menor RTT; 9 tests). `time_ping`/`time_pong` en relay y host LAN; 5 muestras al unirse y re-medición cada 60 s. El host de nube sella `refTs` (hora del relay); el invitado convierte con su offset. Sin pong → cálculo anterior (clamp 0–5 s).
- [x] 5.2 Corrección suave: ≤50 ms nada, 50–450 ms `setPlaybackSpeed(1±0.02)` con histéresis, >450 ms seek (`kCrotoLinkDrift*`). `PlayerController.setPlaybackSpeed` (A/B).
- [x] 5.3 `next_track_hint` (LAN op / remoto `nextHint`) ~10 s antes del final: el invitado precarga la pista siguiente tras la actual (el motor A/B la prepara). `startAtServerMs` se envía pero el arranque lo marca el fin natural de la pista (+ corrección de deriva), no un temporizador.
- [ ] Pendiente de prueba manual: 2 dispositivos, deriva media <100 ms en 10 min.

## CrotoLink Roadmap — Fase 6 (2026-10-06): matching de pistas por metadatos
- [x] `Track` canónico ampliado (`mbid`, `isrc`, `trackNumber`; opcionales), `NavidromeService.getSong`, protocolo (`trackToCrotoLinkJson`/`trackFromCrotoLinkJson`, +`durationSec`), whitelist del relay.
- [x] `crotolink_track_matcher.dart` (normalización, MBID > ISRC > título+artista+duración ±3 s; live/remix no equivalen al estudio; sin falsos positivos por homónimos; 10 tests) y `CrotoLinkTrackResolver` (caché incl. negativos, fast path por ID verificado, errores de red no cacheados, lotes que ceden el hilo; 7 tests).
- [x] Invitado en modo sincronizado reproduce la pista local equivalente; si no existe, la omite con aviso y la cola la muestra atenuada ("No disponible en tu biblioteca"). Error de red del resolver → comportamiento anterior.
- Nota: la precarga `next_track_hint` también resuelve la pista local antes de encolarla.

## CrotoLink Roadmap — Fase 7 (2026-10-06): continuidad
- [x] 7.1 Relay: `hostToken` (128 bits, solo hash en memoria), `transfer_host`/`host_changed`, `resume_host`, failover automático al invitado más antiguo tras `hostFailoverMs` (opt-in del host con `failover`, configurable en `/admin`), `guestId` en `guest_joined`. Cliente: `RemoteCrotoLinkService` unifica eventos (el rol cambia sin reabrir el socket), `CrotoLinkController` asume/cede anfitrión (`_becomeRemoteHost`/`_demoteToRemoteGuest`), reanuda con `resume_host` antes de recrear. UI: "Transferir anfitrión", switch de failover.
- [x] 7.2 Salas persistentes: tabla SQLite (PIN reservado, `ownerToken` solo como hash scrypt, expiración por inactividad o nunca), solo con `persistentRoomsEnabled`; se persiste únicamente la configuración (permisos, modo de cola), nunca qué suena. Panel `/admin` (crear/borrar, token mostrado una sola vez). Cliente: PIN fijo + token en "Sala persistente (avanzado)".
- [x] 7.3 `GET /j/:code` (si `webLinkEnabled`), `/.well-known/assetlinks.json` y `apple-app-site-association` desde ajustes del panel. Cliente: `CrotoLinkInviteLink` (`crotowave://join?code=…&server=…` y `https://host/j/PIN`), `app_links`, diálogo de unión, "Copiar enlace de invitación", pegar enlace en el campo PIN. AndroidManifest: filtro `crotowave://join` (el filtro https está comentado: pon tu dominio).
- [ ] No hecho: "migrar a la nube" desde LAN (`migrate_to_remote`); en LAN el host sigue siendo el servidor embebido (limitación documentada). iOS Universal Links/desktop no configurados.
- Probar a mano: matar la app del host con failover activado; abrir `https://<relay>/j/PIN` en el móvil.

## CrotoLink Roadmap — Fase 8 (2026-10-06): extras sociales
- [x] Reacciones efímeras (whitelist de 8 emoji, 5/5 s por conexión) y chat ligero (≤280 car., sin historial, 5/10 s). Relay: flags `reactionsEnabled` (por defecto sí) y `chatEnabled` (por defecto NO) en `/api/capabilities` y panel; el host puede desactivar el chat de su sala (`set_chat`). LAN: ops `reaction`/`chat_message`. UI: barra de reacciones + chat en la vista de CrotoLink activa. 3 tests node + 3 dart.
- [ ] No hecho (opcionales del roadmap): notificación persistente de CrotoLink en Android, cast de letras a otra pantalla, proxy de stream opt-in (rompe el principio de no retransmitir audio; queda sin implementar a propósito).
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

- [x] Usar `/storage/emulated/0/Music` sin subcarpeta CrotoWave; conservar descargas anteriores y rutas personalizadas.
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

- [x] Preparar los cambios del proyecto para la rama `PC123` de `PC123PC123/CrotoWave`; análisis limpio y 527 pruebas aprobadas en el estado actual.

## Ecualizador de tres niveles y modos Hi-Fi (2026-10-07)

Origen: carpeta `Eculiza/` (paquete `crotowave_eq` + `EQUALIZER.md`). Estado previo: el EQ de 10 bandas solo guardaba ajustes; no estaba conectado al reproductor.

- [x] **11.1** Incorporar modelos, matemática biquad, presets, import/export AutoEQ, backends, `EqualizerService` v2, curva y pantalla; retirar el EQ antiguo y sus pruebas; documentación en `docs/equalizer.md`.
- [x] **11.2** Android (conectado y compilado; falta confirmar el sonido en el teléfono): `AndroidEqualizer` en el `AudioPipeline` de los reproductores A y B del crossfade; verificar en el teléfono.
- [x] **11.3** Escritorio (verificado con libmpv real en `test/eq_mpv_integration_test.dart`): copia parcheada de `just_audio_media_kit` (acceso al `Player` de mpv) para aplicar el filtro `af`.
- [x] **11.4** Hi-Fi: `HifiPlanner`, plugin nativo Android (bit-perfect USB), ajuste de modo en Ajustes y `PlayerController.applyHifi`. Modo Estándar = comportamiento actual.
- [x] **11.5** Validación: `flutter analyze` limpio y 571 pruebas aprobadas. Pendiente: confirmar a oído en un teléfono Android.

## Datos ocultos y sincronización entre dispositivos (2026-10-07)

- [x] **12.1** Datos de escritorio en la carpeta oculta de soporte de la app (migración desde `~/Documentos/CrotoWave`); la carpeta de temas por defecto muestra la real (carpeta de importados). Las descargas finales ya iban a la carpeta de música del usuario; solo los temporales quedan privados.
- [x] **12.2** `crotolink-server`: `/api/sync/v1` (bóvedas de blobs cifrados, last-write-wins, límites en `/admin`, desactivado por defecto). 43 pruebas del servidor.
- [x] **12.3** Cliente: `SyncCrypto` (HKDF + AES-GCM), `SyncService` (ciclo cada 5 min, push/pull por documento) y sección en Ajustes → Servidor CrotoLink. Sincroniza temas importados, ajustes (sin `crotoLinkServerUrl`), seguidos/excluidos, playlists fijadas, orden de favoritos, valoraciones y ecualizador.
- [x] **12.4** `crotolink-server` redesplegado en 192.168.1.21 (backup previo de `data/` en `/root`) y `syncEnabled` activado (2026-10-07). Falta probar con dos dispositivos reales.
- [ ] **12.5** Pendiente/limitaciones: no se propagan borrados; solo `settings.json` y los temas se recargan al instante, el resto se aplica al reiniciar; vincular escaneando QR (hoy se escribe la clave).

## CrotoWave Connect: controlar tus dispositivos (2026-10-07)

Como Spotify Connect: ver los dispositivos del usuario por LAN y por el servidor CrotoLink, pasarles la reproducción y controlarlos a distancia. El "grupo" es la clave de sincronización (sección 12): solo se ven dispositivos con la misma clave y todo viaja cifrado de extremo a extremo.

- [x] **13.1** `crotolink-server`: `connect_join` / `connect_send` (presencia y relé de blobs cifrados, 16 dispositivos por grupo). 48 pruebas.
- [x] **13.2** Cliente: `ConnectService` (transferir, traer de vuelta, comandos, estado remoto, anti-repetición), `RelayTransport`, `LanTransport` (baliza UDP 47624 + WebSocket directo, saludo cifrado), `PlayerConnectPort`.
- [x] **13.3** UI: `ConnectPanel` (selector de dispositivos) y botón Connect en la barra en lugar del botón de la cola (escritorio y móvil); la barra muestra y controla el dispositivo remoto (play/pausa, siguiente, anterior, seek, volumen).
- [x] **13.4** Validación: relé probado contra el servidor Node real; `flutter analyze` limpio y 600 pruebas aprobadas.
- [x] **13.6** Sincronización completa: `PlayerController` en modo espejo (`RemotePlayback`/`ConnectMirror`). Mientras se controla otro dispositivo, la cola, la canción actual, el progreso, el volumen, mezcla y repetición son los del remoto y reproducir, encolar, reordenar o vaciar la cola se ejecutan allá (comandos `play_queue`, `queue_*`, `shuffle`, `repeat`). La cola viaja como ventana de 40 canciones solo cuando cambia. Pruebas en `test/player_mirror_test.dart` y `test/connect_service_test.dart`.
- [ ] **13.5** Pendiente: probar entre PC y teléfono reales (LAN y por internet); nombre de dispositivo editable; solo se transfieren las 40 canciones siguientes de la cola; solo entre dispositivos del mismo servidor Navidrome.

## Connect por usuario de Navidrome (2026-10-07)

Cambio: Connect ya no depende de la clave de sincronización. Cada usuario de Navidrome forma su grupo (admin solo ve a admin) y la detección ocurre directamente en el servidor CrotoLink.

- [x] **14.1** `crotolink-server`: `connect_join` con `user` + token Subsonic; el servidor verifica con `ping` en el Navidrome fijado por `navidromeUrl` (ajuste de `/admin`, sin SSRF) y agrupa por usuario (sin distinguir mayúsculas). Caché de verificación de 5 min. 52 pruebas.
- [x] **14.2** Cliente: `ConnectAccount` (token Subsonic y clave E2E derivada con PBKDF2 de la clave del usuario). Connect arranca solo al iniciar sesión; el panel ya no pide sincronización. LAN y relé usan la misma clave derivada.
- [x] **14.3** Servidor de producción actualizado (backup previo de `data/`) con `navidromeUrl = https://navidrome.templo.cloud`; verificado el rechazo de claves falsas contra Navidrome real. APK instalado en el teléfono y AppImage regenerado.
- [x] **14.5** Corregido: el servidor cortaba el WebSocket (1009) con tramas de más de `maxMessageBytes` (16 KB) y los mensajes de Connect con la cola lo superaban; ahora la trama admite hasta 128 KB y solo las salas CrotoLink siguen limitadas. Una instancia desplazada por otra con el mismo id de dispositivo ya no reintenta en bucle.
- [ ] **14.4** Pendiente: probar PC + teléfono con el mismo usuario. Cambiar la clave en Navidrome cambia la clave de cifrado: hay que volver a iniciar sesión en los demás dispositivos.

## Versión para Android TV (2026-10-07)

El mismo APK sirve para teléfono y tele. En una tele se activa un modo con la interfaz amplia, navegación con el control remoto y un anillo de foco visible.

- [x] **15.1** Manifiesto: `LEANBACK_LAUNCHER`, banner 320x180, y `uses-feature` sin exigir pantalla táctil, cámara, micrófono ni leanback (verificado con `aapt2 dump badging`).
- [x] **15.2** `TvMode` (canal `crotowave/device` → `UiModeManager`/`FEATURE_LEANBACK`; `--dart-define=FORCE_TV=true` para probar en un emulador). En TV: interfaz de escritorio siempre, login empieza en "Vincular" con el teléfono (sin cámara, sin botón de QR), tema con foco marcado y botón A de mandos de juego.
- [x] **15.3** `TvFocusRing`: borde visible alrededor del elemento enfocado (botones, tarjetas, listas, campos, sliders) y desplazamiento automático. Probado en emulador 1920x1080 con teclas direccionales: navegar, abrir álbum, reproducir, atrás, volumen y pausa con tecla multimedia.
- [x] **15.5** Corregido tras probar en un Chromecast HD (Google TV): los selectores de pestaña del login eran `GestureDetector` (no enfocables) y la flecha abajo/arriba dentro de un campo de texto movía el cursor (aserción `isValid`) en vez del foco. Ahora son `InkWell` y `TvTextFieldNavigation` mueve el foco desde los campos. Verificado recorriendo todo el formulario con las flechas.
- [x] **15.6** Teclado en pantalla propio para la tele (`showTvKeyboard`): OK/Enter en un campo lo abre (letras, mayúsculas, números, símbolos, `.com`, mostrar/ocultar clave, solo dígitos en campos numéricos); se desactiva el teclado del sistema (en Google TV pide conectar el teléfono) y un teclado físico sigue escribiendo.
- [ ] **15.4** Pendiente: probar en una tele real; el foco inicial al abrir una pantalla cae en la barra superior; no se tocó la pantalla completa del reproductor ni Ajustes con el control remoto; CrotoLink (cámara/QR) no está pensado para tele. La tele funciona como destino de Connect (se controla desde el teléfono).

## Compatibilidad bit-perfect en esta PC Linux (2026-10-08)

- [x] Reproducir con un WAV silencioso: PipeWire exclusivo termina 3 s en 0,27 s y registra `no target node available`; salida normal funciona.
- [x] Conservar la salida del sistema sin exclusividad en Linux, mantener el modo sin procesado y aclarar sus límites en Ajustes.
- [x] Verificar el reloj y la salida real con libmpv y un WAV silencioso (1 integración), 30 pruebas unitarias, análisis limpio y compilación Linux release terminada.
- [ ] Reabrir CrotoWave y comprobar una canción audible con los Galaxy Buds2 Pro.

## Recuperación de descargas antiguas (2026-10-08)

- [x] Reescanear la carpeta elegida y sus subcarpetas; recuperar archivos sin índice comparando título, artista, álbum y duración con el catálogo del servidor activo.
- [x] Conservar todas las copias de igual contenido como una sola canción y persistir la identidad para uso sin conexión y evitar descargas repetidas.
- [x] Leer etiquetas con MediaMetadataRetriever en Android y ffprobe en escritorio; mostrar recuperadas y archivos sin identificar, sin atribuir coincidencias ambiguas.
- [x] Validar 60 pruebas de recuperación, descargas, caché y biblioteca sin conexión (incluida lectura real de FLAC), análisis limpio, Linux release y APK Android debug compilados. Pendiente prueba en teléfono físico.


## Publicación del estado local en PC123 (2026-10-08)

- [x] Revisar los cambios locales y verificar análisis limpio, 616 pruebas Flutter aprobadas (2 integraciones omitidas) y 54 pruebas del servidor CrotoLink aprobadas.
- [x] Preparar PC123 con los 25 commits posteriores de main y las correcciones locales de recuperación de descargas y salida Hi-Fi en Linux para publicar sin forzar el historial.

## Mejoras (plan en `tasks/plan-mejoras.md`)

- [x] **M2** Nombre de dispositivo editable en Connect (se guarda en ajustes y se reanuncia por LAN y relé).
- [x] **M3** Connect transfiere la cola completa (hasta 1000 canciones) en trozos ordenados; clientes viejos siguen recibiendo 40.
- [x] **M7** El cliente lee `/api/capabilities` completo (`CrotoLinkCapabilities`) y oculta opciones que el relé no ofrece.
- [x] **M11** El escaneo de descargas muestra progreso y se puede cancelar sin perder el índice.
- [x] **M12** Caché de 3 min del catálogo de recuperación (por sesión, sin descargas duplicadas).
- [x] **M1** Selector de salida ALSA `hw:` para Bit-perfect en Linux (probado con libmpv; falta probar con un DAC real).
- [x] **M4** Vincular la sincronización por QR (`crotowave-sync://`), con aviso de secreto y biometría; falta probar la cámara en un teléfono real.
- [x] **M6** Android TV: foco inicial en el contenido, reproductor completo con el mando (saltos de 10 s) y Ajustes recorrible con flechas; falta probar en tele/emulador.
- [x] **M8** El invitado de una CrotoLink tiene su propio historial (lo que sonó desde que entró) y puede guardar sus aportaciones como playlist; sin cambios de protocolo.
- [x] **M13** La notificación de medios de Android muestra la CrotoLink y trae el botón de salir (solo con una pista sonando); falta verlo en un teléfono real.
- [x] **M10** Pruebas de integración de la recuperación de descargas en Android (7/7 en emulador); script `tool/run_android_integration.sh`.
- [x] **M5** Los temas importados que se borran en un dispositivo se borran en los demás (con papelera de 30 días y varias guardas); falta probar entre dos dispositivos reales.
- [x] **M9** `navidrome_service`, `player_controller`, `crotolink_controller` y `home_screen` partidos en mixins/`part` (≤1076 líneas el mayor), sin cambios de comportamiento.

## Mejoras, tanda 2 (plan en `tasks/plan-mejoras-2.md`)
- [x] 1 CI (GitHub Actions) · 4 aviso de firma debug · 17 ignorar APK · 20 versionar build de Android (2026-10-09).
- [x] 2 tests intermitentes · 3 lints · 6 aviso http · 8 diagnóstico · 9 cobertura · 12 timers · 16 archivos grandes · 15 parcial (rxdart). Suite: 852 verdes (2026-10-09).
- [x] Fix: activar Bit-perfect en Linux rompía Ajustes (`setState` del selector ALSA devolvía un Future). Test de regresión en `material_presentation_test.dart` (2026-10-09).

## Mejoras, tanda 3 (plan en `tasks/plan-mejoras-3.md`)
- [x] 2 instalación segura · 3 build identificable · 4 recuadro de error · 5 humo de Ajustes · 6 arranque real · 9 APK por ABI · 10 catches · 11 unión a CrotoLink + web_socket_channel 3 · 12 crotolink_host_service. Suite: 886 verdes (2026-10-09).
## Soporte para Android TV y Versiones por Plataforma (2026-10-12)

- [x] **15.1** Control lateral del mouse (`DesktopWindowFrame`): botón lateral trasero (Back / `kBackMouseButton` / `browserBack`) configurado para alternar Reproducir / Pausar (`_togglePlayPause`), y botón lateral delantero (Forward / `kForwardMouseButton` / `browserForward`) para pasar a la siguiente pista (`_skipNext`), además de bindings multimedia directos.
- [x] **15.2** Soporte Android TV / Google TV (`AndroidManifest.xml` + `tv_banner.xml`): declaración de pantalla táctil opcional (`touchscreen=false`), `leanback=false`, banner horizontal de 320x180 y filtro `LEANBACK_LAUNCHER` para visualización nativa en pantallas de TV y soporte de D-Pad.
- [x] **15.3** Workflows de GitHub Actions dedicados por plataforma:
  - `android.yml` ➔ Compilación automática de `CrotoWave-Android.apk` (Release `android-latest`).
  - `tv.yml` ➔ Compilación automática de `CrotoWave-TV.apk` (Release `tv-latest`).
  - `linux.yml` ➔ Compilación automática de `CrotoWave-Linux-x64.tar.gz` (Release `linux-latest`).
  - `windows.yml` ➔ `CrotoWave-Windows-x64.zip` (Release `windows-latest`).
  - `ios.yml` ➔ `CrotoWave.ipa` (Release `ios-latest`).

## Integración de las ramas Lau y santi (2026-10-16)

- [x] `Lau` entró por avance rápido (42 commits: radios, Discord, MPRIS, Chromecast, Android Auto…).
- [x] `santi` fusionada (23 commits: Windows ThumbBar y botones laterales del ratón, rueda de volumen, 124 temas empaquetados, CI por plataforma, accesos rápidos de escritorio). Conflictos: Android TV, `.gitignore`, `main.cpp` y `Runner.rc` se quedaron con lo de `main` (sabores `phone`/`tv`, marca CrotoWave); `flutter_window.*` y el fondo oscuro del splash, de santi.
- [x] Ajuste tras la fusión: el botón «Mezclar todo» se oculta si el campo de búsqueda mide menos de 260 px (desbordaba 2,5 px a 720 px con texto 1,5); `await` en `_shuffleAllTracks`.
- [x] `flutter analyze` limpio y 964 pruebas aprobadas. Falta compilar y probar el runner de Windows (ThumbBar, botones del ratón) en una máquina Windows.

## Licencias y firma propia (2026-10-16)

- [x] Licencias: `LICENSE` (GPL-3.0-or-later + excepción para tiendas, inglés vinculante y traducción), `crotolink-server/LICENSE` (AGPL-3.0-or-later), `LICENSING.md` (por componente, dependencias revisadas: ninguna GPL), `CONTRIBUTING.md` (DCO; las contribuciones heredan la excepción).
- [x] App: Ajustes → «Licencias de código abierto» (`lib/utils/app_licenses.dart`): licencia propia, servidor CrotoLink y, en escritorio, libmpv/FFmpeg/keybinder. Flutter ya junta las de los paquetes.
- [x] Servidor CrotoLink: `SOURCE_URL` → `GET /source`, `license`/`sourceUrl` en `/api/capabilities`, pie en `/admin` (AGPL §13).
- [x] AppImage: `LICENSE`, `LICENSING.md`, copyright de los 160 paquetes de Debian incluidos y `THIRD_PARTY_SOURCES.txt` con versión y fuente.
- [x] Firma Android: keystore propio en `~/.config/crotowave-signing/`, `applicationId` `cloud.templo.crotowave`. Teléfono migrado con todos sus datos (`tool/migrate_android_signing.sh`).
- [x] Secretos: `.gitignore` ampliado y hook `.githooks/pre-commit` (activo con `core.hooksPath`).
- [x] `scripts/sign_release.sh`: verifica la huella de los APK y genera `SHA256SUMS` (+ minisign).
- [x] minisign instalado; clave creada con contraseña pedida en ventana (`scripts/sign_release.sh --init`), pública `crotowave-release.pub`.
- [x] URL del repo público (`https://github.com/Dante0Q/CrotoWave`) en `UPSTREAM_SOURCE_URL`, `LICENSE`, instalador y User-Agent.
- [ ] Migrar la tele y el Chromecast (`tool/migrate_android_signing.sh <id> tv backup|restore`, desde `el id de la plantilla de Flutter`).
- [ ] CI de Android/TV: flavor + firma con secretos (o firmar solo en local). Ver `docs/SIGNING.md`.
- [ ] Publicar con historial limpio cuando esté terminado (`docs/PUBLICAR.md`); cambiar igual la contraseña de la cuenta `Proyecto` (está en el historial de desarrollo).
- [ ] Windows: pedir la firma gratis a SignPath Foundation después de la primera publicación (`docs/PUBLICAR.md`).

## Cambio de nombre: CrotoWave y CrotoLink (2026-10-16)

- [x] App «CrotoWave» → **CrotoWave**; CrotoLink → **CrotoLink** (textos, Android/iOS/Linux/Windows, instalador, AppImage, docs, servidor).
- [x] Enlaces: se generan `crotowave://` y `crotowave-sync://`; se siguen aceptando `crotowave://` y `crotowave-sync://` (`lib/utils/app_links.dart`).
- [x] Se mantienen los identificadores internos que guardan datos o hacen de protocolo (claves `crotowave.*`, nonces, etiquetas de red, canales nativos). Ver `LICENSING.md` → «Nombres y logo».
- [x] `LICENSE`: condición de la sección 7(e) sobre los nombres y el logo. `PRIVACY.md` y `docs/CODE_SIGNING_POLICY.md` (requisitos de SignPath).
- [x] Android: `applicationId` `cloud.templo.crotowave`, clave nueva `CN=CrotoWave` en `~/.config/crotowave-signing/` (la de CrotoWave queda en `legacy/` para migrar). Teléfono migrado desde `cloud.templo.crotowave`.
- [x] `tool/migrate_android_signing.sh`: origen configurable (`FROM_APP`, `FROM_KEY`), arregla la carpeta de datos que quedaba en 755 y ya no usa `tar --delete` (dañaba la copia).
- [x] Sin servidor CrotoLink por defecto (antes `jam.templo.cloud`): las instalaciones nuevas lo configuran en Ajustes; las existentes conservan el guardado. Sin servidor, crear/unirse a una sala remota avisa «Configurá un servidor CrotoLink…».
- [ ] Redeploy del servidor: el contenedor pasa a llamarse `crotolink`; cambiar el ingress del túnel de `crotolink:8080` a `crotolink:8080`.
- [ ] Desinstalar del teléfono `cloud.templo.crotowave` y `el id de la plantilla de Flutter` cuando el usuario confirme que CrotoWave está bien.
## Descubrimiento personalizado y portadas (2026-10-16)
- [x] Especificación en docs/personalized-discovery.md; base main 13b90f8 recuperada en D:\codex\crotowave, respaldo previo intacto.
- [x] Perfil de biblioteca, favoritos, valoraciones y escuchas recientes por cuenta exacta; catálogo completo, exclusión por MBID/ISRC y metadatos normalizados.
- [x] ListenBrainz Radio + MusicBrainz: consultas públicas con límites, timeout, caché y regulación; canciones, álbumes y artistas externos en Inicio de escritorio/móvil.
- [x] Portadas 44x44 con fallback en Añadir canciones; selección múltiple, búsquedas y guardado conservados; probado a 320px y descubrimiento a 360px con texto 1.5.
- [x] 39 pruebas de verificación aprobadas y consulta real de descubrimiento aprobada. Suite general: 961 aprobadas, 15 omitidas, 3 fallos intermitentes en diagnósticos/descargas; los archivos afectados pasan en la verificación posterior.
- [x] Conservada corrección previa de arranque Windows (teclas multimedia); test específico aprobado. Análisis: 0 errores/warnings y 11 avisos informativos previos.
- [x] Release final Windows x64 compilado y probado: ventana CrotoWave respondiendo tras 15 s. Portable y ZIP en outputs/CrotoWave-mejoras-Windows-x64.

## Ajuste de Recomendados para ti: solo Navidrome (2026-10-16)
- [x] Se sustituye el descubrimiento externo por recomendaciones de canciones del catálogo completo de la cuenta activa, con IDs originales reproducibles.
- [x] Se retiran proveedores externos, fichas y pestañas de álbumes/artistas de esta sección; se mantienen portadas de Añadir canciones y las demás secciones de biblioteca.
- [x] Ranking según historial exacto por cuenta, artistas/géneros, favoritos y valoraciones; diversidad y deduplicación, sin descartar toda la biblioteca por ser existente.
- [x] 15 pruebas aprobadas: ranking, reproducción por ID Navidrome, aislamiento, respuestas tardías, más de 500 canciones y diálogo de añadir canciones.
- [x] Compilación Flutter release AOT y assets aprobada; empaquetada con el runner nativo anterior (sin cambios nativos). Arranque verificado 12 s, fuentes/JSON y ZIP válidos. El build nativo completo se detuvo por acceso denegado en MSBuild FileTracker. Portable actualizado: outputs/CrotoWave-Navidrome-Windows-x64.

## Carrusel de recomendaciones (2026-10-16)
- [x] Flechas anterior/siguiente con animación por pantalla de tarjetas y deshabilitadas en los extremos; barra horizontal arrastrable y gesto táctil conservado.
- [x] Dos pruebas de navegación, extremos, gesto táctil y reproducción aprobadas; análisis sin errores/warnings, 11 infos previos.
- [x] Release Flutter AOT actualizado y assets sincronizados al runner local y al portable CrotoWave-Carrusel-Windows-x64; fuentes y ZIP válidos; arranque verificado durante 10 s.

## Portadas como Álbumes destacados (2026-10-16)
- [x] Recomendaciones con dimensiones 130x180 en escritorio y 120x180 en móvil (más ajuste de texto), padding 8, radio 6 y tipografía equivalente; título/artista bajo la portada.
- [x] Carrusel adaptado al nuevo ancho; dos pruebas aprobadas de tamaño/estilo, flechas, deslizamiento y reproducción; análisis sin errores/warnings nuevos (11 infos anteriores).
- [x] Release AOT y assets actualizados sobre runner existente, fuentes y ZIP verificados y arranque respondiendo a los 10 s. Portable: outputs/CrotoWave-Portadas-Windows-x64.

## Actualizar recomendaciones junto al título (2026-10-16)
- [x] Encabezado integrado en DiscoverySection: título, actualizar y flechas en la misma fila en escritorio y móvil, sin título duplicado.
- [x] Dos pruebas de carrusel/reproducción aprobadas y análisis sin errores/warnings (11 infos previos); build Flutter release AOT aprobado y arranque respondiendo a los 10 s.
- [x] Por falta de espacio en C:, temporales y nuevo portable/ZIP en D:\codex\crotowave\dist\CrotoWave-Actualizado-Windows-x64, accesible también desde outputs por junction; fuentes y ZIP verificados.

## Alineación vertical del encabezado en DiscoverySection (2026-10-16)
- [x] Fijada explícitamente la propiedad `crossAxisAlignment: CrossAxisAlignment.center` en el `Row` del encabezado de `DiscoverySection` con `Expanded(child: title)` y los `IconButton` en una sola fila horizontal sin títulos externos duplicados.
- [x] Verificado con prueba de widgets que el centro vertical del título (`tester.getCenter(find.text('Recomendados para ti')).dy`) coincide con el de los botones (`Icons.refresh_rounded`, `Icons.chevron_left_rounded`, `Icons.chevron_right_rounded`) (`closeTo(..., 1.0)`) y que el título aparece exactamente una vez (`findsOneWidget`).
- [x] Pruebas (`flutter test test/discovery_section_test.dart`) PASS y `flutter analyze` sin errores ni warnings nuevos.
- [x] Bundle de Windows Release AOT y assets compilados, y portable completo empaquetado en `D:\gemini\.exes\` con `CrotoWave.exe` y `data/app.so` actualizados.

## Correcciones de sesión, conexión y reproductor (Claude Code)

- [x] Scrobbles: validar aceptación Subsonic, fijar cuenta durante flush y compartir carga inicial de cola; regresiones de rechazo y cambio de cuenta.
- [x] Sync: cambio de identidad, suspensión de cuenta al logout, migración segura de claves anteriores, persistencia serializada y aislamiento de archivos por cuenta.
- [x] Home desktop/móvil: invalidar búsquedas antiguas y mostrar errores de catálogo con reintento; corregir Material de resultados sin silenciar errores de Flutter.
- [x] Conectividad: validar respuestas/ping, retry acotado de 5xx, recuperación offline y estado degradado por consulta sin ocultarlo como lista vacía.
- [x] Reproductor ampliado: portada firmada/caché de resolución por sesión y tinte neutro; waveform desde archivo local o MP3 96 kbps, análisis fuera de UI, coalescing y estados visibles. Sin decodificador comprimido en Android/iOS se informa indisponibilidad, no se inventa una onda.
- [x] Verificación integral: `flutter analyze --no-pub` sin issues; suite Flutter con 1088 aprobadas, 3 omitidas y 0 fallidas; build Linux debug aprobado. Dos warnings C++ previos de `hotkey_manager_linux`. Render de widgets con portada y WAV locales inspeccionado en tema claro/oscuro. Especificación y límites: `docs/session-connectivity-player-fixes.md`.
- [x] Paquetes actualizados en `dist/`: APK release teléfono arm64 firmado (versionCode 12247) y AppImage x86_64 portable compilado en Debian 12, con FFmpeg/ffprobe incluidos y probados. Checksums verificados; retirados APK TV/Chromecast, bundle antiguo y firma minisign anterior. No se generó una nueva firma minisign.

## Waveform nativa Android

- [x] Contrato y fuentes oficiales en `docs/android-native-waveform.md`; sin dependencias adicionales ni FFmpeg CLI móvil.
- [x] Decoder Kotlin MediaExtractor/MediaCodec en worker acotado, RMS/picos por bloques y limpieza/cancelación; FlutterPlugin vinculado al engine de audio, no a la Activity.
- [x] Integración Dart para archivos locales/stream de análisis, descargas abortables, coalescing y caché con publicación atómica; cancelación antes de resolver origen, al cambiar pista/vaciar cola/dispose y antes del commit de caché.
- [x] Análisis sin issues; 47 tests dirigidos y suite de 1106 aprobados/3 omitidos/0 fallidos; Linux debug aprobado. Veinte checks JVM de PCM y 12 checks reales Android 14, incluidos MP3/FLAC 16/24 bits, archivo >30 MB, reproducción/onda sin Activity y cierre del engine sin crash.
- [x] APK release teléfono ARM64 actualizado en `dist/` (versionCode 12251), misma firma verificada, entrypoint normal y checksums comprobados. AppImage anterior preservado. Pendiente prueba en teléfono físico. Detalles: `docs/android-native-waveform.md`.

## Vista previa de temas
- Implementado: tarjetas con colores del tema, sin capturas de miniaturas instaladas; assets/themes verificado sin imágenes en los 122 ZIP. Pruebas de temas: 13 aprobadas. Análisis estático pendiente de terminar.

## Nombres de temas en español
- [x] Renombrados 122 temas empaquetados y 6 fijos según su paleta; IDs conservados. Alias visibles para copias previamente importadas, sin escribir datos del dispositivo.
- [x] Verificados ZIP íntegros, nombres únicos y manifiestos coincidentes. 13 pruebas de temas aprobadas. Análisis: 11 avisos informativos de unawaited_futures en archivos ajenos al cambio; sin hallazgos en archivos modificados.

## Orden del selector de temas
- [x] Conservados los seis temas fijos al inicio en su orden actual; instalados ordenados por nombre, sin distinguir mayúsculas ni tildes vocálicas. Hot restart aplicado.
- [x] 13 pruebas de temas aprobadas; análisis con los mismos 11 avisos informativos ajenos al cambio.

## Primera selección de temas retirados
- [x] Retirados Aurora suave, Estudio claro, Mostaza suave, Mostaza intensa, Arena clara y Arena suave del ZIP y fuentes temporales; copias antiguas omitidas en el selector sin borrar datos del dispositivo. Quedan 116 empaquetados más seis fijos. 13 pruebas aprobadas; hot restart solicitado.

## Segunda selección de temas retirados
- [x] Retirados Lavanda, Malva cálida (fijo), Malva, Acero naranja, Ámbar, Anochecer, Azul eléctrico, Azul lima, Azul medianoche, Azul retro, Chispa, Jardín rosa y Neón turquesa. Paquete con 104 temas y cinco fijos (109 total); copias antiguas filtradas. Predeterminado actualizado a Crema.
- [x] ZIP íntegro, 13 pruebas aprobadas; hot restart aplicado. Análisis conserva los 11 avisos informativos ajenos a los cambios.

## Tercera selección de temas retirados
- [x] Retirados Terminal verde, Sol violeta, Verde láser, Verde urbano, Verde vivo, Vainilla azul, Ventana clara, Turquesa clásico, Turquesa digital y Turquesa retro del paquete y fuentes; copias antiguas filtradas. Quedan 94 empaquetados y cinco fijos (99 total).
- [x] ZIP íntegro y 13 pruebas de temas aprobadas. Análisis mantiene los 11 avisos informativos previos; hot restart aplicado.

## Tarjetas de temas compactas
- [x] Tarjetas de 152 x 164 px a escala normal, con vista previa de 96 px, nombre y papelera a la derecha en la misma fila. Retiradas versión y etiqueta CVD del pie; indicador de selección conservado. Altura adaptable al tamaño de texto.

## Tema personalizado
- [x] Tarjeta Personalizado al final con icono de paleta en lugar de papelera. Editor con fondo y dos acentos, colores sugeridos, códigos hexadecimales validados, vista previa y Guardar y aplicar. Colores y selección persistidos en themes.json; contraste claro/oscuro según el fondo.
- [x] 14 pruebas aprobadas, incluida persistencia/recarga de colores y posición final. Análisis sin hallazgos en cambios (11 avisos informativos previos en otros archivos).

## Editor de colores por casillas y RGB
- [x] Selector exclusivo 1 Fondo / 2 Acento principal / 3 Acento secundario; barras Color, Tonalidad y Luz, RGB visible y panel Ajustar RGB con canales de 0 a 255. Vista previa y colores independientes por casilla.
- [x] 15 pruebas aprobadas, incluyendo interacción RGB, cambio de casilla, cancelación y persistencia. Análisis conserva 11 avisos informativos previos en archivos ajenos al cambio.

## Blur y transparencia de Personalizado
- [x] Retirado panel Ajustar RGB; agregadas barras Blur (0–30 px) y Transparencia (0–100 %). Vista previa con fondo de contraste y desenfoque. Efectos persistidos y aplicados a MaterialSurface cuando Personalizado está activo; demás temas sin efectos.
- [x] 15 pruebas de temas aprobadas; verificadas persistencia, desactivación al cambiar de tema, BackdropFilter real y alfa de superficies. Análisis mantiene 11 avisos informativos previos en archivos ajenos. Hot restart aplicado.

## Efectos del tema en toda la app
- [x] Transparencia extendida a fondos de pantallas, biblioteca lateral, reproductor y superficies elevadas. Fondo global con los colores del tema y desenfoque propio, conservando texto y controles nítidos. ThemeData adaptado para pantallas que usan el fondo predeterminado. Corregida lectura reactiva fuera de build en aviso de Temas incluidos.
- [x] Verificados alfa de fondo/barra lateral/reproductor, filtro global, persistencia y regreso a tema opaco. Archivos de la extensión analizados sin issues; 15 pruebas de temas aprobadas.

## Transparencia del escritorio de Windows
- [x] Aclarado alcance: escritorio detrás de la ventana. Eliminado fondo pintado en Windows; bgApp transparente para evitar capas opacas superpuestas y tinte global único. Marco y mini reproductor cubiertos por el fondo común.
- [x] Canal nativo com.crotowave/window_effects en runner: DWM Desktop Acrylic, composición por ventana si EnableTransparency del sistema está apagado, restauración opaca y errores propagados. Sin modificar ajustes de Windows ni opacidad del texto. Sincronización serializada con tema; en Windows Blur es interruptor por radio fijo del SO.
- [x] flutter run -d windows recompiló runner nativo y app abierta sin errores del canal. 16 pruebas aprobadas; archivos cambiados con análisis sin issues; diff --check sin errores. PrintWindow confirma interfaz renderizada; no se pudo verificar composición visual sobre escritorio porque otra aplicación ocupa el primer plano.

## Simplificación del editor personalizado
- [x] Quitados Blur (incluido efecto persistido/activo) y texto RGB. Transparencia inmediatamente debajo de Luz; se conservan las tres casillas y vista previa. Windows recibe siempre blur=false para limpiar el efecto previo y mantener transparencia simple.
- [x] Análisis conserva los 11 avisos informativos previos en otros archivos; pruebas de persistencia/controles y protocolo nativo actualizadas para ausencia de blur y RGB.

## Vista previa fiel de Personalizado
- [x] Sustituido degradado de acentos y franja blanca por damero neutro. Fondo seleccionado con su transparencia; dos franjas inferiores reservadas a acentos. El negro no hereda el tono de los acentos.
- [x] Tres pruebas de píxeles reales aprobadas (negro opaco, transparencia75% neutra y100% damero, franjas exactas) y dos pruebas del editor aprobadas. Captura renderizada inspeccionada; hot reload aplicado. Análisis conserva los 11 avisos informativos previos.

## Vista previa igual a la tarjeta
- [x] Por corrección del usuario: retirado damero. Vista previa opaca con fondo elegido y dos bandas de acento, idéntica a la tarjeta; el control Transparencia sigue aplicándose a la ventana.
- [x] Tres pruebas de píxeles de colores sólidos y bandas, más dos pruebas del editor, aprobadas. Archivos de vista previa analizados sin issues. Hot reload aplicado.

## Compartir e importar Personalizado por código
- [x] Código CWT1 generado desde el borrador (fondo, dos acentos, transparencia), con Copiar código, pegar del portapapeles/entrada manual y Cargar código dentro del editor. Cargar valida y previsualiza; Guardar y aplicar persiste; cancelar y códigos inválidos conservan configuración anterior.
- [x] Formato versionado documentado en docs/custom-theme-sharing.md, límite128 caracteres y validación estricta; sin datos de cuenta ni nuevas dependencias.
- [x] 17 pruebas aprobadas (11 formato,1 flujo copiar/pegar/importar/error/cancelación,2 editor/persistencia,3 píxeles). Análisis de archivos modificados sin issues; análisis global conserva 11 avisos informativos previos. Hot reload aplicado.

## Instalación SSH en CachyOS
- [x] Acceso por clave a pc@192.168.1.78. Proyecto actual transferido y compilado con Flutter3.47.4 (versión CI), lockfile respetado; herramientas faltantes extraídas en usuario, sin sudo ni cambios de paquetes del sistema.
- [x] AppImage de92MB instalado en ~/.local/opt/crotowave/CrotoWave.AppImage, lanzador ~/.local/bin/crotowave y entrada de menú validados. Servicio de usuario crotowave.service activo y arranque GTK/media_kit verificado. Log reporta dos atajos AudioNext/AudioPrev ocupados en KDE.
- [x] Copia en outputs/CrotoWave-Linux-x64.AppImage de esta conversación. SHA256 BC084854A7AE30B733C3692F3A7CA91FE9482205CC01DBDD83F46B26E2C05EC1 coincide entre equipos. Sin WSL instalado en Windows: compilación realizada en CachyOS. Servidor HTTP temporal de claves cerrado y archivo SDK descargado retirado tras compilación.

## Corrección de render en VMware
- [x] Reproducida corrupción visual con SVGA3D de VMware e Impeller. Probado LIBGL_ALWAYS_SOFTWARE=1: Mesa llvmpipe dibuja textos/campos/botones completos, captura real inspeccionada.
- [x] AppRun detecta VMware y usa Mesa por CPU solo si LIBGL_ALWAYS_SOFTWARE no fue definido explícitamente; resto de equipos conserva aceleración. AppImage recompilado/empaquetado, reinstalado y relanzado en VM. Verificada variable desde proceso real con lanzador normal sin override externo.
- [x] AppImage y captura actualizados en outputs de la conversación. SHA256 5B62E7F540E237124714C642FB217501B483692C99344C7789B1276D8203C035 coincide entre equipos. Servicio activo y vista de login completa verificada.
- Verificación final tras reinstalar y reabrir: captura de la ventana CrotoWave enfocada confirma formulario de login completo, tipografía y controles sin corrupción; imagen de outputs actualizada con esa captura.

## Icono de widget en la barra inferior
- [x] Retirado botón Widget / Mini reproductor de PersistentPlayerBar, junto con su separador e imports sin uso.
- [x] 28 pruebas existentes aprobadas (playback_time, player_position_builder y waveform_progress_bar). Análisis sin errores ni warnings: conserva los 11 avisos informativos previos en otros archivos; diff --check sin errores.
