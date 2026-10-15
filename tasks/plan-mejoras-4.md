# Plan de mejoras — tanda 4 (2026-10-15)

Estado: `[ ]` pendiente · `[~]` en curso · `[x]` hecho · `[!]` necesita decisión del usuario.

Base: `main` @ `e90a24c`. Tanda 3 cerrada en `tasks/plan-mejoras-3.md`.

Origen: revisión completa del proyecto (seguridad, reproducción/descargas,
Jam/Connect/Sync, UI/rendimiento, build/CI) hecha en Windows el 2026-10-15.

Estado de partida en Windows:
- `flutter analyze`: 0 issues.
- `flutter test`: **867 verdes, 8 rojos**. La tanda 3 cerró con 886 verdes,
  pero en Linux. Hasta ahora nadie había corrido la suite en Windows, y
  `flutter test | tail` devolvía 0 aunque hubiera fallos.
- jam-server: sin ejecutar (falta `node_modules`).
- Árbol: `.metadata` y `pubspec.lock` modificados, `installer/` sin seguimiento.

Fiabilidad de los hallazgos:
- **(V)** verificado leyendo el código o ejecutándolo en esta sesión.
- **(R)** lo reportó la revisión; hay que confirmarlo antes de corregir.

Regla para cada corrección: primero un test que falle, luego el arreglo.
El test va en el archivo de pruebas del servicio, si ya existe.

---

## Fase 0 — Urgente

### [~] 1. Credenciales reales publicadas (V)
- **Evidencia:** `git grep Proyecto123 origin/main` devuelve:
  - `lib/main_preview.dart:22`
  - `lib/screens/desktop_login_screen.dart:25` (`this.initialPass = 'Proyecto123'`)
  - `lib/screens/login_screen.dart:120` (`_savedPass ?? 'Proyecto123'`)
  - URL `https://navidrome.templo.cloud` y usuario `Proyecto` en los mismos sitios.
  - Están en el historial desde `6dab55c`.
- **Impacto:**
  - Quien tenga acceso al repositorio o a cualquier APK, AppImage o instalador
    que se comparta puede entrar a ese Navidrome.
  - Ese usuario también sirve para autenticarse en Connect de `jam-server`.
- **Usuario:** cambiar la contraseña de `Proyecto` en Navidrome (no lo puede
  hacer el agente).
- **Código:**
  - Valores por defecto vacíos en los dos logins.
  - `main_preview.dart` lee URL, usuario y clave de `--dart-define`
    (`PREVIEW_URL`, `PREVIEW_USER`, `PREVIEW_PASS`) y, si faltan, muestra el
    login vacío.
- **Decisión pendiente:** si el repositorio es o será público, limpiar el
  historial con `git filter-repo`. Reescribe la historia: solo con permiso
  explícito.
- **Aceptación:**
  - `git grep -n "Proyecto123\|templo.cloud" -- lib test` vacío. Si algún
    test necesita una URL, usar `example.invalid`.
  - Test de widget: el login arranca con campos vacíos.

### [x] 2. El repositorio no compila desde un clon limpio (V)
- **Android:**
  - `.gitignore:51-57` ignora `res/values/*` y `res/drawable/*`.
  - Faltan en git `res/values/styles.xml` (`LaunchTheme` y `NormalTheme`,
    usados en `AndroidManifest.xml:36,46`), `res/drawable/launch_background.xml`,
    el `tv_banner` (`src/tv/AndroidManifest.xml`), `gradlew`, `gradlew.bat`
    y `gradle/wrapper/gradle-wrapper.jar` + `.properties`.
- **Linux:**
  - `git ls-files linux` devuelve solo `CMakeLists.txt` y
    `runner/my_application.cc`.
  - Faltan `runner/CMakeLists.txt`, `runner/main.cc`,
    `runner/my_application.h` y `linux/flutter/CMakeLists.txt`.
  - En esta copia tampoco existen; hay que regenerarlos con
    `flutter create --platforms=linux .` y conservar lo propio de Scrotify.
- **Windows:** `.gitignore:13` (`**/windows`) lo ignora entero.
- **`.metadata`:** el cambio sin commitear añade `windows` y **borra** la
  entrada `platform: android`. Restaurarla antes de commitear.
- **Arreglo:**
  - Reemplazar el bloque de ignores de plataformas por el `.gitignore`
    estándar de Flutter.
  - Versionar `android/` (sin `local.properties`, `key.properties`, `.gradle/`
    ni `app/build/`), `linux/` (sin `flutter/ephemeral/`) y `windows/`
    (sin `flutter/ephemeral/`).
- **Aceptación:**
  - `git clone` a una carpeta temporal y luego `flutter build linux`,
    `flutter build apk --flavor phone --debug` y `flutter build windows`
    compilan sin copiar nada a mano.
  - El punto 31 (CI) lo comprueba en cada push.

### [x] 3. `installer/` sin ignorar (V)
- **Problema:** `git check-ignore installer/output` no devuelve nada. Un
  `git add .` subiría `Scrotify-Setup-1.0.0.exe` (86 MB, por encima del límite
  de 50 MB de GitHub) y `installer/stage/` entero.
- **Arreglo:** ignorar `installer/output/` e `installer/stage/` y versionar
  `installer/scrotify.iss`.
- **Aceptación:** `git status --porcelain` muestra solo `installer/scrotify.iss`.

### [x] 4. En Windows se guardan rutas y nombres en minúsculas (V)
- **Causa:** `p.canonicalize` en Windows convierte toda la ruta a minúsculas.
- **Usos:**
  - `lib/services/offline_cache_service.dart:481,483,630-631,660-661,677-678,692-693,721,784`
  - `lib/services/local_music_service.dart:541`
  - `lib/services/offline_download_manager.dart:450`
- **Efecto visible:**
  - Una playlist recuperada aparece como «rock viejo» en vez de «Rock viejo»
    (`offline_library_test`).
  - La ruta guardada de una canción queda `...\playlist(rock)\canción.mp3`
    (`local_music_service_test.dart:104`). Hay que confirmar si el archivo se
    crea en disco con ese nombre.
  - `cachePath(...).startsWith(tempDir.path)` falla
    (`offline_cache_service_test.dart:54,384`).
- **Arreglo:**
  - Usar `canonicalize` solo para **comparar** (`p.isWithin` / `p.equals`) y
    guardar `p.normalize(p.absolute(path))`.
  - Un helper en `lib/utils/` (`normalizePathKeepCase`) para todas las llamadas.
  - Los nombres de playlist o carpeta que se muestran se leen de la ruta sin
    canonicalizar.
- **Datos ya guardados:**
  - Las rutas en minúsculas en índices existentes siguen funcionando, porque
    NTFS no distingue mayúsculas.
  - Pero los nombres recuperados de carpeta se ven mal: al cargar el índice,
    si el archivo existe, reconstruir la ruta real con
    `Directory.list` + `p.equals`.
- **Aceptación:** los 5 tests afectados pasan en Windows y siguen pasando en
  Linux (CI).

### [x] 5. Los otros 3 tests rojos en Windows (V)
- `offline_artwork_test.dart:66`: `Deletion failed ... El directorio no está
  vacío` / `está siendo utilizado por otro proceso`.
  - Queda algún `File`/`RandomAccessFile`/`IOSink`/base sqflite abierto al
    terminar el test, o lo deja abierto el propio servicio.
  - Buscar el handle (cerrar el servicio en `tearDown` antes de borrar).
  - Si el servicio no cierra lo que abre, es una fuga real: corregirla en `lib/`.
- `diagnostics_panel_test.dart`: «guardar escribe un archivo y vaciar limpia
  el registro». Pasa a veces y depende de `Future.delayed`
  (`diagnostics_panel_test.dart:64`). Esperar la condición, no un tiempo.
- La mezcla de separadores en tests (`'$tmp/Music\\a.flac'`) debe usar `p.join`.
- **Aceptación:** `flutter test` en Windows = 0 rojos; documentar el comando
  sin `| tail` (o con `set -o pipefail`).

---

## Fase 1 — Seguridad

### [x] 6. El invitado de Jam en LAN filtra su token Subsonic (V)
- **Dónde:** `lib/services/jam_guest_service.dart:1004` envía
  `'albumArtUrl': track.albumArtUrl` sin limpiar.
  - La URL de carátula lleva `u`, `s` y `t` (`navidrome_service.dart:375-381`).
  - La ruta remota sí la limpia (`jam_controller.dart:466`, `sanitizeArtUrl`).
- **Impacto:**
  - El anfitrión obtiene un par `t`/`s` válido para toda la API Subsonic
    del invitado.
  - También le sirve para autenticarse en Connect de `jam-server`, que cachea
    pares válidos 5 min (`jam-server/src/navidrome-auth.js:22-40`).
- **Arreglo:**
  - Usar `trackToJamJson` / `sanitizeArtUrl` en la línea 1004.
  - Mismo cambio en Connect: `lib/services/connect/track_codec.dart:11`
    (va cifrado y entre dispositivos del mismo usuario, pero mejor no mandarlo).
  - Buscar con grep cualquier otro `albumArtUrl` que se serialice hacia la red.
- **A estudiar:** no guardar `u`/`s`/`t` en `Track.albumArtUrl` y firmar la
  URL al pedir la imagen. Es un cambio más amplio: dejarlo como subtarea
  aparte si se decide.
- **Aceptación:**
  - Test: el mensaje `add_to_queue` del invitado no contiene `t=`, `s=` ni `u=`.
  - Test equivalente para el codec de Connect.

### [ ] 7. Emparejamiento por código sin autenticar al PC (R)
- **Dónde:** `lib/services/pairing_client.dart:227` (`http://$host:$port/pair/claim`).
  - El móvil manda un `find` por UDP y acepta el primer `here` que responda.
- **Ataque:** un equipo en la misma red responde antes, recibe el código de
  6 caracteres y lo usa contra el PC real con su propia clave.
- **Arreglo:**
  - Derivar el código de emparejamiento de una huella de la clave efímera
    del PC, o añadir a lo que el usuario teclea 2–4 caracteres de esa huella.
  - El cliente verifica la clave del servidor antes de enviar nada.
  - El QR ya puede llevar la huella completa.
- **Aceptación:** test con un «PC falso» que responde primero: el cliente
  rechaza la clave y no envía el claim.

### [ ] 8. Tráfico en claro permitido en toda la app (V/R)
- **Dónde:** `android/app/src/main/AndroidManifest.xml:30`
  (`usesCleartextTraffic="true"`).
- **Arreglo:**
  - `res/xml/network_security_config.xml` con `cleartextTrafficPermitted`
    solo para rangos privados.
  - Android no admite CIDR, así que la alternativa es mantener HTTP permitido
    pero exigir confirmación explícita en la UI (ya existe
    `cleartext_url_warning`) y guardar ese consentimiento por servidor.
- **Decisión de diseño:** listar las opciones antes de implementar.

### [x] 9. Copias de seguridad de Android (R)
- **Problema:** no hay `android:allowBackup` ni `dataExtractionRules` en
  `<application>`. Base sqflite, preferencias y caché pueden ir a la copia en
  la nube o salir por `adb backup`.
- **Arreglo:** `allowBackup="false"` + `fullBackupContent="false"` +
  `dataExtractionRules` vacías.

### [ ] 10. Respaldo de credenciales en texto plano (R)
- **Dónde:** `lib/services/secure_storage.dart:51-89`.
  - El JSON de respaldo no lleva `chmod` en Windows.
  - `secureRead` (~l.103) lo consulta aunque el keyring funcione.
- **Arreglo:**
  - En Windows, cifrar con DPAPI (`CryptProtectData` vía `ffi`, que ya es
    dependencia).
  - Al escribir con éxito en el keyring, migrar y borrar el respaldo.
  - Aviso en Ajustes → Diagnóstico cuando se está usando el respaldo.
- **Aceptación:** tests de migración (respaldo presente + keyring OK →
  respaldo borrado).

### [ ] 11. El anfitrión Jam en LAN no limita los mensajes (R)
- **Dónde:** `lib/services/jam_host_service.dart:~405-410` hace `utf8.decode`
  + `jsonDecode` del frame tal como llega.
- **Arreglo:**
  - Rechazar y cerrar (1009) frames de más de 64 KB.
  - Timer de saludo de 5 s: si un socket no manda `join_request`, se cierra
    (ver también el punto 23).
- **Aceptación:** test con un frame de 1 MB: el socket se cierra y el anfitrión
  sigue atendiendo a los demás.

### [ ] 12. Emparejamiento: datos expuestos y bloqueo global (R)
- **Datos expuestos:** el `discover` (`pairing_server.dart`, final de
  `_handleDiscoveryDatagram`) y `/pair/status` exponen `serverUrl`. Quitarlo.
- **Bloqueo global:**
  - 5 claims fallidos cierran toda la sesión (`_maxFailedClaims`): cualquiera
    en la red puede cortar el emparejamiento.
  - Contar fallos por IP (y por remitente en el relé).
  - Cerrar la sesión solo al superar un total alto (p. ej. 50) o al expirar.
- **Timer de cierre:** `pairing_server.dart:260,401`
  (`Future.delayed(500ms, stop)`) puede cerrar una sesión nueva. Usar un
  `Timer` cancelable o un contador de generación.

### [ ] 13. Bloqueo de PIN de Jam LAN sin distinguir IP (R)
- **Dónde:** `jam_host_service.dart:456-462` + `jam_security.dart:13-33`.
  - 10 fallos por minuto de cualquiera bloquean todas las uniones, incluidas
    las reconexiones con token válido.
- **Arreglo:**
  - Contar por `remoteAddress`.
  - La ruta `participantId + reconnectToken` no pasa por el bloqueo de PIN.

### [ ] 14. jam-server: primer admin sin protección (R)
- **Problema:** `docker-compose.yml:8` deja `ADMIN_PASSWORD` vacío y
  `admin.js` acepta `POST /admin/api/setup` mientras no haya admin. Tras
  desplegar, cualquiera puede apropiarse del panel y cambiar `navidromeUrl`.
- **Arreglo:**
  - Si no hay `ADMIN_PASSWORD`, generar un token de un solo uso, escribirlo
    en el log al arrancar y exigirlo en `/setup`.
  - Test con `node --test`.
- **Menor:** `admin.js:75`. El flag `Secure` de la cookie depende de
  `x-forwarded-proto` aunque `trustProxy=none`; respetar `trustProxy`.

---

## Fase 2 — Reproducción y cola

### [x] 15. Un corte de red vacía la cola (V)
- **Dónde:** `lib/services/player_stats.dart:228-232`. `_currentMostPlayedSession`
  devuelve `null` si `!_service.connected`, y `_onServiceChanged` (l.249-252)
  hace `clearQueue()` + `_recentlyPlayed.clear()` cuando la sesión cambia.
  - Pasar de conectado a desconectado cuenta como cambio de sesión.
- **Arreglo:**
  - La sesión depende solo de `serverUrl|username`.
  - `connected` no influye.
  - Limpiar la cola solo si cambia el servidor o el usuario.
- **Aceptación:** test con un servicio falso: conectado → desconectado →
  conectado deja la cola y la pista actual intactas; cambiar de usuario sí
  la limpia.

### [ ] 16. Scrobbles perdidos (R)
- **Desde playlists:** en `player_stats.dart:41-45` solo se llama a
  `_recordPlaylistPlay`, y `_recordTrackPlay` (l.137) sale antes si hay
  `_sourcePlaylist`.
- **Sin conexión:** `navidrome_library.dart:569` (`if (!_connected) return;`)
  los descarta.
- **Arreglo:**
  - Scrobble siempre; la estadística de la playlist va aparte.
  - Cola persistente por perfil (`scrobble_queue_<scope>.json`, escritura
    atómica) con `time=` original. Se vacía al reconectar, por lotes, en orden.
- **Aceptación:**
  - Test: una pista desde playlist genera scrobble.
  - Test: tres scrobbles offline se envían al reconectar con su timestamp.

### [x] 17. `addNextInQueue` no descarta la precarga (V)
- **Dónde:** `lib/services/player_queue.dart:87-94`. Inserta en `_order` sin
  `_cancelFade()` / `_prepareNextForSkip()`.
- **Efecto:** el reproductor B ya tenía cargada la siguiente pista;
  `_playPreparedNext` (`player_transitions.dart:166`) mueve `_pos` a la pista
  insertada pero suena la anterior.
- **Arreglo:** hacer lo mismo que `removeFromQueue` / `reorderQueue`.
  Revisar también `addAllToQueue`.
- **Aceptación:** test con reproductores falsos: precargar, insertar, avanzar →
  suena la pista insertada.

### [x] 18. `toggleShuffle` revive pistas quitadas y desincroniza `_pos` (V)
- **Dónde:** `player_queue.dart:171-180` reconstruye con `List.generate(n)`
  sobre todo `_queue`, pero `removeFromQueue` solo quita de `_order`.
  - Al activar el aleatorio no fija `_pos`.
- **Arreglo:**
  - Rehacer el orden solo con los índices vivos de `_order`.
  - Después, `_pos = _order.indexOf(cur)`.
  - De paso, decidir si `removeFromQueue` debe compactar `_queue` (fuga leve,
    punto 39).
- **Aceptación:** test: quitar 2 pistas, activar y desactivar el aleatorio →
  siguen fuera y la pista actual no cambia.

### [ ] 19. La barra de progreso sigue al reproductor viejo tras un crossfade (R)
- **Dónde:**
  - `player_controller.dart:552`: `positionStream` devuelve
    `_lead.positionStream` del momento en que alguien se suscribe.
  - `widgets/player_position_builder.dart:128-135`: solo se vuelve a
    suscribir al cambiar karaoke.
- **Arreglo:**
  - Stream estable del controlador: `BehaviorSubject` alimentado por el `lead`
    actual, o un `leadGeneration` + `switchMap` de rxdart (ya es dependencia).
- **Aceptación:** test: crossfade y luego seek → el stream emite la nueva
  posición.

### [ ] 20. `playQueue` / `addAllToQueue` sin protección (R)
- **Dónde:** `player_queue.dart:25,75,98`: `await _loadTrackOn` sin try ni
  `_loadGen`.
- **Efecto:** sin red o con dos toques rápidos queda la cola cambiada, sin
  `notifyListeners` y sin vigilancia.
- **Arreglo:** el mismo patrón que `_loadCurrentAndPlay`.

### [ ] 21. Temporizador de apagado (R)
- **Dónde:** `player_sleep_timer.dart:83-108`.
- **Problemas:**
  - El fundido de 5 s ignora la cancelación.
  - No se detiene en `dispose`.
  - Si cambia el `lead`, baja el volumen del reproductor equivocado.
- **Arreglo:** token de cancelación y `identical(_lead, p)` en cada paso.

### [ ] 22. Otros de reproducción (R)
- `player_transitions.dart:295-301`: `_beginFadeRamp` puede dejar
  `_fading = true` (salida por `fadeDur < 50ms` o `!_preloaded`), y eso
  bloquea `setVolume` y los crossfades siguientes.
- `player_karaoke.dart:22`: cada evento de posición hace `notifyListeners()`,
  lo que dispara `syncFromPlayer`, que reconstruye toda la cola de `MediaItem`
  (`scrotify_audio_handler.dart:240-252`). Notificar solo cuando cambia la
  línea; reconstruir la cola solo si cambió.
- `hifi/hifi_coordinator.dart:144,165`: `refresh` sin generación y con
  `notifyListeners` posible tras `dispose`.
- `player_controller.dart:976`: el salto en karaoke usa siempre streaming y
  falla sin conexión. Usar `localFileResolver`.

---

## Fase 3 — Descargas y red

### [ ] 23. Pausar y reanudar rápido corrompe la descarga (R)
- **Dónde:** `offline_download_manager.dart:577-588,618-626,795-797,969`.
  - La descarga vieja borra el `.tmp` de la nueva.
  - El `finally` quita el token de la nueva.
- **Arreglo:**
  - Temporal único por intento (`<key>.<attemptId>.tmp`).
  - Quitar el token solo si es el propio:
    `if (identical(_activeCancellations[key], cancelToken))`.
- **Aceptación:** test con `fake_async`: pausar y reanudar sin esperar → una
  sola descarga termina y sigue siendo cancelable.

### [ ] 24. Timeout de toda la transferencia en lugar de inactividad (R)
- **Dónde:** `navidrome_library.dart:523` (`completer.future.timeout(30s)`).
  - Un FLAC grande en red lenta falla siempre y reintenta desde 0.
- **Arreglo:**
  - Timeout por fragmento: `response.stream.timeout(idle)`, 30 s sin datos.
  - Reanudar con `Range` si el servidor lo admite (Navidrome sí, con `raw`).
    Si no, empezar de 0.

### [ ] 25. Un error de Subsonic guardado como audio (R)
- **Problema:** `stream.view` puede responder 200 con JSON o XML de error.
  - Solo se mira el código (`navidrome_library.dart:450`) y que el tamaño no
    sea 0 (`offline_download_manager.dart:803`).
- **Arreglo:**
  - Rechazar `Content-Type` `application/json`, `*/xml` y `text/*`.
  - Comprobar los primeros bytes (`{`, `<?xml`) antes de dar el archivo
    por bueno.

### [ ] 26. Peticiones sin timeout ni comprobación de estado (R)
- **Dónde:**
  - `navidrome_library.dart:126,177,210,240,553,585`
  - `navidrome_playlists.dart:26,70,152…`
  - `navidrome_favorites.dart:40,62,290`
  - `artist_screen.dart:57-95`
- **Arreglo:**
  - Helper `_getJson(uri, {timeout})` en `NavidromeService` con `.timeout`.
  - Comprobar `statusCode` y `Content-Type` antes de `jsonDecode`.
  - Error tipado (`SubsonicException`) con el `code` de Subsonic.
  - Migrar todas las llamadas.

### [ ] 27. Compatibilidad con otros servidores Subsonic (R)
- **Dónde:** `navidrome_library.dart:246` (`(entries as List)`) falla cuando
  Subsonic/Airsonic devuelve un objeto suelto (álbum de una pista).
- **Arreglo:**
  - Usar `_asList`, que ya existe.
  - Buscar con grep todos los `as List` y `as String` sobre respuestas de la API.
- **Aceptación:** tests con respuestas mínimas: un elemento suelto,
  campos opcionales ausentes.

### [ ] 28. Waveform: red innecesaria y fuga del token (R)
- **Dónde:**
  - `player_controller.dart:491` usa `getStreamUrl` aunque la pista esté
    descargada.
  - `audio_waveform_service.dart:230` mira el tamaño **después** de bajar
    todo a memoria.
  - `audio_waveform_service.dart:243` hace `'Audio download failed: $e'`.
    El `ClientException` incluye la URI con `u/t/s`, y
    `player_controller.dart:507` lo imprime con `debugPrint`, que no pasa por
    `redactSecrets`.
- **Arreglo:**
  - Usar el archivo local si existe.
  - Cortar por `contentLength` antes de descargar.
  - Cancelar al cambiar de pista.
  - Pasar el error por `redactSecrets`.

### [ ] 29. Historial y estadísticas (R)
- **Historial:**
  - `player_stats.dart:122`: `_saveHistory` escribe sin `.tmp` ni rename, y
    sin serializar las escrituras.
  - `_loadHistory` se llama dos veces en el constructor (l.653,655).
  - Si no hay archivo del perfil, carga el `recently_played.json` global de
    otro servidor.
  - **Arreglo:** escritura atómica (copiar el patrón de
    `listening_stats_service.dart:482`), cola de escrituras, generación, y no
    usar el archivo global.
- **Estadísticas:**
  - `listening_stats_service.dart:192-193`: los eventos crecen sin límite y
    se reescribe el JSON entero en cada reproducción.
  - Compactar por día pasados N días o pasar a sqflite (ya es dependencia).
  - `_filteredEvents` con perfil vacío muestra eventos de otros perfiles
    (l.205-206).

### [ ] 30. Caché offline sin límite (R)
- **Problema:** no hay tope de tamaño ni desalojo en `offline_cache_service.dart`.
- **Arreglo:**
  - Ajuste «tamaño máximo de caché de streaming».
  - Desalojar por LRU solo lo cacheado al escuchar, nunca lo descargado
    explícitamente.

---

## Fase 4 — Jam, Connect y Sync

### [x] 31. «Terminar» una Jam remota no cierra la sala (R)
- **Dónde:** `remote_jam_service.dart:666-676`, `jam-server/src/server.js:481-487,779-800`.
  - El servidor no tiene acción para cerrar la sala.
  - Lo trata como caída: `host_away`, espera de 60 s y nombra anfitrión a
    un invitado.
- **Arreglo:**
  - Acción `close_room` → `closeRoom(room)`.
  - El cliente la envía en `leaveOrEndSession` antes de `disconnect()`.
- **Aceptación:**
  - Test `node --test`: `close_room` notifica a los invitados y borra la sala.
  - Test Dart: el mensaje se envía.

### [x] 32. El invitado remoto no envía la contraseña de la sala (V)
- **Dónde:** `remote_jam_service.dart:345-349` (`{action, pin, guestName}`),
  aunque `jam_join.dart:323` guarda `roomPassword`.
- **Arreglo:** añadir `'roomPassword'`.
- **Aceptación:**
  - Test Dart del mensaje.
  - Test del servidor: la sala con clave admite la clave correcta.

### [ ] 33. El anfitrión LAN echa al invitado antes de que acabe la gracia (R)
- **Dónde:** `jam_host_service.dart:855-864` desaloja a los 25 s
  (`pingInterval + pongTimeout`), pero `disconnectGracePeriod` es de 30 s
  (l.101).
- **Arreglo:**
  - No desalojar a quien está en `_graceTimers`.
  - Garantizar `grace > hostSilenceTimeout + backoff máximo` con un `assert`
    o un test.

### [ ] 34. Reconexión del invitado LAN (R)
- **Dónde:** `jam_guest_service.dart:920-983`.
- **Problemas:**
  - No tiene límite de intentos.
  - Decide si rendirse buscando 'inválido' o 'expirada' en el texto del error
    (l.975-977).
  - Un `join_response` tardío deja un socket viejo vivo (l.825, 945, 534-575).
- **Arreglo:**
  - Códigos de rechazo tipados en el protocolo (`reason: 'bad_pin' | 'expired' | 'rate_limited' | ...`).
  - Tope de 5 min o N intentos.
  - `_teardownSocket()` al vencer el timeout.
  - Cancelar `_reconnectTimer` al aceptar.

### [ ] 35. El cliente remoto (relé) no detecta caídas (R)
- **Dónde:** `remote_jam_service.dart:157,202-207,291,335-340`.
  - Sin `pingInterval`.
  - `onDone` solo baja una bandera.
- **Arreglo:**
  - `IOWebSocketChannel.connect(..., pingInterval: 15s)`.
  - Callback `onDisconnected` y reconexión con backoff exponencial + jitter
    (reutilizar la lógica del invitado LAN).
  - Avisar en la UI.

### [ ] 36. Connect (R)
- `connect/lan_transport.dart:272-309`: listener `async`. Un frame que llega
  durante `await crypto.decrypt(hello)` se procesa con `peer == null` y cierra
  el socket. Procesar los frames en serie (`StreamQueue` o una cadena de
  `Future`).
- `connect/relay_transport.dart:23,127-128`: reintento fijo de 5 s. Usar
  backoff exponencial con jitter y tope de 60 s; si no, al reiniciar el
  servidor todos chocan con el límite de `connect.js:96`.

### [ ] 37. jam-server (R)
- `server.js:422-433`: `closeRoom` no avisa al socket del anfitrión ni borra
  `socketRooms`.
- `guard.js:11-16`: por encima de 5000 claves, `prune()` recorre los mapas en
  cada intento. Podar por intervalo.
- `Dockerfile:22`: `CMD ["npm","start"]` → `CMD ["node","src/server.js"]`.
- Healthcheck con el puerto 8080 fijo: usar `${PORT}`.

### [ ] 38. Sync y modelos (R)
- `sync_service.dart:395`: decide conflictos comparando el mtime local con el
  `updatedAt` remoto, que son relojes de dispositivos distintos. Usar versión
  o contador por documento.
- `sync_service.dart:388,449-462`: tras purgar los tombstones, un dispositivo
  que estuvo offline vuelve a subir temas borrados. No hacer push si existe
  estado local con hash igual y falta el remoto.
- `jam_models.dart:391-392`: un elemento mal formado descarta el snapshot
  entero. Usar `tryParse` por elemento y registrar en `DiagnosticsLog`.
- `jam_clock.dart:24-25`: medir el RTT con `Stopwatch` (monotónico).

---

## Fase 5 — UI y rendimiento

### [ ] 39. Reconstrucciones amplias (R)
- **`PlayerController`:** `_onPlayerState` (`player_controller.dart:702`)
  notifica en cada cambio de estado, y lo escuchan:
  - `home_screen_content.dart:212,257,447,759`
  - `mobile_home_tab.dart:147,601`
  - `track_context_menu.dart:46`
- **`NavidromeService`:** lo escucha la pantalla de inicio entera
  (`home_screen.dart:207`, `mobile_home_screen.dart:348`).
- **Arreglo:** `context.select` por campo (`currentTrack?.id`, `isPlaying`,
  `mostPlayed`, `currentSessionKey`, `coverArtVersion`).
- **Aceptación:** medir con DevTools (rebuild counts) antes y después;
  anotar los números en la bitácora.

### [ ] 40. Listas e imágenes (R)
- `ListView(children:)` con listas grandes:
  - `home_screen_library.dart:48,218`
  - `mobile_search_library_tabs.dart:107,211`
  - Pasar a `SliverList.builder`.
- `GridView` con `shrinkWrap`:
  - `artist_screen.dart:603`
  - `home_screen_content.dart:276,497`
  - `mobile_home_tab.dart:163`
  - Pasar a slivers.
- `NetworkImage` sin reducir:
  - `album_detail_screen.dart:76`
  - `artist_screen.dart:147,631`
  - `settings_screen.dart:740`
  - `mobile_home_tab.dart:457,561`
  - `account_avatar.dart:89`
  - Usar `CoverArt` o `ResizeImage.resizeIfNeeded` (como `cover_art.dart:162`).
- `waveform_progress_bar.dart:182`: `_pulse.repeat` sigue en pestañas ocultas
  de un `IndexedStack`. Envolver en `TickerMode`.

### [ ] 41. Async en la UI (R)
- `setState` tras `await` sin `mounted`:
  - `album_detail_screen.dart:147`
  - `artist_screen.dart:582`
  - Confirmar también `playlist_actions_panel`, `add_playlist_tracks_dialog`,
    `mobile_home_screen` y `pairing_join_panel`.
- `mobile_login_screen.dart:101`: `context` usado después de la biometría.
- `FutureBuilder` con `snapshot.data ?? []` sin estado de error ni de carga
  (`home_screen_library.dart:42`, entre otros). Usar `AppErrorBox` + esqueleto.

### [ ] 42. Imagen de artista desde terceros (R)
- **Dónde:** `artist_screen.dart:57-95` manda el nombre del artista a
  TheAudioDB y Deezer, sin timeout y desde el widget.
- **Arreglo:**
  - `ArtistImageService` con caché.
  - Primero `getArtistInfo2` de Navidrome (idea 46).
  - Terceros solo con un ajuste de opt-in.

### [ ] 43. Duplicación entre móvil y escritorio (R)
- **Dónde:** `home_screen.dart:100-225` y `mobile_home_screen.dart:110-360`
  repiten carga, búsqueda y reinicio por sesión.
- **Arreglo:**
  - `HomeDataController` (ChangeNotifier, registrado en `main.dart`) con la
    lógica.
  - Las pantallas solo maquetan.
- **Más adelante:** lo mismo para los dos logins.

### [ ] 44. Accesibilidad (R)
- Unos 54 de 113 `IconButton` no tienen `tooltip`
  (`persistent_player_bar.dart`: 3 de 11).
- Solo hay 8 `Semantics`.
- Áreas de toque menores de 48 dp (`VisualDensity.compact`, `Size.zero`);
  iconos de 15 px en `persistent_player_bar.dart:292`.
- **Aceptación:** test con `meetsGuideline(androidTapTargetGuideline)` y
  `labeledTapTargetGuideline` en el reproductor y la pantalla de inicio.

---

## Fase 6 — Build, CI y dependencias

### [x] 45. CI que compile todas las plataformas (V)
- **Problema:** `.github/workflows/ci.yml` solo tiene jobs en ubuntu.
- **Añadir:**
  - Job Android: `setup-java` 17, `flutter build apk --flavor phone --debug`.
  - Job `windows-latest`: `flutter test` + `flutter build windows`. Así se
    habrían detectado los puntos 2 y 4.
- **Otros cambios:**
  - Fijar `flutter-version` igual en CI y en local (CI 3.47.4, local 3.47.5;
    explica el diff de `pubspec.lock`).
  - Cachear los paquetes apt.
  - Revisar si sobra `libayatana-appindicator3-dev`.
- **Pendiente:** confirmar el resultado real del job `linux-smoke`.

### [!] 46. Firma y `applicationId` (sigue de la tanda 3, ítems 7 y 8)
- **Firma:** `android/app/build.gradle.kts:74-76` firma el release con la clave
  debug y solo avisa. Que `assembleRelease` falle si falta `key.properties`,
  salvo con `-PallowDebugSigning`.
- **ID de la app:** `com.example.navidrome_client` también aparece en
  `linux/CMakeLists.txt:10` y `tool/run_android_integration.sh:12`.
  Cambiarlo junto con la firma.
- **Release:** `isMinifyEnabled` + `isShrinkResources`, con reglas ProGuard
  para media_kit y audio_service. Probar en un dispositivo.

### [!] 47. Permisos de Android
- `MANAGE_EXTERNAL_STORAGE` (Manifest l.16): Play lo restringe. Decidir si se
  publica en Play.
- `requestLegacyExternalStorage` (l.26): no hace nada con targetSdk ≥ 30.
  Quitarlo.

### [ ] 48. Dependencias
- Pendientes de la tanda 3 (necesitan dispositivo):
  - `just_audio` 0.9.46 → 0.10.6 + `audio_session` 0.2 (reaplicar
    `third_party/just_audio_media_kit/SCROTIFY_PATCH.md`).
  - `mobile_scanner` 5 → 7.
- `flutter_lints` 3 → 6 y lints nuevos:
  - `avoid_dynamic_calls` (unos 326 `dynamic` en `lib/`; empezar como warning
    por archivos).
  - `prefer_final_locals`, `avoid_slow_async_io`.
- `cupertino_icons` 2.
- `sdk: '>=3.0.0'` → mínimo real (la copia local de `just_audio_media_kit`
  exige `>=3.1.3`; propuesta `>=3.5.0 <4.0.0`).
- `json_annotation`, `build_runner` y `json_serializable` no se usan.
  - Opción A: quitarlos y corregir AGENTS.md.
  - Opción B: empezar a usarlos en los modelos de Jam.
  - **Decidir.**
- Quitar del `analysis_options.yaml` la exclusión `Eculiza/**` si ya no existe.

### [ ] 49. Tests frágiles y cobertura
- 52 `Future.delayed` en `test/`: pasarlos a `fake_async` o
  `tester.pump(d)`, o esperar la condición concreta. Prioridad:
  - `diagnostics_panel_test.dart:64`
  - `equalizer_service_test.dart:121`
  - `jam_test.dart:333,471`
  - `jam_guest_history_test.dart:225,228`
- Sin tests: `cover_fallback_service.dart`, `mini_player_controller.dart`.
- Que el CI no esconda los fallos: `set -o pipefail` en cualquier paso con
  pipes.

### [ ] 50. Empaquetado de Windows y documentación
- `installer/scrotify.iss`:
  - Versión leída de `pubspec.yaml` (`/DAppVersion=` desde un script).
  - `SetupIconFile`.
  - Comprobar o incluir el VC++ Redistributable.
  - `AppPublisherURL`.
- `scripts/build_windows_installer.sh`: `flutter build windows` → copiar a
  `stage/` → `iscc`, con `BuildInfo` (commit y fecha) como en los otros
  scripts.
- `.gitattributes`: `*.sh text eol=lf`.
- `tool/run_android_integration.sh:11`: `ANDROID_SDK_ROOT` por defecto
  según el sistema.
- README: compilar Android (sabores phone/tv, `key.properties`), Windows
  (instalador) y Linux (AppImage). Quitar la mención a iOS mientras no
  exista `ios/`.

---

## Fase 7 — Funciones nuevas (cada una con su mini-spec antes de empezar)

Verificado con grep que no existen. Tamaño estimado: S pequeño · M medio · L grande.

| # | Idea | API / base | Tamaño |
|---|---|---|---|
| 51 | Radio por artista o canción | `getSimilarSongs2`, `getTopSongs` | S |
| 52 | Cola que se conserva al reiniciar y entre dispositivos | `savePlayQueue` / `getPlayQueue` | S |
| 53 | Biografía y artistas similares (sustituye a TheAudioDB/Deezer, ver 42) | `getArtistInfo2` | S |
| 54 | Tema de colores según la carátula | `ColorScheme.fromImageProvider` + `ThemeController` | S |
| 55 | Marcadores en pistas largas | `createBookmark` / `getBookmarks` | S |
| 56 | Discord Rich Presence (escritorio) | IPC local de Discord | S |
| 57 | Controles del sistema: SMTC (Windows), MPRIS (Linux), atajos globales | `audio_service`/plugins + `hotkey_manager` | M |
| 58 | Android Auto | `getChildren` en `ScrotifyAudioHandler` | M |
| 59 | Playlists inteligentes (reglas locales; NSP de Navidrome) | consultas locales + API | M |
| 60 | Búsqueda con filtros y orden (año, género, formato, favoritas) | `search3` + filtros locales | M |
| 61 | Radios por internet y podcasts | `getInternetRadioStations`, `getPodcasts` | M |
| 62 | Envío a Chromecast o DLNA | plugin cast + URL de stream | L |

Otras propuestas de la revisión, sin prioridad: router declarativo
(`go_router` con `ShellRoute`) para tener deep links a álbumes y artistas,
localización (punto 18 de la tanda 3) y partir `track_context_menu.dart`
(1090 líneas) y `settings_screen.dart` (1057).

---

## Orden
1 (usuario) → 3 → 2 → 4, 5 → 45 → 6 → 15 → 32 → 17, 18 → 23, 25 → 31, 33 →
resto de la Fase 1 → resto de las Fases 2–4 → 39–44 → 46–50 → Fase 7.

Motivo: primero lo que expone datos o impide compilar, después que Windows
quede en verde y vigilado por el CI. Luego los fallos que el usuario ve
(cola vaciada, salas con contraseña, desincronización), y al final la
robustez y las funciones nuevas.

## Definición de terminado (por ítem)
- Test que falla antes y pasa después (salvo los cambios solo de build o
  documentación).
- `flutter analyze` 0 issues.
- `flutter test` verde en **Windows y Linux** (CI).
- `cd jam-server && npm test` verde si se tocó el servidor.
- Commit por ítem; una línea en la bitácora con commit y lo que quedó sin
  probar en un dispositivo real.

## Bitácora

- 2026-10-15 — Fase 0 y parte de 1–4 (Windows: `flutter test` 884 verdes, 0 rojos).
  - 1 (código): sin credenciales por defecto en los logins; `main_preview.dart` usa `--dart-define`. **Pendiente del usuario:** cambiar la clave en Navidrome y decidir `git filter-repo`.
  - 2: android/linux/windows versionados; `flutter build windows --debug` compila. Falta comprobar APK y Linux desde un clon limpio (lo vigila el CI).
  - 3: `installer/output` y `installer/stage` ignorados.
  - 4/5: `normalizePathKeepCase`; fuga de `LocalMusicService` en reescaneo tras `dispose`; `ThemeController` notificaba tras `dispose`. El borrado del temporal en `offline_artwork_test` es de mejor esfuerzo en Windows (el decodificador de imágenes retiene el archivo).
  - 6, 32: `addToQueueTrackJson`/codec de Connect con `sanitizeArtUrl`; `roomPassword` en `join_room`.
  - 15, 17, 18: cola intacta ante cortes de red; precarga descartada al insertar; `removeFromQueue` compacta `_queue`; `toggleShuffle` fija `_pos`. Harness nuevo `test/support/fake_audio_player.dart`.
  - 31: `close_room` en jam-server (+2 tests `node --test`) y cliente (`disconnect(endRoom: true)`). Sin probar con un servidor real.
  - 9: `allowBackup=false` + reglas de extracción (sin probar en dispositivo). 47: quitado `requestLegacyExternalStorage`.
  - 37 (parcial): Dockerfile usa `node src/server.js` y healthcheck con `${PORT}`.
  - 45: CI con jobs `windows` y `android`, Flutter 3.47.5 fijo (no ejecutado aún).
  - Pairing: estado `paired` antes de responder; cierre con `Timer` cancelable (parte del 12).
