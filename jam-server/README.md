# Servidor remoto de Scrotify Jam

Servidor WebSocket en Node.js para salas Jam remotas. Conserva las salas sólo en memoria: reiniciar el contenedor cierra todas las salas activas. Los **ajustes y la cuenta de admin** sí persisten en `/data/jam.db` (SQLite vía `node:sqlite`, requiere Node ≥ 22.13; la imagen usa Node 24).

## Configuración y panel `/admin`

| Variable | Uso |
|---|---|
| `ADMIN_PASSWORD` | Contraseña inicial (≥ 8 car.). Solo se usa si aún no hay admin; se guarda su hash scrypt. Sin ella, el primer acceso a `/admin` abre un asistente de creación. |
| `PUBLIC_URL` | Valor inicial de `publicUrl` (el panel lo sobrescribe). |
| `TRUST_PROXY` | `none` (defecto) \| `cloudflare` (`CF-Connecting-IP`) \| `forwarded` (`X-Forwarded-For`). Solo así se confía en cabeceras de proxy para el rate limit del login. |
| `DATA_DIR` | Directorio de la base (defecto `/data`). |
| `PORT`, `MAX_MESSAGE_BYTES`, `MAX_PARTICIPANTS`, `ROOM_IDLE_MS` | Valores iniciales de los límites. |

El panel (`/admin`) edita límites (participantes, salas, cola, tamaño de mensaje, inactividad) y funciones (listado público, chat, salas persistentes, enlaces web). Los cambios se aplican sin reiniciar. Sesión por cookie `HttpOnly; SameSite=Strict`, CSRF en mutaciones y límite de intentos de login por IP.

**Protege `/admin`** además con Cloudflare Access o restricción por IP/ruta cuando lo expongas por Internet.

`GET /api/capabilities` devuelve `protocolVersion`, funciones habilitadas y límites para que el cliente adapte su UI.

**Funciones del relay (todas configurables sin reiniciar):** rate limit por IP y bloqueo progresivo, IPs bloqueadas, contraseña de sala (solo su hash scrypt en RAM), transferencia/failover de anfitrión (`hostFailoverMs`), salas persistentes (solo con `persistentRoomsEnabled`; guarda únicamente configuración), enlaces `/j/<PIN>` y `/.well-known/{assetlinks.json,apple-app-site-association}` (con `webLinkEnabled`), reloj de referencia `time_ping`, reacciones y chat opcional. Ver `JAM.md` para el protocolo.

**Backups:** `tar czf data-$(date +%F).tgz data/` antes de cada despliegue.

## Desplegar con Portainer

1. En Portainer, creá un **Stack** y cargá el contenido de `docker-compose.yml`.
2. Si usás *Git repository* como método de despliegue, elegí `jam-server/docker-compose.yml` como fichero del stack. Para el editor web, construí/pusheá la imagen antes o adaptá `build: .` a la imagen publicada.
3. Desplegá el stack. El servicio escucha internamente en `8080` y no publica un puerto a Internet.
4. En Cloudflare Tunnel, añadí un hostname público con `jam.templo.cloud` apuntando a `http://scrotify-jam:8080` (o `http://192.168.1.21:8080`). Cloudflare hace el upgrade WebSocket automáticamente.
5. En Scrotify configurá `wss://jam.templo.cloud/` como endpoint de Jam remota.

Cloudflare debe terminar TLS. No expongas `8080` directamente a Internet ni configures el cliente Flutter con `ws://` para un uso remoto.

## Health check

```sh
curl http://scrotify-jam:8080/health
# {"status":"ok","rooms":0}
```

## Protocolo WebSocket

Los PIN se normalizan a seis caracteres alfanuméricos en mayúsculas; `GCG-36B` se guarda y responde como `GCG36B`.

### Crear sala (host)

```json
{
  "action": "create_room",
  "pin": "GCG-36B",
  "hostName": "Proyecto",
  "initialState": {
    "trackId": "abc-123",
    "position": 0,
    "isPlaying": false,
    "queue": []
  }
}
```

Respuesta:

```json
{"status":"room_created","pin":"GCG36B"}
```

### Unirse (guest)

```json
{"action":"join_room","pin":"GCG-36B","guestName":"Amigo"}
```

El invitado recibe `{"status":"joined","state":{...}}`; el host recibe `{"event":"guest_joined","guestName":"Amigo","totalParticipants":2}`.

### Sincronizar (sólo host)

```json
{
  "action": "update_state",
  "pin": "GCG36B",
  "state": {
    "trackId": "xyz-789",
    "position": 4500,
    "isPlaying": true,
    "queue": ["next-track"]
  }
}
```

El servidor emite `{"event":"sync_state","state":{...}}` a invitados. Si el host desconecta, cada invitado recibe `room_closed` y se cierra su conexión.

Los invitados son de sólo lectura en esta versión: el protocolo no acepta comandos de reproducción ni cambios de cola enviados por ellos.

## Variables de entorno

| Variable | Predeterminado | Uso |
| --- | --- | --- |
| `PORT` | `8080` | Puerto HTTP/WebSocket interno. |
| `MAX_MESSAGE_BYTES` | `16384` | Tamaño máximo de un frame WebSocket. |
| `MAX_PARTICIPANTS` | `50` | Máximo total, host incluido. |
| `ROOM_IDLE_MS` | `3600000` | Cierre automático por inactividad. |

## Desarrollo y pruebas

```sh
cd jam-server
npm install
npm test
```

Para probar manualmente se puede usar `wscat` contra un endpoint local o el hostname `wss` publicado:

```sh
npx wscat -c wss://jam.templo.cloud/
```

Nunca pegues tokens, contraseñas ni credenciales de Navidrome en los mensajes WebSocket: el servicio sólo recibe PIN, nombres de sala y estado de reproducción.

## Sincronización de datos entre dispositivos (`/api/sync/v1`)

Desactivada por defecto (`syncEnabled` en `/admin` → Funciones). El servidor solo guarda **blobs cifrados en el cliente**: no puede leer temas, ajustes ni la clave de sincronización.

Todas las rutas llevan `Authorization: Bearer <64 hex>`. `vaultId` (64 hex) y el token salen de derivaciones distintas de la clave; el servidor guarda solo el SHA-256 del token. El primer `PUT` a una bóveda nueva la crea.

| Método y ruta | Uso |
|---|---|
| `GET /api/sync/v1/<vaultId>` | Lista `{key, updatedAt, size}` |
| `GET /api/sync/v1/<vaultId>/<key>` | Devuelve `{key, updatedAt, blob}` |
| `PUT /api/sync/v1/<vaultId>/<key>` | Cuerpo `{updatedAt, blob}`; `409` si hay una versión más reciente (gana el último cambio) |
| `DELETE /api/sync/v1/<vaultId>[/<key>]` | Borra un documento o toda la bóveda |

Límites editables: tamaño por documento (4 MB), documentos por bóveda (64) y bóvedas (100). Credenciales erróneas cuentan para el bloqueo progresivo por IP.
