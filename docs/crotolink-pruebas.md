# CrotoLink — pruebas y despliegue remoto

Fecha: 2026-09-17

## Objetivo

Desplegar el servidor remoto de CrotoLink en Portainer para que los clientes Flutter se conecten mediante Cloudflare Tunnel usando una URL segura `wss://`.

El servidor administra salas temporales en memoria. No transmite audio: sólo sincroniza identificador de pista, posición, play/pause y cola. Cada dispositivo reproduce desde su propio servidor Navidrome.

## Archivos creados

El stack y el servidor están en [`crotolink-server/`](crotolink-server/):

- [`crotolink-server/src/server.js`](crotolink-server/src/server.js): servidor HTTP/WebSocket con salas CrotoLink.
- [`crotolink-server/Dockerfile`](crotolink-server/Dockerfile): imagen Node.js 24 Alpine.
- [`crotolink-server/docker-compose.yml`](crotolink-server/docker-compose.yml): stack para Portainer.
- [`crotolink-server/.env.example`](crotolink-server/.env.example): límites configurables.
- [`crotolink-server/package.json`](crotolink-server/package.json): dependencia `ws` y scripts.
- [`crotolink-server/test/server.test.js`](crotolink-server/test/server.test.js): pruebas de protocolo.
- [`crotolink-server/README.md`](crotolink-server/README.md): documentación ampliada.

## Desplegar en Portainer

1. Crear un Stack nuevo en Portainer.
2. Usar el archivo [`crotolink-server/docker-compose.yml`](crotolink-server/docker-compose.yml).
3. Si Portainer despliega desde Git, seleccionar ese archivo como Compose path.
4. Desplegar el stack. El servicio se llama `crotolink` y escucha internamente en el puerto `8080`.
5. No publicar ese puerto en Internet. Cloudflare Tunnel debe ser el único punto de entrada público y de TLS.

Configuración de ejemplo del túnel Cloudflare:

```yaml
ingress:
  - hostname: jam.templo.cloud
    service: http://crotolink:8080
  - service: http_status:404
```

> `cloudflared` y `crotolink` deben estar en la misma red Docker para que el nombre del servicio se resuelva. Si no lo están, conectar ambos servicios a una red externa común y apuntar el túnel al nombre/contenedor accesible en esa red (o a `http://192.168.1.21:8080`).

Endpoint que deberá configurarse luego en Flutter:

```text
wss://jam.templo.cloud/
```

## Health check

Desde otro contenedor de la misma red Docker o desde el host si se publica temporalmente el puerto:

```sh
curl http://crotolink:8080/health
```

Respuesta esperada:

```json
{"status":"ok","rooms":0}
```

## Protocolo WebSocket

Los PIN se normalizan: `GCG-36B` se guarda como `GCG36B`.

### 1. Host: crear una sala

Cliente → servidor:

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

Respuesta esperada:

```json
{"status":"room_created","pin":"GCG36B"}
```

### 2. Invitado: unirse

Cliente → servidor:

```json
{
  "action": "join_room",
  "pin": "GCG-36B",
  "guestName": "Amigo"
}
```

Invitado recibe:

```json
{
  "status": "joined",
  "state": {
    "trackId": "abc-123",
    "position": 0,
    "isPlaying": false,
    "queue": []
  }
}
```

Host recibe:

```json
{
  "event": "guest_joined",
  "guestName": "Amigo",
  "totalParticipants": 2
}
```

### 3. Host: actualizar estado

Cliente host → servidor:

```json
{
  "action": "update_state",
  "pin": "GCG36B",
  "state": {
    "trackId": "xyz-789",
    "position": 4500,
    "isPlaying": true,
    "queue": ["siguiente-track"]
  }
}
```

Invitados reciben:

```json
{
  "event": "sync_state",
  "state": {
    "trackId": "xyz-789",
    "position": 4500,
    "isPlaying": true,
    "queue": ["siguiente-track"]
  }
}
```

### Errores y cierre

Errores de validación, PIN inexistente o acciones no permitidas:

```json
{"status":"error","message":"..."}
```

Si se desconecta el host, los invitados reciben:

```json
{
  "event": "room_closed",
  "message": "El anfitrión ha finalizado la sesión CrotoLink"
}
```

Los invitados son de sólo lectura por ahora: sólo el host puede emitir `update_state`.

## Límites configurables

| Variable | Valor | Descripción |
| --- | ---: | --- |
| `PORT` | `8080` | Puerto interno HTTP/WebSocket. |
| `MAX_MESSAGE_BYTES` | `16384` | Máximo tamaño de cada mensaje WebSocket. |
| `MAX_PARTICIPANTS` | `50` | Máximo de integrantes por sala, host incluido. |
| `ROOM_IDLE_MS` | `3600000` | Tiempo de inactividad antes de cerrar una sala. |

## Pruebas ejecutadas

Se verificó localmente:

```text
node --test crotolink-server/test/server.test.js
```

Resultado: **2 pruebas aprobadas**.

Cobertura actual:

1. El host crea una sala, un invitado se une y recibe un `sync_state` emitido por el host.
2. Un invitado no puede actualizar el estado y la sala se cierra para los invitados al desconectarse el host.

También se validó:

```text
node --check crotolink-server/src/server.js
docker compose -f crotolink-server/docker-compose.yml config
```

## Prueba manual recomendada

1. Desplegar el stack y comprobar `GET /health`.
2. Configurar el hostname de Cloudflare y comprobar que responde `wss://jam.templo.cloud/`.
3. Con dos clientes WebSocket (`wscat` o, más adelante, dos instalaciones de CrotoWave): crear una sala y unirse con el PIN.
4. Enviar `update_state` desde el host y confirmar que el invitado recibe `sync_state`.
5. Probar play/pause, seek, cambio de pista y cola.
6. Cerrar la conexión del host y confirmar que el invitado recibe `room_closed`.
7. Confirmar que el endpoint público utiliza siempre `wss://`, nunca `ws://`.

## Próximo paso en Flutter

Implementar la capa cliente remota en paralelo al CrotoLink LAN actual:

- modelo `RemoteCrotoLinkState`;
- servicio WebSocket con `web_socket_channel`;
- endpoint configurable en Ajustes;
- integración de `sync_state` con `PlayerController` y resolución de `trackId` en Navidrome.
