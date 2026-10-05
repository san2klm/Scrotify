import http from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';

const defaultLimits = {
  maxMessageBytes: 16 * 1024,
  maxNameLength: 48,
  maxQueueLength: 500,
  maxParticipants: 50,
  roomIdleMs: 60 * 60 * 1000,
  maxFailedAttempts: 10,
  heartbeatMs: 30 * 1000,
  publicHost: null,
};

const allowedGuestActions = new Set([
  'playback_control',
  'queue_add',
  'queue_remove',
  'queue_reorder',
]);

// Parámetros Subsonic que equivalen a credenciales (el token `t` no caduca).
const secretQueryParams = ['u', 's', 't', 'p', 'apiKey'];

function sanitizeUrl(value) {
  if (typeof value !== 'string' || value.length === 0) return value;
  try {
    const url = new URL(value);
    for (const key of secretQueryParams) url.searchParams.delete(key);
    return url.toString();
  } catch {
    return value;
  }
}

function sanitizeQueueItem(item) {
  if (!item || typeof item !== 'object' || Array.isArray(item)) return null;
  const clone = structuredClone(item);
  if (clone.track && typeof clone.track === 'object') {
    clone.track.albumArtUrl = sanitizeUrl(clone.track.albumArtUrl);
  }
  if (typeof clone.albumArtUrl === 'string') {
    clone.albumArtUrl = sanitizeUrl(clone.albumArtUrl);
  }
  return clone;
}

function readPositiveInteger(value, fallback) {
  const parsed = Number.parseInt(value ?? '', 10);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : fallback;
}

function normalizePin(value) {
  if (typeof value !== 'string') return null;
  const pin = value.toUpperCase().replace(/[^A-Z0-9]/g, '');
  return pin.length === 6 ? pin : null;
}

function normalizeName(value, maxLength) {
  if (typeof value !== 'string') return null;
  const name = value.trim();
  return name.length > 0 && name.length <= maxLength ? name : null;
}

function normalizeState(value, limits, existingState = null) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const merged = existingState ? { ...existingState, ...value } : value;
  const {
    trackId,
    position,
    isPlaying,
    queue,
    title,
    artist,
    album,
    albumArtUrl,
    duration,
    mode,
    allowGuestControls,
    allowGuestQueueManage,
  } = merged;

  if (trackId !== null && trackId !== undefined &&
      (typeof trackId !== 'string' || trackId.trim().length === 0)) {
    return null;
  }
  if (typeof position !== 'number' || !Number.isFinite(position)) return null;
  if (typeof isPlaying !== 'boolean' || !Array.isArray(queue) ||
      queue.length > limits.maxQueueLength) {
    return null;
  }
  const normalizedQueue = [];
  for (const item of queue) {
    if (typeof item === 'string' && item.trim().length > 0 && item.length <= 512) {
      normalizedQueue.push(item.trim());
    } else {
      const safe = sanitizeQueueItem(item);
      if (safe) normalizedQueue.push(safe);
    }
  }
  const res = {
    trackId: typeof trackId === 'string' ? trackId.trim() : null,
    position: Math.max(0, Math.floor(position)),
    isPlaying,
    queue: normalizedQueue,
  };
  if (typeof title === 'string') res.title = title.slice(0, 256);
  if (typeof artist === 'string') res.artist = artist.slice(0, 256);
  if (typeof album === 'string') res.album = album.slice(0, 256);
  if (typeof albumArtUrl === 'string') res.albumArtUrl = sanitizeUrl(albumArtUrl.slice(0, 1024));
  if (typeof duration === 'number' && Number.isFinite(duration)) {
    res.duration = Math.max(0, Math.floor(duration));
  } else if (typeof duration === 'string' && duration.trim().length > 0) {
    const parsed = Number(duration);
    if (!Number.isNaN(parsed) && Number.isFinite(parsed)) {
      res.duration = Math.max(0, Math.floor(parsed));
    } else {
      res.duration = duration.trim().slice(0, 32);
    }
  }
  if (typeof mode === 'string') res.mode = mode.slice(0, 32);
  if (typeof allowGuestControls === 'boolean') res.allowGuestControls = allowGuestControls;
  if (typeof allowGuestQueueManage === 'boolean') res.allowGuestQueueManage = allowGuestQueueManage;

  return res;
}

function send(socket, message) {
  if (socket.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify(message));
  }
}

function serverError(socket, message) {
  send(socket, { status: 'error', message });
}

export function createJamServer({ port, host = '0.0.0.0', ...overrides } = {}) {
  const limits = { ...defaultLimits, ...overrides };
  const publicHost = limits.publicHost ?? 'localhost';
  const rooms = new Map();
  const socketRooms = new WeakMap();
  const httpServer = http.createServer((request, response) => {
    if (request.method === 'GET' && request.url === '/health') {
      response.writeHead(200, {
        'content-type': 'application/json',
        'access-control-allow-origin': '*',
      });
      response.end(JSON.stringify({ status: 'ok', rooms: rooms.size }));
      return;
    }
    if (request.method === 'GET' && (request.url === '/rooms' || request.url === '/api/rooms')) {
      const publicRooms = [];
      for (const room of rooms.values()) {
        if (!room.isPublic) continue;
        publicRooms.push({
          pin: room.pin,
          hostName: room.hostName,
          sessionTitle: `Jam de ${room.hostName}`,
          participantCount: room.guests.size + 1,
          currentTrackTitle: room.state?.title ?? null,
          currentTrackArtist: room.state?.artist ?? null,
          albumArtUrl: room.state?.albumArtUrl ?? null,
          mode: room.state?.mode ?? 'partySpeaker',
          host: publicHost,
          port: 443,
          remoteHost: publicHost,
          remotePort: 443,
          isPublic: true,
          updatedAt: room.updatedAt,
        });
      }
      response.writeHead(200, {
        'content-type': 'application/json',
        'access-control-allow-origin': '*',
      });
      response.end(JSON.stringify(publicRooms));
      return;
    }
    response.writeHead(404);
    response.end();
  });
  const websocketServer = new WebSocketServer({
    server: httpServer,
    maxPayload: limits.maxMessageBytes,
  });

  const failedAttempts = new WeakMap();

  // Frena la enumeración de PINs: tras N fallos se cierra la conexión.
  function failedAttempt(socket, message, reply) {
    const count = (failedAttempts.get(socket) ?? 0) + 1;
    failedAttempts.set(socket, count);
    if (message) serverError(socket, message);
    else send(socket, reply);
    if (count >= limits.maxFailedAttempts) socket.close(1008, 'Too many attempts');
  }

  function closeRoom(room, reason = 'El anfitrión ha finalizado la sesión Jam') {
    if (rooms.get(room.pin) !== room) return;
    rooms.delete(room.pin);
    for (const guest of room.guests) {
      send(guest.socket, { event: 'room_closed', message: reason });
      guest.socket.close(1000, 'Room closed');
    }
    const guestCount = room.guests.size;
    room.guests.clear();
    console.info(`Jam room closed (${guestCount} guests)`);
  }

  function removeSocket(socket) {
    const membership = socketRooms.get(socket);
    if (!membership) return;
    socketRooms.delete(socket);
    const room = rooms.get(membership.pin);
    if (!room) return;
    if (membership.role === 'host' && room.host === socket) {
      closeRoom(room);
      return;
    }
    if (membership.role === 'guest') {
      room.guests.delete(membership.guest);
      room.updatedAt = Date.now();
    }
  }

  function createRoom(socket, message) {
    if (socketRooms.has(socket)) return serverError(socket, 'Esta conexión ya pertenece a una sala.');
    const pin = normalizePin(message.pin);
    const hostName = normalizeName(message.hostName, limits.maxNameLength);
    const state = normalizeState(message.initialState, limits);
    if (!pin || !hostName || !state) return serverError(socket, 'Datos de sala inválidos.');
    if (rooms.has(pin)) return serverError(socket, 'Ese PIN ya está en uso.');
    const room = {
      pin, host: socket, hostName, state, guests: new Set(), updatedAt: Date.now(),
      isPublic: message.isPublic === true,
    };
    rooms.set(pin, room);
    socketRooms.set(socket, { pin, role: 'host' });
    send(socket, { status: 'room_created', pin });
    console.info('Jam room created');
  }

  function joinRoom(socket, message) {
    if (socketRooms.has(socket)) return serverError(socket, 'Esta conexión ya pertenece a una sala.');
    const pin = normalizePin(message.pin);
    const guestName = normalizeName(message.guestName, limits.maxNameLength);
    const room = pin ? rooms.get(pin) : null;
    if (!room || !guestName) return failedAttempt(socket, 'Sala no encontrada o PIN inválido.');
    if (guestName === room.hostName || [...room.guests].some((g) => g.name === guestName)) {
      return serverError(socket, 'Ya hay un participante con ese nombre en la sala.');
    }
    if (room.guests.size + 1 >= limits.maxParticipants) return serverError(socket, 'La sala alcanzó el límite de participantes.');
    const guest = { socket, name: guestName };
    room.guests.add(guest);
    room.updatedAt = Date.now();
    socketRooms.set(socket, { pin, role: 'guest', guest });
    send(socket, { status: 'joined', state: room.state });
    send(room.host, { event: 'guest_joined', guestName, totalParticipants: room.guests.size + 1 });
  }

  function updateState(socket, message) {
    const membership = socketRooms.get(socket);
    const pin = normalizePin(message.pin);
    const room = pin ? rooms.get(pin) : null;
    if (!membership || !room || membership.pin !== pin || membership.role !== 'host' || room.host !== socket) {
      return serverError(socket, 'Sólo el anfitrión puede actualizar el estado.');
    }
    const state = normalizeState(message.state, limits, room.state);
    if (!state) return serverError(socket, 'Estado de reproducción inválido.');
    room.state = state;
    room.updatedAt = Date.now();
    for (const guest of room.guests) send(guest.socket, { event: 'sync_state', state });
  }

  function relayGuestAction(socket, message) {
    const membership = socketRooms.get(socket);
    if (!membership || membership.role !== 'guest') {
      return serverError(socket, 'Sólo los invitados pueden enviar acciones.');
    }
    const room = rooms.get(membership.pin);
    if (!room || !room.host) {
      return serverError(socket, 'Sala no encontrada.');
    }
    if (typeof message.actionType !== 'string' || !allowedGuestActions.has(message.actionType)) {
      return serverError(socket, 'Acción de invitado no permitida.');
    }
    if (message.payload !== undefined && message.payload !== null &&
        (typeof message.payload !== 'object' || Array.isArray(message.payload))) {
      return serverError(socket, 'Payload inválido.');
    }
    send(room.host, {
      event: 'guest_action',
      guestName: membership.guest?.name ?? 'Invitado',
      actionType: message.actionType,
      payload: message.payload,
    });
  }

  function kickGuest(socket, message) {
    const membership = socketRooms.get(socket);
    const pin = normalizePin(message.pin);
    const room = pin ? rooms.get(pin) : null;
    if (!membership || !room || membership.pin !== pin || membership.role !== 'host' || room.host !== socket) {
      return serverError(socket, 'Sólo el anfitrión puede expulsar invitados.');
    }
    const guestName = normalizeName(message.guestName, limits.maxNameLength);
    if (!guestName) return serverError(socket, 'Nombre de invitado inválido.');
    let found = false;
    for (const guest of room.guests) {
      if (guest.name === guestName) {
        found = true;
        send(guest.socket, { event: 'kicked', message: 'Has sido expulsado de la sala por el anfitrión.' });
        guest.socket.close(1000, 'Kicked by host');
        room.guests.delete(guest);
        room.updatedAt = Date.now();
        break;
      }
    }
    if (found) {
      send(socket, { status: 'guest_kicked', guestName, totalParticipants: room.guests.size + 1 });
    }
  }

  function checkRoom(socket, message) {
    const pin = normalizePin(message.pin);
    const room = pin ? rooms.get(pin) : null;
    if (!room) {
      return failedAttempt(socket, null, { status: 'not_found', pin });
    }
    const { queue: _queue, ...stateWithoutQueue } = room.state;
    return send(socket, {
      status: 'room_found',
      pin: room.pin,
      hostName: room.hostName,
      state: stateWithoutQueue,
      participantCount: room.guests.size + 1,
    });
  }

  websocketServer.on('connection', (socket) => {
    socket.isAlive = true;
    socket.on('pong', () => { socket.isAlive = true; });
    socket.on('message', (raw, isBinary) => {
      if (isBinary) return serverError(socket, 'Sólo se aceptan mensajes JSON.');
      let message;
      try {
        message = JSON.parse(raw.toString());
      } catch {
        return serverError(socket, 'JSON inválido.');
      }
      if (!message || typeof message !== 'object' || Array.isArray(message)) {
        return serverError(socket, 'Mensaje inválido.');
      }
      switch (message.action) {
        case 'create_room': return createRoom(socket, message);
        case 'join_room': return joinRoom(socket, message);
        case 'update_state': return updateState(socket, message);
        case 'guest_action': return relayGuestAction(socket, message);
        case 'kick_guest': return kickGuest(socket, message);
        case 'check_room': return checkRoom(socket, message);
        default: return serverError(socket, 'Acción no permitida.');
      }
    });
    socket.on('close', () => removeSocket(socket));
    socket.on('error', () => removeSocket(socket));
  });

  const heartbeatTimer = setInterval(() => {
    for (const socket of websocketServer.clients) {
      if (!socket.isAlive) {
        socket.terminate();
        continue;
      }
      socket.isAlive = false;
      socket.ping();
    }
  }, limits.heartbeatMs);
  heartbeatTimer.unref();

  const expiryTimer = setInterval(() => {
    const threshold = Date.now() - limits.roomIdleMs;
    for (const room of rooms.values()) {
      if (room.updatedAt < threshold) closeRoom(room, 'La sala Jam expiró por inactividad.');
    }
  }, Math.min(limits.roomIdleMs, 60 * 1000));
  expiryTimer.unref();

  return {
    get port() {
      const address = httpServer.address();
      return typeof address === 'object' && address ? address.port : null;
    },
    async start() {
      await new Promise((resolve, reject) => {
        httpServer.once('error', reject);
        httpServer.listen(port ?? 8080, host, () => {
          httpServer.off('error', reject);
          resolve();
        });
      });
      console.info(`Scrotify Jam server listening on ${host}:${this.port}`);
    },
    async stop() {
      clearInterval(expiryTimer);
      clearInterval(heartbeatTimer);
      for (const room of [...rooms.values()]) closeRoom(room, 'El servidor Jam se está apagando.');
      await new Promise((resolve) => websocketServer.close(() => resolve()));
      await new Promise((resolve) => httpServer.close(() => resolve()));
    },
  };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const server = createJamServer({
    port: readPositiveInteger(process.env.PORT, 8080),
    maxMessageBytes: readPositiveInteger(process.env.MAX_MESSAGE_BYTES, defaultLimits.maxMessageBytes),
    maxParticipants: readPositiveInteger(process.env.MAX_PARTICIPANTS, defaultLimits.maxParticipants),
    roomIdleMs: readPositiveInteger(process.env.ROOM_IDLE_MS, defaultLimits.roomIdleMs),
    publicHost: process.env.PUBLIC_HOST || undefined,
  });
  await server.start();
  const shutdown = async () => {
    await server.stop();
    process.exit(0);
  };
  process.once('SIGTERM', shutdown);
  process.once('SIGINT', shutdown);
}
