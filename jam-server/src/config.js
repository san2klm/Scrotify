import { DatabaseSync } from 'node:sqlite';

/// Definición de los ajustes editables desde `/admin`. El valor efectivo es:
/// panel (SQLite) > override/variable de entorno > valor por defecto.
export const SETTING_DEFS = {
  maxParticipants: { type: 'int', default: 50, min: 2, max: 500, group: 'limits' },
  maxRooms: { type: 'int', default: 200, min: 1, max: 100000, group: 'limits' },
  maxMessageBytes: { type: 'int', default: 16 * 1024, min: 1024, max: 1024 * 1024, group: 'limits' },
  maxQueueItems: { type: 'int', default: 500, min: 1, max: 5000, group: 'limits' },
  roomIdleMs: { type: 'int', default: 60 * 60 * 1000, min: 10 * 1000, max: 30 * 24 * 3600 * 1000, group: 'limits' },
  publicListingEnabled: { type: 'bool', default: true, group: 'features' },
  chatEnabled: { type: 'bool', default: false, group: 'features' },
  persistentRoomsEnabled: { type: 'bool', default: false, group: 'features' },
  webLinkEnabled: { type: 'bool', default: false, group: 'features' },
  publicUrl: { type: 'url', default: '', group: 'general' },
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
    default:
      throw new Error(`Tipo no soportado: ${def.type}`);
  }
}

/// Almacén SQLite (`node:sqlite`, sin dependencias nativas) para config y admin.
export function openStore(path = ':memory:', overrides = {}) {
  const db = new DatabaseSync(path);
  db.exec(`
    CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS admin (id INTEGER PRIMARY KEY CHECK (id = 1), salt TEXT NOT NULL, hash TEXT NOT NULL);
  `);
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
    close: () => db.close(),
  };
}
