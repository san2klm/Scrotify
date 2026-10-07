import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import http from 'node:http';
import { afterEach, test } from 'node:test';
import { WebSocket } from 'ws';

import { createJamServer } from '../src/server.js';

const running = [];
const closers = [];
afterEach(async () => {
  await Promise.all(running.splice(0).map((server) => server.stop()));
  await Promise.all(closers.splice(0).map((close) => close()));
});

const md5 = (value) => crypto.createHash('md5').update(value).digest('hex');
const USERS = { admin: 'clave-admin', maria: 'clave-maria' };

/// Navidrome falso: acepta `ping` si el token es md5(clave + salt).
async function fakeNavidrome() {
  let calls = 0;
  const server = http.createServer((req, res) => {
    calls += 1;
    const q = new URL(req.url, 'http://x').searchParams;
    const password = USERS[q.get('u')?.toLowerCase()];
    const ok = password !== undefined && q.get('t') === md5(password + q.get('s'));
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ 'subsonic-response': { status: ok ? 'ok' : 'failed' } }));
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  closers.push(() => new Promise((resolve) => { server.closeAllConnections(); server.close(resolve); }));
  return { url: `http://127.0.0.1:${server.address().port}`, calls: () => calls };
}

async function startServer(options) {
  const server = createJamServer({ port: 0, host: '127.0.0.1', ...options });
  await server.start();
  running.push(server);
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
  for (let i = 0; i < 150; i += 1) {
    const found = socket.messages.find(predicate);
    if (found) return found;
    await new Promise((r) => setTimeout(r, 10));
  }
  throw new Error(`No llegó el mensaje esperado: ${JSON.stringify(socket.messages)}`);
}

function hello(deviceId, name, { user = 'admin', password, salt = 'abc123xyz', kind = 'phone' } = {}) {
  const pass = password ?? USERS[user.toLowerCase()] ?? 'otra';
  return JSON.stringify({ action: 'connect_join', user, token: md5(pass + salt), salt, deviceId, name, kind });
}

test('los dispositivos del mismo usuario se ven entre sí', async () => {
  const navidrome = await fakeNavidrome();
  const server = await startServer({ navidromeUrl: navidrome.url });
  const a = await open(server);
  a.send(hello('device-aaaa', 'Teléfono'));
  assert.deepEqual((await waitFor(a, (m) => m.status === 'connect_joined')).devices.map((d) => d.name), ['Teléfono']);

  const b = await open(server);
  b.send(hello('device-bbbb', 'PC', { kind: 'desktop', salt: 'otrasalt99' }));
  await waitFor(b, (m) => m.status === 'connect_joined');
  const update = await waitFor(a, (m) => m.event === 'connect_devices' && m.devices.length === 2);
  assert.deepEqual(update.devices.map((d) => d.kind).sort(), ['desktop', 'phone']);

  b.close();
  await waitFor(a, (m) => m.event === 'connect_devices' && m.devices.length === 1);
});

test('admin solo ve a admin: otro usuario queda en su propio grupo', async () => {
  const navidrome = await fakeNavidrome();
  const server = await startServer({ navidromeUrl: navidrome.url });
  const admin = await open(server);
  const maria = await open(server);
  const adminPc = await open(server);
  admin.send(hello('device-aaaa', 'Móvil de admin', { user: 'admin' }));
  maria.send(hello('device-mmmm', 'Móvil de maría', { user: 'maria' }));
  adminPc.send(hello('device-pppp', 'PC de admin', { user: 'Admin', kind: 'desktop' })); // mayúsculas: mismo usuario
  for (const s of [admin, maria, adminPc]) await waitFor(s, (m) => m.status === 'connect_joined');

  const seen = await waitFor(admin, (m) => m.event === 'connect_devices' && m.devices.length === 2);
  assert.deepEqual(seen.devices.map((d) => d.name).sort(), ['Móvil de admin', 'PC de admin']);
  assert.equal(maria.messages.find((m) => m.status === 'connect_joined').devices.length, 1);

  // Los mensajes tampoco cruzan de un usuario a otro.
  maria.send(JSON.stringify({ action: 'connect_send', to: 'device-aaaa', blob: 'intruso' }));
  maria.send(JSON.stringify({ action: 'connect_send', to: '*', blob: 'a todos' }));
  admin.send(JSON.stringify({ action: 'connect_send', to: 'device-pppp', blob: 'hola' }));
  await waitFor(adminPc, (m) => m.event === 'connect_msg' && m.blob === 'hola');
  assert.equal(admin.messages.some((m) => m.event === 'connect_msg'), false);
  assert.equal(adminPc.messages.filter((m) => m.event === 'connect_msg').length, 1);
});

test('reenvía mensajes cifrados a un dispositivo o a todos', async () => {
  const navidrome = await fakeNavidrome();
  const server = await startServer({ navidromeUrl: navidrome.url });
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

test('rechaza clave incorrecta, usuario inexistente y envíos sin unirse', async () => {
  const navidrome = await fakeNavidrome();
  const server = await startServer({ navidromeUrl: navidrome.url });
  const a = await open(server);
  a.send(hello('device-aaaa', 'A', { password: 'equivocada' }));
  assert.equal((await waitFor(a, (m) => m.status === 'connect_error')).message, 'Usuario o clave incorrectos.');
  const b = await open(server);
  b.send(hello('device-bbbb', 'B', { user: 'fantasma' }));
  await waitFor(b, (m) => m.message === 'Usuario o clave incorrectos.');
  b.send(JSON.stringify({ action: 'connect_send', to: '*', blob: 'x' }));
  await waitFor(b, (m) => m.message === 'Primero únete con connect_join.');
});

test('valida el formato de las credenciales sin consultar a Navidrome', async () => {
  const navidrome = await fakeNavidrome();
  const server = await startServer({ navidromeUrl: navidrome.url });
  const a = await open(server);
  a.send(JSON.stringify({ action: 'connect_join', user: 'admin', token: 'no-es-md5', salt: 'abc123xyz', deviceId: 'device-aaaa', name: 'A' }));
  await waitFor(a, (m) => m.status === 'connect_error');
  assert.equal(navidrome.calls(), 0);
});

test('guarda en caché la verificación y no la repite en cada conexión', async () => {
  const navidrome = await fakeNavidrome();
  const server = await startServer({ navidromeUrl: navidrome.url });
  for (const id of ['device-aaaa', 'device-bbbb']) {
    const s = await open(server);
    s.send(hello(id, id));
    await waitFor(s, (m) => m.status === 'connect_joined');
  }
  assert.equal(navidrome.calls(), 1);
});

test('si Navidrome no responde lo informa', async () => {
  const server = await startServer({ navidromeUrl: 'http://127.0.0.1:9' });
  const a = await open(server);
  a.send(hello('device-aaaa', 'A'));
  assert.match((await waitFor(a, (m) => m.status === 'connect_error')).message, /No se pudo verificar/);
});

test('está desactivado si no hay URL de Navidrome configurada', async () => {
  const server = await startServer();
  const a = await open(server);
  a.send(hello('device-aaaa', 'A'));
  assert.match((await waitFor(a, (m) => m.status === 'connect_error')).message, /no está configurado/);
  const caps = await (await fetch(`http://127.0.0.1:${server.port}/api/capabilities`)).json();
  assert.equal(caps.features.connect, false);
});

test('una segunda conexión del mismo dispositivo reemplaza a la anterior', async () => {
  const navidrome = await fakeNavidrome();
  const server = await startServer({ navidromeUrl: navidrome.url });
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

test('un mensaje de Connect grande (cola de reproducción) no corta la conexión', async () => {
  const navidrome = await fakeNavidrome();
  const server = await startServer({ navidromeUrl: navidrome.url });
  const a = await open(server);
  const b = await open(server);
  a.send(hello('device-aaaa', 'A'));
  b.send(hello('device-bbbb', 'B'));
  for (const s of [a, b]) await waitFor(s, (m) => m.status === 'connect_joined');
  const big = 'x'.repeat(60 * 1024); // supera maxMessageBytes (16 KB) de las salas
  let closed = false;
  a.once('close', () => { closed = true; });
  a.send(JSON.stringify({ action: 'connect_send', to: 'device-bbbb', blob: big }));
  const received = await waitFor(b, (m) => m.event === 'connect_msg');
  assert.equal(received.blob.length, big.length);
  assert.equal(closed, false);
});

test('las acciones de sala siguen limitadas por maxMessageBytes', async () => {
  const server = await startServer();
  const a = await open(server);
  a.send(JSON.stringify({ action: 'chat_message', text: 'x'.repeat(40 * 1024) }));
  assert.match((await waitFor(a, (m) => m.status === 'error')).message, /demasiado grande/);
});
