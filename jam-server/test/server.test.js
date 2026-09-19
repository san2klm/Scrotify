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
