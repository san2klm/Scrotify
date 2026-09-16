import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/jam_models.dart';
import 'navidrome_service.dart';

typedef OnGuestStateSync = void Function(JamSessionState state);
typedef OnGuestPlaybackUpdated = void Function(
    Track? track,
    JamParticipant? addedBy,
    bool isPlaying,
    int positionMs,
    int serverTimestamp);
typedef OnGuestQueueUpdated = void Function(List<JamQueueItem> queue);
typedef OnGuestKicked = void Function(String reason);
typedef OnGuestSessionClosed = void Function(String reason);

/// Servicio de cliente Jam para unirse a sesiones como Invitado (Guest).
///
/// Gestiona:
/// 1. Descubrimiento de sesiones activas en la LAN vía UDP (Radar de Jam).
/// 2. Búsqueda directa por PIN de 6 caracteres.
/// 3. Conexión WebSocket al Host, sincronización de estado y despacho de acciones colaborativas.
class JamGuestService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  JamSessionState? _sessionState;
  JamParticipant? _localParticipant;

  OnGuestStateSync? onStateSync;
  OnGuestPlaybackUpdated? onPlaybackUpdated;
  OnGuestQueueUpdated? onQueueUpdated;
  OnGuestKicked? onKicked;
  OnGuestSessionClosed? onSessionClosed;

  bool get isConnected => _channel != null;
  JamSessionState? get sessionState => _sessionState;
  JamParticipant? get localParticipant => _localParticipant;

  // ---------------------------------------------------------------------------
  // Descubrimiento UDP en Red Local (Radar)
  // ---------------------------------------------------------------------------

  /// Escanea la red local mediante broadcasts UDP en el puerto [kJamDiscoveryPort] (47623).
  Future<List<DiscoveredJamSession>> scanRadar({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final discovered = <String, DiscoveredJamSession>{};
    final completer = Completer<List<DiscoveredJamSession>>();
    RawDatagramSocket? socket;
    Timer? timeoutTimer;

    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket?.receive();
          if (dg == null) return;
          try {
            final text = utf8.decode(dg.data);
            final json = jsonDecode(text) as Map<String, dynamic>;
            if (json['tag'] == kJamDiscoveryAppTag &&
                json['op'] == 'jam_presence') {
              final session = DiscoveredJamSession.fromJson(
                  json, dg.address.address);
              if (session.port > 0) {
                final key = '${session.host}:${session.port}:${session.pin}';
                discovered[key] = session;
              }
            }
          } catch (_) {}
        }
      });

      final queryPayload = jsonEncode({
        'tag': kJamDiscoveryAppTag,
        'op': 'discover_jam',
      });
      final bytes = utf8.encode(queryPayload);

      void sendBroadcasts() async {
        try {
          try {
            socket?.send(bytes, InternetAddress.loopbackIPv4, kJamDiscoveryPort);
          } catch (_) {}
          try {
            socket?.send(
                bytes, InternetAddress('255.255.255.255'), kJamDiscoveryPort);
          } catch (_) {}

          final interfaces = await NetworkInterface.list(
            type: InternetAddressType.IPv4,
            includeLoopback: false,
          );
          for (final iface in interfaces) {
            for (final addr in iface.addresses) {
              final parts = addr.address.split('.');
              if (parts.length == 4) {
                final subnetBcast =
                    '${parts[0]}.${parts[1]}.${parts[2]}.255';
                try {
                  socket?.send(
                      bytes, InternetAddress(subnetBcast), kJamDiscoveryPort);
                } catch (_) {}
              }
            }
          }
        } catch (_) {}
      }

      sendBroadcasts();
      Timer(const Duration(milliseconds: 500), sendBroadcasts);
      Timer(const Duration(milliseconds: 1200), sendBroadcasts);

      timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.complete(discovered.values.toList());
        }
      });

      final result = await completer.future;
      return result;
    } catch (e) {
      debugPrint('JamGuestService.scanRadar error: $e');
      return discovered.values.toList();
    } finally {
      timeoutTimer?.cancel();
      socket?.close();
    }
  }

  /// Busca una sesión Jam activa específica por su PIN de 6 caracteres.
  Future<DiscoveredJamSession?> findByPin(
    String pin, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final cleanPin = pin.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final completer = Completer<DiscoveredJamSession?>();
    RawDatagramSocket? socket;
    Timer? timeoutTimer;

    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket?.receive();
          if (dg == null) return;
          try {
            final text = utf8.decode(dg.data);
            final json = jsonDecode(text) as Map<String, dynamic>;
            if (json['tag'] == kJamDiscoveryAppTag &&
                json['op'] == 'jam_presence' &&
                (json['pin'] as String?)?.toUpperCase() == cleanPin) {
              final session = DiscoveredJamSession.fromJson(
                  json, dg.address.address);
              if (!completer.isCompleted) {
                completer.complete(session);
              }
            }
          } catch (_) {}
        }
      });

      final queryPayload = jsonEncode({
        'tag': kJamDiscoveryAppTag,
        'op': 'find_jam',
        'pin': cleanPin,
      });
      final bytes = utf8.encode(queryPayload);

      void sendBroadcasts() async {
        try {
          try {
            socket?.send(bytes, InternetAddress.loopbackIPv4, kJamDiscoveryPort);
          } catch (_) {}
          try {
            socket?.send(
                bytes, InternetAddress('255.255.255.255'), kJamDiscoveryPort);
          } catch (_) {}

          final interfaces = await NetworkInterface.list(
            type: InternetAddressType.IPv4,
            includeLoopback: false,
          );
          for (final iface in interfaces) {
            for (final addr in iface.addresses) {
              final parts = addr.address.split('.');
              if (parts.length == 4) {
                final subnetBcast =
                    '${parts[0]}.${parts[1]}.${parts[2]}.255';
                try {
                  socket?.send(
                      bytes, InternetAddress(subnetBcast), kJamDiscoveryPort);
                } catch (_) {}
              }
            }
          }
        } catch (_) {}
      }

      sendBroadcasts();
      Timer(const Duration(milliseconds: 400), sendBroadcasts);

      timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      });

      return await completer.future;
    } catch (e) {
      debugPrint('JamGuestService.findByPin error: $e');
      return null;
    } finally {
      timeoutTimer?.cancel();
      socket?.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Conexión y Gestión de Sesión WebSocket
  // ---------------------------------------------------------------------------

  Future<bool> connect({
    required String host,
    required int port,
    required String pin,
    required String name,
    required int avatarColorValue,
    String? participantId,
  }) async {
    await disconnect();

    final completer = Completer<bool>();
    final uri = Uri.parse('ws://$host:$port/jam/ws');

    try {
      final ws = await WebSocket.connect(uri.toString())
          .timeout(const Duration(seconds: 5));
      _channel = IOWebSocketChannel(ws);

      _subscription = _channel!.stream.listen(
        (data) {
          try {
            final raw = data is String ? data : utf8.decode(data as List<int>);
            final msg = jsonDecode(raw) as Map<String, dynamic>;
            final op = msg['op'] as String?;

            switch (op) {
              case 'join_response':
                final accepted = msg['accepted'] as bool? ?? false;
                if (accepted && msg['state'] != null) {
                  _sessionState = JamSessionState.fromJson(
                      msg['state'] as Map<String, dynamic>);
                  if (msg['assignedParticipant'] != null) {
                    _localParticipant = JamParticipant.fromJson(
                        msg['assignedParticipant'] as Map<String, dynamic>);
                  }
                  if (!completer.isCompleted) {
                    completer.complete(true);
                  }
                  onStateSync?.call(_sessionState!);
                } else {
                  if (!completer.isCompleted) {
                    completer.complete(false);
                  }
                  disconnect();
                }
                break;

              case 'state_sync':
                if (msg['state'] != null) {
                  _sessionState = JamSessionState.fromJson(
                      msg['state'] as Map<String, dynamic>);
                  onStateSync?.call(_sessionState!);
                }
                break;

              case 'playback_updated':
                Track? track;
                if (msg['track'] != null) {
                  final t = msg['track'] as Map<String, dynamic>;
                  track = Track(
                    id: (t['id'] as String?) ?? '',
                    title: (t['title'] as String?) ?? 'Unknown',
                    artist: (t['artist'] as String?) ?? 'Unknown',
                    album: (t['album'] as String?) ?? 'Unknown',
                    duration: (t['duration'] as String?) ?? '',
                    albumArtUrl: t['albumArtUrl'] as String?,
                  );
                }
                JamParticipant? addedBy;
                if (msg['addedBy'] != null) {
                  addedBy = JamParticipant.fromJson(
                      msg['addedBy'] as Map<String, dynamic>);
                }
                final isPlaying = msg['isPlaying'] as bool? ?? false;
                final posMs = (msg['positionMs'] as num?)?.toInt() ?? 0;
                final serverTs = (msg['serverTimestamp'] as num?)?.toInt() ??
                    DateTime.now().millisecondsSinceEpoch;

                if (_sessionState != null) {
                  _sessionState = _sessionState!.copyWith(
                    currentTrack: track,
                    currentTrackAddedBy: addedBy,
                    isPlaying: isPlaying,
                    positionMs: posMs,
                    updatedAtMs: serverTs,
                  );
                }

                onPlaybackUpdated?.call(
                    track, addedBy, isPlaying, posMs, serverTs);
                break;

              case 'queue_updated':
                if (msg['queue'] != null) {
                  final qList = (msg['queue'] as List<dynamic>)
                      .map((e) =>
                          JamQueueItem.fromJson(e as Map<String, dynamic>))
                      .toList();
                  if (_sessionState != null) {
                    _sessionState = _sessionState!.copyWith(queue: qList);
                  }
                  onQueueUpdated?.call(qList);
                }
                break;

              case 'kicked':
                final reason = msg['reason'] as String? ?? 'Desconectado.';
                onKicked?.call(reason);
                disconnect();
                break;

              case 'session_closed':
                final reason = msg['reason'] as String? ?? 'Sesión finalizada.';
                onSessionClosed?.call(reason);
                disconnect();
                break;
            }
          } catch (e) {
            debugPrint('JamGuestService WebSocket parse error: $e');
          }
        },
        onDone: () {
          debugPrint('JamGuestService: Connection closed');
          if (!completer.isCompleted) completer.complete(false);
          disconnect();
        },
        onError: (e) {
          debugPrint('JamGuestService: Connection error $e');
          if (!completer.isCompleted) completer.complete(false);
          disconnect();
        },
      );

      // Enviar solicitud de unión inmediata
      _send({
        'op': 'join_request',
        'pin': pin,
        'name': name,
        'avatarColorValue': avatarColorValue,
        if (participantId != null) 'participantId': participantId,
      });

      return await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
    } catch (e) {
      debugPrint('JamGuestService.connect error: $e');
      await disconnect();
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Acciones Colaborativas
  // ---------------------------------------------------------------------------

  void addToQueue(Track track, {bool playNext = false}) {
    _send({
      'op': 'add_to_queue',
      'track': {
        'id': track.id,
        'title': track.title,
        'artist': track.artist,
        'album': track.album,
        'duration': track.duration,
        'albumArtUrl': track.albumArtUrl,
      },
      'playNext': playNext,
    });
  }

  void removeFromQueue(String queueItemId) {
    _send({
      'op': 'remove_from_queue',
      'queueItemId': queueItemId,
    });
  }

  void reorderQueue(int oldIndex, int newIndex) {
    _send({
      'op': 'reorder_queue',
      'oldIndex': oldIndex,
      'newIndex': newIndex,
    });
  }

  void sendPlaybackControl(String action, {int? positionMs}) {
    _send({
      'op': 'playback_control',
      'action': action,
      if (positionMs != null) 'positionMs': positionMs,
    });
  }

  void _send(Map<String, dynamic> data) {
    try {
      _channel?.sink.add(jsonEncode(data));
    } catch (e) {
      debugPrint('JamGuestService send error: $e');
    }
  }

  Future<void> disconnect() async {
    try {
      _send({'op': 'leave'});
    } catch (_) {}
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _sessionState = null;
    _localParticipant = null;
  }
}
