import assert from 'node:assert/strict';
import { afterEach, test } from 'node:test';
import { WebSocket } from 'ws';

import { createCrotoLinkServer } from '../src/server.js';

const running = [];

afterEach(async () => {
  await Promise.all(running.splice(0).map((server) => server.stop()));
});

async function startServer(options) {
  const server = createCrotoLinkServer({ port: 0, ...options });
  await server.start();
  running.push(server);
  return server;
}

function connect(url) {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(url);
    socket.once('open', () => resolve(socket));
    socket.once('error', reject);
  });
}

function nextMessage(socket) {
  return new Promise((resolve, reject) => {
    socket.once('message', (data) => resolve(JSON.parse(data.toString())));
    socket.once('error', reject);
  });
}

const initialState = {
  trackId: 'track-1',
  position: 0,
  isPlaying: false,
  queue: ['track-2'],
};

test('creates a room, joins a guest, and broadcasts host state', async () => {
  const server = await startServer();
  const endpoint = `ws://127.0.0.1:${server.port}`;
  const host = await connect(endpoint);

  const created = nextMessage(host);
  host.send(JSON.stringify({
    action: 'create_room',
    pin: 'GCG-36B',
    hostName: 'Proyecto',
    initialState,
  }));
  const createdMsg = await created;
  assert.equal(createdMsg.status, 'room_created');
  assert.equal(createdMsg.pin, 'GCG36B');
  assert.match(createdMsg.hostToken, /^[0-9a-f]{32}$/); // 128 bits

  const guest = await connect(endpoint);
  const hostJoined = nextMessage(host);
  const joined = nextMessage(guest);
  guest.send(JSON.stringify({
    action: 'join_room',
    pin: 'GCG-36B',
    guestName: 'Amigo',
  }));

  assert.deepEqual(await joined, { status: 'joined', state: initialState });
  const joinedEvent = await hostJoined;
  assert.match(joinedEvent.guestId, /^[0-9a-f]{12}$/);
  delete joinedEvent.guestId;
  assert.deepEqual(joinedEvent, {
    event: 'guest_joined',
    guestName: 'Amigo',
    totalParticipants: 2,
  });

  const sync = nextMessage(guest);
  host.send(JSON.stringify({
    action: 'update_state',
    pin: 'GCG36B',
    state: {
      trackId: 'track-3',
      position: 4500,
      isPlaying: true,
      queue: ['track-4', 'track-4'],
    },
  }));

  assert.deepEqual(await sync, {
    event: 'sync_state',
    state: {
      trackId: 'track-3',
      position: 4500,
      isPlaying: true,
      queue: ['track-4', 'track-4'],
    },
  });

  host.close();
  guest.close();
});

test('rejects an update from a guest and closes the room when host leaves', async () => {
  const server = await startServer();
  const endpoint = `ws://127.0.0.1:${server.port}`;
  const host = await connect(endpoint);
  host.send(JSON.stringify({
    action: 'create_room',
    pin: 'ABC123',
    hostName: 'Host',
    initialState,
  }));
  await nextMessage(host);

  const guest = await connect(endpoint);
  guest.send(JSON.stringify({
    action: 'join_room',
    pin: 'ABC123',
    guestName: 'Guest',
  }));
  await nextMessage(guest);
  await nextMessage(host);

  const denied = nextMessage(guest);
  guest.send(JSON.stringify({
    action: 'update_state',
    pin: 'ABC123',
    state: initialState,
  }));
  assert.equal((await denied).status, 'error');

  const closed = nextMessage(guest);
  host.close();
  guest.close();
});

test('relays guest actions to host and checks room info', async () => {
  const server = await startServer();
  const endpoint = `ws://127.0.0.1:${server.port}`;
  const host = await connect(endpoint);
  host.send(JSON.stringify({
    action: 'create_room',
    pin: 'ACT123',
    hostName: 'HostAction',
    initialState,
  }));
  await nextMessage(host);

  const guest = await connect(endpoint);
  guest.send(JSON.stringify({
    action: 'join_room',
    pin: 'ACT123',
    guestName: 'GuestAction',
  }));
  await nextMessage(guest);
  await nextMessage(host);

  const guestActionOnHost = nextMessage(host);
  guest.send(JSON.stringify({
    action: 'guest_action',
    actionType: 'queue_add',
    payload: { trackId: 'song-99' },
  }));

  assert.deepEqual(await guestActionOnHost, {
    event: 'guest_action',
    guestName: 'GuestAction',
    actionType: 'queue_add',
    payload: { trackId: 'song-99' },
  });

  const checkClient = await connect(endpoint);
  const checkRes = nextMessage(checkClient);
  checkClient.send(JSON.stringify({
    action: 'check_room',
    pin: 'ACT123',
  }));

  const res = await checkRes;
  assert.equal(res.status, 'room_found');
  assert.equal(res.pin, 'ACT123');
  assert.equal(res.hostName, 'HostAction');

  host.close();
  guest.close();
  checkClient.close();
});

test('supports partial state updates merging with previous state and parses string/number durations', async () => {
  const server = await startServer();
  const endpoint = `ws://127.0.0.1:${server.port}`;
  const host = await connect(endpoint);
  host.send(JSON.stringify({
    action: 'create_room',
    pin: 'DUR123',
    hostName: 'DurationHost',
    initialState: {
      trackId: 'track-d1',
      position: 1000,
      isPlaying: true,
      queue: ['track-d2'],
      duration: '215',
    },
  }));
  const created = await nextMessage(host);
  assert.equal(created.status, 'room_created');

  const guest = await connect(endpoint);
  const joined = nextMessage(guest);
  guest.send(JSON.stringify({
    action: 'join_room',
    pin: 'DUR123',
    guestName: 'GuestDuration',
  }));
  const joinedRes = await joined;
  assert.equal(joinedRes.status, 'joined');
  assert.equal(joinedRes.state.duration, 215);

  const synced = nextMessage(guest);
  // Partial update: only changing allowGuestControls and mode, without re-sending queue or position
  host.send(JSON.stringify({
    action: 'update_state',
    pin: 'DUR123',
    state: {
      mode: 'synchronizedListening',
      allowGuestControls: false,
    },
  }));

  const syncRes = await synced;
  assert.equal(syncRes.event, 'sync_state');
  assert.equal(syncRes.state.mode, 'synchronizedListening');
  assert.equal(syncRes.state.allowGuestControls, false);
  assert.equal(syncRes.state.trackId, 'track-d1');
  assert.equal(syncRes.state.position, 1000);
  assert.deepEqual(syncRes.state.queue, ['track-d2']);

  host.close();
  guest.close();
});

test('host can kick a guest from the room', async () => {
  const server = await startServer();
  const endpoint = `ws://127.0.0.1:${server.port}`;
  const host = await connect(endpoint);

  host.send(JSON.stringify({
    action: 'create_room',
    pin: 'KCK123',
    hostName: 'HostUser',
    initialState,
  }));
  await nextMessage(host);

  const guest = await connect(endpoint);
  const hostJoined = nextMessage(host);
  guest.send(JSON.stringify({
    action: 'join_room',
    pin: 'KCK123',
    guestName: 'UnwantedGuest',
  }));
  await nextMessage(guest);
  await hostJoined;

  const kickedMsgPromise = nextMessage(guest);
  const hostKickConfirmPromise = nextMessage(host);

  host.send(JSON.stringify({
    action: 'kick_guest',
    pin: 'KCK123',
    guestName: 'UnwantedGuest',
  }));

  const kickedMsg = await kickedMsgPromise;
  assert.equal(kickedMsg.event, 'kicked');

  const hostConfirm = await hostKickConfirmPromise;
  assert.equal(hostConfirm.status, 'guest_kicked');
  assert.equal(hostConfirm.guestName, 'UnwantedGuest');

  host.close();
});


// --- Fase 1: panel /admin y /api/capabilities -------------------------------

async function http(server, method, path, { body, cookie, csrf, headers = {} } = {}) {
  const res = await fetch(`http://127.0.0.1:${server.port}${path}`, {
    method,
    headers: {
      ...(body ? { 'content-type': 'application/json' } : {}),
      ...(cookie ? { cookie } : {}),
      ...(csrf ? { 'x-csrf-token': csrf } : {}),
      ...headers,
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = null;
  try { json = JSON.parse(text); } catch { /* html u otro */ }
  return { status: res.status, json, headers: res.headers, text };
}

async function adminLogin(server, password = 'supersecret1') {
  const res = await http(server, 'POST', '/admin/api/login', { body: { password } });
  const cookie = res.headers.get('set-cookie')?.split(';')[0];
  return { res, cookie, csrf: res.json?.csrf };
}

test('GET /api/capabilities reports defaults', async () => {
  const server = await startServer();
  const { status, json } = await http(server, 'GET', '/api/capabilities');
  assert.equal(status, 200);
  assert.equal(json.protocolVersion, 2);
  assert.equal(json.features.publicListing, true);
  assert.equal(json.features.chat, false);
  assert.equal(json.limits.maxParticipants, 50);
  assert.equal(json.limits.maxQueueItems, 500);
  assert.equal(json.license, 'AGPL-3.0-or-later');
  assert.equal(json.sourceUrl, 'https://github.com/Dante0Q/CrotoWave');
});

test('GET /source redirige al código fuente (AGPL §13)', async () => {
  const server = await startServer({ sourceUrl: 'https://example.org/crotolink' });
  const res = await fetch(`http://127.0.0.1:${server.port}/source`, { redirect: 'manual' });
  assert.equal(res.status, 302);
  assert.equal(res.headers.get('location'), 'https://example.org/crotolink');
  const caps = await http(server, 'GET', '/api/capabilities');
  assert.equal(caps.json.sourceUrl, 'https://example.org/crotolink');
});

test('GET /source sin URL configurada explica la licencia', async () => {
  const server = await startServer({ sourceUrl: '' });
  const { status, text } = await http(server, 'GET', '/source');
  assert.equal(status, 200);
  assert.match(text, /AGPL-3\.0-or-later/);
});

test('admin API requires login and sets a hardened cookie', async () => {
  const server = await startServer({ adminPassword: 'supersecret1' });
  assert.equal((await http(server, 'GET', '/admin/api/status')).status, 401);
  assert.equal((await http(server, 'POST', '/admin/api/login', { body: { password: 'nope' } })).status, 401);

  const { res, cookie } = await adminLogin(server);
  assert.equal(res.status, 200);
  const setCookie = res.headers.get('set-cookie');
  assert.match(setCookie, /HttpOnly/);
  assert.match(setCookie, /SameSite=Strict/);
  const status = await http(server, 'GET', '/admin/api/status', { cookie });
  assert.equal(status.status, 200);
  assert.equal(status.json.rooms, 0);
  assert.equal((await http(server, 'GET', '/admin')).status, 200);
});

test('login is rate limited per IP', async () => {
  const server = await startServer({ adminPassword: 'supersecret1', loginMaxFailures: 3 });
  for (let i = 0; i < 3; i++) {
    assert.equal((await http(server, 'POST', '/admin/api/login', { body: { password: 'bad' } })).status, 401);
  }
  // Ni siquiera la contraseña correcta pasa mientras dure el bloqueo.
  assert.equal((await adminLogin(server)).res.status, 429);
});

test('proxy headers are ignored unless trustProxy is set', async () => {
  const server = await startServer({ adminPassword: 'supersecret1', loginMaxFailures: 2 });
  for (let i = 0; i < 2; i++) {
    await http(server, 'POST', '/admin/api/login', { body: { password: 'bad' }, headers: { 'cf-connecting-ip': `9.9.9.${i}` } });
  }
  assert.equal((await adminLogin(server)).res.status, 429);
});

test('first-run setup creates the admin only once', async () => {
  const server = await startServer({ setupToken: 'tok-test-123' });
  const session = await http(server, 'GET', '/admin/api/session');
  assert.equal(session.json.configured, false);
  // Sin token válido nadie puede apropiarse del panel.
  assert.equal((await http(server, 'POST', '/admin/api/setup', { body: { password: 'supersecret1' } })).status, 403);
  assert.equal((await http(server, 'POST', '/admin/api/setup', { body: { password: 'supersecret1', setupToken: 'otro' } })).status, 403);
  assert.equal((await http(server, 'POST', '/admin/api/setup', { body: { password: 'short', setupToken: 'tok-test-123' } })).status, 400);
  assert.equal((await http(server, 'POST', '/admin/api/setup', { body: { password: 'supersecret1', setupToken: 'tok-test-123' } })).status, 200);
  assert.equal((await http(server, 'POST', '/admin/api/setup', { body: { password: 'otherpass99', setupToken: 'tok-test-123' } })).status, 409);
});

test('settings changes need CSRF and apply without restart', async () => {
  const server = await startServer({ adminPassword: 'supersecret1' });
  const { cookie, csrf } = await adminLogin(server);

  const noCsrf = await http(server, 'PUT', '/admin/api/settings', { cookie, body: { maxParticipants: 3 } });
  assert.equal(noCsrf.status, 403);

  const bad = await http(server, 'PUT', '/admin/api/settings', { cookie, csrf, body: { maxParticipants: 1 } });
  assert.equal(bad.status, 400);

  const ok = await http(server, 'PUT', '/admin/api/settings', {
    cookie, csrf, body: { maxParticipants: 2, chatEnabled: true, publicUrl: 'https://crotolink.example.org/' },
  });
  assert.equal(ok.status, 200);
  const caps = (await http(server, 'GET', '/api/capabilities')).json;
  assert.equal(caps.limits.maxParticipants, 2);
  assert.equal(caps.features.chat, true);
  assert.equal(caps.publicUrl, 'https://crotolink.example.org');

  // El nuevo límite se aplica en caliente a las uniones.
  const endpoint = `ws://127.0.0.1:${server.port}`;
  const host = await connect(endpoint);
  host.send(JSON.stringify({ action: 'create_room', pin: 'LIM123', hostName: 'H', initialState }));
  await nextMessage(host);
  const guest = await connect(endpoint);
  const second = await connect(endpoint);
  try {
    const first = nextMessage(guest);
    guest.send(JSON.stringify({ action: 'join_room', pin: 'LIM123', guestName: 'G1' }));
    assert.equal((await first).status, 'joined');
    const refused = nextMessage(second);
    second.send(JSON.stringify({ action: 'join_room', pin: 'LIM123', guestName: 'G2' }));
    assert.equal((await refused).status, 'error');
  } finally {
    host.close();
    guest.close();
    second.close();
  }
});

test('public listing can be disabled from the panel', async () => {
  const server = await startServer({ adminPassword: 'supersecret1' });
  const endpoint = `ws://127.0.0.1:${server.port}`;
  const host = await connect(endpoint);
  host.send(JSON.stringify({ action: 'create_room', pin: 'PUB123', hostName: 'H', initialState }));
  await nextMessage(host);
  assert.equal((await http(server, 'GET', '/rooms')).json.length, 1);
  const { cookie, csrf } = await adminLogin(server);
  await http(server, 'PUT', '/admin/api/settings', { cookie, csrf, body: { publicListingEnabled: false } });
  assert.deepEqual((await http(server, 'GET', '/rooms')).json, []);
  host.close();
});

test('settings persist across restarts, rooms do not', async () => {
  const { mkdtempSync, rmSync } = await import('node:fs');
  const { tmpdir } = await import('node:os');
  const dir = mkdtempSync(`${tmpdir()}/crotolink-`);
  try {
    const dbPath = `${dir}/crotolink.db`;
    const first = await startServer({ dbPath, adminPassword: 'supersecret1' });
    const { cookie, csrf } = await adminLogin(first);
    await http(first, 'PUT', '/admin/api/settings', { cookie, csrf, body: { roomIdleMs: 120000 } });
    await first.stop();
    running.splice(running.indexOf(first), 1);

    const second = await startServer({ dbPath });
    assert.equal((await http(second, 'GET', '/api/capabilities')).json.protocolVersion, 2);
    assert.equal((await adminLogin(second)).res.status, 200); // admin también persiste
    assert.equal((await http(second, 'GET', '/health')).json.rooms, 0);
  } finally {
    await Promise.all(running.splice(0).map((s) => s.stop()));
    rmSync(dir, { recursive: true, force: true });
  }
});

test('relays queue-mode fields and drops invalid ones', async () => {
  const server = await startServer();
  const endpoint = `ws://127.0.0.1:${server.port}`;
  const host = await connect(endpoint);
  const guest = await connect(endpoint);
  try {
    host.send(JSON.stringify({ action: 'create_room', pin: 'QMD123', hostName: 'H', initialState }));
    await nextMessage(host);
    const joined = nextMessage(guest);
    guest.send(JSON.stringify({ action: 'join_room', pin: 'QMD123', guestName: 'G' }));
    await joined;
    const sync = nextMessage(guest);
    host.send(JSON.stringify({
      action: 'update_state', pin: 'QMD123',
      state: {
        trackId: 't', position: 0, isPlaying: false, queue: [],
        queueMode: 'voting', fairTurnsPerPerson: 99, requireApproval: true,
        pendingRequests: [{ id: 'r1' }, 'junk'],
      },
    }));
    const { state } = await sync;
    assert.equal(state.queueMode, 'voting');
    assert.equal(state.fairTurnsPerPerson, 10);
    assert.equal(state.requireApproval, true);
    assert.deepEqual(state.pendingRequests, [{ id: 'r1' }]);

    const sync2 = nextMessage(guest);
    host.send(JSON.stringify({ action: 'update_state', pin: 'QMD123', state: { queueMode: 'bogus' } }));
    assert.equal((await sync2).state.queueMode, 'voting'); // inválido: se conserva (merge)
  } finally {
    host.close();
    guest.close();
  }
});

// --- Fase 4: seguridad -------------------------------------------------------

async function ask(socket, payload) {
  const reply = nextMessage(socket);
  socket.send(JSON.stringify(payload));
  return reply;
}

async function makeRoom(endpoint, pin, extra = {}) {
  const host = await connect(endpoint);
  const created = await ask(host, { action: 'create_room', pin, hostName: 'H', initialState, ...extra });
  assert.equal(created.status, 'room_created');
  return host;
}

test('PIN brute force from one IP gets blocked, even for the right PIN', async () => {
  const server = await startServer({ pinFailMax: 3, joinRateMax: 100 });
  const endpoint = `ws://127.0.0.1:${server.port}`;
  const host = await makeRoom(endpoint, 'RIGHT1');
  const attacker = await connect(endpoint);
  try {
    for (let i = 0; i < 3; i++) {
      const r = await ask(attacker, { action: 'join_room', pin: `BAD00${i}`, guestName: 'x' });
      assert.equal(r.message, 'Sala no encontrada o PIN inválido.');
    }
    const blocked = await ask(attacker, { action: 'join_room', pin: 'RIGHT1', guestName: 'x' });
    assert.equal(blocked.status, 'error');
    assert.match(blocked.message, /Demasiados intentos/);
    assert.ok(blocked.retryAfterMs > 0);
  } finally {
    host.close();
    attacker.close();
  }
});

test('join rate limit applies per IP window', async () => {
  const server = await startServer({ joinRateMax: 2, pinFailMax: 1000 });
  const endpoint = `ws://127.0.0.1:${server.port}`;
  const s = await connect(endpoint);
  try {
    assert.equal((await ask(s, { action: 'check_room', pin: 'AAA111' })).status, 'not_found');
    assert.equal((await ask(s, { action: 'check_room', pin: 'AAA111' })).status, 'not_found');
    assert.match((await ask(s, { action: 'check_room', pin: 'AAA111' })).message, /Demasiados/);
  } finally {
    s.close();
  }
});

test('password-protected rooms reject without it and answer generically', async () => {
  const server = await startServer();
  const endpoint = `ws://127.0.0.1:${server.port}`;
  const host = await makeRoom(endpoint, 'PWD123', { roomPassword: 'secreto1' });
  const g1 = await connect(endpoint);
  const g2 = await connect(endpoint);
  const g3 = await connect(endpoint);
  try {
    const missing = await ask(g1, { action: 'join_room', pin: 'PWD123', guestName: 'a' });
    const unknown = await ask(g2, { action: 'join_room', pin: 'ZZZ999', guestName: 'a' });
    assert.equal(missing.message, unknown.message); // no revela si el PIN existe

    const peek = await ask(g1, { action: 'check_room', pin: 'PWD123' });
    assert.equal(peek.hasPassword, true);
    assert.equal(peek.state, undefined);

    const ok = await ask(g3, { action: 'join_room', pin: 'PWD123', guestName: 'b', roomPassword: 'secreto1' });
    assert.equal(ok.status, 'joined');
    const rooms = (await http(server, 'GET', '/rooms')).json;
    assert.equal(rooms[0].hasPassword, true);
    assert.equal(JSON.stringify(rooms).includes('secreto1'), false);
  } finally {
    host.close(); g1.close(); g2.close(); g3.close();
  }
});

test('a kicked guest cannot rejoin the room under the same name', async () => {
  const server = await startServer();
  const endpoint = `ws://127.0.0.1:${server.port}`;
  const host = await makeRoom(endpoint, 'BAN123');
  const guest = await connect(endpoint);
  const again = await connect(endpoint);
  try {
    assert.equal((await ask(guest, { action: 'join_room', pin: 'BAN123', guestName: 'Pepe' })).status, 'joined');
    await nextMessage(host); // guest_joined
    host.send(JSON.stringify({ action: 'kick_guest', pin: 'BAN123', guestName: 'Pepe' }));
    await new Promise((r) => setTimeout(r, 50));
    const retry = await ask(again, { action: 'join_room', pin: 'BAN123', guestName: 'pepe' });
    assert.equal(retry.status, 'error');
  } finally {
    host.close(); guest.close(); again.close();
  }
});

test('admin-blocked IPs are refused and management needs auth/CSRF', async () => {
  const server = await startServer({ adminPassword: 'supersecret1' });
  const endpoint = `ws://127.0.0.1:${server.port}`;
  const host = await makeRoom(endpoint, 'IPB123');
  const { cookie, csrf } = await adminLogin(server);
  try {
    assert.equal((await http(server, 'POST', '/admin/api/blocked-ips', { cookie, body: { ip: '127.0.0.1' } })).status, 403);
    assert.equal((await http(server, 'POST', '/admin/api/blocked-ips', { cookie, csrf, body: { ip: 'nope' } })).status, 400);
    const added = await http(server, 'POST', '/admin/api/blocked-ips', { cookie, csrf, body: { ip: '127.0.0.1', reason: 'test' } });
    assert.equal(added.json.ips[0].ip, '127.0.0.1');

    const guest = await connect(endpoint);
    const r = await ask(guest, { action: 'join_room', pin: 'IPB123', guestName: 'g' });
    assert.equal(r.message, 'Acceso denegado.');
    guest.close();

    await http(server, 'DELETE', '/admin/api/blocked-ips?ip=127.0.0.1', { cookie, csrf });
    const guest2 = await connect(endpoint);
    assert.equal((await ask(guest2, { action: 'join_room', pin: 'IPB123', guestName: 'g' })).status, 'joined');
    guest2.close();
  } finally {
    host.close();
  }
});

// --- Fase 5: reloj de referencia ---------------------------------------------

test('time_ping returns the server clock and echoes clientTs', async () => {
  const server = await startServer();
  const socket = await connect(`ws://127.0.0.1:${server.port}`);
  try {
    const before = Date.now();
    const pong = await ask(socket, { action: 'time_ping', clientTs: 12345 });
    assert.equal(pong.status, 'time_pong');
    assert.equal(pong.clientTs, 12345);
    assert.ok(pong.serverNowMs >= before && pong.serverNowMs <= Date.now());
  } finally {
    socket.close();
  }
});

test('refTs/nextHint are ephemeral: not carried over by partial updates', async () => {
  const server = await startServer();
  const endpoint = `ws://127.0.0.1:${server.port}`;
  const host = await makeRoom(endpoint, 'EPH123');
  const guest = await connect(endpoint);
  try {
    await ask(guest, { action: 'join_room', pin: 'EPH123', guestName: 'g' });
    const a = nextMessage(guest);
    host.send(JSON.stringify({ action: 'update_state', pin: 'EPH123', state: { trackId: 't', position: 1, isPlaying: true, queue: [], refTs: 99, nextHint: { track: { id: 'n' }, startAtMs: 5 } } }));
    const first = (await a).state;
    assert.equal(first.refTs, 99);
    assert.equal(first.nextHint.track.id, 'n');
    const b = nextMessage(guest);
    host.send(JSON.stringify({ action: 'update_state', pin: 'EPH123', state: { position: 2, nextHint: null } }));
    const second = (await b).state;
    assert.equal(second.refTs, undefined);
    assert.equal(second.nextHint, undefined);
  } finally {
    host.close(); guest.close();
  }
});

// --- Fase 7: continuidad -----------------------------------------------------

function waitFor(socket, predicate, ms = 3000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => { socket.off('message', onMsg); reject(new Error('timeout waiting for message')); }, ms);
    function onMsg(data) {
      const msg = JSON.parse(data.toString());
      if (predicate(msg)) { clearTimeout(timer); socket.off('message', onMsg); resolve(msg); }
    }
    socket.on('message', onMsg);
  });
}

async function roomWithGuest(server, pin, { failover = false, guestName = 'G' } = {}) {
  const endpoint = `ws://127.0.0.1:${server.port}`;
  const host = await connect(endpoint);
  const created = await ask(host, { action: 'create_room', pin, hostName: 'H', initialState, failover });
  const guest = await connect(endpoint);
  const hostSees = waitFor(host, (m) => m.event === 'guest_joined');
  const joined = await ask(guest, { action: 'join_room', pin, guestName });
  assert.equal(joined.status, 'joined');
  const gj = await hostSees;
  return { host, guest, hostToken: created.hostToken, guestId: gj.guestId };
}

test('host transfer: guest becomes host, old host becomes guest, old token dies', async () => {
  const server = await startServer();
  const { host, guest, hostToken, guestId } = await roomWithGuest(server, 'TRF123');
  try {
    assert.ok(guestId);
    const toNew = waitFor(guest, (m) => m.event === 'host_changed');
    const toOld = waitFor(host, (m) => m.event === 'host_changed');
    host.send(JSON.stringify({ action: 'transfer_host', pin: 'TRF123', toGuestId: guestId }));
    const newHost = await toNew;
    const oldHost = await toOld;
    assert.equal(newHost.youAreHost, true);
    assert.match(newHost.hostToken, /^[0-9a-f]{32}$/);
    assert.notEqual(newHost.hostToken, hostToken);
    assert.equal(oldHost.youAreHost, false);
    assert.equal(newHost.guests.length, 1); // el anfitrión anterior ahora es invitado

    // El anfitrión anterior ya no puede actualizar el estado; el nuevo sí.
    assert.equal((await ask(host, { action: 'update_state', pin: 'TRF123', state: initialState })).status, 'error');
    const sync = waitFor(host, (m) => m.event === 'sync_state');
    guest.send(JSON.stringify({ action: 'update_state', pin: 'TRF123', state: { ...initialState, position: 77 } }));
    assert.equal((await sync).state.position, 77);
  } finally {
    host.close(); guest.close();
  }
});

test('only the host can transfer, and only to an existing guest', async () => {
  const server = await startServer();
  const { host, guest } = await roomWithGuest(server, 'TRF456');
  try {
    assert.equal((await ask(guest, { action: 'transfer_host', pin: 'TRF456', toGuestId: 'x' })).status, 'error');
    assert.equal((await ask(host, { action: 'transfer_host', pin: 'TRF456', toGuestId: 'nope' })).status, 'error');
  } finally {
    host.close(); guest.close();
  }
});

test('failover: room survives host loss and promotes the oldest guest', async () => {
  const server = await startServer({ hostFailoverMs: 150 });
  const { host, guest } = await roomWithGuest(server, 'FOV123', { failover: true });
  try {
    const away = waitFor(guest, (m) => m.event === 'host_away');
    const promoted = waitFor(guest, (m) => m.event === 'host_changed');
    host.terminate();
    await away;
    const msg = await promoted;
    assert.equal(msg.youAreHost, true);
    assert.equal(msg.reason, 'failover');
    assert.equal((await http(server, 'GET', '/health')).json.rooms, 1);
  } finally {
    guest.close();
  }
});

test('resume_host within the window keeps the original host; bad token is refused', async () => {
  const server = await startServer({ hostFailoverMs: 2000 });
  const { host, guest, hostToken } = await roomWithGuest(server, 'RSM123', { failover: true });
  const endpoint = `ws://127.0.0.1:${server.port}`;
  try {
    const away = waitFor(guest, (m) => m.event === 'host_away');
    host.terminate();
    await away;
    const intruder = await connect(endpoint);
    assert.equal((await ask(intruder, { action: 'resume_host', pin: 'RSM123', hostToken: 'f'.repeat(32) })).status, 'error');
    intruder.close();

    const back = waitFor(guest, (m) => m.event === 'host_back');
    const again = await connect(endpoint);
    const resumed = await ask(again, { action: 'resume_host', pin: 'RSM123', hostToken });
    assert.equal(resumed.status, 'host_resumed');
    await back;
    again.close();
  } finally {
    guest.close();
  }
});

test('without failover the room closes when the host leaves (as before)', async () => {
  const server = await startServer({ hostFailoverMs: 100 });
  const { host, guest } = await roomWithGuest(server, 'NOF123', { failover: false });
  const closed = waitFor(guest, (m) => m.event === 'room_closed');
  host.terminate();
  await closed;
  assert.equal((await http(server, 'GET', '/health')).json.rooms, 0);
  guest.close();
});

test('close_room: the host ends the room on purpose, guests get room_closed (no failover)', async () => {
  const server = await startServer({ hostFailoverMs: 5000 });
  const { host, guest } = await roomWithGuest(server, 'CLS123', { failover: true });
  let away = false;
  guest.on('message', (d) => { if (JSON.parse(d.toString()).event === 'host_away') away = true; });
  const closed = waitFor(guest, (m) => m.event === 'room_closed');
  const ack = await ask(host, { action: 'close_room' });
  assert.equal(ack.status, 'room_closed');
  await closed;
  assert.equal(away, false);
  assert.equal((await http(server, 'GET', '/health')).json.rooms, 0);
  host.close();
  guest.close();
});

test('close_room: a guest cannot close the room', async () => {
  const server = await startServer();
  const { host, guest } = await roomWithGuest(server, 'CLS456');
  const reply = await ask(guest, { action: 'close_room' });
  assert.equal(reply.status, 'error');
  assert.equal((await http(server, 'GET', '/health')).json.rooms, 1);
  host.close();
  guest.close();
});

test('persistent rooms: reserved PIN, owner claim, config survives restart', async () => {
  const { mkdtempSync, rmSync } = await import('node:fs');
  const { tmpdir } = await import('node:os');
  const dir = mkdtempSync(`${tmpdir()}/crotolink-`);
  try {
    const dbPath = `${dir}/crotolink.db`;
    const first = await startServer({ dbPath, adminPassword: 'supersecret1', persistentRoomsEnabled: true });
    const { cookie, csrf } = await adminLogin(first);
    const bad = await http(first, 'POST', '/admin/api/persistent-rooms', { cookie, csrf, body: { pin: 'ABC10O', name: 'x' } });
    assert.equal(bad.status, 400); // 0/1/I/O no válidos
    const made = await http(first, 'POST', '/admin/api/persistent-rooms', { cookie, csrf, body: { pin: 'FKX234', name: 'Sala fija' } });
    assert.equal(made.status, 200);
    const { ownerToken } = made.json;
    assert.match(ownerToken, /^[0-9a-f]{32}$/);
    assert.equal(JSON.stringify(made.json.rooms).includes(ownerToken), false); // el token no se vuelve a listar

    const endpoint1 = `ws://127.0.0.1:${first.port}`;
    const intruder = await connect(endpoint1);
    assert.equal((await ask(intruder, { action: 'create_room', pin: 'FKX234', hostName: 'x', initialState })).status, 'error');
    intruder.close();

    const owner = await connect(endpoint1);
    const claimed = await ask(owner, { action: 'create_room', pin: 'FKX234', hostName: 'Dueño', ownerToken, initialState: { ...initialState, queueMode: 'voting', allowGuestControls: false } });
    assert.equal(claimed.status, 'room_created');
    assert.equal(claimed.persistent, true);
    owner.close(); // al cerrar se guarda solo la configuración
    await new Promise((r) => setTimeout(r, 50));
    await first.stop();
    running.splice(running.indexOf(first), 1);

    const second = await startServer({ dbPath, persistentRoomsEnabled: true });
    const owner2 = await connect(`ws://127.0.0.1:${second.port}`);
    const again = await ask(owner2, { action: 'create_room', pin: 'FKX234', hostName: 'Dueño', ownerToken, initialState });
    assert.equal(again.status, 'room_created');
    assert.equal(again.config.queueMode, 'voting');
    assert.equal(again.config.allowGuestControls, false);
    assert.equal(JSON.stringify(again.config).includes('trackId'), false); // nada de lo que suena
    owner2.close();
  } finally {
    await Promise.all(running.splice(0).map((s) => s.stop()));
    rmSync(dir, { recursive: true, force: true });
  }
});

test('persistent room reservation is off unless enabled', async () => {
  const server = await startServer({ adminPassword: 'supersecret1' });
  const { cookie, csrf } = await adminLogin(server);
  await http(server, 'POST', '/admin/api/persistent-rooms', { cookie, csrf, body: { pin: 'PFF234', name: 'x' } });
  const s = await connect(`ws://127.0.0.1:${server.port}`);
  assert.equal((await ask(s, { action: 'create_room', pin: 'PFF234', hostName: 'x', initialState })).status, 'room_created');
  s.close();
});

test('web link landing: gated by setting, sanitized, well-known served from settings', async () => {
  const server = await startServer({ adminPassword: 'supersecret1', publicUrl: 'https://crotolink.example.org' });
  assert.equal((await http(server, 'GET', '/j/ABC234')).status, 404);
  const { cookie, csrf } = await adminLogin(server);
  const links = JSON.stringify([{ relation: ['delegate_permission/common.handle_all_urls'] }]);
  assert.equal((await http(server, 'PUT', '/admin/api/settings', { cookie, csrf, body: { webLinkEnabled: true, assetLinksJson: links } })).status, 200);
  assert.equal((await http(server, 'PUT', '/admin/api/settings', { cookie, csrf, body: { assetLinksJson: '{no json' } })).status, 400);

  const page = await http(server, 'GET', '/j/abc-234');
  assert.equal(page.status, 200);
  assert.match(page.text, /crotowave:\/\/join\?code=ABC234&server=crotolink\.example\.org/);
  assert.equal((await http(server, 'GET', '/j/<script>')).status, 404);
  const wk = await http(server, 'GET', '/.well-known/assetlinks.json');
  assert.equal(wk.status, 200);
  assert.equal((await http(server, 'GET', '/.well-known/apple-app-site-association')).status, 404);
});

// --- Fase 8: reacciones y chat -------------------------------------------------

test('reactions: relayed to everyone else, whitelisted, rate limited, flag-gated', async () => {
  const server = await startServer({ adminPassword: 'supersecret1' });
  const { host, guest } = await roomWithGuest(server, 'RCT123');
  try {
    const onHost = waitFor(host, (m) => m.event === 'reaction');
    guest.send(JSON.stringify({ action: 'reaction', emoji: '🔥' }));
    assert.deepEqual(await onHost, { event: 'reaction', from: 'G', emoji: '🔥' });

    assert.equal((await ask(guest, { action: 'reaction', emoji: '<script>' })).status, 'error');

    // Límite: 5 cada 5 s; el resto se descarta sin eco.
    let received = 0;
    host.on('message', (d) => { if (JSON.parse(d.toString()).event === 'reaction') received++; });
    for (let i = 0; i < 10; i++) guest.send(JSON.stringify({ action: 'reaction', emoji: '🎉' }));
    await new Promise((r) => setTimeout(r, 200));
    assert.ok(received <= 4); // 1 ya consumida arriba

    const { cookie, csrf } = await adminLogin(server);
    await http(server, 'PUT', '/admin/api/settings', { cookie, csrf, body: { reactionsEnabled: false } });
    assert.equal((await http(server, 'GET', '/api/capabilities')).json.features.reactions, false);
    assert.equal((await ask(guest, { action: 'reaction', emoji: '👍' })).status, 'error');
  } finally {
    host.close(); guest.close();
  }
});

test('chat: off by default, 280-char limit, no history, host can disable per room', async () => {
  const server = await startServer({ adminPassword: 'supersecret1', chatEnabled: true });
  const { host, guest } = await roomWithGuest(server, 'CHT123');
  try {
    const onHost = waitFor(host, (m) => m.event === 'chat');
    guest.send(JSON.stringify({ action: 'chat_message', text: '  hola\u0007 mundo  ' }));
    const msg = await onHost;
    assert.equal(msg.from, 'G');
    assert.equal(msg.text, 'hola  mundo');
    assert.ok(!msg.text.includes('\u0007'));
    assert.ok(msg.ts > 0);

    assert.equal((await ask(guest, { action: 'chat_message', text: 'x'.repeat(281) })).status, 'error');
    assert.equal((await ask(guest, { action: 'chat_message', text: '   ' })).status, 'error');

    const off = waitFor(guest, (m) => m.event === 'chat_state');
    host.send(JSON.stringify({ action: 'set_chat', enabled: false }));
    assert.equal((await off).enabled, false);
    assert.match((await ask(guest, { action: 'chat_message', text: 'hola' })).message, /desactiv/);
    // Un invitado no puede cambiarlo.
    assert.equal((await ask(guest, { action: 'set_chat', enabled: true })).status, 'error');
  } finally {
    host.close(); guest.close();
  }
});

test('chat is disabled globally by default', async () => {
  const server = await startServer();
  const { host, guest } = await roomWithGuest(server, 'CHT456');
  try {
    assert.equal((await http(server, 'GET', '/api/capabilities')).json.features.chat, false);
    assert.equal((await ask(guest, { action: 'chat_message', text: 'hola' })).status, 'error');
  } finally {
    host.close(); guest.close();
  }
});

// --- Chat comunitario (lobby) ---------------------------------------------------

test('lobby chat: per-channel, ordered, gated by chatEnabled, validated', async () => {
  const server = await startServer({ chatEnabled: true });
  const post = (body) => http(server, 'POST', '/api/lobby/messages', { body });
  assert.equal((await post({ channel: 'navidrome.example.org', username: 'ana', message: 'hola' })).status, 200);
  assert.equal((await post({ channel: 'navidrome.example.org', username: 'bob', message: 'qué tal' })).status, 200);
  assert.equal((await post({ channel: 'otro.org', username: 'x', message: 'aparte' })).status, 200);

  const all = (await http(server, 'GET', '/api/lobby/messages?channel=navidrome.example.org')).json.messages;
  assert.deepEqual(all.map((m) => `${m.username}:${m.message}`), ['ana:hola', 'bob:qué tal']);
  assert.ok(all[1].time > all[0].time);
  const since = (await http(server, 'GET', `/api/lobby/messages?channel=navidrome.example.org&since=${all[0].time}`)).json.messages;
  assert.equal(since.length, 1);

  assert.equal((await post({ channel: 'BAD CHANNEL!', username: 'a', message: 'x' })).status, 400);
  assert.equal((await post({ channel: 'ok', username: 'a', message: '' })).status, 400);
  assert.equal((await post({ channel: 'ok', username: 'a', message: 'x'.repeat(2049) })).status, 400);
});

test('lobby chat is off when chat is disabled and rate limited when on', async () => {
  const off = await startServer();
  assert.equal((await http(off, 'GET', '/api/lobby/messages?channel=x')).status, 403);
  const on = await startServer({ chatEnabled: true });
  let limited = 0;
  for (let i = 0; i < 14; i++) {
    const r = await http(on, 'POST', '/api/lobby/messages', { body: { channel: 'c', username: 'u', message: `m${i}` } });
    if (r.status === 429) limited++;
  }
  assert.ok(limited >= 3);
});

test('lobby: CROTOLINK_LIVE announcements are deduplicated per session', async () => {
  const server = await startServer({ chatEnabled: true });
  const live = (sid, track) => `[CROTOLINK_LIVE]:${JSON.stringify({ sessionId: sid, trackTitle: track })}`;
  const post = (message) => http(server, 'POST', '/api/lobby/messages', { body: { channel: 'c', username: 'u', message } });
  await post(live('s1', 'a'));
  await post('hola');
  await post(live('s1', 'b'));
  await post(live('s2', 'x'));
  const msgs = (await http(server, 'GET', '/api/lobby/messages?channel=c')).json.messages.map((m) => m.message);
  assert.equal(msgs.filter((m) => m.startsWith('[CROTOLINK_LIVE]')).length, 2);
  assert.ok(msgs.includes('hola'));
  assert.ok(msgs.some((m) => m.includes('"trackTitle":"b"')));
  assert.ok(!msgs.some((m) => m.includes('"trackTitle":"a"')));
});

test('private rooms are not listed and respect isPublic updates', async () => {
  const server = await startServer({});
  const host = await connect(`ws://127.0.0.1:${server.port}`);
  host.send(JSON.stringify({ action: 'create_room', pin: 'PRV123', hostName: 'H', initialState, isPublic: false }));
  await nextMessage(host);
  assert.deepEqual((await http(server, 'GET', '/rooms')).json, []);
  host.send(JSON.stringify({ action: 'update_state', pin: 'PRV123', state: { ...initialState, isPublic: true } }));
  await new Promise((r) => setTimeout(r, 100));
  assert.equal((await http(server, 'GET', '/rooms')).json.length, 1);
  host.close();
});
