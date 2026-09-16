import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/jam_models.dart';
import 'navidrome_service.dart';

typedef OnJamJoinRequested = Future<bool> Function(
    JamParticipant participant, WebSocket socket);
typedef OnJamTrackAddRequested = void Function(
    Track track, JamParticipant participant, bool playNext);
typedef OnJamTrackRemoveRequested = void Function(
    String queueItemId, JamParticipant participant);
typedef OnJamQueueReorderRequested = void Function(
    int oldIndex, int newIndex, JamParticipant participant);
typedef OnJamPlaybackControlRequested = void Function(
    String action, int? positionMs, JamParticipant participant);
typedef OnJamParticipantLeft = void Function(JamParticipant participant);

/// Servidor de sesión Jam que corre en el dispositivo Anfitrión (Host).
///
/// Gestiona:
/// 1. Servidor WebSocket para comunicación bidireccional en tiempo real con invitados.
/// 2. Beacon UDP en puerto [kJamDiscoveryPort] (47623) para descubrimiento en red local (Radar).
/// 3. Registro de participantes, control de permisos y difusión de estado.
class JamHostService {
  HttpServer? _server;
  RawDatagramSocket? _discoverySocket;

  final Map<String, WebSocket> _clientSockets = {};
  final Map<String, JamParticipant> _participants = {};

  String? _sessionId;
  JamCode? _pinCode;
  String _hostName = '';
  String? _hostIp;
  List<String> _allLocalIps = [];
  int _port = 0;
  JamMode _mode = JamMode.partySpeaker;
  bool _allowGuestControls = true;

  // Metadatos para presencia UDP
  String? _currentTrackTitle;
  String? _currentTrackArtist;
  String? _albumArtUrl;

  // Callbacks hacia JamController
  OnJamJoinRequested? onJoinRequested;
  OnJamTrackAddRequested? onTrackAddRequested;
  OnJamTrackRemoveRequested? onTrackRemoveRequested;
  OnJamQueueReorderRequested? onQueueReorderRequested;
  OnJamPlaybackControlRequested? onPlaybackControlRequested;
  OnJamParticipantLeft? onParticipantLeft;

  bool get isRunning => _server != null;
  String? get sessionId => _sessionId;
  JamCode? get pinCode => _pinCode;
  String? get hostIp => _hostIp;
  List<String> get allLocalIps => _allLocalIps;
  int get port => _port;
  JamMode get mode => _mode;
  bool get allowGuestControls => _allowGuestControls;
  List<JamParticipant> get participants => _participants.values.toList();

  String? get qrDataUri => _pinCode != null && _hostIp != null
      ? JamQrData(
          host: _hostIp!,
          port: _port,
          code: _pinCode!.value,
          sessionId: _sessionId,
        ).toUri()
      : null;

  /// Inicia el servidor Jam y el beacon de descubrimiento.
  Future<void> start({
    required String sessionId,
    required JamCode pinCode,
    required String hostName,
    JamMode mode = JamMode.partySpeaker,
    bool allowGuestControls = true,
  }) async {
    await stop();

    _sessionId = sessionId;
    _pinCode = pinCode;
    _hostName = hostName;
    _mode = mode;
    _allowGuestControls = allowGuestControls;

    // Bind a puerto dinámico en todas las interfaces de red
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _port = _server!.port;
    _allLocalIps = await _getAllLocalIps();
    _hostIp = _allLocalIps.isNotEmpty ? _allLocalIps.first : '127.0.0.1';

    debugPrint(
        'JamHostService: Server listening on $_hostIp:$_port (code: ${_pinCode?.value}, mode: $_mode)');

    _server!.listen(_handleHttpRequest);

    // Iniciar beacon de radar UDP
    await _startDiscoveryBeacon();
  }

  void updateTrackMetadata({
    String? title,
    String? artist,
    String? albumArtUrl,
  }) {
    _currentTrackTitle = title;
    _currentTrackArtist = artist;
    _albumArtUrl = albumArtUrl;
  }

  void updateSettings({JamMode? mode, bool? allowGuestControls}) {
    if (mode != null) _mode = mode;
    if (allowGuestControls != null) _allowGuestControls = allowGuestControls;
  }

  // ---------------------------------------------------------------------------
  // Manejo de peticiones HTTP y WebSocket
  // ---------------------------------------------------------------------------
  Future<void> _handleHttpRequest(HttpRequest req) async {
    final path = req.uri.path;

    try {
      if (path == '/jam/ws') {
        if (WebSocketTransformer.isUpgradeRequest(req)) {
          final socket = await WebSocketTransformer.upgrade(req);
          _handleWebSocketClient(socket);
        } else {
          req.response.statusCode = HttpStatus.badRequest;
          req.response.write('Expected WebSocket upgrade');
          await req.response.close();
        }
      } else if (path == '/jam/status' && req.method == 'GET') {
        final body = jsonEncode({
          'tag': kJamDiscoveryAppTag,
          'sessionId': _sessionId,
          'hostName': _hostName,
          'pin': _pinCode?.value,
          'mode': _mode.name,
          'participantCount': _participants.length + 1,
          'allowGuestControls': _allowGuestControls,
        });
        req.response.headers.contentType = ContentType.json;
        req.response.write(body);
        await req.response.close();
      } else {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
      }
    } catch (e) {
      debugPrint('JamHostService HTTP error: $e');
    }
  }

  void _handleWebSocketClient(WebSocket socket) {
    String? participantId;

    socket.listen(
      (data) {
        try {
          final raw = data is String ? data : utf8.decode(data as List<int>);
          final msg = jsonDecode(raw) as Map<String, dynamic>;
          final op = msg['op'] as String?;

          switch (op) {
            case 'join_request':
              final pin = msg['pin'] as String?;
              if (pin != null && pin != _pinCode?.value) {
                socket.add(jsonEncode({
                  'op': 'join_response',
                  'accepted': false,
                  'reason': 'PIN incorrecto',
                }));
                socket.close();
                return;
              }

              final name = (msg['name'] as String?)?.trim() ?? 'Invitado';
              final color = (msg['avatarColorValue'] as num?)?.toInt() ?? 0xFF10B981;
              final id = msg['participantId'] as String? ??
                  'guest_${DateTime.now().millisecondsSinceEpoch}_${_participants.length + 1}';

              final participant = JamParticipant(
                id: id,
                name: name.isNotEmpty ? name : 'Invitado',
                avatarColorValue: color,
                isHost: false,
                joinedAt: DateTime.now(),
                canControlPlayback: _allowGuestControls,
                canManageQueue: true,
              );

              participantId = id;
              _clientSockets[id] = socket;
              _participants[id] = participant;

              if (onJoinRequested != null) {
                onJoinRequested!(participant, socket);
              } else {
                // Respuesta por defecto con el estado actual
                socket.add(jsonEncode({
                  'op': 'join_response',
                  'accepted': true,
                  'assignedParticipant': participant.toJson(),
                  'state': {
                    'sessionId': _sessionId,
                    'pinCode': _pinCode?.value,
                    'hostName': _hostName,
                    'hostIp': _hostIp,
                    'port': _port,
                    'mode': _mode.name,
                    'isPlaying': false,
                    'positionMs': 0,
                    'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
                    'queue': [],
                    'participants':
                        _participants.values.map((e) => e.toJson()).toList(),
                    'allowGuestControls': _allowGuestControls,
                  },
                }));
              }
              break;

            case 'add_to_queue':
              if (participantId != null && _participants.containsKey(participantId)) {
                final participant = _participants[participantId]!;
                final trackJson = msg['track'] as Map<String, dynamic>;
                final track = Track(
                  id: (trackJson['id'] as String?) ?? '',
                  title: (trackJson['title'] as String?) ?? 'Unknown',
                  artist: (trackJson['artist'] as String?) ?? 'Unknown',
                  album: (trackJson['album'] as String?) ?? 'Unknown',
                  duration: (trackJson['duration'] as String?) ?? '',
                  albumArtUrl: trackJson['albumArtUrl'] as String?,
                );
                final playNext = msg['playNext'] as bool? ?? false;
                onTrackAddRequested?.call(track, participant, playNext);
              }
              break;

            case 'remove_from_queue':
              if (participantId != null && _participants.containsKey(participantId)) {
                final participant = _participants[participantId]!;
                final queueItemId = msg['queueItemId'] as String?;
                if (queueItemId != null) {
                  onTrackRemoveRequested?.call(queueItemId, participant);
                }
              }
              break;

            case 'reorder_queue':
              if (participantId != null && _participants.containsKey(participantId)) {
                final participant = _participants[participantId]!;
                final oldIdx = (msg['oldIndex'] as num?)?.toInt();
                final newIdx = (msg['newIndex'] as num?)?.toInt();
                if (oldIdx != null && newIdx != null) {
                  onQueueReorderRequested?.call(oldIdx, newIdx, participant);
                }
              }
              break;

            case 'playback_control':
              if (participantId != null && _participants.containsKey(participantId)) {
                final participant = _participants[participantId]!;
                if (!_allowGuestControls && !participant.isHost) {
                  socket.add(jsonEncode({
                    'op': 'error',
                    'message': 'El anfitrión ha deshabilitado el control de reproducción.',
                  }));
                  return;
                }
                final action = msg['action'] as String?;
                final posMs = (msg['positionMs'] as num?)?.toInt();
                if (action != null) {
                  onPlaybackControlRequested?.call(action, posMs, participant);
                }
              }
              break;

            case 'leave':
              _removeParticipant(participantId);
              break;
          }
        } catch (e) {
          debugPrint('JamHostService WebSocket error parsing msg: $e');
        }
      },
      onDone: () => _removeParticipant(participantId),
      onError: (_) => _removeParticipant(participantId),
    );
  }

  void _removeParticipant(String? id) {
    if (id == null) return;
    final participant = _participants.remove(id);
    _clientSockets.remove(id);
    if (participant != null) {
      onParticipantLeft?.call(participant);
      broadcastMessage({
        'op': 'participant_left',
        'participant': participant.toJson(),
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Difusión de Mensajes (Broadcasting)
  // ---------------------------------------------------------------------------
  void broadcastMessage(Map<String, dynamic> message) {
    final encoded = jsonEncode(message);
    for (final socket in _clientSockets.values) {
      try {
        if (socket.readyState == WebSocket.open) {
          socket.add(encoded);
        }
      } catch (_) {}
    }
  }

  void broadcastSessionState(JamSessionState state) {
    broadcastMessage({
      'op': 'state_sync',
      'state': state.toJson(),
    });
  }

  void broadcastPlaybackUpdate({
    Track? track,
    JamParticipant? addedBy,
    required bool isPlaying,
    required int positionMs,
  }) {
    broadcastMessage({
      'op': 'playback_updated',
      if (track != null)
        'track': {
          'id': track.id,
          'title': track.title,
          'artist': track.artist,
          'album': track.album,
          'duration': track.duration,
          'albumArtUrl': track.albumArtUrl,
        },
      if (addedBy != null) 'addedBy': addedBy.toJson(),
      'isPlaying': isPlaying,
      'positionMs': positionMs,
      'serverTimestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void broadcastQueueUpdate(List<JamQueueItem> queue) {
    broadcastMessage({
      'op': 'queue_updated',
      'queue': queue.map((e) => e.toJson()).toList(),
    });
  }

  void sendToClient(String participantId, Map<String, dynamic> message) {
    final socket = _clientSockets[participantId];
    if (socket != null && socket.readyState == WebSocket.open) {
      socket.add(jsonEncode(message));
    }
  }

  void kickParticipant(String participantId) {
    final socket = _clientSockets[participantId];
    if (socket != null) {
      socket.add(jsonEncode({
        'op': 'kicked',
        'reason': 'Has sido removido de la sesión por el anfitrión.',
      }));
      socket.close();
    }
    _removeParticipant(participantId);
  }

  // ---------------------------------------------------------------------------
  // Beacon UDP para Radar en Red Local
  // ---------------------------------------------------------------------------
  Future<void> _startDiscoveryBeacon() async {
    try {
      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kJamDiscoveryPort,
        reuseAddress: true,
        reusePort: true,
      );
      _discoverySocket!.broadcastEnabled = true;
      _discoverySocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = _discoverySocket?.receive();
          if (dg != null) {
            _handleDiscoveryDatagram(dg);
          }
        }
      });
      debugPrint('JamHostService: Discovery beacon bound on port $kJamDiscoveryPort');
    } catch (e) {
      debugPrint('JamHostService: Discovery beacon failed to bind: $e');
    }
  }

  void _handleDiscoveryDatagram(Datagram dg) {
    if (_server == null || _pinCode == null) return;

    try {
      final msg = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
      if (msg['tag'] != kJamDiscoveryAppTag) return;

      final op = msg['op'] as String?;
      final pin = msg['pin'] as String?;

      bool shouldReply = false;
      if (op == 'discover_jam') {
        shouldReply = true;
      } else if (op == 'find_jam' && pin != null) {
        shouldReply = pin.toUpperCase() == _pinCode!.value;
      }

      if (shouldReply) {
        final reply = jsonEncode({
          'tag': kJamDiscoveryAppTag,
          'op': 'jam_presence',
          'host': _hostIp,
          'port': _port,
          'pin': _pinCode!.value,
          'sessionTitle': 'Jam de $_hostName',
          'hostName': _hostName,
          'participantCount': _participants.length + 1,
          'currentTrackTitle': _currentTrackTitle,
          'currentTrackArtist': _currentTrackArtist,
          'albumArtUrl': _albumArtUrl,
          'mode': _mode.name,
        });

        _discoverySocket?.send(
          utf8.encode(reply),
          dg.address,
          dg.port,
        );
      }
    } catch (_) {}
  }

  Future<List<String>> _getAllLocalIps() async {
    final ips = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.isLoopback &&
              !addr.address.startsWith('169.254.') &&
              !ips.contains(addr.address)) {
            ips.add(addr.address);
          }
        }
      }
    } catch (_) {}
    if (ips.isEmpty) ips.add('127.0.0.1');
    return ips;
  }

  Future<void> stop() async {
    // Notificar cierre a todos los clientes
    broadcastMessage({
      'op': 'session_closed',
      'reason': 'El anfitrión ha finalizado la sesión Jam.',
    });

    for (final socket in List.of(_clientSockets.values)) {
      try {
        await socket.close();
      } catch (_) {}
    }
    _clientSockets.clear();
    _participants.clear();

    _discoverySocket?.close();
    _discoverySocket = null;

    await _server?.close(force: true);
    _server = null;

    _sessionId = null;
    _pinCode = null;
    _hostIp = null;
    _port = 0;
    debugPrint('JamHostService stopped');
  }
}
