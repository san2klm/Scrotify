# Scrotify Jam — Arquitectura, Protocolo y Funcionamiento Integral

> **Documento Técnico de Referencia**  
> Proyecto: Scrotify (Cliente Flutter para Navidrome / Subsonic)  
> Componente: Scrotify Jam (Sincronización social y cola colaborativa en tiempo real)  
> Fecha de actualización: 2026-10-06  

---

## 1. Visión General y Filosofía de Diseño

**Scrotify Jam** es el subsistema de escucha social compartida y gestión colaborativa de colas en tiempo real de Scrotify, inspirado conceptualmente en *Spotify Jam*, pero adaptado al ecosistema de servidores de música autohospedados (*self-hosted*) bajo la API de Subsonic / Navidrome (v1.16.1).

### 1.1. Principio Fundamental: Streaming Local Desacoplado (Sin Retransmisión de Audio P2P)

A diferencia de sistemas que retransmiten el flujo binario de audio punto a punto (lo que saturaría el ancho de banda del dispositivo anfitrión y consumiría planes de datos móviles), **Scrotify Jam no transmite audio entre dispositivos**. 

* **Lo que viaja por la red:** Identificadores canónicos de pista (`trackId`), metadatos (`title`, `artist`, `album`, `duration`), marcas temporales de alta precisión, estado de reproducción (`isPlaying`, `positionMs`), revisiones de la cola colaborativa y eventos de usuarios.
* **Lo que hace cada dispositivo:** Cada cliente conectado resuelve el `trackId` y descarga/reproduce el flujo de audio de forma independiente desde su propio servidor Navidrome (o el catálogo Subsonic configurado en su perfil).
* **Beneficio:** Consumo de ancho de banda insignificante para el Jam (mensajes JSON de pocos kilobytes), cero sobrecarga de compresión o codificación en el host, y fidelidad de audio original (FLAC, Opus o MP3 directo del servidor).

```
   ┌────────────────────────────────────────────────────────┐
   │                  NAVIDROME / SUBSONIC                  │
   │               (Servidor Central de Música)             │
   └───────────────▲────────────────────────▲───────────────┘
                   │ Audio Directo          │ Audio Directo
                   │ (HTTP Stream)          │ (HTTP Stream)
           ┌───────┴──────┐         ┌───────┴──────┐
           │     HOST     │         │    GUEST     │
           │  (Anfitrión) │         │  (Invitado)  │
           └───────┬──────┘         └───────┬──────┘
                   │                        │
                   └────── WSS / WebSockets ◄
                      (Metadatos, Sync y Cola)
```

---

## 2. Modos de Funcionamiento

La sesión Jam ofrece dos modos de operación mutuamente excluyentes, configurados por el anfitrión al crear la sesión:

### 2.1. Modo Altavoz de Fiesta (`JamMode.partySpeaker`)
* **Propósito:** Situaciones sociales donde la música suena a través de un único equipo físico (altavoces Bluetooth en el salón, barra de sonido, PC de la fiesta).
* **Comportamiento del Host:** Es el único dispositivo que reproduce sonido mediante su motor `PlayerController` (`just_audio` o `media_kit`).
* **Comportamiento de los Invitados:** Sus reproductores de audio permanecen en silencio. Los dispositivos de los invitados actúan como un **mando a distancia social**:
  * Visualizan la pista actual y el arte de tapa en tiempo real.
  * Añaden canciones a la cola (al final o como "reproducir siguiente").
  * Reordenan y eliminan pistas colaborativamente (si el host lo autoriza).
  * Pausan, reanudan o saltan de pista (si el host lo autoriza).

### 2.2. Modo Escucha Sincronizada (`JamMode.synchronizedListening`)
* **Propósito:** Múltiples personas escuchando simultáneamente en sus propios auriculares o altavoces (ej. salir a correr juntos, escuchar en la oficina, o escuchar con amigos a distancia por Internet).
* **Comportamiento:** La música suena **simultáneamente en todos los dispositivos conectados**.
* **Mecanismo de Sincronización:** Cada cliente invitado recibe el estado del host con marcas de tiempo Unix del servidor (`serverTimestamp`) y aplica un algoritmo continuo de cálculo de deriva (*drift*) y compensación de latencia de red en milisegundos.

---

## 3. Topología de Red Dual: LAN Directa vs. Cloud Relay

Scrotify Jam implementa una arquitectura híbrida de doble canal que funciona de manera transparente para el usuario:

```
                      ┌────────────────────────────────────────┐
                      │          SCROTIFY JAM NETWORK          │
                      └──────────────────┬─────────────────────┘
                                         │
                 ┌───────────────────────┴───────────────────────┐
                 ▼                                               ▼
   ┌───────────────────────────┐                   ┌───────────────────────────┐
   │    CANAL LOCAL (LAN)      │                   │    CANAL REMOTO (CLOUD)   │
   ├───────────────────────────┤                   ├───────────────────────────┤
   │ • Host monta HttpServer  │                   │ • Node.js Server en nube  │
   │   seguro embebido (WSS)   │                   │   (jam.templo.cloud:443)  │
   │ • Puerto 47620 (TLS self) │                   │ • Túnel Cloudflare Tunnel │
   │ • Pinning SHA-256 en QR   │                   │ • Sin abrir puertos / NAT │
   │ • Radar UDP Broadcast y   │                   │ • Conexión vía 4G/5G o    │
   │   Multicast (puerto 47623)│                   │   redes externas          │
   └───────────────────────────┘                   └───────────────────────────┘
```

### 3.1. Canal Red Local (LAN P2P Seguro)
* **Caso de uso:** Todos los integrantes están conectados al mismo router o Wi-Fi.
* **Latencia:** Mínima (1 a 10 ms).
* **Autonomía:** Funciona incluso si se cae la conexión a Internet externa, siempre que la red local siga enrutando paquetes.
* **Seguridad:** Utiliza certificados TLS efímeros generados en memoria y validados estrictamente mediante *Certificate Pinning* con código QR.

### 3.2. Canal Nube / Remoto (Cloud Jam Relay)
* **Caso de uso:** Invitados que están fuera de casa, usando redes móviles (4G/5G) o en distintas ubicaciones geográficas.
* **Servidor Central:** Servidor ligero en Node.js (`jam-server`) alojado en infraestructura propia y expuesto mediante **Cloudflare Tunnel** con TLS terminado por Cloudflare (`wss://jam.templo.cloud/`).
* **Intermediación:** No requiere abrir puertos en el router del host (cero configuración UPnP o port forwarding). El host abre un WebSocket saliente hacia la nube y los invitados se conectan al mismo túnel.

---

## 4. Modelos de Datos (`lib/models/jam_models.dart`)

Los modelos encapsulan el estado inmutable, la serialización JSON y las utilidades criptográficas de la sesión:

### 4.1. Código PIN de Sala (`JamCode`)
* **Longitud:** Exactamente 6 caracteres alfanuméricos.
* **Conjunto de caracteres:** `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (32 caracteres). Se excluyen deliberadamente caracteres ambiguos como `0` (cero), `O` (letra O), `1` (uno) e `I` (letra I) para evitar confusiones al dictarlo o escribirlo manualmente.
* **Generación:** Utiliza un generador seguro pseudoaleatorio criptográfico (`Random.secure()`).
* **Formateo visual:** Se presenta al usuario dividido en dos bloques de 3 caracteres con un guion intermedio (ej. `AB3-4EF`), normalizándose internamente sin guion (`AB34EF`).

### 4.2. Datos del Código QR (`JamQrData`)
Define el esquema del enlace profundo (*deep link*) embebido en el código QR:
```text
scrotify://jam?host=192.168.1.50&port=47620&code=AB34EF&sessionId=jam_1728182000&transport=wss&tlsFingerprint=3a8f...&remoteHost=192.168.1.51&remotePort=47620
```
* `host` y `port`: Dirección IP y puerto TCP primarios del anfitrión en la LAN.
* `code`: Código PIN de la sesión.
* `sessionId`: Identificador único de sesión.
* `transport`: Protocolo seguro (`wss`).
* `tlsFingerprint`: Hash SHA-256 hexadecimal de 64 caracteres del certificado X.509 efímero del anfitrión.
* `remoteHost` y `remotePort`: IP y puerto de respaldo (si el host cuenta con múltiples interfaces de red activas, ej. Wi-Fi y Ethernet).

### 4.3. Participante (`JamParticipant`)
Representa a cada usuario conectado:
* `id`: String único (ej. `guest_1728182000000_12345678` o `host_local`).
* `name`: Nombre visible del usuario (hasta 48 caracteres).
* `avatarColorValue`: Color en formato entero `0xAARRGGBB` para el avatar en la UI.
* `isHost`: Booleano que define si es el anfitrión.
* `joinedAt`: Timestamp ISO-8601 de incorporación.
* `canControlPlayback`: Permiso para pausar, reanudar y saltar canciones.
* `canManageQueue`: Permiso para agregar, reordenar y eliminar canciones de la cola.

### 4.4. Elemento de la Cola (`JamQueueItem`)
Envuelve una canción (`Track`) con metadatos sociales:
* `id`: Identificador único del ítem en la cola.
* `track`: Pista canónica de Scrotify (`id`, `title`, `artist`, `album`, `duration`, `albumArtUrl`).
* `addedBy`: Instancia de `JamParticipant` que agregó la canción (para mostrar el chip *"Añadida por Laura"*).
* `addedAt`: Fecha y hora de incorporación.

### 4.5. Estado Global de la Sesión (`JamSessionState`)
Instantánea canónica e inmutable que se transmite y sincroniza entre nodos:
```dart
class JamSessionState {
  final String sessionId;
  final String pinCode;
  final String hostName;
  final String hostIp;
  final int port;
  final JamMode mode;
  final Track? currentTrack;
  final JamParticipant? currentTrackAddedBy;
  final bool isPlaying;
  final int positionMs;
  final int updatedAtMs; // Unix timestamp del Host para compensación de latencia
  final List<JamQueueItem> queue;
  final List<JamParticipant> participants;
  final bool allowGuestControls;
  final bool allowGuestQueueManage;
  final String? remoteHost;
  final int? remotePort;
  final bool isPublic;
  final String? initialPlaylistId;
  final int maxParticipants;
  final int queueRevision; // Contador monótono para resolver conflictos de concurrencia
}
```

### 4.6. Sanitización de Credenciales (`sanitizeArtUrl`)
La API de Navidrome/Subsonic frecuentemente incluye parámetros de autenticación en las URLs de carátulas (`u`, `s`, `t`, `p`, `apiKey`). Dado que el token `t` no expira, compartir la URL cruda comprometería la cuenta del anfitrión.  
La función `sanitizeArtUrl` **elimina de forma determinista cualquier parámetro sensible** antes de transmitir URLs de arte de tapa por WebSocket o UDP.

---

## 5. Arquitectura del Anfitrión (`JamHostService`)

El anfitrión ejecuta un servidor local con capacidad criptográfica y descubrimiento por red:

### 5.1. Ciclo de Vida y Servidor Seguro Embebido
1. **Generación de Identidad TLS Efímera (`JamTlsIdentity`):**
   * Al iniciar la sesión, se genera un par de claves asimétricas RSA de 2048 bits en memoria.
   * Se crea y autofirma un certificado X.509 con vigencia de 1 día y `CN = "Scrotify Jam $sessionId"`.
   * La clave privada permanece estrictamente en la memoria RAM del host y nunca se transmite.
   * Se extrae el hash SHA-256 en formato hexadecimal de la codificación binaria DER del certificado.
2. **Enlace HTTP/WSS (`HttpServer.bindSecure`):**
   * Intenta enlazar en el puerto preferido `47620` (`kJamHostPort`).
   * Si el puerto está ocupado por otra instancia o servicio, hace *fallback* al puerto dinámico `0` del sistema operativo.
   * Configura rutas:
     * `GET /jam/status`: Endpoint JSON con telemetría básica de la sala.
     * `GET /jam/ws`: Endpoint de actualización a WebSocket bidireccional.
3. **Priorización de Interfaces de Red:**
   * Al recopilar las IPs locales del dispositivo para el QR y el radar, prioriza interfaces físicas de alta velocidad (`wlan0`, `wifi0`, `eth0`, `en0`) por encima de adaptadores virtuales (`docker0`, `vboxnet`, `tailscale0`, `tun0`).

### 5.2. Beacon de Descubrimiento UDP (Radar LAN)
* Enlaza un `RawDatagramSocket` en el puerto `47623` (`kJamDiscoveryPort`) con `reuseAddress: true`.
* **Multicast + Subred Broadcast:**
  * Se une al grupo multicast IPv4 `239.255.0.1`.
  * Calcula las direcciones de broadcast específicas de cada subred activa (ej. `192.168.1.255`) además de la genérica `255.255.255.255`.
* **Ráfaga Inicial y Ritmo Constante:**
  * Emite una ráfaga inmediata de 3 paquetes de presencia en $t=0$, $t=250\text{ ms}$ y $t=500\text{ ms}$.
  * Mantiene un latido periódico cada 8 segundos sin re-escanear interfaces de red para minimizar el impacto en batería y CPU.
* **Bloqueo Multicast en Android (`JamNetworkPlatform`):**
  * Invoca mediante `MethodChannel` la API nativa `WifiManager.MulticastLock` en Android, impidiendo que el sistema operativo descarte paquetes UDP cuando la pantalla entra en reposo.

### 5.3. Protección contra Abusos y Resiliencia en el Host
* **Limitador de Tasa Deslizante (`JamRateLimiter`):**
  * Control de reproducción: Máximo 4 comandos cada 2 segundos por participante.
  * Modificación de cola: Máximo 10 operaciones cada 10 segundos por participante.
  * Superar estos límites resulta en un mensaje de error y descarte de la acción.
* **Período de Gracia para Reconexiones (`disconnectGracePeriod` = 30 segundos):**
  * Si un invitado pierde la conexión (ej. cambio de torre Wi-Fi o bloqueo de pantalla), el Host **no lo elimina inmediatamente** de la sala ni de la cola.
  * Al ingresar por primera vez, el Host asigna al invitado un `reconnectToken` seguro de 128 bits (CSPRNG).
  * Si el invitado se reconecta antes de 30 segundos enviando su token y `participantId`, recupera su identidad original sin duplicar participantes.
* **Monitoreo de Heartbeat y Desalojo:**
  * Ping periódico cada 15 segundos con margen de espera (*pong timeout*) de 10 segundos. Si un participante pasa 25 segundos sin actividad entrante, es desalojado.

---

## 6. Arquitectura del Invitado (`JamGuestService`)

Gestiona la conexión del lado del cliente cuando se une a una sala como invitado:

### 6.1. Escaneo de Radar LAN
* Abre un socket UDP efímero y emite peticiones `discover_jam` tanto a `255.255.255.255` como a `239.255.0.1`.
* Escucha las respuestas `jam_presence` entrantes durante un intervalo configurable (por defecto 4 segundos).
* **Preferencia de IP de Origen:**  
  Si el host anuncia una IP en su payload JSON pero el datagrama UDP fue recibido desde otra IP diferente (típico en configuraciones complejas de Docker, VPN o NAT), el invitado utiliza la IP de origen del paquete UDP (`fallbackHost`), garantizando que la ruta de red sea válida.

### 6.2. Conexión WebSocket y Validación Criptográfica
* Construye un cliente `HttpClient` personalizado con un validador `badCertificateCallback`:
  ```dart
  badCertificateCallback = (certificate, host, port) =>
      JamTlsIdentity.fingerprintForDer(certificate.der) == tlsFingerprint;
  ```
* Esto garantiza que, a pesar de usar certificados autofirmados efímeros sin una Autoridad Certificadora (CA) comercial, la conexión es **inmune a ataques Man-in-the-Middle (MitM)** en la red local: sólo el anfitrión que generó el código QR tiene la clave privada correspondiente al fingerprint fijado.

### 6.3. Reconexión Automática con Retroceso Exponencial y Jitter
* Si la conexión se interrumpe de forma no explícita, se activa el motor de reconexión:
  * Intentos progresivos: $2^0 = 1\text{ s}$, $2^1 = 2\text{ s}$, $2^2 = 4\text{ s}$, $2^3 = 8\text{ s}$, $2^4 = 16\text{ s}$, y techo de 30 segundos.
  * **Jitter aleatorio:** Se suma una variación aleatoria de entre 0 y 1000 ms a cada intervalo para evitar que múltiples invitados intenten reconectarse exactamente en el mismo instante y saturen al anfitrión (*thundering herd problem*).
* **Detección de Silencio:** Si transcurren 30 segundos sin recibir ningún mensaje o latido del Host, el cliente fuerza el reinicio del socket.

---

## 7. Servidor Central Cloud Relay (`jam-server`) y `RemoteJamService`

El componente en la nube permite sesiones a través de Internet:

### 7.1. Servidor Node.js (`jam-server/src/server.js`)
* Servidor HTTP y WebSocket basado en `ws` para Node.js 24 (contenedorizado en Alpine Linux).
* **Almacenamiento en Memoria:** Las salas se guardan en un mapa en memoria RAM. Reiniciar el contenedor reinicia el estado limpio.
* **Recolección de Basura:** Un temporizador cada 60 segundos elimina salas que no hayan tenido actividad durante más de 1 hora (`ROOM_IDLE_MS = 3600000`).
* **Endpoints HTTP:**
  * `GET /health`: Estado del servicio (`{"status":"ok","rooms":N}`).
  * `GET /rooms` o `/api/rooms`: Lista de salas públicas activas para el radar de descubrimiento.
* **Límites de Seguridad:**
  * `MAX_MESSAGE_BYTES`: 16 KB por frame WebSocket.
  * `MAX_PARTICIPANTS`: 50 participantes por sala.
  * Longitud de nombre máxima: 48 caracteres.
  * Longitud máxima de cola: 500 ítems.

### 7.2. Cliente Remoto en Flutter (`RemoteJamService`)
* Mantiene la conexión WebSocket contra `wss://jam.templo.cloud/`.
* **Ajuste y Truncamiento de Payload (`fitStateToMessageLimit`):**
  * Si la cola de reproducción tiene cientos de canciones, serializarla completa superaría el límite de 16 KB de Cloudflare/Node.js, provocando que el socket sea cerrado con error `1009 (Message Too Big)`.
  * `fitStateToMessageLimit` calcula en tiempo real el tamaño en bytes y recorta de manera segura los ítems finales de la cola para que el mensaje siempre quepa en el búfer seguro (< 15.5 KB), garantizando la estabilidad de la sesión.
* **Relay de Acciones del Invitado:**  
  Los invitados envían `guest_action` al servidor central, el servidor las retransmite al Host, y el Host las aplica en su `PlayerController` antes de propagar la actualización canónica a todos los clientes.

---

## 8. El Coordinador Central: `JamController` (`lib/services/jam_controller.dart`)

`JamController` es la clase central que extiende `ChangeNotifier` y actúa como orquestador entre la UI, los servicios de red (`JamHostService`, `JamGuestService`, `RemoteJamService`) y el reproductor de audio (`PlayerController`).

### 8.1. Dualidad Simultánea Host: LAN + Nube
Cuando un usuario pulsa *"Crear Jam"*, `JamController` ejecuta simultáneamente:
1. Inicia `JamHostService` en la red local (HTTPS/WSS + Radar UDP).
2. Se conecta al servidor en la nube y crea la sala en `RemoteJamService.createRoom`.
3. Notifica al servidor Navidrome mediante `_navidrome.publishServerJam`.
4. De esta manera, **la misma sala con el mismo PIN es accesible tanto por Wi-Fi local como por Internet**.

```
                        ┌────────────────────────┐
                        │     JamController      │
                        │    (Anfitrión Host)    │
                        └───────────┬────────────┘
         ┌──────────────────────────┼──────────────────────────┐
         ▼                          ▼                          ▼
┌──────────────────┐      ┌──────────────────┐      ┌──────────────────┐
│  JamHostService  │      │ RemoteJamService │      │ NavidromeService │
│    (LAN / WSS)   │      │  (Cloud / WSS)   │      │ (Anuncio Público)│
└──────────────────┘      └──────────────────┘      └──────────────────┘
```

### 8.2. Reconciliación de Cola entre el Reproductor y la Jam
El reproductor local maneja su propio orden y la pista en curso. `JamController` realiza una reconciliación bidireccional continua mediante `_rebuildHostQueueFromPlayer()`:
* Separa la pista actual (`currentTrack`) de las pistas futuras (`orderedQueue.skip(currentOrderPos + 1)`).
* Mantiene la trazabilidad de qué participante añadió cada pista (`_trackAddedBy[track.id]`).
* Incrementa monótonamente `_queueRevision` ante cualquier adición, reordenamiento o eliminación, evitando condiciones de carrera o sobreescritura de estados antiguos.

---

## 9. Algoritmo de Sincronización Temporal y Latencia

En modo **Escucha Sincronizada** (`JamMode.synchronizedListening`), el método `_syncGuestAudioIfApplicable` sincroniza el audio del invitado con el del host:

### 9.1. Variables del Algoritmo
* $T_{\text{server}}$ (`serverTs`): Marca de tiempo Unix en milisegundos tomada en el host en el instante exacto de emitir el paquete.
* $P_{\text{server}}$ (`positionMs`): Posición de reproducción del host en milisegundos en el momento $T_{\text{server}}$.
* $T_{\text{local}}$ (`now`): Marca de tiempo Unix local del invitado en el momento de procesar el paquete.
* $P_{\text{local}}$ (`currentPosMs`): Posición de reproducción actual del reproductor del invitado.

### 9.2. Ecuaciones de Compensación
1. **Retardo de Tránsito de Red:**
   $$\Delta T_{\text{transit}} = \text{clamp}(T_{\text{local}} - T_{\text{server}}, 0, 5000)$$
2. **Posición Objetivo Proyectada:**
   $$P_{\text{target}} = P_{\text{server}} + (\text{isPlaying} ? \Delta T_{\text{transit}} : 0)$$
3. **Cálculo de Deriva (*Drift*):**
   $$\text{Drift} = |P_{\text{target}} - P_{\text{local}}|$$

### 9.3. Criterio de Resincronización (Umbral de Deriva)
* Si $\text{Drift} > 450\text{ ms}$: Se ejecuta un salto temporal forzado (`await _player.seek(P_{\text{target}})`).
* Si $\text{Drift} \le 450\text{ ms}$: Se permite que la reproducción continúe con el reloj del motor de audio local sin interrumpir el búfer para evitar microcortes o tartamudeos audibles.
* **Generación de Sincronización (`_syncGeneration`):**  
  Cada actualización incrementa un contador `_syncGeneration`. Cualquier operación asíncrona de carga o seek comprueba si la generación actual sigue vigente antes de aplicar cambios, evitando que peticiones lentas anteriores sobreescriban el estado presente.

---

## 10. Sistema de Radar de Descubrimiento Multi-Vía

Al abrir el panel de Jam o pulsar *"Buscar Jam en Radar"*, Scrotify dispara **tres consultas concurrentes** mediante `Future.wait`:

```
                           ┌────────────────────────┐
                           │   JamController.scan   │
                           └───────────┬────────────┘
         ┌─────────────────────────────┼─────────────────────────────┐
         ▼                             ▼                             ▼
┌──────────────────┐         ┌──────────────────┐          ┌──────────────────┐
│   Canal 1: LAN   │         │ Canal 2: Navidro │          │ Canal 3: Cloud   │
│  UDP Broadcast   │         │ REST / API Jams  │          │ HTTP GET /rooms  │
└────────┬─────────┘         └────────┬─────────┘          └────────┬─────────┘
         │                            │                             │
         └────────────────────────► Deduplicación ◄─────────────────┘
                                       │
                                       ▼
                       Priorización LAN sobre Remoto
```

1. **Canal 1 (LAN UDP):** Broadcast y Multicast en la red local (`JamGuestService.scanRadar`).
2. **Canal 2 (Servidor Navidrome):** Consulta de sesiones anunciadas en la instancia Navidrome (`NavidromeService.getServerActiveJams`).
3. **Canal 3 (Servidor Cloud):** Petición HTTP `GET /rooms` contra `https://jam.templo.cloud/rooms`.

### Regla de Resolución y Prioridad:
Los resultados se indexan por su código PIN normalizado. Si una misma sesión es descubierta tanto en la nube como en la red local LAN, **el sistema selecciona y prioriza la conexión LAN**, garantizando una menor latencia y evitando el consumo de ancho de banda exterior.

---

## 11. Protocolo de Comunicación y Esquema de Mensajes

Los mensajes son tramas JSON estructuradas. A continuación se detallan los formatos canónicos:

### 11.1. Mensajes del Canal LAN Directo

#### `join_request` (Invitado → Host)
```json
{
  "op": "join_request",
  "pin": "AB34EF",
  "name": "Carlos",
  "avatarColorValue": 4279384449,
  "participantId": "guest_12345",
  "token": "a1b2c3d4e5f6789012345678abcdef01"
}
```

#### `join_response` (Host → Invitado)
```json
{
  "op": "join_response",
  "accepted": true,
  "token": "a1b2c3d4e5f6789012345678abcdef01",
  "assignedParticipant": {
    "id": "guest_12345",
    "name": "Carlos",
    "avatarColorValue": 4279384449,
    "isHost": false,
    "joinedAt": "2026-10-06T02:00:00.000Z",
    "canControlPlayback": true,
    "canManageQueue": true
  }
}
```

#### `jam_state_snapshot` (Host → Invitado)
Enviado inmediatamente tras aceptar al invitado con el estado completo de la sala.

#### `playback_updated` (Host → Todos los Invitados)
```json
{
  "op": "playback_updated",
  "track": {
    "id": "track-999",
    "title": "Starlight",
    "artist": "Muse",
    "album": "Black Holes and Revelations",
    "duration": "240",
    "albumArtUrl": "https://servidor.com/rest/getCoverArt?id=al-1"
  },
  "addedBy": { "id": "host_local", "name": "Laura" },
  "isPlaying": true,
  "positionMs": 35200,
  "serverTimestamp": 1728182400000
}
```

#### `queue_updated` (Host → Todos los Invitados)
```json
{
  "op": "queue_updated",
  "queueRevision": 14,
  "queue": [
    {
      "id": "item_1728182401_0",
      "track": { "id": "t-1", "title": "Song A", "artist": "Artist A" },
      "addedBy": { "name": "Carlos" },
      "addedAt": "2026-10-06T02:05:00.000Z"
    }
  ]
}
```

#### `add_to_queue` (Invitado → Host)
```json
{
  "op": "add_to_queue",
  "playNext": false,
  "track": {
    "id": "track-500",
    "title": "Time",
    "artist": "Pink Floyd",
    "album": "The Dark Side of the Moon",
    "duration": "413"
  }
}
```

#### `playback_control` (Invitado → Host)
```json
{
  "op": "playback_control",
  "action": "seek",
  "positionMs": 65000
}
```
*Acciones válidas:* `toggle`, `play`, `pause`, `skip_next`, `skip_previous`, `seek`.

---

### 11.2. Mensajes del Canal Remoto Cloud (`jam-server`)

| Acción / Evento | Origen | Destino | Propósito |
| :--- | :--- | :--- | :--- |
| `create_room` | Host | Servidor | Registra una nueva sala en memoria con su PIN y estado inicial. |
| `room_created` | Servidor | Host | Confirmación de sala creada. |
| `join_room` | Invitado | Servidor | Intenta unirse a una sala remota existente por su PIN. |
| `joined` | Servidor | Invitado | Confirma la unión y devuelve el estado inicial de la sala. |
| `guest_joined` | Servidor | Host | Notifica al host que un nuevo invitado se unió. |
| `update_state` | Host | Servidor | Actualiza la pista, reproducción y cola de la sala. |
| `sync_state` | Servidor | Invitados | Emite el nuevo estado a todos los invitados. |
| `guest_action` | Invitado | Host | Relay de comandos de reproducción o cola del invitado al host. |
| `kick_guest` | Host | Servidor | Expulsa y desconecta a un invitado por su nombre. |
| `room_closed` | Servidor | Invitados | Notifica el cierre o expiración de la sesión. |

---

## 12. Seguridad, Criptografía y Privacidad

1. **Protección de Credenciales Subsonic:**
   * Las credenciales de acceso al servidor Navidrome (`username`, `password`, `salt`, `token`) nunca se comparten con invitados ni con el servidor central de la nube.
   * `sanitizeArtUrl` asegura que las URLs de portada no fuguen tokens de sesión.
2. **Criptografía de Canal en LAN:**
   * Certificados TLS RSA-2048 efímeros con fijación estricta de hash SHA-256 (`tlsFingerprint`).
   * No requiere confiar en entidades certificadoras externas para la red local.
3. **Aislamiento de Infraestructura Cloud:**
   * El contenedor Docker no publica puertos directamente a Internet; Cloudflare Tunnel es el único punto de entrada público con terminación TLS gestionada.
4. **Prevención de Suplantación de Identidad:**
   * Cada participante recibe un token de reconexión de 128 bits generado criptográficamente que debe presentar para reanudar su sesión.
5. **Control de Acceso Granular:**
   * El anfitrión puede revocar dinámicamente el control de reproducción (`allowGuestControls = false`) o de la cola (`allowGuestQueueManage = false`), así como expulsar participantes específicos en cualquier momento.

---

## 13. Interfaz de Usuario y Componentes

### 13.1. Modal de Gestión (`JamDialog` — `lib/widgets/jam_dialog.dart`)
* **Diseño Adaptativo:** Diálogo flotante centrado en escritorio (`maxWidth: 540`) y BottomSheet deslizable en dispositivos móviles (`heightFactor: 0.88`).
* **Pestaña "Crear":**
  * Selector de modo (Altavoz de fiesta vs. Escucha sincronizada).
  * Conmutadores de permisos para invitados (reproducción y cola).
  * Selector de visibilidad (pública en radar o privada sólo con QR/PIN).
  * Límite de participantes máximos.
* **Pestaña "Unirse":**
  * Radar en vivo con tarjetas de sesiones descubiertas en LAN, Navidrome y Nube.
  * Botón para abrir el escáner de cámara de código QR en tiempo real (`mobile_scanner`).
  * Entrada manual de código PIN con autoformateo (`ABC-DEF`).
* **Vista de Sesión Activa:**
  * Indicador de estado de conexión (`Conectado`, `Reconectando`, etc.).
  * Código QR ampliable para mostrar en pantalla completa a amigos.
  * Lista de participantes en vivo con avatares de color neón y corona de Host.
  * Botones de expulsión individual para el host.

### 13.2. Panel de Cola Compartida (`JamQueuePanel` — `lib/widgets/jam_queue_panel.dart`)
* Lista visual de la cola con trazabilidad de cada canción.
* Badge identificador con el nombre y avatar del usuario que la agregó.
* Soporte para reordenamiento mediante arrastrar y soltar (*drag & drop*) sincronizado con el anfitrión.
* Botón de eliminación directa por ítem.

---

## 14. Despliegue e Infraestructura del Servidor Remoto

### 14.1. Archivo Docker Compose (`jam-server/docker-compose.yml`)
```yaml
services:
  scrotify-jam:
    build: .
    restart: unless-stopped
    environment:
      - PORT=8080
      - MAX_PARTICIPANTS=50
      - ROOM_IDLE_MS=3600000
    expose:
      - "8080"
```

### 14.2. Ingress de Cloudflare Tunnel
```yaml
ingress:
  - hostname: jam.templo.cloud
    service: http://scrotify-jam:8080
  - service: http_status:404
```

### 14.3. Verificación de Salud
```sh
curl http://scrotify-jam:8080/health
# Respuesta: {"status":"ok","rooms":0}
```

---

## 15. Tabla de Referencia Rápida

| Parámetro | Valor / Constante | Descripción |
| :--- | :--- | :--- |
| **Puerto TCP Host LAN** | `47620` (`kJamHostPort`) | Puerto preferido para el servidor HTTPS/WSS del host. |
| **Puerto UDP Radar** | `47623` (`kJamDiscoveryPort`) | Puerto para anuncios broadcast y peticiones de descubrimiento. |
| **Grupo Multicast** | `239.255.0.1` | Grupo de multidifusión local para redes que bloquean broadcast. |
| **Tag de Descubrimiento** | `scrotify-jam` | Identificador de protocolo en los datagramas UDP. |
| **Endpoint Nube por Defecto** | `wss://jam.templo.cloud/` | URL pública protegida con TLS para Jam remota. |
| **Longitud del PIN** | `6` caracteres (`JamCode.length`) | PIN sin caracteres ambiguos (`ABC-DEF`). |
| **Umbral de Deriva (Audio)** | `450` milisegundos | Desfase mínimo para forzar un `seek` en escucha sincronizada. |
| **Período de Gracia Host** | `30` segundos | Tiempo que el host reserva el lugar de un invitado desconectado. |
| **Timeout Silencio Host** | `30` segundos | Tiempo sin datos antes de que el invitado inicie reconexión. |
| **Heartbeat Ping** | `15` segundos | Intervalo regular de ping del host a invitados. |
| **Heartbeat Timeout** | `10` segundos | Tiempo de espera de pong antes de considerar el enlace muerto. |
| **Rate Limit Reproducción** | `4` eventos / `2` seg | Límite por invitado para play, pause, seek. |
| **Rate Limit Cola** | `10` eventos / `10` seg | Límite por invitado para añadir o mover temas en la cola. |
| **Tamaño Máximo Frame WS** | `16384` bytes (16 KB) | Límite del servidor central antes de cerrar el socket. |
| **Límite de Participantes** | `50` (Cloud) / Configurable (LAN)| Máximo de dispositivos por sala. |
| **Inactividad Máxima Sala** | `3600000` ms (1 hora) | Tiempo para recolección de basura de salas inactivas en nube. |


## Anexo: servidor configurable (Roadmap Fase 1)

- El endpoint remoto ya no es fijo: `SettingsController.jamServerUrl` (por defecto `wss://jam.templo.cloud/`) alimenta `RemoteJamService`, el radar (`GET /rooms`) y los anuncios de sala. Validación en `JamServerEndpoint` (`wss://`; `ws://` solo en hosts privados).
- `jam-server`: `GET /api/capabilities` → `{protocolVersion: 2, features, limits, publicUrl}`; panel `/admin` y ajustes persistentes en `/data/jam.db`. Ver `jam-server/README.md`.
