import crypto from 'node:crypto';
import { mkdirSync } from 'node:fs';
import http from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';

import { createAdmin } from './admin.js';
import { openStore, SETTING_DEFS } from './config.js';
import { createGuard } from './guard.js';

export const PROTOCOL_VERSION = 2;
const MAX_NAME_LENGTH = 48;
const REACTIONS = new Set(['👍', '❤️', '🔥', '😂', '🎉', '👏', '😮', '🎶']);
const MAX_CHAT_LENGTH = 280;
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
  // Estos dos son efímeros: se toman solo del mensaje actual (no del merge).
  const { nextHint, refTs } = value;

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
  // Metadatos de la pista actual: se toman del mensaje actual, no del merge,
  // para que no sobrevivan al cambio de pista.
  if (typeof value.mbid === 'string') res.mbid = value.mbid.slice(0, 64);
  if (typeof value.isrc === 'string') res.isrc = value.isrc.slice(0, 32);
  if (Number.isInteger(value.trackNumber)) res.trackNumber = value.trackNumber;
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
  if (Number.isFinite(refTs)) res.refTs = Math.floor(refTs);
  if (nextHint && typeof nextHint === 'object' && !Array.isArray(nextHint)) res.nextHint = nextHint;
  if (Array.isArray(pendingRequests)) {
    res.pendingRequests = pendingRequests.filter((r) => r && typeof r === 'object').slice(0, 50);
  }

  // Un valor inválido no borra el último válido.
  for (const key of ['queueMode', 'fairTurnsPerPerson', 'requireApproval']) {
    if (res[key] === undefined && existingState?.[key] !== undefined) res[key] = existingState[key];
  }

  return res;
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest();
}

function newToken() {
  return crypto.randomBytes(16).toString('hex'); // 128 bits
}

function tokenMatches(token, expectedHash) {
  if (typeof token !== 'string' || !expectedHash) return false;
  return crypto.timingSafeEqual(sha256(token), expectedHash);
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
  if (socket && socket.readyState === WebSocket.OPEN) {
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
  // Chat comunitario ("lobby") por canal (p. ej. el host de Navidrome). Solo RAM.
  const lobby = new Map(); // channel -> [{ username, time, message }]
  const LOBBY_KEEP = 100;
  const LOBBY_MAX_AGE_MS = 24 * 3600 * 1000;
  const LOBBY_MAX_CHANNELS = 200;
  const LOBBY_MAX_MESSAGE = 2048;
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
    if (request.method === 'GET' && path === '/.well-known/assetlinks.json' && limits.assetLinksJson) {
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end(limits.assetLinksJson);
      return;
    }
    if (request.method === 'GET' && path === '/.well-known/apple-app-site-association' && limits.appleAppSiteAssociation) {
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end(limits.appleAppSiteAssociation);
      return;
    }
    const linkMatch = path?.match(/^\/j\/([A-Za-z0-9-]{1,12})$/);
    if (request.method === 'GET' && linkMatch && limits.webLinkEnabled) {
      const code = normalizePin(linkMatch[1]);
      if (!code) {
        response.writeHead(404);
        response.end();
        return;
      }
      const server = limits.publicUrl ? new URL(limits.publicUrl).host : (request.headers.host ?? '');
      const deep = `scrotify://join?code=${code}&server=${encodeURIComponent(server)}`;
      response.writeHead(200, {
        'content-type': 'text/html; charset=utf-8',
        'content-security-policy': "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; base-uri 'none'",
        'x-frame-options': 'DENY',
        'referrer-policy': 'no-referrer',
      });
      response.end(`<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Unirse a la Jam</title><style>body{font:16px system-ui;background:#121212;color:#eee;text-align:center;padding:48px 16px}a.b{display:inline-block;background:#1db954;color:#000;padding:12px 24px;border-radius:24px;text-decoration:none;margin:16px}code{font-size:28px;letter-spacing:4px}</style></head><body><h1>Te invitaron a una Jam de Scrotify</h1><p>PIN de la sala</p><p><code>${code}</code></p><a class="b" href="${deep}">Abrir en Scrotify</a><p>¿No tienes la app? Instala Scrotify, abre <b>Jam → Unirse</b> e introduce el PIN.</p><script>setTimeout(function(){location.href=${JSON.stringify(deep)}},300)</script></body></html>`);
      return;
    }
    if (path === '/api/lobby/messages') {
      handleLobby(request, response);
      return;
    }
    if (request.method === 'GET' && path === '/api/capabilities') {
      response.writeHead(200, { 'content-type': 'application/json', 'access-control-allow-origin': '*' });
      response.end(JSON.stringify({
        protocolVersion: PROTOCOL_VERSION,
        features: {
          publicListing: limits.publicListingEnabled,
          chat: limits.chatEnabled,
          reactions: limits.reactionsEnabled,
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
  function handleLobby(request, response) {
    const reply = (status, body) => {
      response.writeHead(status, { 'content-type': 'application/json', 'access-control-allow-origin': '*', 'cache-control': 'no-store' });
      response.end(JSON.stringify(body));
    };
    if (!limits.chatEnabled) return reply(403, { error: 'El chat está desactivado en este servidor.' });
    const ip = clientIp(request, trustProxy);
    if (store.isBlockedIp(ip)) return reply(403, { error: 'Acceso denegado.' });
    const url = new URL(request.url, 'http://x');
    const validChannel = (c) => typeof c === 'string' && /^[a-z0-9.:_-]{1,100}$/.test(c);
    const now = Date.now();
    const prune = (list) => list.filter((m) => now - m.time < LOBBY_MAX_AGE_MS);

    if (request.method === 'GET') {
      const channel = url.searchParams.get('channel');
      if (!validChannel(channel)) return reply(400, { error: 'Canal inválido.' });
      const gate = guard.attempt(`lobby-read:${ip}`, { max: 60, windowMs: 60_000 });
      if (!gate.ok) return reply(429, { error: 'Demasiadas consultas.' });
      const since = Number(url.searchParams.get('since') ?? 0) || 0;
      const list = prune(lobby.get(channel) ?? []);
      lobby.set(channel, list);
      return reply(200, { messages: list.filter((m) => m.time > since) });
    }
    if (request.method === 'POST') {
      const chunks = [];
      let size = 0;
      request.on('data', (c) => { size += c.length; if (size <= 8192) chunks.push(c); });
      request.on('end', () => {
        if (size > 8192) return reply(413, { error: 'Mensaje demasiado grande.' });
        let body;
        try { body = JSON.parse(Buffer.concat(chunks).toString()); } catch { return reply(400, { error: 'JSON inválido.' }); }
        const gate = guard.attempt(`lobby-write:${ip}`, { max: 10, windowMs: 10_000 });
        if (!gate.ok) return reply(429, { error: 'Vas demasiado rápido.' });
        const username = normalizeName(body.username, limits.maxNameLength);
        const message = typeof body.message === 'string'
          ? body.message.replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, ' ').trim() : '';
        if (!validChannel(body.channel) || !username || !message || message.length > LOBBY_MAX_MESSAGE) {
          return reply(400, { error: 'Datos de mensaje inválidos.' });
        }
        if (!lobby.has(body.channel) && lobby.size >= LOBBY_MAX_CHANNELS) lobby.delete(lobby.keys().next().value);
        let list = prune(lobby.get(body.channel) ?? []);
        // Los anuncios de Jam se refrescan a menudo: se conserva solo el último por sesión.
        if (message.startsWith('[JAM_LIVE]:')) {
          try {
            const sid = JSON.parse(message.slice('[JAM_LIVE]:'.length)).sessionId;
            if (typeof sid === 'string') {
              list = list.filter((m) => {
                if (!m.message.startsWith('[JAM_LIVE]:')) return true;
                try { return JSON.parse(m.message.slice('[JAM_LIVE]:'.length)).sessionId !== sid; } catch { return true; }
              });
            }
          } catch { /* mensaje malformado: se guarda tal cual */ }
        }
        // time estrictamente creciente para que `since` no pierda mensajes.
        const time = Math.max(now, (list.at(-1)?.time ?? 0) + 1);
        list.push({ username, time, message });
        lobby.set(body.channel, list.slice(-LOBBY_KEEP));
        return reply(200, { ok: true, time });
      });
      return;
    }
    reply(405, { error: 'Método no permitido.' });
  }

  const websocketServer = new WebSocketServer({
    server: httpServer,
    maxPayload: limits.maxMessageBytes,
  });
  logs.push('Servidor iniciado');

  const PERSISTED_CONFIG_KEYS = ['allowGuestControls', 'allowGuestQueueManage', 'queueMode', 'fairTurnsPerPerson', 'requireApproval', 'mode'];

  /// Persiste solo la configuración de una sala persistente (nunca qué suena).
  function persistRoomConfig(room) {
    if (!room.persistent) return;
    const config = {};
    for (const key of PERSISTED_CONFIG_KEYS) if (room.state?.[key] !== undefined) config[key] = room.state[key];
    store.touchPersistentRoom(room.pin, config);
  }

  function closeRoom(room, reason = 'El anfitrión ha finalizado la sesión Jam') {
    if (rooms.get(room.pin) !== room) return;
    rooms.delete(room.pin);
    clearTimeout(room.failoverTimer);
    persistRoomConfig(room);
    for (const guest of room.guests) {
      send(guest.socket, { event: 'room_closed', message: reason });
      guest.socket.close(1000, 'Room closed');
    }
    room.guests.clear();
    console.info('Jam room closed');
  }

  function roster(room) {
    return [...room.guests].map((g) => ({ id: g.id, name: g.name }));
  }

  /// Convierte a [guest] en anfitrión: recibe estado, roster y un hostToken nuevo.
  function promoteGuest(room, guest, reason) {
    room.guests.delete(guest);
    clearTimeout(room.failoverTimer);
    room.host = guest.socket;
    room.hostName = guest.name;
    room.hostGone = false;
    const hostToken = newToken();
    room.hostTokenHash = sha256(hostToken);
    socketRooms.set(guest.socket, { pin: room.pin, role: 'host' });
    room.updatedAt = Date.now();
    send(guest.socket, {
      event: 'host_changed', youAreHost: true, reason, hostToken,
      hostName: room.hostName, hostId: guest.id, state: room.state, guests: roster(room),
    });
    for (const other of room.guests) {
      send(other.socket, { event: 'host_changed', youAreHost: false, reason, hostName: room.hostName, hostId: guest.id });
    }
    logs.push(`Anfitrión cambiado (${reason})`);
  }

  function startFailoverTimer(room) {
    clearTimeout(room.failoverTimer);
    room.failoverTimer = setTimeout(() => {
      if (rooms.get(room.pin) !== room || !room.hostGone) return;
      // Solo se promueve si los invitados pueden gestionar la cola (el host lo permitió).
      const eligible = room.state?.allowGuestQueueManage !== false
        ? [...room.guests].sort((a, b) => a.joinedAt - b.joinedAt)[0]
        : null;
      if (eligible) promoteGuest(room, eligible, 'failover');
      else closeRoom(room, 'El anfitrión se desconectó y no hay quien lo sustituya.');
    }, limits.hostFailoverMs);
    room.failoverTimer.unref?.();
  }

  function removeSocket(socket) {
    const membership = socketRooms.get(socket);
    if (!membership) return;
    socketRooms.delete(socket);
    const room = rooms.get(membership.pin);
    if (!room) return;
    if (membership.role === 'host' && room.host === socket) {
      if (room.failover && limits.hostFailoverMs > 0 && room.guests.size > 0) {
        room.host = null;
        room.hostGone = true;
        for (const g of room.guests) send(g.socket, { event: 'host_away', failoverMs: limits.hostFailoverMs });
        startFailoverTimer(room);
        return;
      }
      closeRoom(room);
      return;
    }
    if (membership.role === 'guest') {
      room.guests.delete(membership.guest);
      room.updatedAt = Date.now();
    }
  }

  function ownerTokenValid(persistent, token) {
    if (typeof token !== 'string') return false;
    const given = crypto.scryptSync(token, persistent.ownerSalt, 64).toString('hex');
    return given.length === persistent.ownerHash.length &&
      crypto.timingSafeEqual(Buffer.from(given, 'hex'), Buffer.from(persistent.ownerHash, 'hex'));
  }

  function createRoom(socket, message) {
    if (socketRooms.has(socket)) return serverError(socket, 'Esta conexión ya pertenece a una sala.');
    const pin = normalizePin(message.pin);
    const hostName = normalizeName(message.hostName, limits.maxNameLength);
    const state = normalizeState(message.initialState, limits);
    if (!pin || !hostName || !state) return serverError(socket, 'Datos de sala inválidos.');
    if (rooms.has(pin)) return serverError(socket, 'Ese PIN ya está en uso.');
    // PIN reservado por una sala persistente: solo su propietario puede reclamarlo.
    store.purgeExpiredPersistentRooms();
    const persistent = limits.persistentRoomsEnabled ? store.getPersistentRoom(pin) : null;
    if (persistent && !ownerTokenValid(persistent, message.ownerToken)) {
      return serverError(socket, 'Ese PIN ya está en uso.');
    }
    if (rooms.size >= limits.maxRooms) return serverError(socket, 'El servidor alcanzó el límite de salas.');
    let password = null;
    if (message.roomPassword !== undefined && message.roomPassword !== null && message.roomPassword !== '') {
      if (typeof message.roomPassword !== 'string' || message.roomPassword.length < 4 || message.roomPassword.length > 128) {
        return serverError(socket, 'Contraseña de sala inválida (4–128 caracteres).');
      }
      password = hashRoomPassword(message.roomPassword);
    }
    const hostToken = newToken();
    const room = {
      pin, host: socket, hostName, state, guests: new Set(), updatedAt: Date.now(),
      password, banned: new Set(), hostTokenHash: sha256(hostToken), hostGone: false,
      failover: message.failover === true, failoverTimer: null,
      persistent: !!persistent,
    };
    rooms.set(pin, room);
    socketRooms.set(socket, { pin, role: 'host' });
    if (persistent) store.touchPersistentRoom(pin);
    send(socket, {
      status: 'room_created', pin, hostToken,
      ...(persistent ? { persistent: true, name: persistent.name, config: persistent.config } : {}),
    });
    console.info('Jam room created');
  }

  /// El anfitrión recupera su sala tras una caída (dentro de hostFailoverMs).
  function resumeHost(socket, message) {
    if (socketRooms.has(socket)) return serverError(socket, 'Esta conexión ya pertenece a una sala.');
    if (!admitAttempt(socket)) return;
    const pin = normalizePin(message.pin);
    const room = pin ? rooms.get(pin) : null;
    if (!room || !tokenMatches(message.hostToken, room.hostTokenHash)) {
      failAttempt(socket);
      return serverError(socket, 'No se pudo recuperar la sala.');
    }
    guard.success(socketIps.get(socket) ?? 'unknown');
    if (room.host && room.host !== socket) {
      socketRooms.delete(room.host);
      room.host.close(1000, 'Replaced by resumed host');
    }
    clearTimeout(room.failoverTimer);
    room.host = socket;
    room.hostGone = false;
    room.updatedAt = Date.now();
    socketRooms.set(socket, { pin, role: 'host' });
    send(socket, { status: 'host_resumed', pin, state: room.state, guests: roster(room) });
    for (const g of room.guests) send(g.socket, { event: 'host_back' });
  }

  /// El anfitrión cede el control a un invitado; el anterior pasa a invitado.
  function transferHost(socket, message) {
    const membership = socketRooms.get(socket);
    const pin = normalizePin(message.pin);
    const room = pin ? rooms.get(pin) : null;
    if (!membership || !room || membership.pin !== pin || membership.role !== 'host' || room.host !== socket) {
      return serverError(socket, 'Sólo el anfitrión puede transferir la sala.');
    }
    const target = [...room.guests].find((g) => g.id === message.toGuestId);
    if (!target) return serverError(socket, 'Invitado no encontrado.');
    const former = { socket, name: room.hostName, id: crypto.randomBytes(6).toString('hex'), joinedAt: Date.now() };
    room.guests.add(former);
    socketRooms.set(socket, { pin, role: 'guest', guest: former });
    promoteGuest(room, target, 'transfer');
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
    const guest = { socket, name: guestName, id: crypto.randomBytes(6).toString('hex'), joinedAt: Date.now() };
    room.guests.add(guest);
    room.updatedAt = Date.now();
    socketRooms.set(socket, { pin, role: 'guest', guest });
    send(socket, { status: 'joined', state: room.state });
    send(room.host, { event: 'guest_joined', guestName, guestId: guest.id, totalParticipants: room.guests.size + 1 });
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
    persistRoomConfig(room);
    for (const guest of room.guests) send(guest.socket, { event: 'sync_state', state });
  }

  function relayGuestAction(socket, message) {
    const membership = socketRooms.get(socket);
    if (!membership || membership.role !== 'guest') {
      return serverError(socket, 'Sólo los invitados pueden enviar acciones.');
    }
    const room = rooms.get(membership.pin);
    if (!room) return serverError(socket, 'Sala no encontrada.');
    if (!room.host) return serverError(socket, 'El anfitrión no está conectado ahora mismo.');
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

  /// Mínimo de milisegundos entre mensajes sociales por socket (anti-spam).
  const social = new WeakMap();
  function socialAllowed(socket, kind, max, windowMs) {
    const now = Date.now();
    const byKind = social.get(socket) ?? {};
    const list = (byKind[kind] ?? []).filter((t) => now - t < windowMs);
    if (list.length >= max) return false;
    list.push(now);
    byKind[kind] = list;
    social.set(socket, byKind);
    return true;
  }

  /// Quién envía y a quién se reenvía: todos los miembros de la sala menos el emisor.
  function socialContext(socket) {
    const membership = socketRooms.get(socket);
    const room = membership ? rooms.get(membership.pin) : null;
    if (!room) return null;
    const from = membership.role === 'host' ? room.hostName : membership.guest?.name ?? 'Invitado';
    const recipients = [room.host, ...[...room.guests].map((g) => g.socket)].filter((s) => s && s !== socket);
    return { room, from, recipients };
  }

  function reaction(socket, message) {
    if (!limits.reactionsEnabled) return serverError(socket, 'Las reacciones están desactivadas en este servidor.');
    const ctx = socialContext(socket);
    if (!ctx) return serverError(socket, 'No perteneces a ninguna sala.');
    if (typeof message.emoji !== 'string' || !REACTIONS.has(message.emoji)) return serverError(socket, 'Reacción no permitida.');
    if (!socialAllowed(socket, 'reaction', 5, 5000)) return; // se descarta en silencio
    for (const s of ctx.recipients) send(s, { event: 'reaction', from: ctx.from, emoji: message.emoji });
  }

  function chat(socket, message) {
    if (!limits.chatEnabled) return serverError(socket, 'El chat está desactivado en este servidor.');
    const ctx = socialContext(socket);
    if (!ctx) return serverError(socket, 'No perteneces a ninguna sala.');
    if (ctx.room.chatDisabled) return serverError(socket, 'El anfitrión desactivó el chat de esta sala.');
    if (typeof message.text !== 'string') return serverError(socket, 'Mensaje inválido.');
    // Sin historial: solo se reenvía. Se descartan caracteres de control.
    const text = message.text.replace(/[\u0000-\u001f\u007f]/g, ' ').trim();
    if (text.length === 0 || text.length > MAX_CHAT_LENGTH) return serverError(socket, `El mensaje debe tener entre 1 y ${MAX_CHAT_LENGTH} caracteres.`);
    if (!socialAllowed(socket, 'chat', 5, 10000)) return serverError(socket, 'Vas demasiado rápido.');
    const ts = Date.now();
    for (const s of ctx.recipients) send(s, { event: 'chat', from: ctx.from, text, ts });
  }

  function setChat(socket, message) {
    const membership = socketRooms.get(socket);
    const room = membership ? rooms.get(membership.pin) : null;
    if (!room || membership.role !== 'host' || room.host !== socket) return serverError(socket, 'Sólo el anfitrión puede cambiar el chat.');
    room.chatDisabled = message.enabled === false;
    for (const g of room.guests) send(g.socket, { event: 'chat_state', enabled: !room.chatDisabled });
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
        case 'resume_host': return resumeHost(socket, message);
        case 'reaction': return reaction(socket, message);
        case 'chat_message': return chat(socket, message);
        case 'set_chat': return setChat(socket, message);
        case 'transfer_host': return transferHost(socket, message);
        case 'time_ping':
          return send(socket, {
            status: 'time_pong',
            clientTs: Number.isFinite(message.clientTs) ? message.clientTs : null,
            serverNowMs: Date.now(),
          });
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
