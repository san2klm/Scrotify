import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { afterEach, test } from 'node:test';
import { WebSocket } from 'ws';

import { createJamServer } from '../src/server.js';

const running = [];
afterEach(async () => {
  await Promise.all(running.splice(0).map((server) => server.stop()));
});

const vaultId = 'a'.repeat(64);
const token = 'b'.repeat(64);

async function startServer(options) {
  const server = createJamServer({ port: 0, host: '127.0.0.1', syncEnabled: true, ...options });
  await server.start();
  running.push(server);
  // La bóveda la crea el primer PUT de sincronización.
  await fetch(`http://127.0.0.1:${server.port}/api/sync/v1/${vaultId}/x`, {
    method: 'PUT',
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: JSON.stringify({ updatedAt: 1, blob: 'x' }),
  });
  return server;
}

function open(server) {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(`ws://127.0.0.1:${server.port}`);
    socket.messages = [];
    socket.on('message', (data) => socket.messages.push(JSON.parse(data.toString())));
    socket.once('open', () => resolve(socket));
    socket.once('error', reject);
  });
}

async function waitFor(socket, predicate) {
  for (let i = 0; i < 100; i += 1) {
    const found = socket.messages.find(predicate);
    if (found) return found;
    await new Promise((r) => setTimeout(r, 10));
  }
  throw new Error(`No llegó el mensaje esperado: ${JSON.stringify(socket.messages)}`);
}

const hello = (deviceId, name, extra = {}) => JSON.stringify({
  action: 'connect_join', vaultId, token, deviceId, name, kind: 'phone', ...extra,
});

test('los dispositivos del mismo grupo se ven entre sí', async () => {
  const server = await startServer();
  const a = await open(server);
  a.send(hello('device-aaaa', 'Teléfono'));
  assert.deepEqual((await waitFor(a, (m) => m.status === 'connect_joined')).devices.map((d) => d.name), ['Teléfono']);

  const b = await open(server);
  b.send(hello('device-bbbb', 'PC', { kind: 'desktop' }));
  await waitFor(b, (m) => m.status === 'connect_joined');
  const update = await waitFor(a, (m) => m.event === 'connect_devices' && m.devices.length === 2);
  assert.deepEqual(update.devices.map((d) => d.kind).sort(), ['desktop', 'phone']);

  b.close();
  await waitFor(a, (m) => m.event === 'connect_devices' && m.devices.length === 1);
});

test('reenvía mensajes cifrados a un dispositivo o a todos', async () => {
  const server = await startServer();
  const [a, b, c] = [await open(server), await open(server), await open(server)];
  a.send(hello('device-aaaa', 'A'));
  b.send(hello('device-bbbb', 'B'));
  c.send(hello('device-cccc', 'C'));
  for (const s of [a, b, c]) await waitFor(s, (m) => m.status === 'connect_joined');

  a.send(JSON.stringify({ action: 'connect_send', to: 'device-bbbb', blob: 'secreto' }));
  assert.equal((await waitFor(b, (m) => m.event === 'connect_msg')).from, 'device-aaaa');
  a.send(JSON.stringify({ action: 'connect_send', to: '*', blob: 'todos' }));
  await waitFor(c, (m) => m.event === 'connect_msg' && m.blob === 'todos');
  assert.equal(c.messages.some((m) => m.blob === 'secreto'), false);
  assert.equal(a.messages.some((m) => m.event === 'connect_msg'), false);
});

test('rechaza credenciales incorrectas, bóvedas ajenas y envíos sin unirse', async () => {
  const server = await startServer();
  const a = await open(server);
  a.send(hello('device-aaaa', 'A', { token: 'c'.repeat(64) }));
  assert.equal((await waitFor(a, (m) => m.status === 'connect_error')).message, 'Credencial inválida.');
  const b = await open(server);
  b.send(hello('device-bbbb', 'B', { vaultId: 'd'.repeat(64) }));
  await waitFor(b, (m) => m.status === 'connect_error');
  b.send(JSON.stringify({ action: 'connect_send', to: '*', blob: 'x' }));
  await waitFor(b, (m) => m.message === 'Primero únete con connect_join.');
});

test('está desactivado si no hay sincronización', async () => {
  const server = createJamServer({ port: 0, host: '127.0.0.1' });
  await server.start();
  running.push(server);
  const a = await open(server);
  a.send(hello('device-aaaa', 'A'));
  await waitFor(a, (m) => m.status === 'connect_error');
});

test('una segunda conexión del mismo dispositivo reemplaza a la anterior', async () => {
  const server = await startServer();
  const first = await open(server);
  first.send(hello('device-aaaa', 'A'));
  await waitFor(first, (m) => m.status === 'connect_joined');
  const closed = new Promise((resolve) => first.once('close', resolve));
  const second = await open(server);
  second.send(hello('device-aaaa', 'A'));
  await waitFor(second, (m) => m.status === 'connect_joined');
  await closed;
  assert.equal(second.messages.find((m) => m.status === 'connect_joined').devices.length, 1);
});
