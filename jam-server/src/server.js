import crypto from 'node:crypto';
import { mkdirSync } from 'node:fs';
import http from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';

import { createAdmin } from './admin.js';
import { openStore, SETTING_DEFS } from './config.js';
import { createGuard } from './guard.js';

export const PROTOCOL_VERSION = 2;
const MAX_NAME_LENGTH = 48;
const QUEUE_MODES = new Set(['free', 'fairTurns', 'voting', 'approval']);

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
    queueMode,
    fairTurnsPerPerson,
    requireApproval,
    pendingRequests,
  } = merged;

  if (trackId !== null && trackId !== undefined &&
      (typeof trackId !== 'string' || trackId.trim().length === 0)) {
    return null;
  }
  if (typeof position !== 'number' || !Number.isFinite(position)) return null;
  if (typeof isPlaying !== 'boolean' || !Array.isArray(queue) ||
      queue.length > limits.maxQueueItems) {
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
  if (typeof mode === 'string') res.mode = mode;
  if (typeof allowGuestControls === 'boolean') res.allowGuestControls = allowGuestControls;
  if (typeof allowGuestQueueManage === 'boolean') res.allowGuestQueueManage = allowGuestQueueManage;
  if (typeof queueMode === 'string' && QUEUE_MODES.has(queueMode)) res.queueMode = queueMode;
  if (Number.isInteger(fairTurnsPerPerson)) res.fairTurnsPerPerson = Math.min(10, Math.max(1, fairTurnsPerPerson));
  if (typeof requireApproval === 'boolean') res.requireApproval = requireApproval;
  if (Array.isArray(pendingRequests)) {
    res.pendingRequests = pendingRequests.filter((r) => r && typeof r === 'object').slice(0, 50);
  }

  // Un valor inválido no borra el último válido.
  for (const key of ['queueMode', 'fairTurnsPerPerson', 'requireApproval']) {
    if (res[key] === undefined && existingState?.[key] !== undefined) res[key] = existingState[key];
  }

  return res;
}

function hashRoomPassword(password, salt = crypto.randomBytes(16)) {
  return { salt, hash: crypto.scryptSync(password, salt, 32) };
}

function checkRoomPassword(room, password) {
  if (!room.password) return true;
  if (typeof password !== 'string') return false;
  const { hash } = hashRoomPassword(password, room.password.salt);
  return crypto.timingSafeEqual(hash, room.password.hash);
}

function send(socket, message) {
  if (socket.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify(message));
  }
}

function serverError(socket, message) {
  send(socket, { status: 'error', message });
}

function createLogBuffer(max = 200) {
  const entries = [];
  return {
    push(text) {
      entries.push(`${new Date().toISOString()} ${text}`);
      if (entries.length > max) entries.shift();
    },
    lines: () => [...entries],
  };
}

/// IP del cliente. Las cabeceras de proxy solo se respetan si `trustProxy`
/// lo indica explícitamente (`cloudflare` | `forwarded`), nunca por defecto.
function clientIp(request, trustProxy) {
  const header = (name) => {
    const v = request.headers[name];
    return typeof v === 'string' ? v.split(',')[0].trim() : null;
  };
  if (trustProxy === 'cloudflare') return header('cf-connecting-ip') ?? request.socket.remoteAddress ?? 'unknown';
  if (trustProxy === 'forwarded') return header('x-forwarded-for') ?? request.socket.remoteAddress ?? 'unknown';
  return request.socket.remoteAddress ?? 'unknown';
}

export function createJamServer({
  port,
  host = '0.0.0.0',
  dbPath = ':memory:',
  adminPassword,
  trustProxy = 'none',
  loginMaxFailures,
  ...overrides
} = {}) {
  const store = openStore(dbPath, overrides);
  const limits = { maxNameLength: MAX_NAME_LENGTH };
  for (const key of Object.keys(SETTING_DEFS)) {
    Object.defineProperty(limits, key, { get: () => store.get(key), enumerable: true });
  }
  const startedAt = Date.now();
  const logs = createLogBuffer();
  const rooms = new Map();
  const socketRooms = new WeakMap();
  const socketIps = new WeakMap();
  const guard = createGuard();
  const admin = createAdmin({
    store,
    adminPassword,
    loginMaxFailures,
    logs,
    getStatus: () => {
      let participants = 0;
      for (const room of rooms.values()) participants += room.guests.size + 1;
      return {
        rooms: rooms.size,
        participants,
        uptimeSec: Math.floor((Date.now() - startedAt) / 1000),
        memoryMb: Math.round(process.memoryUsage().rss / (1024 * 1024)),
      };
    },
  });
  const httpServer = http.createServer(async (request, response) => {
    const path = request.url?.split('?')[0];
    if (path === '/admin' || path?.startsWith('/admin/')) {
      await admin.handle(request, response, clientIp(request, trustProxy));
      websocketServer.options.maxPayload = limits.maxMessageBytes;
      return;
    }
    if (request.method === 'GET' && path === '/api/capabilities') {
      response.writeHead(200, { 'content-type': 'application/json', 'access-control-allow-origin': '*' });
      response.end(JSON.stringify({
        protocolVersion: PROTOCOL_VERSION,
        features: {
          publicListing: limits.publicListingEnabled,
          chat: limits.chatEnabled,
          persistentRooms: limits.persistentRoomsEnabled,
          webLink: limits.webLinkEnabled,
        },
        limits: {
          maxParticipants: limits.maxParticipants,
          maxQueueItems: limits.maxQueueItems,
          maxMessageBytes: limits.maxMessageBytes,
        },
        publicUrl: limits.publicUrl || null,
      }));
      return;
    }
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
      let publicHost = request.headers.host?.split(':')[0] ?? 'localhost';
      let publicPort = 443;
      if (limits.publicUrl) {
        const parsed = new URL(limits.publicUrl);
        publicHost = parsed.hostname;
        publicPort = parsed.port ? Number(parsed.port) : (parsed.protocol === 'https:' ? 443 : 80);
      }
      for (const room of limits.publicListingEnabled ? rooms.values() : []) {
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
          port: publicPort,
          remoteHost: publicHost,
          remotePort: publicPort,
          isPublic: true,
          hasPassword: !!room.password,
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
  logs.push('Servidor iniciado');

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
    if (rooms.size >= limits.maxRooms) return serverError(socket, 'El servidor alcanzó el límite de salas.');
    let password = null;
    if (message.roomPassword !== undefined && message.roomPassword !== null && message.roomPassword !== '') {
      if (typeof message.roomPassword !== 'string' || message.roomPassword.length < 4 || message.roomPassword.length > 128) {
        return serverError(socket, 'Contraseña de sala inválida (4–128 caracteres).');
      }
      password = hashRoomPassword(message.roomPassword);
    }
    const room = {
      pin, host: socket, hostName, state, guests: new Set(), updatedAt: Date.now(),
      password, banned: new Set(),
    };
    rooms.set(pin, room);
    socketRooms.set(socket, { pin, role: 'host' });
    send(socket, { status: 'room_created', pin });
    console.info('Jam room created');
  }

  /// Aplica ventana de intentos + bloqueo progresivo. `false` si hay que
  /// rechazar (ya se respondió al cliente).
  function admitAttempt(socket) {
    const ip = socketIps.get(socket) ?? 'unknown';
    if (store.isBlockedIp(ip)) {
      serverError(socket, 'Acceso denegado.');
      return false;
    }
    const gate = guard.attempt(ip, { max: limits.joinRateMax, windowMs: limits.joinRateWindowMs });
    if (!gate.ok) {
      send(socket, { status: 'error', message: 'Demasiados intentos. Prueba más tarde.', retryAfterMs: gate.retryMs });
      return false;
    }
    return true;
  }

  function failAttempt(socket) {
    guard.fail(socketIps.get(socket) ?? 'unknown', { max: limits.pinFailMax });
  }

  function joinRoom(socket, message) {
    if (socketRooms.has(socket)) return serverError(socket, 'Esta conexión ya pertenece a una sala.');
    if (!admitAttempt(socket)) return;
    const pin = normalizePin(message.pin);
    const guestName = normalizeName(message.guestName, limits.maxNameLength);
    const room = pin ? rooms.get(pin) : null;
    // Misma respuesta para PIN inexistente y contraseña errónea: no revelar cuál.
    if (!room || !guestName || !checkRoomPassword(room, message.roomPassword)) {
      failAttempt(socket);
      return serverError(socket, 'Sala no encontrada o PIN inválido.');
    }
    if (room.banned.has(guestName.toLowerCase())) {
      failAttempt(socket);
      return serverError(socket, 'Sala no encontrada o PIN inválido.');
    }
    if (room.guests.size + 1 >= limits.maxParticipants) return serverError(socket, 'La sala alcanzó el límite de participantes.');
    guard.success(socketIps.get(socket) ?? 'unknown');
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
    room.banned.add(guestName.toLowerCase());
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
    if (!admitAttempt(socket)) return;
    const pin = normalizePin(message.pin);
    const room = pin ? rooms.get(pin) : null;
    if (!room) {
      failAttempt(socket);
      return send(socket, { status: 'not_found', pin });
    }
    const unlocked = checkRoomPassword(room, message.roomPassword);
    return send(socket, {
      status: 'room_found',
      pin: room.pin,
      hostName: room.hostName,
      ...(unlocked ? { state: room.state } : {}),
      participantCount: room.guests.size + 1,
      hasPassword: !!room.password,
    });
  }

  websocketServer.on('connection', (socket, request) => {
    socketIps.set(socket, clientIp(request, trustProxy));
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

  const expiryTimer = setInterval(() => {
    const threshold = Date.now() - limits.roomIdleMs;
    for (const room of rooms.values()) {
      if (room.updatedAt < threshold) closeRoom(room, 'La sala Jam expiró por inactividad.');
    }
  }, 5 * 1000);
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
      store.close();
    },
  };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const envInt = (name) => {
    const parsed = Number.parseInt(process.env[name] ?? '', 10);
    return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : undefined;
  };
  const dataDir = process.env.DATA_DIR ?? '/data';
  mkdirSync(dataDir, { recursive: true });
  const server = createJamServer({
    port: envInt('PORT') ?? 8080,
    dbPath: `${dataDir}/jam.db`,
    adminPassword: process.env.ADMIN_PASSWORD,
    trustProxy: process.env.TRUST_PROXY ?? 'none',
    publicUrl: process.env.PUBLIC_URL || undefined,
    maxMessageBytes: envInt('MAX_MESSAGE_BYTES'),
    maxParticipants: envInt('MAX_PARTICIPANTS'),
    roomIdleMs: envInt('ROOM_IDLE_MS'),
  });
  await server.start();
  const shutdown = async () => {
    await server.stop();
    process.exit(0);
  };
  process.once('SIGTERM', shutdown);
  process.once('SIGINT', shutdown);
}
