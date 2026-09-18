import http from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';

const defaultLimits = {
  maxMessageBytes: 16 * 1024,
  maxNameLength: 48,
  maxQueueLength: 500,
  maxParticipants: 50,
  roomIdleMs: 60 * 60 * 1000,
};

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

function normalizeState(value, limits) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
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
  } = value;

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
    } else if (item && typeof item === 'object') {
      normalizedQueue.push(item);
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
  if (typeof albumArtUrl === 'string') res.albumArtUrl = albumArtUrl.slice(0, 1024);
  if (typeof duration === 'number') res.duration = duration;
  if (typeof mode === 'string') res.mode = mode;
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
        publicRooms.push({
          pin: room.pin,
          hostName: room.hostName,
          sessionTitle: `Jam de ${room.hostName}`,
          participantCount: room.guests.size + 1,
          currentTrackTitle: room.state?.title ?? null,
          currentTrackArtist: room.state?.artist ?? null,
          albumArtUrl: room.state?.albumArtUrl ?? null,
          mode: room.state?.mode ?? 'partySpeaker',
          host: 'jam.templo.cloud',
          port: 443,
          remoteHost: 'jam.templo.cloud',
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

  function closeRoom(room, reason = 'El anfitrión ha finalizado la sesión Jam') {
    if (rooms.get(room.pin) !== room) return;
    rooms.delete(room.pin);
    for (const guest of room.guests) {
      send(guest.socket, { event: 'room_closed', message: reason });
      guest.socket.close(1000, 'Room closed');
    }
    room.guests.clear();
    console.info(`Jam room closed (${room.guests.size} guests)`);
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
    const room = { pin, host: socket, hostName, state, guests: new Set(), updatedAt: Date.now() };
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
    if (!room || !guestName) return serverError(socket, 'Sala no encontrada o PIN inválido.');
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
    const state = normalizeState(message.state, limits);
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
    send(room.host, {
      event: 'guest_action',
      guestName: membership.guest?.name ?? 'Invitado',
      actionType: message.actionType,
      payload: message.payload,
    });
  }

  function checkRoom(socket, message) {
    const pin = normalizePin(message.pin);
    const room = pin ? rooms.get(pin) : null;
    if (!room) {
      return send(socket, { status: 'not_found', pin });
    }
    return send(socket, {
      status: 'room_found',
      pin: room.pin,
      hostName: room.hostName,
      state: room.state,
      participantCount: room.guests.size + 1,
    });
  }

  websocketServer.on('connection', (socket) => {
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
        case 'check_room': return checkRoom(socket, message);
        default: return serverError(socket, 'Acción no permitida.');
      }
    });
    socket.on('close', () => removeSocket(socket));
    socket.on('error', () => removeSocket(socket));
  });

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
  });
  await server.start();
  const shutdown = async () => {
    await server.stop();
    process.exit(0);
  };
  process.once('SIGTERM', shutdown);
  process.once('SIGINT', shutdown);
}
