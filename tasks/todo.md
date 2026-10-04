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


