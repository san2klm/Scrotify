import crypto from 'node:crypto';

/// Sincronización de datos entre dispositivos. El servidor solo guarda blobs
/// opacos ya cifrados en el cliente: nunca ve temas, ajustes ni la clave.
///
/// - `vaultId`: 64 hex derivados de la clave de sincronización (identifican la bóveda).
/// - `Authorization: Bearer <64 hex>`: otra derivación distinta; el servidor
///   solo conserva su SHA-256. El primer `PUT` a una bóveda nueva la crea.
/// - Documentos por clave (`settings`, `themes`…) con `updatedAt`: gana el más reciente.
const ROUTE = /^\/api\/sync\/v1\/([0-9a-f]{64})(?:\/([a-z0-9._-]{1,64}))?$/;
const TOKEN = /^Bearer ([0-9a-f]{64})$/;
const MAX_CLOCK_SKEW_MS = 24 * 3600 * 1000;

export function isSyncPath(path) {
  return typeof path === 'string' && path.startsWith('/api/sync/');
}

function sha256Hex(value) {
  return crypto.createHash('sha256').update(value, 'utf8').digest('hex');
}

function safeEqualHex(a, b) {
  const x = Buffer.from(a, 'hex');
  const y = Buffer.from(b, 'hex');
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

/// Si el cuerpo excede el máximo se descarta el resto (sin acumularlo) y se
/// rechaza al terminar, para poder contestar 413 sin cortar el socket.
function readBody(request, maxBytes) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    request.on('data', (chunk) => {
      size += chunk.length;
      if (size <= maxBytes) chunks.push(chunk);
    });
    request.on('end', () => {
      if (size > maxBytes) reject(Object.assign(new Error('too large'), { status: 413 }));
      else resolve(Buffer.concat(chunks).toString('utf8'));
    });
    request.on('error', reject);
  });
}

export function createSyncHandler({ store, limits, guard, clientIp, trustProxy }) {
  return async function handleSync(request, response) {
    const reply = (status, body) => {
      response.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store' });
      response.end(JSON.stringify(body));
    };
    if (!limits.syncEnabled) return reply(403, { error: 'La sincronización está desactivada en este servidor.' });
    const ip = clientIp(request, trustProxy);
    if (store.isBlockedIp(ip)) return reply(403, { error: 'Acceso denegado.' });
    const gate = guard.attempt(`sync:${ip}`, { max: limits.syncRateMax, windowMs: 60_000 });
    if (!gate.ok) return reply(429, { error: 'Demasiadas peticiones.' });

    const path = request.url.split('?')[0];
    const route = path.match(ROUTE);
    const token = String(request.headers.authorization ?? '').match(TOKEN)?.[1];
    if (!route || !token) return reply(route ? 401 : 404, { error: route ? 'Falta la credencial.' : 'No encontrado.' });
    const [, vaultId, key] = route;
    const authHash = sha256Hex(token);

    let vault = store.getSyncVault(vaultId);
    if (vault && !safeEqualHex(vault.authHash, authHash)) {
      guard.fail(ip, { max: limits.pinFailMax });
      return reply(401, { error: 'Credencial inválida.' });
    }
    guard.success(ip);

    try {
      if (request.method === 'GET' && !key) {
        if (!vault) return reply(404, { error: 'Bóveda inexistente.' });
        store.touchSyncVault(vaultId);
        return reply(200, { docs: store.listSyncDocs(vaultId) });
      }
      if (request.method === 'GET') {
        const doc = vault && store.getSyncDoc(vaultId, key);
        return doc ? reply(200, doc) : reply(404, { error: 'Documento inexistente.' });
      }
      if (request.method === 'DELETE' && !key) {
        if (vault) store.deleteSyncVault(vaultId);
        return reply(200, { ok: true });
      }
      if (request.method === 'DELETE') {
        if (vault) store.deleteSyncDoc(vaultId, key);
        return reply(200, { ok: true });
      }
      if (request.method === 'PUT' && key) {
        let body;
        try {
          body = JSON.parse(await readBody(request, limits.syncMaxDocBytes + 256));
        } catch (error) {
          if (error.status === 413) return reply(413, { error: 'Documento demasiado grande.' });
          return reply(400, { error: 'JSON inválido.' });
        }
        const { updatedAt, blob } = body ?? {};
        if (!Number.isSafeInteger(updatedAt) || updatedAt < 0 || updatedAt > Date.now() + MAX_CLOCK_SKEW_MS
          || typeof blob !== 'string' || blob.length === 0 || blob.length > limits.syncMaxDocBytes) {
          return reply(400, { error: 'Documento inválido.' });
        }
        if (!vault) {
          if (store.countSyncVaults() >= limits.syncMaxVaults) return reply(507, { error: 'Servidor sin espacio para más bóvedas.' });
          store.addSyncVault(vaultId, authHash);
          vault = { id: vaultId, authHash };
        }
        const current = store.getSyncDoc(vaultId, key);
        if (current && current.updatedAt > updatedAt) {
          return reply(409, { error: 'Hay una versión más reciente.', updatedAt: current.updatedAt });
        }
        if (!current && store.countSyncDocs(vaultId) >= limits.syncMaxDocs) {
          return reply(507, { error: 'La bóveda alcanzó el máximo de documentos.' });
        }
        store.putSyncDoc(vaultId, key, updatedAt, blob);
        store.touchSyncVault(vaultId);
        return reply(200, { ok: true, updatedAt });
      }
      return reply(405, { error: 'Método no permitido.' });
    } catch (error) {
      return reply(500, { error: 'Error interno.' });
    }
  };
}
