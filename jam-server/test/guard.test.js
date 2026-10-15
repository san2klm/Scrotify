import assert from 'node:assert/strict';
import { test } from 'node:test';

import { createGuard } from '../src/guard.js';

test('prune: con muchas claves vivas no recorre los mapas en cada intento', () => {
  let t = 1_000_000;
  const guard = createGuard({ now: () => t });
  // 5000+ IPs activas: nada que podar, pero el coste no debe repetirse.
  for (let i = 0; i < 5100; i += 1) guard.attempt(`10.0.${i >> 8}.${i & 255}`, { max: 100, windowMs: 3_600_000 });

  let iterations = 0;
  const realEntries = Map.prototype[Symbol.iterator];
  Map.prototype[Symbol.iterator] = function patched() {
    iterations += 1;
    return realEntries.call(this);
  };
  try {
    for (let i = 0; i < 50; i += 1) guard.attempt('192.168.0.1', { max: 100, windowMs: 3_600_000 });
  } finally {
    Map.prototype[Symbol.iterator] = realEntries;
  }
  assert.ok(iterations <= 2, `se podó ${iterations} veces en 50 intentos`);
});

test('los fallos repetidos bloquean la IP con duración creciente', () => {
  let t = 0;
  const guard = createGuard({ now: () => t });
  for (let i = 0; i < 3; i += 1) guard.fail('1.1.1.1', { max: 3 });
  const blocked = guard.attempt('1.1.1.1', { max: 10, windowMs: 1000 });
  assert.equal(blocked.ok, false);
  t += 61_000;
  assert.equal(guard.attempt('1.1.1.1', { max: 10, windowMs: 1000 }).ok, true);
});
