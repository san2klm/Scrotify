import crypto from 'node:crypto';

/// Scrotify Connect: presencia y relé de mensajes entre los dispositivos de un
/// mismo usuario. El grupo es la bóveda de sincronización (misma clave), y los
/// mensajes son blobs cifrados de extremo a extremo que el servidor solo reenvía.
const HEX64 = /^[0-9a-f]{64}$/;
const DEVICE_ID = /^[A-Za-z0-9_-]{8,64}$/;
const KINDS = new Set(['phone', 'tablet', 'desktop', 'other']);
const MAX_DEVICES_PER_GROUP = 16;
const MAX_BLOB_CHARS = 64 * 1024;
const MAX_NAME_LENGTH = 48;

function sha256Hex(value) {
  return crypto.createHash('sha256').update(value, 'utf8').digest('hex');
}

function safeEqualHex(a, b) {
  const x = Buffer.from(a, 'hex');
  const y = Buffer.from(b, 'hex');
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

export function createConnectHub({ store, limits, guard, send, ipOf }) {
  const groups = new Map(); // vaultId -> Map(deviceId -> { socket, name, kind })
  const members = new WeakMap(); // socket -> { vaultId, deviceId }

  const list = (group) => [...group].map(([deviceId, d]) => ({ deviceId, name: d.name, kind: d.kind }));
  const broadcast = (group, message, except = null) => {
    for (const d of group.values()) if (d.socket !== except) send(d.socket, message);
  };
  const fail = (socket, message) => send(socket, { status: 'connect_error', message });

  function leave(socket) {
    const member = members.get(socket);
    if (!member) return;
    members.delete(socket);
    const group = groups.get(member.vaultId);
    if (!group || group.get(member.deviceId)?.socket !== socket) return;
    group.delete(member.deviceId);
    if (group.size === 0) groups.delete(member.vaultId);
    else broadcast(group, { event: 'connect_devices', devices: list(group) });
  }

  function join(socket, message) {
    if (!limits.syncEnabled) return fail(socket, 'Scrotify Connect está desactivado en este servidor.');
    const ip = ipOf(socket);
    if (store.isBlockedIp(ip)) return fail(socket, 'Acceso denegado.');
    if (!guard.attempt(`connect:${ip}`, { max: 30, windowMs: 60_000 }).ok) return fail(socket, 'Demasiados intentos.');
    const { vaultId, token, deviceId, name, kind } = message;
    if (!HEX64.test(vaultId ?? '') || !HEX64.test(token ?? '') || !DEVICE_ID.test(deviceId ?? '')) {
      return fail(socket, 'Datos de dispositivo inválidos.');
    }
    const label = typeof name === 'string' ? name.trim() : '';
    if (label.length === 0 || label.length > MAX_NAME_LENGTH) return fail(socket, 'Nombre de dispositivo inválido.');
    const vault = store.getSyncVault(vaultId);
    if (!vault || !safeEqualHex(vault.authHash, sha256Hex(token))) {
      guard.fail(ip, { max: limits.pinFailMax });
      return fail(socket, 'Credencial inválida.');
    }
    guard.success(ip);
    leave(socket);
    let group = groups.get(vaultId);
    if (!group) groups.set(vaultId, (group = new Map()));
    const previous = group.get(deviceId);
    if (!previous && group.size >= MAX_DEVICES_PER_GROUP) return fail(socket, 'Demasiados dispositivos conectados.');
    if (previous && previous.socket !== socket) {
      members.delete(previous.socket);
      previous.socket.close(4000, 'replaced');
    }
    group.set(deviceId, { socket, name: label, kind: KINDS.has(kind) ? kind : 'other' });
    members.set(socket, { vaultId, deviceId });
    send(socket, { status: 'connect_joined', devices: list(group) });
    broadcast(group, { event: 'connect_devices', devices: list(group) }, socket);
  }

  function relay(socket, message) {
    const member = members.get(socket);
    if (!member) return fail(socket, 'Primero únete con connect_join.');
    const { to, blob } = message;
    if (typeof blob !== 'string' || blob.length === 0 || blob.length > MAX_BLOB_CHARS) {
      return fail(socket, 'Mensaje inválido.');
    }
    if (!guard.attempt(`connect-msg:${member.vaultId}:${member.deviceId}`, { max: 100, windowMs: 1000 }).ok) return;
    const group = groups.get(member.vaultId);
    const payload = { event: 'connect_msg', from: member.deviceId, blob };
    if (to === '*') {
      broadcast(group, payload, socket);
    } else if (typeof to === 'string' && group.has(to)) {
      send(group.get(to).socket, payload);
    }
  }

  return { join, relay, leave };
}
