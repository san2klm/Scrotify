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


async function httpGet(server, path) {
  const res = await fetch(`http://127.0.0.1:${server.port}${path}`);
  return res.json();
}

test('strips Subsonic credentials from album art URLs', async () => {
  const server = await startServer();
  const host = await connect(`ws://127.0.0.1:${server.port}`);
  const created = nextMessage(host);
  host.send(JSON.stringify({
    action: 'create_room',
    pin: 'SEC123',
    hostName: 'Host',
    isPublic: true,
    initialState: {
      ...initialState,
      albumArtUrl: 'https://nd.example/rest/getCoverArt.view?u=bob&s=abc&t=tok&id=7&size=300',
      queue: [{ track: { id: '1', albumArtUrl: 'https://nd.example/a?u=bob&t=tok&id=1' } }],
    },
  }));
  await created;

  const [room] = await httpGet(server, '/rooms');
  assert.equal(room.albumArtUrl, 'https://nd.example/rest/getCoverArt.view?id=7&size=300');
  const raw = JSON.stringify(await httpGet(server, '/rooms'));
  assert.ok(!raw.includes('tok'));
  host.close();
});

test('private rooms are not listed in /rooms', async () => {
  const server = await startServer();
  const host = await connect(`ws://127.0.0.1:${server.port}`);
  const created = nextMessage(host);
  host.send(JSON.stringify({ action: 'create_room', pin: 'PRV123', hostName: 'Host', initialState }));
  await created;
  assert.deepEqual(await httpGet(server, '/rooms'), []);
  host.close();
});

test('rejects unknown guest actions and duplicate guest names', async () => {
  const server = await startServer();
  const endpoint = `ws://127.0.0.1:${server.port}`;
  const host = await connect(endpoint);
  host.send(JSON.stringify({ action: 'create_room', pin: 'VAL123', hostName: 'Host', initialState }));
  await nextMessage(host);

  const guest = await connect(endpoint);
  const joined = nextMessage(guest);
  guest.send(JSON.stringify({ action: 'join_room', pin: 'VAL123', guestName: 'Ana' }));
  await joined;

  const bad = nextMessage(guest);
  guest.send(JSON.stringify({ action: 'guest_action', actionType: 'rm_rf', payload: {} }));
  assert.equal((await bad).status, 'error');

  const dup = await connect(endpoint);
  const dupReply = nextMessage(dup);
  dup.send(JSON.stringify({ action: 'join_room', pin: 'VAL123', guestName: 'Ana' }));
  assert.equal((await dupReply).status, 'error');

  host.close(); guest.close(); dup.close();
});

test('closes a connection after too many failed PIN attempts', async () => {
  const server = await startServer({ maxFailedAttempts: 3 });
  const socket = await connect(`ws://127.0.0.1:${server.port}`);
  const closed = new Promise((resolve) => socket.once('close', resolve));
  for (let i = 0; i < 3; i += 1) {
    socket.send(JSON.stringify({ action: 'check_room', pin: `ZZZ00${i}` }));
  }
  assert.equal(await closed, 1008);
});
