import crypto from 'node:crypto';

/// Verifica un usuario de Navidrome con el esquema de token de Subsonic
/// (`t = md5(clave + salt)`) llamando a `ping` en el Navidrome configurado.
/// El servidor Jam nunca recibe la clave. Solo se consulta la URL fijada por
/// el administrador, nunca una enviada por el cliente.
const USER = /^[^\u0000-\u001f\u007f]{1,64}$/;
const TOKEN = /^[0-9a-f]{32}$/;
const SALT = /^[A-Za-z0-9]{6,64}$/;
const CACHE_MS = 5 * 60 * 1000;
const MAX_CACHE = 500;

export function normalizeUser(user) {
  return typeof user === 'string' ? user.trim().toLowerCase() : '';
}

export function createNavidromeAuth({ getBaseUrl, fetchImpl = fetch, now = () => Date.now(), timeoutMs = 5000 }) {
  const cache = new Map(); // huella -> expira

  /// `true` solo si Navidrome confirma las credenciales. Lanza si no hay
  /// Navidrome configurado o no responde.
  async function verify(user, token, salt) {
    const base = getBaseUrl();
    if (!base) throw new Error('not-configured');
    if (!USER.test(user ?? '') || !TOKEN.test(token ?? '') || !SALT.test(salt ?? '')) return false;
    const key = crypto.createHash('sha256').update(`${normalizeUser(user)}\n${token}\n${salt}`).digest('hex');
    const hit = cache.get(key);
    if (hit && hit > now()) return true;
    const url = new URL('/rest/ping.view', base);
    url.search = new URLSearchParams({
      u: user.trim(), t: token, s: salt, v: '1.16.1', c: 'scrotify-jam', f: 'json',
    }).toString();
    const response = await fetchImpl(url, { signal: AbortSignal.timeout(timeoutMs), redirect: 'error' });
    if (!response.ok) throw new Error(`navidrome-${response.status}`);
    const text = await response.text();
    if (text.length > 65536) throw new Error('navidrome-too-large');
    const ok = JSON.parse(text)?.['subsonic-response']?.status === 'ok';
    if (ok) {
      if (cache.size >= MAX_CACHE) cache.delete(cache.keys().next().value);
      cache.set(key, now() + CACHE_MS);
    }
    return ok;
  }

  return { verify };
}
