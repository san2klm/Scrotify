import { DatabaseSync } from 'node:sqlite';

/// Definición de los ajustes editables desde `/admin`. El valor efectivo es:
/// panel (SQLite) > override/variable de entorno > valor por defecto.
export const SETTING_DEFS = {
  maxParticipants: { type: 'int', default: 50, min: 2, max: 500, group: 'limits' },
  maxRooms: { type: 'int', default: 200, min: 1, max: 100000, group: 'limits' },
  maxMessageBytes: { type: 'int', default: 16 * 1024, min: 1024, max: 1024 * 1024, group: 'limits' },
  maxQueueItems: { type: 'int', default: 500, min: 1, max: 5000, group: 'limits' },
  hostFailoverMs: { type: 'int', default: 60 * 1000, min: 0, max: 24 * 3600 * 1000, group: 'limits' },
  roomIdleMs: { type: 'int', default: 60 * 60 * 1000, min: 10 * 1000, max: 30 * 24 * 3600 * 1000, group: 'limits' },
  publicListingEnabled: { type: 'bool', default: true, group: 'features' },
  reactionsEnabled: { type: 'bool', default: true, group: 'features' },
  chatEnabled: { type: 'bool', default: false, group: 'features' },
  persistentRoomsEnabled: { type: 'bool', default: false, group: 'features' },
  webLinkEnabled: { type: 'bool', default: false, group: 'features' },
  syncEnabled: { type: 'bool', default: false, group: 'features' },
  syncMaxDocBytes: { type: 'int', default: 4 * 1024 * 1024, min: 1024, max: 32 * 1024 * 1024, group: 'limits' },
  syncMaxDocs: { type: 'int', default: 64, min: 1, max: 1000, group: 'limits' },
  syncMaxVaults: { type: 'int', default: 100, min: 1, max: 100000, group: 'limits' },
  publicUrl: { type: 'url', default: '', group: 'general' },
  assetLinksJson: { type: 'json', default: '', group: 'links' },
  appleAppSiteAssociation: { type: 'json', default: '', group: 'links' },
  joinRateMax: { type: 'int', default: 10, min: 1, max: 1000, group: 'security' },
  joinRateWindowMs: { type: 'int', default: 60 * 1000, min: 1000, max: 3600 * 1000, group: 'security' },
  pinFailMax: { type: 'int', default: 10, min: 1, max: 1000, group: 'security' },
};

export function coerceSetting(key, value) {
  const def = SETTING_DEFS[key];
  if (!def) throw new Error(`Ajuste desconocido: ${key}`);
  switch (def.type) {
    case 'int': {
      const n = typeof value === 'string' && value.trim() !== '' ? Number(value) : value;
      if (!Number.isInteger(n) || n < def.min || n > def.max) {
        throw new Error(`${key} debe ser un entero entre ${def.min} y ${def.max}`);
      }
      return n;
    }
    case 'bool':
      if (typeof value !== 'boolean') throw new Error(`${key} debe ser booleano`);
      return value;
    case 'url': {
      if (typeof value !== 'string') throw new Error(`${key} debe ser texto`);
      const v = value.trim().replace(/\/+$/, '');
      if (v === '') return '';
      let parsed;
      try { parsed = new URL(v); } catch { throw new Error(`${key} no es una URL válida`); }
      if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
        throw new Error(`${key} debe empezar por https:// o http://`);
      }
      return parsed.origin;
    }
    case 'json': {
      if (typeof value !== 'string') throw new Error(`${key} debe ser texto JSON`);
      const v = value.trim();
      if (v === '') return '';
      if (v.length > 8192) throw new Error(`${key} es demasiado largo (máx. 8 KB)`);
      try { JSON.parse(v); } catch { throw new Error(`${key} no es JSON válido`); }
      return v;
    }
    default:
      throw new Error(`Tipo no soportado: ${def.type}`);
  }
}

/// Almacén SQLite (`node:sqlite`, sin dependencias nativas) para config y admin.
export function openStore(path = ':memory:', overrides = {}) {
  const db = new DatabaseSync(path);
  db.exec(`
    CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS blocked_ips (ip TEXT PRIMARY KEY, reason TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS persistent_rooms (
      pin TEXT PRIMARY KEY, name TEXT NOT NULL, owner_salt TEXT NOT NULL, owner_hash TEXT NOT NULL,
      idle_expiry_ms INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, last_used_at INTEGER NOT NULL,
      config TEXT NOT NULL DEFAULT '{}'
    );
    CREATE TABLE IF NOT EXISTS sync_vaults (
      id TEXT PRIMARY KEY, auth_hash TEXT NOT NULL, created_at INTEGER NOT NULL, last_used_at INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS sync_docs (
      vault_id TEXT NOT NULL REFERENCES sync_vaults(id) ON DELETE CASCADE, key TEXT NOT NULL,
      updated_at INTEGER NOT NULL, blob TEXT NOT NULL, PRIMARY KEY (vault_id, key)
    );
    CREATE TABLE IF NOT EXISTS admin (id INTEGER PRIMARY KEY CHECK (id = 1), salt TEXT NOT NULL, hash TEXT NOT NULL);
  `);
  db.exec('PRAGMA foreign_keys = ON');
  const getRow = db.prepare('SELECT value FROM settings WHERE key = ?');
  const setRow = db.prepare('INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value');
  const cache = new Map();

  function get(key) {
    if (cache.has(key)) return cache.get(key);
    const def = SETTING_DEFS[key];
    let value = def.default;
    if (overrides[key] !== undefined) {
      try { value = coerceSetting(key, overrides[key]); } catch { /* usar default */ }
    }
    const row = getRow.get(key);
    if (row) {
      try { value = coerceSetting(key, JSON.parse(row.value)); } catch { /* fila corrupta: ignorar */ }
    }
    cache.set(key, value);
    return value;
  }

  return {
    get,
    all() {
      return Object.fromEntries(Object.keys(SETTING_DEFS).map((k) => [k, get(k)]));
    },
    /// Valida todo el lote antes de escribir nada.
    update(patch) {
      const clean = {};
      for (const [key, value] of Object.entries(patch ?? {})) clean[key] = coerceSetting(key, value);
      for (const [key, value] of Object.entries(clean)) {
        setRow.run(key, JSON.stringify(value));
        cache.set(key, value);
      }
      return clean;
    },
    getAdmin: () => db.prepare('SELECT salt, hash FROM admin WHERE id = 1').get() ?? null,
    setAdmin: (salt, hash) => db.prepare(
      'INSERT INTO admin (id, salt, hash) VALUES (1, ?, ?) ON CONFLICT(id) DO UPDATE SET salt = excluded.salt, hash = excluded.hash',
    ).run(salt, hash),
    listBlockedIps: () => db.prepare('SELECT ip, reason, created_at AS createdAt FROM blocked_ips ORDER BY created_at DESC').all(),
    isBlockedIp: (ip) => !!db.prepare('SELECT 1 AS x FROM blocked_ips WHERE ip = ?').get(ip),
    blockIp: (ip, reason = '') => db.prepare(
      'INSERT INTO blocked_ips (ip, reason, created_at) VALUES (?, ?, ?) ON CONFLICT(ip) DO UPDATE SET reason = excluded.reason',
    ).run(ip, String(reason).slice(0, 200), Date.now()),
    unblockIp: (ip) => db.prepare('DELETE FROM blocked_ips WHERE ip = ?').run(ip),
    listPersistentRooms: () => db.prepare(
      'SELECT pin, name, idle_expiry_ms AS idleExpiryMs, created_at AS createdAt, last_used_at AS lastUsedAt, config FROM persistent_rooms ORDER BY created_at DESC',
    ).all().map((r) => ({ ...r, config: JSON.parse(r.config) })),
    getPersistentRoom: (pin) => {
      const r = db.prepare('SELECT pin, name, owner_salt AS ownerSalt, owner_hash AS ownerHash, idle_expiry_ms AS idleExpiryMs, last_used_at AS lastUsedAt, config FROM persistent_rooms WHERE pin = ?').get(pin);
      return r ? { ...r, config: JSON.parse(r.config) } : null;
    },
    addPersistentRoom: ({ pin, name, ownerSalt, ownerHash, idleExpiryMs }) => {
      const now = Date.now();
      db.prepare('INSERT INTO persistent_rooms (pin, name, owner_salt, owner_hash, idle_expiry_ms, created_at, last_used_at) VALUES (?, ?, ?, ?, ?, ?, ?)')
        .run(pin, name, ownerSalt, ownerHash, idleExpiryMs, now, now);
    },
    deletePersistentRoom: (pin) => db.prepare('DELETE FROM persistent_rooms WHERE pin = ?').run(pin),
    touchPersistentRoom: (pin, config) => db.prepare(
      config === undefined
        ? 'UPDATE persistent_rooms SET last_used_at = ? WHERE pin = ?'
        : 'UPDATE persistent_rooms SET last_used_at = ?, config = ? WHERE pin = ?',
    ).run(...(config === undefined ? [Date.now(), pin] : [Date.now(), JSON.stringify(config), pin])),
    purgeExpiredPersistentRooms: () => db.prepare(
      'DELETE FROM persistent_rooms WHERE idle_expiry_ms > 0 AND last_used_at + idle_expiry_ms < ?',
    ).run(Date.now()),
    /// Almacén de sincronización: solo guarda blobs ya cifrados por el cliente.
    getSyncVault: (id) => db.prepare('SELECT id, auth_hash AS authHash FROM sync_vaults WHERE id = ?').get(id) ?? null,
    countSyncVaults: () => db.prepare('SELECT COUNT(*) AS n FROM sync_vaults').get().n,
    addSyncVault: (id, authHash) => {
      const now = Date.now();
      db.prepare('INSERT INTO sync_vaults (id, auth_hash, created_at, last_used_at) VALUES (?, ?, ?, ?)').run(id, authHash, now, now);
    },
    touchSyncVault: (id) => db.prepare('UPDATE sync_vaults SET last_used_at = ? WHERE id = ?').run(Date.now(), id),
    deleteSyncVault: (id) => db.prepare('DELETE FROM sync_vaults WHERE id = ?').run(id),
    listSyncDocs: (id) => db.prepare(
      'SELECT key, updated_at AS updatedAt, length(blob) AS size FROM sync_docs WHERE vault_id = ? ORDER BY key',
    ).all(id),
    getSyncDoc: (id, key) => db.prepare('SELECT key, updated_at AS updatedAt, blob FROM sync_docs WHERE vault_id = ? AND key = ?').get(id, key) ?? null,
    countSyncDocs: (id) => db.prepare('SELECT COUNT(*) AS n FROM sync_docs WHERE vault_id = ?').get(id).n,
    putSyncDoc: (id, key, updatedAt, blob) => db.prepare(
      'INSERT INTO sync_docs (vault_id, key, updated_at, blob) VALUES (?, ?, ?, ?) ON CONFLICT(vault_id, key) DO UPDATE SET updated_at = excluded.updated_at, blob = excluded.blob',
    ).run(id, key, updatedAt, blob),
    deleteSyncDoc: (id, key) => db.prepare('DELETE FROM sync_docs WHERE vault_id = ? AND key = ?').run(id, key),
    close: () => db.close(),
  };
}
