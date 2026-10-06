import assert from 'node:assert/strict';
import { afterEach, test } from 'node:test';
import { WebSocket } from 'ws';

import { createJamServer } from '../src/server.js';

const running = [];

afterEach(async () => {
  await Promise.all(running.splice(0).map((server) => server.stop()));
});

async function startServer(options) {
  const server = createJamServer({ port: 0, ...options });
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
  assert.deepEqual(await created, { status: 'room_created', pin: 'GCG36B' });

  const guest = await connect(endpoint);
  const hostJoined = nextMessage(host);
  const joined = nextMessage(guest);
  guest.send(JSON.stringify({
    action: 'join_room',
    pin: 'GCG-36B',
    guestName: 'Amigo',
  }));

  assert.deepEqual(await joined, { status: 'joined', state: initialState });
  assert.deepEqual(await hostJoined, {
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
  const server = await startServer();
  const session = await http(server, 'GET', '/admin/api/session');
  assert.equal(session.json.configured, false);
  assert.equal((await http(server, 'POST', '/admin/api/setup', { body: { password: 'short' } })).status, 400);
  assert.equal((await http(server, 'POST', '/admin/api/setup', { body: { password: 'supersecret1' } })).status, 200);
  assert.equal((await http(server, 'POST', '/admin/api/setup', { body: { password: 'otherpass99' } })).status, 409);
});

test('settings changes need CSRF and apply without restart', async () => {
  const server = await startServer({ adminPassword: 'supersecret1' });
  const { cookie, csrf } = await adminLogin(server);

  const noCsrf = await http(server, 'PUT', '/admin/api/settings', { cookie, body: { maxParticipants: 3 } });
  assert.equal(noCsrf.status, 403);

  const bad = await http(server, 'PUT', '/admin/api/settings', { cookie, csrf, body: { maxParticipants: 1 } });
  assert.equal(bad.status, 400);

  const ok = await http(server, 'PUT', '/admin/api/settings', {
    cookie, csrf, body: { maxParticipants: 2, chatEnabled: true, publicUrl: 'https://jam.example.org/' },
  });
  assert.equal(ok.status, 200);
  const caps = (await http(server, 'GET', '/api/capabilities')).json;
  assert.equal(caps.limits.maxParticipants, 2);
  assert.equal(caps.features.chat, true);
  assert.equal(caps.publicUrl, 'https://jam.example.org');

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
  const dir = mkdtempSync(`${tmpdir()}/jam-`);
  try {
    const dbPath = `${dir}/jam.db`;
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
