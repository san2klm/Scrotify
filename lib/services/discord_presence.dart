import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'navidrome_service.dart';

/// Canal de bajo nivel hacia el cliente de Discord (IPC local).
abstract class DiscordIpcTransport {
  /// Abre el canal; `false` si Discord no está en ejecución.
  Future<bool> connect();

  Future<void> write(List<int> bytes);

  Future<void> close();
}

/// Discord Rich Presence por IPC local: «Escuchando X — Y» en el perfil.
///
/// Necesita el *Application ID* de una aplicación creada en el portal de
/// desarrolladores de Discord (lo introduce el usuario en Ajustes). Solo
/// escritorio. No envía nada fuera del equipo: habla con el cliente de Discord
/// por una tubería/socket local.
class DiscordRichPresence {
  DiscordRichPresence({
    required this.clientId,
    DiscordIpcTransport? transport,
  }) : _transport = transport ?? createDiscordTransport();

  final String clientId;
  final DiscordIpcTransport _transport;

  bool _connected = false;
  int _nonce = 0;

  bool get isConnected => _connected;

  static const int opHandshake = 0;
  static const int opFrame = 1;
  static const int opClose = 2;

  /// Trama IPC: `opcode (uint32 LE) | longitud (uint32 LE) | JSON UTF-8`.
  static Uint8List encodeFrame(int op, Map<String, dynamic> payload) {
    final body = utf8.encode(jsonEncode(payload));
    final data = ByteData(8 + body.length)
      ..setUint32(0, op, Endian.little)
      ..setUint32(4, body.length, Endian.little);
    final bytes = data.buffer.asUint8List();
    bytes.setRange(8, 8 + body.length, body);
    return bytes;
  }

  /// Decodifica una trama completa; `null` si está truncada o mal formada.
  static ({int op, Map<String, dynamic> data})? decodeFrame(List<int> bytes) {
    if (bytes.length < 8) return null;
    final header =
        ByteData.sublistView(Uint8List.fromList(bytes.sublist(0, 8)));
    final op = header.getUint32(0, Endian.little);
    final length = header.getUint32(4, Endian.little);
    if (bytes.length < 8 + length) return null;
    try {
      final json = jsonDecode(utf8.decode(bytes.sublist(8, 8 + length)));
      if (json is! Map) return null;
      return (op: op, data: Map<String, dynamic>.from(json));
    } catch (_) {
      return null;
    }
  }

  /// `activity` de `SET_ACTIVITY` para [track]. [position] permite que Discord
  /// muestre el tiempo transcurrido; sin ella (o en pausa) no hay cronómetro.
  static Map<String, dynamic> buildActivity(
    Track track, {
    required bool playing,
    Duration? position,
    DateTime? now,
  }) {
    String clip(String text, int max) =>
        text.length <= max ? text : '${text.substring(0, max - 1)}…';
    // Discord exige 2–128 caracteres en cada línea.
    String line(String text) {
      final t = clip(text.trim(), 128);
      return t.length >= 2 ? t : '$t ';
    }

    final activity = <String, dynamic>{
      'type': 2, // Listening
      'details': line(track.title),
      'state':
          line(track.artist.isEmpty ? 'Artista desconocido' : track.artist),
      'assets': {
        'large_text': line(track.album.isEmpty ? 'Scrotify' : track.album),
        'small_text': playing ? 'Reproduciendo' : 'En pausa',
      },
    };
    if (playing && position != null) {
      final clock = (now ?? DateTime.now()).millisecondsSinceEpoch;
      activity['timestamps'] = {'start': clock - position.inMilliseconds};
    }
    return activity;
  }

  /// Conecta y hace el saludo. `false` si Discord no está abierto.
  Future<bool> start() async {
    if (_connected) return true;
    if (clientId.trim().isEmpty) return false;
    try {
      if (!await _transport.connect()) return false;
      await _transport.write(
          encodeFrame(opHandshake, {'v': 1, 'client_id': clientId.trim()}));
      _connected = true;
      return true;
    } catch (e) {
      debugPrint('DiscordRichPresence: no se pudo conectar ($e)');
      _connected = false;
      return false;
    }
  }

  Future<void> _setActivity(Map<String, dynamic>? activity) async {
    if (!_connected) return;
    try {
      await _transport.write(encodeFrame(opFrame, {
        'cmd': 'SET_ACTIVITY',
        'args': {'pid': pid, 'activity': activity},
        'nonce': '${++_nonce}',
      }));
    } catch (e) {
      // Discord se cerró: se reintentará al siguiente cambio.
      debugPrint('DiscordRichPresence: escritura fallida ($e)');
      _connected = false;
      unawaited(_transport.close());
    }
  }

  /// Publica la pista actual (o la borra si [track] es `null`).
  Future<void> update(Track? track,
      {required bool playing, Duration? position}) async {
    if (!_connected && !await start()) return;
    if (track == null) return clear();
    await _setActivity(
        buildActivity(track, playing: playing, position: position));
  }

  Future<void> clear() => _setActivity(null);

  Future<void> stop() async {
    if (_connected) await clear();
    _connected = false;
    await _transport.close();
  }
}

/// Transporte adecuado para la plataforma actual.
DiscordIpcTransport createDiscordTransport() =>
    Platform.isWindows ? _WindowsPipeTransport() : _UnixSocketTransport();

/// Linux y macOS: socket Unix `discord-ipc-N` en el directorio temporal.
class _UnixSocketTransport implements DiscordIpcTransport {
  Socket? _socket;

  @override
  Future<bool> connect() async {
    final env = Platform.environment;
    final bases = <String>{
      for (final key in ['XDG_RUNTIME_DIR', 'TMPDIR', 'TMP', 'TEMP'])
        if ((env[key] ?? '').isNotEmpty) env[key]!,
      '/tmp',
    };
    for (final base in bases) {
      for (var i = 0; i < 10; i++) {
        final path = '$base/discord-ipc-$i';
        try {
          final socket = await Socket.connect(
            InternetAddress(path, type: InternetAddressType.unix),
            0,
            timeout: const Duration(seconds: 2),
          );
          // Respuestas de Discord: no se usan, pero hay que consumirlas.
          socket.listen((_) {}, onError: (_) {}, cancelOnError: true);
          _socket = socket;
          return true;
        } catch (_) {
          continue;
        }
      }
    }
    return false;
  }

  @override
  Future<void> write(List<int> bytes) async {
    final socket = _socket;
    if (socket == null) throw const SocketException('sin conexión');
    socket.add(bytes);
    await socket.flush();
  }

  @override
  Future<void> close() async {
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
  }
}

/// Windows: tubería con nombre `\\.\pipe\discord-ipc-N`.
class _WindowsPipeTransport implements DiscordIpcTransport {
  RandomAccessFile? _pipe;

  @override
  Future<bool> connect() async {
    for (var i = 0; i < 10; i++) {
      try {
        _pipe = await File('\\\\.\\pipe\\discord-ipc-$i')
            .open(mode: FileMode.writeOnlyAppend);
        return true;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  @override
  Future<void> write(List<int> bytes) async {
    final pipe = _pipe;
    if (pipe == null) throw const FileSystemException('sin conexión');
    await pipe.writeFrom(bytes);
    await pipe.flush();
  }

  @override
  Future<void> close() async {
    try {
      await _pipe?.close();
    } catch (_) {}
    _pipe = null;
  }
}
