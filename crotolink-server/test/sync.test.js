import assert from 'node:assert/strict';
import { afterEach, test } from 'node:test';

import { createCrotoLinkServer } from '../src/server.js';

const running = [];
afterEach(async () => {
  await Promise.all(running.splice(0).map((server) => server.stop()));
});

async function startServer(options) {
  const server = createCrotoLinkServer({ port: 0, host: '127.0.0.1', syncEnabled: true, ...options });
  await server.start();
  running.push(server);
  return server;
}

const vault = 'a'.repeat(64);
const token = 'b'.repeat(64);

function call(server, method, path, { auth = token, body } = {}) {
  return fetch(`http://127.0.0.1:${server.port}/api/sync/v1/${path}`, {
    method,
    headers: { ...(auth ? { authorization: `Bearer ${auth}` } : {}), 'content-type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

test('sync está desactivado por defecto', async () => {
  const server = await startServer({ syncEnabled: false });
  assert.equal((await call(server, 'GET', vault)).status, 403);
});

test('el primer PUT crea la bóveda y se puede leer de vuelta', async () => {
  const server = await startServer();
  assert.equal((await call(server, 'GET', vault)).status, 404);
  const put = await call(server, 'PUT', `${vault}/settings`, { body: { updatedAt: 100, blob: 'cifrado' } });
  assert.equal(put.status, 200);
  const list = await (await call(server, 'GET', vault)).json();
  assert.deepEqual(list.docs.map((d) => [d.key, d.updatedAt]), [['settings', 100]]);
  const doc = await (await call(server, 'GET', `${vault}/settings`)).json();
  assert.equal(doc.blob, 'cifrado');
});

test('credencial incorrecta o ausente se rechaza', async () => {
  const server = await startServer();
  await call(server, 'PUT', `${vault}/a`, { body: { updatedAt: 1, blob: 'x' } });
  assert.equal((await call(server, 'GET', vault, { auth: 'c'.repeat(64) })).status, 401);
  assert.equal((await call(server, 'GET', vault, { auth: null })).status, 401);
  assert.equal((await call(server, 'DELETE', vault, { auth: 'c'.repeat(64) })).status, 401);
});

test('gana la versión más reciente', async () => {
  const server = await startServer();
  await call(server, 'PUT', `${vault}/a`, { body: { updatedAt: 200, blob: 'nuevo' } });
  const stale = await call(server, 'PUT', `${vault}/a`, { body: { updatedAt: 100, blob: 'viejo' } });
  assert.equal(stale.status, 409);
  assert.equal((await stale.json()).updatedAt, 200);
  const doc = await (await call(server, 'GET', `${vault}/a`)).json();
  assert.equal(doc.blob, 'nuevo');
});

test('valida tamaño, formato y límites', async () => {
  const server = await startServer({ syncMaxDocBytes: 1024, syncMaxDocs: 1 });
  assert.equal((await call(server, 'PUT', `${vault}/a`, { body: { updatedAt: 'ayer', blob: 'x' } })).status, 400);
  assert.equal((await call(server, 'PUT', `${vault}/a`, { body: { updatedAt: Date.now() + 10 * 24 * 3600 * 1000, blob: 'x' } })).status, 400);
  assert.equal((await call(server, 'PUT', `${vault}/a`, { body: { updatedAt: 1, blob: 'x'.repeat(2048) } })).status, 413);
  assert.equal((await call(server, 'PUT', `${vault}/a`, { body: { updatedAt: 1, blob: 'x' } })).status, 200);
  assert.equal((await call(server, 'PUT', `${vault}/b`, { body: { updatedAt: 1, blob: 'x' } })).status, 507);
  assert.equal((await call(server, 'GET', 'xyz')).status, 404);
});

test('limita el número de bóvedas', async () => {
  const server = await startServer({ syncMaxVaults: 1 });
  assert.equal((await call(server, 'PUT', `${vault}/a`, { body: { updatedAt: 1, blob: 'x' } })).status, 200);
  assert.equal((await call(server, 'PUT', `${'d'.repeat(64)}/a`, { body: { updatedAt: 1, blob: 'x' } })).status, 507);
});

test('DELETE borra un documento y la bóveda entera', async () => {
  const server = await startServer();
  await call(server, 'PUT', `${vault}/a`, { body: { updatedAt: 1, blob: 'x' } });
  await call(server, 'PUT', `${vault}/b`, { body: { updatedAt: 1, blob: 'x' } });
  await call(server, 'DELETE', `${vault}/a`);
  assert.equal((await call(server, 'GET', `${vault}/a`)).status, 404);
  assert.equal((await call(server, 'GET', `${vault}/b`)).status, 200);
  await call(server, 'DELETE', vault);
  assert.equal((await call(server, 'GET', vault)).status, 404);
});
