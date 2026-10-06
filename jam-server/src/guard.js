/// Protección contra fuerza bruta de PIN por IP: ventana deslizante de
/// intentos + bloqueo temporal progresivo tras fallos repetidos.
export function createGuard({ now = () => Date.now() } = {}) {
  const attempts = new Map(); // ip -> [timestamps]
  const failures = new Map(); // ip -> { count, strikes, blockedUntil, lastFail }

  const FAIL_MEMORY_MS = 10 * 60 * 1000;
  const BASE_BLOCK_MS = 60 * 1000;
  const MAX_BLOCK_MS = 60 * 60 * 1000;

  function prune() {
    if (attempts.size + failures.size < 5000) return;
    const t = now();
    for (const [ip, list] of attempts) if (!list.some((x) => t - x < 3600_000)) attempts.delete(ip);
    for (const [ip, f] of failures) if (f.blockedUntil < t && t - f.lastFail > FAIL_MEMORY_MS) failures.delete(ip);
  }

  return {
    /// Registra un intento. Devuelve `{ ok: true }` o `{ ok: false, retryMs }`.
    attempt(ip, { max, windowMs }) {
      prune();
      const t = now();
      const f = failures.get(ip);
      if (f && f.blockedUntil > t) return { ok: false, retryMs: f.blockedUntil - t };
      const list = (attempts.get(ip) ?? []).filter((x) => t - x < windowMs);
      if (list.length >= max) {
        attempts.set(ip, list);
        return { ok: false, retryMs: windowMs - (t - list[0]) };
      }
      list.push(t);
      attempts.set(ip, list);
      return { ok: true };
    },
    /// Anota un fallo (PIN/contraseña erróneos). Tras `max` fallos seguidos
    /// bloquea la IP con duración creciente (1 min, 2, 4… hasta 1 h).
    fail(ip, { max }) {
      const t = now();
      const f = failures.get(ip) ?? { count: 0, strikes: 0, blockedUntil: 0, lastFail: 0 };
      if (t - f.lastFail > FAIL_MEMORY_MS) f.count = 0;
      f.count += 1;
      f.lastFail = t;
      if (f.count >= max) {
        f.strikes += 1;
        f.count = 0;
        f.blockedUntil = t + Math.min(MAX_BLOCK_MS, BASE_BLOCK_MS * 2 ** (f.strikes - 1));
      }
      failures.set(ip, f);
    },
    success(ip) {
      const f = failures.get(ip);
      if (f) f.count = 0;
    },
  };
}
