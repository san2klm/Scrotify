import crypto from 'node:crypto';
import { readFileSync } from 'node:fs';
import { SETTING_DEFS } from './config.js';

const SESSION_TTL_MS = 8 * 60 * 60 * 1000;
const LOGIN_WINDOW_MS = 15 * 60 * 1000;
const COOKIE = 'jam_admin';
const PANEL_HTML = readFileSync(new URL('./admin/index.html', import.meta.url));

function scrypt(password, salt) {
  return crypto.scryptSync(password, salt, 64).toString('hex');
}

function safeEqualHex(a, b) {
  const x = Buffer.from(a, 'hex');
  const y = Buffer.from(b, 'hex');
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

function validPassword(p) {
  return typeof p === 'string' && p.length >= 8 && p.length <= 256;
}

/// Panel y API de administración. No conoce nada de las salas salvo lo que
/// expone `getStatus()`; nunca registra contraseñas, hashes ni tokens.
export function createAdmin({ store, adminPassword, getStatus, loginMaxFailures = 5, logs }) {
  const sessions = new Map(); // token -> { csrf, expires }
  const failures = new Map(); // ip -> [timestamps]

  if (!store.getAdmin() && validPassword(adminPassword)) setPassword(adminPassword);

  function setPassword(password) {
    const salt = crypto.randomBytes(16).toString('hex');
    store.setAdmin(salt, scrypt(password, salt));
  }

  function checkPassword(password) {
    const admin = store.getAdmin();
    if (!admin || typeof password !== 'string') return false;
    return safeEqualHex(scrypt(password, admin.salt), admin.hash);
  }

  function recentFailures(ip) {
    const now = Date.now();
    const list = (failures.get(ip) ?? []).filter((t) => now - t < LOGIN_WINDOW_MS);
    if (list.length) failures.set(ip, list); else failures.delete(ip);
    return list;
  }

  function parseCookies(header) {
    const out = {};
    for (const part of (header ?? '').split(';')) {
      const i = part.indexOf('=');
      if (i > 0) out[part.slice(0, i).trim()] = part.slice(i + 1).trim();
    }
    return out;
  }

  function sessionFor(request) {
    const token = parseCookies(request.headers.cookie)[COOKIE];
    const session = token ? sessions.get(token) : null;
    if (!session) return null;
    if (session.expires < Date.now()) {
      sessions.delete(token);
      return null;
    }
    return { token, ...session };
  }

  function startSession(response) {
    const token = crypto.randomBytes(32).toString('hex');
    const csrf = crypto.randomBytes(24).toString('hex');
    sessions.set(token, { csrf, expires: Date.now() + SESSION_TTL_MS });
    const secure = response.req?.socket?.encrypted || response.req?.headers['x-forwarded-proto'] === 'https';
    response.setHeader('set-cookie',
      `${COOKIE}=${token}; HttpOnly; SameSite=Strict; Path=/admin; Max-Age=${SESSION_TTL_MS / 1000}${secure ? '; Secure' : ''}`);
    return csrf;
  }

  function json(response, status, body) {
    response.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store' });
    response.end(JSON.stringify(body));
  }

  function readBody(request) {
    return new Promise((resolve, reject) => {
      const chunks = [];
      let size = 0;
      request.on('data', (c) => {
        size += c.length;
        if (size > 16 * 1024) { reject(new Error('Cuerpo demasiado grande')); request.destroy(); return; }
        chunks.push(c);
      });
      request.on('end', () => {
        try { resolve(chunks.length ? JSON.parse(Buffer.concat(chunks).toString()) : {}); }
        catch { reject(new Error('JSON inválido')); }
      });
      request.on('error', reject);
    });
  }

  /// Devuelve true si la petición era de `/admin*` y ya fue respondida.
  async function handle(request, response, clientIp) {
    const url = new URL(request.url, 'http://x');
    const path = url.pathname;
    if (path !== '/admin' && !path.startsWith('/admin/')) return false;

    if (request.method === 'GET' && (path === '/admin' || path === '/admin/')) {
      response.writeHead(200, {
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'no-store',
        'content-security-policy': "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'",
        'x-frame-options': 'DENY',
      });
      response.end(PANEL_HTML);
      return true;
    }
    if (!path.startsWith('/admin/api/')) { json(response, 404, { error: 'No encontrado' }); return true; }
    const route = path.slice('/admin/api/'.length);

    try {
      if (request.method === 'GET' && route === 'session') {
        const s = sessionFor(request);
        json(response, 200, { authenticated: !!s, configured: !!store.getAdmin(), csrf: s?.csrf ?? null });
        return true;
      }

      if (request.method === 'POST' && (route === 'login' || route === 'setup')) {
        const body = await readBody(request);
        if (route === 'setup') {
          if (store.getAdmin()) return json(response, 409, { error: 'El administrador ya está configurado' }), true;
          if (!validPassword(body.password)) return json(response, 400, { error: 'La contraseña debe tener al menos 8 caracteres' }), true;
          setPassword(body.password);
        } else {
          if (recentFailures(clientIp).length >= loginMaxFailures) {
            response.setHeader('retry-after', String(LOGIN_WINDOW_MS / 1000));
            return json(response, 429, { error: 'Demasiados intentos. Prueba más tarde.' }), true;
          }
          if (!checkPassword(body.password)) {
            failures.set(clientIp, [...recentFailures(clientIp), Date.now()]);
            logs?.push('Intento de login de admin fallido');
            return json(response, 401, { error: 'Credenciales inválidas' }), true;
          }
          failures.delete(clientIp);
        }
        const csrf = startSession(response);
        logs?.push('Sesión de admin iniciada');
        json(response, 200, { authenticated: true, csrf });
        return true;
      }

      const session = sessionFor(request);
      if (!session) return json(response, 401, { error: 'No autenticado' }), true;
      if (request.method !== 'GET') {
        const sent = request.headers['x-csrf-token'];
        if (typeof sent !== 'string' || sent.length !== session.csrf.length ||
            !crypto.timingSafeEqual(Buffer.from(sent), Buffer.from(session.csrf))) {
          return json(response, 403, { error: 'CSRF inválido' }), true;
        }
      }

      if (request.method === 'POST' && route === 'logout') {
        sessions.delete(session.token);
        response.setHeader('set-cookie', `${COOKIE}=; HttpOnly; SameSite=Strict; Path=/admin; Max-Age=0`);
        json(response, 200, { ok: true });
      } else if (request.method === 'GET' && route === 'status') {
        json(response, 200, getStatus());
      } else if (request.method === 'GET' && route === 'settings') {
        json(response, 200, { values: store.all(), defs: SETTING_DEFS });
      } else if (request.method === 'PUT' && route === 'settings') {
        const body = await readBody(request);
        const applied = store.update(body);
        logs?.push(`Ajustes actualizados: ${Object.keys(applied).join(', ')}`);
        json(response, 200, { values: store.all() });
      } else if (request.method === 'POST' && route === 'password') {
        const body = await readBody(request);
        if (!checkPassword(body.current)) return json(response, 401, { error: 'Contraseña actual incorrecta' }), true;
        if (!validPassword(body.next)) return json(response, 400, { error: 'La nueva contraseña debe tener al menos 8 caracteres' }), true;
        setPassword(body.next);
        sessions.clear();
        logs?.push('Contraseña de admin cambiada');
        json(response, 200, { ok: true });
      } else if (request.method === 'GET' && route === 'logs') {
        json(response, 200, { lines: logs?.lines() ?? [] });
      } else {
        json(response, 404, { error: 'No encontrado' });
      }
    } catch (error) {
      json(response, 400, { error: error.message });
    }
    return true;
  }

  return { handle };
}
