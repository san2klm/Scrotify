# CROTOLINK-ROADMAP — Plan de implementación autónoma para CrotoLink

> Archivo de instrucciones para Claude (Claude Code) trabajando en el repo de CrotoWave.
> Léelo completo antes de tocar código. Referencias: `crotowave.md` y `crotolink.md` (arquitectura actual).
> Idioma de código/commits: inglés. Comentarios de UI/strings: español (preparar para localización).

---

## 0. Cómo trabajar (reglas del agente)

1. **Una fase a la vez.** No empieces la fase N+1 hasta que la N cumpla sus criterios de aceptación.
2. **Rama por fase:** `crotolink/fase-N-nombre`. Commits pequeños y atómicos (`feat(crotolink): ...`, `fix(crotolink-server): ...`).
3. **Antes de cada commit:**
   - `flutter analyze` → 0 errores, 0 warnings.
   - `flutter test test/crotolink_test.dart test/crotolink_ui_recovery_test.dart` + los tests nuevos.
   - En `crotolink-server/`: `npm install && node --test test/server.test.js`.
4. **Tests primero** para lógica pura (orden de cola, votos, round-robin, offset de reloj, matching).
5. **No romper compatibilidad:** los clientes viejos deben seguir uniéndose a salas nuevas (campos nuevos opcionales, `op` desconocidos se ignoran). Subir `protocolVersion` y negociar en `join`.
6. **Principios innegociables (de crotowave.md / crotolink.md):**
   - Cero telemetría. El servidor no guarda qué escucha la gente.
   - **Nunca** retransmitir audio por CrotoLink (el proxy de stream, si se hace, es módulo opt-in aparte, Fase 8).
   - **Nunca** enviar credenciales Subsonic (`u`, `t`, `s`, `p`, `apiKey`) por la red; usar `sanitizeArtUrl`.
   - Mensajes WS ≤ 16 KB (`fitStateToMessageLimit`).
7. **Open source:** no hardcodear dominios/secretos. `jam.templo.cloud` pasa a ser solo el *valor por defecto* de un ajuste.
8. **Reparto de responsabilidades:**
   - **Cliente (APK/EXE):** lógica de cola, UI, reproducción, historial, matching, sync de reloj.
   - **Servidor Docker (`crotolink-server`):** estado compartido y autoridad neutral (salas persistentes, límites, rate limit por IP, tiempo de referencia, landing de enlaces). Configurable por **panel web `/admin`**.
   - **Navidrome:** lo que ya resuelve su API (playlists, `savePlayQueue`, similares).
   - Regla: el **admin del servidor define el techo**, el **host de la sala elige dentro de él**.

---

## 1. Acceso a mi servidor (completar antes de empezar)

> Rellena/pide estos datos al usuario; **no inventes valores** ni los subas al repo.

```text
SERVER_SSH      = usuario@HOST            # ej. deploy@192.168.1.10
SERVER_PATH     = /ruta/a/crotolink-server      # donde vive docker-compose.yml
COMPOSE_CMD     = docker compose          # o docker-compose
PUBLIC_URL      = https://jam.templo.cloud
HEALTH_URL      = https://jam.templo.cloud/health
```

Reglas de despliegue:
- Guardar secretos solo en `.env` del servidor (fuera de git). Añadir `.env` y `/data` a `.gitignore`.
- **Antes de desplegar:** backup de `/data` (`tar czf data-$(date +%F).tgz data/`) y anotar el tag/imagen actual para rollback.
- **Despliegue:** `git pull` (o copiar build) → `docker compose build` → `docker compose up -d` → comprobar `curl $HEALTH_URL` (`{"status":"ok",...}`).
- **Rollback:** volver al tag anterior y `docker compose up -d`; restaurar `/data` solo si la migración lo exige.
- **Pide confirmación al usuario antes de:** borrar volúmenes/datos, `docker system prune`, tocar la config de Cloudflare Tunnel, cambiar DNS, o cualquier comando destructivo en el servidor.
- Nunca imprimir en logs ni en commits: contraseñas, hashes de admin, tokens.

---

## 2. Fase 1 — Ajuste "Servidor CrotoLink" + esqueleto del servidor administrable

**Objetivo:** que cualquiera pueda autohostear su relay y que el servidor sea configurable sin tocar código.

### Cliente
- Nuevo ajuste en `SettingsController`: `crotoLinkServerUrl` (default `wss://jam.templo.cloud/`). Validar esquema `wss://` (permitir `ws://` solo si es host local/privado, con aviso).
- `RemoteCrotoLinkService` y el radar Canal 3 (`GET /rooms`) usan ese ajuste (derivar `https://` desde `wss://`).
- UI en `settings_screen.dart`: campo + botón "Probar conexión" (`GET /health`) + restaurar valor por defecto.

### Servidor (`crotolink-server/`)
- Persistencia: **SQLite** (`better-sqlite3`) en `/data/crotolink.db`. Config en tabla `settings` (clave/valor JSON). Variables de entorno son el valor inicial; el panel las sobrescribe.
- **Panel `/admin`** (HTML+JS estático servido por el mismo proceso, sin framework pesado):
  - Login: `ADMIN_PASSWORD` por env, o asistente de primer arranque si no existe. Guardar solo hash (argon2/scrypt). Sesión por cookie `HttpOnly; SameSite=Strict`, rate limit al login.
  - Pestañas: **Estado** (salas, participantes, uptime, memoria), **Límites**, **Seguridad**, **Funciones**, **Salas persistentes**, **Logs**.
- API admin: `/admin/api/*` (JSON), protegida por sesión. CSRF token en mutaciones.
- Config editable (con valores por defecto actuales): `maxParticipants` (50), `maxRooms`, `maxMessageBytes` (16384), `roomIdleMs` (3600000), `maxQueueItems` (500), `publicListingEnabled`, `chatEnabled`, `persistentRoomsEnabled`, `webLinkEnabled`, `publicUrl`.
- Endpoint nuevo `GET /api/capabilities` → el cliente lo lee al unirse/crear para saber qué funciones están permitidas (el host ve solo lo que el admin habilitó).
- Docker: volumen `/data`, `HEALTHCHECK`, usuario no-root, `docker-compose.yml` actualizado (ver sección 11).

**Aceptación:**
- [ ] Cambiar la URL del servidor en la app y crear/unirse a una sala en otro relay.
- [ ] `/admin` protegido; cambiar `roomIdleMs` desde el panel se aplica sin reiniciar.
- [ ] Reinicio del contenedor conserva config; salas efímeras se pierden (esperado).
- [ ] Tests del servidor para login, rate limit de login y `GET /api/capabilities`.

---

## 3. Fase 2 — Modos de cola decididos por el host

**Objetivo:** el host elige al crear la sala (y puede cambiarlo en vivo) cómo se gestiona la cola. Lógica 100 % en cliente (el host es fuente de verdad; el relay solo reenvía).

### Modelo (`crotolink_models.dart`)
- `enum CrotoLinkQueueMode { free, fairTurns, voting, approval }`
- `CrotoLinkSessionState`: `queueMode`, `fairTurnsPerPerson` (int, default 1), `allowVoting`, `pendingRequests` (`List<CrotoLinkQueueRequest>`).
- `CrotoLinkQueueItem`: `votes` (int), `voters` (`Map<String,int>` participantId→±1; **no** serializar la lista completa si excede tamaño, enviar solo `votes` + `myVote` por cliente), `pinned` (bool).
- `CrotoLinkQueueRequest { id, track, requestedBy, requestedAt }`.

### Lógica (nuevo `lib/services/crotolink_queue_logic.dart`, funciones puras y testeables)
- **fairTurns:** reordenar los ítems no fijados intercalando por `addedBy.id` en bloques de `fairTurnsPerPerson`. Estable: respetar orden de llegada dentro de cada participante. No tocar el ítem en reproducción ni los `pinned`.
- **voting:** ordenar ítems no fijados por `votes` desc, desempate por `addedAt`. Un voto por participante por ítem (cambiar/quitar permitido). El host puede fijar/desfijar ítems.
- **approval:** `add_to_queue` de invitados crea un `CrotoLinkQueueRequest` en `pendingRequests` en vez de añadir. El host acepta/rechaza (individual o "aceptar todas"). Las aceptadas entran respetando, además, el orden de `fairTurns` si estuviera activo (combinable).
- Combinables: `approval` + `fairTurns`. `voting` es excluyente con `fairTurns` (documentar en UI).

### Protocolo (nuevos `op`; ignorados por clientes viejos)
| op | Dirección | Payload |
|---|---|---|
| `vote` | Invitado→Host | `itemId`, `value` (-1, 0, 1) |
| `propose_track` | Invitado→Host | `track` |
| `approve_request` | Host (local) | `requestId` |
| `reject_request` | Host (local) | `requestId`, `reason?` |
| `set_queue_mode` | Host (local) | `queueMode`, `fairTurnsPerPerson` |
| `pin_item` | Host (local) | `itemId`, `pinned` |
| `requests_updated` | Host→Todos* | `pendingRequests` (*invitados solo ven las suyas) |

- Todos pasan por `CrotoLinkRateLimiter` (cola: 10/10 s). Votos: máx. 1 voto efectivo por ítem; cambiar voto cuenta como operación.
- Incrementar `queueRevision` en cada reordenamiento.
- `fitStateToMessageLimit` debe contemplar los campos nuevos.

### UI
- `crotolink_dialog.dart` (pestaña Crear): selector de modo de cola + opciones (turnos por persona).
- `crotolink_queue_panel.dart`: botones ▲/▼ con contador (modo voting), icono de fijar (solo host), badge "pendiente" y bandeja de solicitudes para el host (modo approval).

**Aceptación:**
- [ ] Tests unitarios de `crotolink_queue_logic` (30 canciones de un usuario no monopolizan; empates; ítems fijados; reconciliación con `_rebuildHostQueueFromPlayer`).
- [ ] Un invitado con cliente viejo sigue añadiendo canciones en modo `free`.
- [ ] En modo `approval`, el invitado ve su propuesta "pendiente" y pasa a la cola al aceptarla.
- [ ] El reordenamiento no interrumpe la pista actual ni genera parpadeos.

---

## 4. Fase 3 — Historial de CrotoLink + guardar como playlist

**Objetivo:** lista de lo que sonó, quién lo añadió, y botón para guardarlo. Vive en el **cliente del host** (RAM); el servidor no guarda nada.

- `CrotoLinkHistoryEntry { track, addedBy, playedAt }` en `CrotoLinkController`. Se registra al cambiar de pista (solo si sonó ≥ 30 s o ≥ 50 %, mismo criterio que stats).
- Opcional: el host puede compartir el historial con invitados (`history_snapshot`), por defecto solo lo ve el host y se envía al cerrar la sesión.
- UI: pestaña "Historial" en la vista de sesión activa + botón **"Guardar como playlist"** → `createPlaylist.view` (nombre sugerido: "CrotoLink {fecha}"). Opción de filtrar por participante.
- Resumen de fin de sesión (mini-Wrapped): quién añadió más, pista más votada, duración total. Reutilizar `ListeningStatsService` si encaja.
- Los invitados pueden "Guardar mis aportaciones" en su propio servidor Navidrome (matching por Fase 6 si el servidor difiere).

**Aceptación:**
- [ ] Tras un CrotoLink de prueba, la playlist se crea en Navidrome con las pistas en orden.
- [ ] Pistas saltadas antes del umbral no aparecen.
- [ ] Tests del registro de historial.

---

## 5. Fase 4 — Seguridad: rate limit por IP, contraseña de sala, bans

### Servidor
- Rate limit por IP en `join_room` (ventana deslizante configurable desde `/admin`, p. ej. 10 intentos / 60 s) y bloqueo temporal progresivo tras N fallos de PIN. Respetar `CF-Connecting-IP` / `X-Forwarded-For` **solo** si viene de proxy de confianza (Cloudflare Tunnel); configurable.
- Lista de IPs bloqueadas manualmente (tabla en SQLite, gestionada desde el panel).
- No filtrar si un PIN existe o no ante intentos fallidos repetidos (misma respuesta genérica).

### Cliente / protocolo
- **Contraseña opcional de sala:** el host define `roomPassword`; se envía al relay solo su hash (scrypt/argon2 con sal por sala). `join_room` incluye la contraseña en claro **únicamente por canal TLS** y el servidor compara el hash. En LAN, validar en `CrotoLinkHostService`.
- **Ban persistente durante la sesión** por `participantId` (además de kick): el host mantiene `bannedIds`; relay y host rechazan reconexiones con ese ID/token. Documentar que un ban por ID es evadible; el ban por IP es solo del admin.

**Aceptación:**
- [ ] Fuerza bruta de PINs desde una IP queda bloqueada (test automatizado).
- [ ] Sala con contraseña rechaza sin ella, tanto en LAN como en nube.
- [ ] Un participante baneado no puede reconectar con su `reconnectToken`.

---

## 6. Fase 5 — Sincronización avanzada (modo escucha sincronizada)

### 5.1 Reloj tipo NTP
- Nuevo par `time_ping` / `time_pong` (cliente↔relay o host). Servidor responde `serverNowMs`.
- El invitado toma 5 muestras al unirse (y re-mide cada ~60 s): `offset = serverNow + rtt/2 - localNow`; usar la **mediana** de las muestras con menor RTT.
- El host sella `playback_updated.serverTimestamp` con hora de referencia (relay en nube; el propio host en LAN) y el invitado convierte con su `offset`.
- Sustituir `Δt_transit = clamp(T_local - T_server, 0, 5000)` por el cálculo con offset estimado; mantener el clamp como salvaguarda.

### 5.2 Corrección suave de deriva
- Si `|drift| ≤ 450 ms`: nada (como ahora).
- Si `50 ms < |drift| ≤ 450 ms` → ajustar velocidad `setSpeed(1 ± 0.02)` hasta converger y volver a 1.0 (solo en motores que lo soporten; si no, comportamiento actual).
- Si `|drift| > 450 ms`: `seek` (como ahora). Mantener `_syncGeneration`.
- Parametrizar umbrales en constantes `kCrotoLinkDrift*`.

### 5.3 Pre-carga coordinada
- Mensaje `next_track_hint { track, startAtServerMs }`: el host lo emite ~10 s antes del final; los invitados precargan en su reproductor secundario (A/B) y arrancan en `startAtServerMs`.

**Aceptación:**
- [ ] Test unitario del estimador de offset (muestras sintéticas con jitter).
- [ ] Prueba manual con 2 dispositivos: deriva media < 100 ms y sin saltos audibles en 10 min.
- [ ] Con el relay caído o sin `time_pong`, se degrada al algoritmo actual sin errores.

---

## 7. Fase 6 — Matching de pistas por metadatos (servidores distintos)

**Objetivo:** que dos personas con servidores Navidrome distintos puedan escuchar juntas.

- Ampliar `Track` canónico en el protocolo con: `mbid` (si existe), `isrc` (si existe), `title`, `artist`, `album`, `durationSec`, `trackNumber`.
- `CrotoLinkTrackResolver` (cliente, nuevo): dado un track remoto, buscar en **mi** servidor:
  1. Mismo `trackId` + coincidencia de metadatos (fast path, mismo servidor).
  2. MBID/ISRC (`search3` + filtrado por tags si disponibles).
  3. Normalizar (minúsculas, quitar acentos/paréntesis `feat.`/`remaster`) y comparar título+artista(s)+álbum con tolerancia de duración (±3 s).
  4. Si no hay match fiable → estado `unavailable`.
- Caché del resultado por sesión (`remoteId → localTrack?`).
- UI: ítems no resueltos se muestran atenuados con "No disponible en tu biblioteca"; en modo **sincronizada** se saltan automáticamente y se muestra un aviso discreto. En modo **altavoz de fiesta** no afecta (los invitados no reproducen).
- Opcional (Fase 8): proxy de stream.

**Aceptación:**
- [ ] Tests con casos reales: `feat.`, remasters, acentos, duración distinta.
- [ ] Sin falsos positivos en pistas homónimas de distinto artista (test).
- [ ] Rendimiento: resolver una cola de 100 pistas sin bloquear la UI (resolución perezosa/por lotes).

---

## 8. Fase 7 — Continuidad: transferencia de host, salas persistentes, enlace web

### 7.1 Transferencia de host (solo sala en nube)
- El relay mantiene la sala; el host original recibe un `hostToken` (128 bits) al crearla.
- `transfer_host { toParticipantId }` (host→relay) y `host_changed` (relay→todos). Si el host cae y no vuelve en `hostFailoverMs` (configurable en `/admin`), el relay puede promover al participante más antiguo con `canManageQueue` (solo si el host activó "failover automático").
- El nuevo host recibe el estado completo y asume el `PlayerController` en modo altavoz/sincronizado.
- En **LAN** el host es el servidor embebido: documentar limitación; ofrecer "migrar a la nube" (crear sala remota con el estado actual y avisar a los invitados con `migrate_to_remote`).

### 7.2 Salas persistentes / recurrentes
- Tabla `persistent_rooms { pin, name, ownerHash, idleExpiryMs, createdAt }` en SQLite.
- El **admin** puede crearlas desde `/admin`; si `persistentRoomsEnabled`, un host autenticado con su `ownerToken` puede reclamar el PIN fijo. Expiración configurable (por inactividad, o "nunca").
- Persistir solo configuración de la sala (PIN, nombre, permisos, modo de cola) — **no** historial de escucha.

### 7.3 Enlace web compartible
- Servidor: `GET /j/:code` → landing HTML mínima (si `webLinkEnabled`) que intenta abrir `crotowave://crotolink?...` y muestra instrucciones de instalación. Servir `/.well-known/assetlinks.json` y `apple-app-site-association` configurables desde `/admin`.
- Cliente: manejar App Links/Universal Links y el esquema `crotowave://`. Botón "Compartir enlace" en el CrotoLink activo (usa `publicUrl` del servidor configurado).

**Aceptación:**
- [ ] Matar la app del host: la sala sobrevive y otro participante puede continuar (nube).
- [ ] Una sala persistente reaparece tras reiniciar el contenedor con su PIN fijo.
- [ ] Abrir `https://<publicUrl>/j/CODE` en el móvil abre la app en la pantalla de unión con el PIN relleno.

---

## 9. Fase 8 — Extras sociales y opcionales

Hacer solo si las fases anteriores están estables. Cada una detrás de un flag de `/api/capabilities`.

- **Reacciones efímeras** (emoji flotante): `reaction { emoji }`, sin estado, rate limit propio.
- **Chat ligero:** `chat_message { text }` (máx. 280 car., sin historial persistente). El admin puede desactivarlo globalmente; el host por sala.
- **Notificación persistente de CrotoLink** en Android con estado de sala y controles (`audio_service`).
- **Cast de letras:** el host proyecta la letra sincronizada (Karaoke) en otra pantalla/tablet.
- **Proxy de stream opt-in (módulo aparte del Docker):** enlaces temporales firmados para que invitados sin cuenta escuchen. **Aviso explícito en UI y docs** de que rompe el principio de "sin retransmisión de audio". Desactivado por defecto.

---

## 10. Backlog de la app (fuera de CrotoLink, 100 % cliente)

Orden sugerido, cada ítem en su propia rama/PR:

1. `savePlayQueue.view` / `getPlayQueue.view` (continuar en otro dispositivo) + cola persistente local.
2. Radio infinita al terminar la cola (`getSimilarSongs2`, `getTopSongs`).
3. Temporizador de sueño con fade-out.
4. Descarga automática inteligente en Wi-Fi con política LRU y límite de espacio.
5. Smart crossfade (no cruzar pistas consecutivas del mismo álbum/en vivo).
6. Mix diarios y playlists inteligentes locales (`ListeningStatsService`).
7. Búsqueda con operadores (`artist:`, `year:`) e importación M3U/CSV (usa el resolver de la Fase 6).
8. Integraciones opt-in: ListenBrainz/Last.fm, MPRIS (Linux), Discord Rich Presence, Android Auto/CarPlay, Chromecast/DLNA.
9. Accesibilidad (`Semantics` en `WaveformProgressBar`, fuentes escalables, reducir animaciones) y localización (en/pt/fr con `flutter_localizations`/ARB).
10. Galería comunitaria de temas vía `index.json` en un repo (sin servidor).

---

## 11. Docker del servidor (objetivo)

```yaml
services:
  crotolink:
    build: .
    restart: unless-stopped
    environment:
      - PORT=8080
      - ADMIN_PASSWORD=${ADMIN_PASSWORD}      # solo para el primer arranque
      - PUBLIC_URL=${PUBLIC_URL}
      - TRUST_PROXY=cloudflare                # o none
    volumes:
      - ./data:/data
    expose:
      - "8080"
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/health"]
      interval: 30s
      timeout: 5s
      retries: 3
```

Ingress de Cloudflare Tunnel sin cambios (`jam.templo.cloud → http://crotolink:8080`). `/admin` queda expuesto por el mismo hostname: **protegerlo además con Cloudflare Access** o restringir por IP/ruta (recomendado) y documentarlo en el README.

---

## 12. Documentación a mantener

Al cerrar cada fase, actualizar en el mismo PR:
- `crotolink.md` (protocolo: nuevos `op`, campos de `CrotoLinkSessionState`, tabla de referencia rápida).
- `crotowave.md` si cambia la arquitectura general.
- `crotolink-server/README.md` (variables de entorno, panel `/admin`, backups de `/data`, reverse proxy).
- `CHANGELOG.md` (una línea por cambio visible).

---

## 13. Definición de "hecho" por fase

- [ ] Criterios de aceptación de la fase marcados.
- [ ] `flutter analyze` limpio y tests (Flutter + Node) en verde.
- [ ] Compatible hacia atrás con clientes de la versión anterior (probado).
- [ ] Documentación actualizada.
- [ ] Desplegado en mi servidor siguiendo la sección 1 y `curl $HEALTH_URL` OK.
- [ ] Resumen de 5-10 líneas al usuario: qué se hizo, qué quedó pendiente, riesgos.

## 14. Cuándo detenerte y preguntar

- Falta información de acceso al servidor (sección 1) o un secreto.
- Una decisión rompe compatibilidad de protocolo o cambia la privacidad (p. ej. guardar datos de escucha en el servidor).
- Acción destructiva en el servidor o cambios en Cloudflare/DNS.
- Ambigüedad real entre dos diseños con impacto en UX (propón 2 opciones con pros/contras).

Para todo lo demás: decide, anótalo en el PR y continúa.
