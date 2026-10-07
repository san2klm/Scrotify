import crypto from 'node:crypto';

import { normalizeUser } from './navidrome-auth.js';

/// Scrotify Connect: presencia y relé de mensajes entre los dispositivos de un
/// mismo usuario de Navidrome (admin solo ve a admin). El servidor verifica
/// al usuario con Navidrome y agrupa por usuario; los mensajes son blobs
/// cifrados de extremo a extremo que solo se reenvían.
const DEVICE_ID = /^[A-Za-z0-9_-]{8,64}$/;
const KINDS = new Set(['phone', 'tablet', 'desktop', 'other']);
const MAX_DEVICES_PER_GROUP = 16;
const MAX_BLOB_CHARS = 64 * 1024;
const MAX_NAME_LENGTH = 48;

export function createConnectHub({ store, limits, guard, send, ipOf, auth }) {
  const groups = new Map(); // grupo -> Map(deviceId -> { socket, name, kind })
  const members = new WeakMap(); // socket -> { group, deviceId }
  const joining = new WeakSet();

  const list = (group) => [...group].map(([deviceId, d]) => ({ deviceId, name: d.name, kind: d.kind }));
  const broadcast = (group, message, except = null) => {
    for (const d of group.values()) if (d.socket !== except) send(d.socket, message);
  };
  const fail = (socket, message) => send(socket, { status: 'connect_error', message });

  function leave(socket) {
    const member = members.get(socket);
    if (!member) return;
    members.delete(socket);
    const group = groups.get(member.group);
    if (!group || group.get(member.deviceId)?.socket !== socket) return;
    group.delete(member.deviceId);
    if (group.size === 0) groups.delete(member.group);
    else broadcast(group, { event: 'connect_devices', devices: list(group) });
  }

  async function join(socket, message) {
    if (!limits.navidromeUrl) return fail(socket, 'Scrotify Connect no está configurado en este servidor.');
    const ip = ipOf(socket);
    if (store.isBlockedIp(ip)) return fail(socket, 'Acceso denegado.');
    if (joining.has(socket)) return;
    if (!guard.attempt(`connect:${ip}`, { max: 30, windowMs: 60_000 }).ok) return fail(socket, 'Demasiados intentos.');
    const { user, token, salt, deviceId, name, kind } = message;
    const label = typeof name === 'string' ? name.trim() : '';
    if (!DEVICE_ID.test(deviceId ?? '') || label.length === 0 || label.length > MAX_NAME_LENGTH) {
      return fail(socket, 'Datos de dispositivo inválidos.');
    }
    joining.add(socket);
    let ok;
    try {
      ok = await auth.verify(user, token, salt);
    } catch {
      joining.delete(socket);
      return fail(socket, 'No se pudo verificar el usuario con Navidrome.');
    }
    joining.delete(socket);
    if (!ok) {
      guard.fail(ip, { max: limits.pinFailMax });
      return fail(socket, 'Usuario o clave incorrectos.');
    }
    guard.success(ip);
    if (socket.readyState !== 1) return; // Se cerró mientras se verificaba.
    leave(socket);
    const groupId = crypto.createHash('sha256')
      .update(`${new URL(limits.navidromeUrl).origin}\n${normalizeUser(user)}`).digest('hex');
    let group = groups.get(groupId);
    if (!group) groups.set(groupId, (group = new Map()));
    const previous = group.get(deviceId);
    if (!previous && group.size >= MAX_DEVICES_PER_GROUP) return fail(socket, 'Demasiados dispositivos conectados.');
    if (previous && previous.socket !== socket) {
      members.delete(previous.socket);
      previous.socket.close(4000, 'replaced');
    }
    group.set(deviceId, { socket, name: label, kind: KINDS.has(kind) ? kind : 'other' });
    members.set(socket, { group: groupId, deviceId });
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
    if (!guard.attempt(`connect-msg:${member.group}:${member.deviceId}`, { max: 100, windowMs: 1000 }).ok) return;
    const group = groups.get(member.group);
    const payload = { event: 'connect_msg', from: member.deviceId, blob };
    if (to === '*') {
      broadcast(group, payload, socket);
    } else if (typeof to === 'string' && group.has(to)) {
      send(group.get(to).socket, payload);
    }
  }

  return { join, relay, leave };
}
