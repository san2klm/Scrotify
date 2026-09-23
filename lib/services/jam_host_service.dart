import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/jam_models.dart';
import 'jam_network_platform.dart';
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
  Timer? _presenceTimer;
  bool _holdsMulticastReception = false;

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
  bool _allowGuestQueueManage = true;
  bool _isPublic = true;
  int _maxParticipants = 0;
  String? _initialPlaylistId;

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
  bool get allowGuestQueueManage => _allowGuestQueueManage;
  bool get isPublic => _isPublic;
  int get maxParticipants => _maxParticipants;
  String? get initialPlaylistId => _initialPlaylistId;
  List<JamParticipant> get participants => _participants.values.toList();

  String? get qrDataUri => _pinCode != null && _hostIp != null
      ? JamQrData(
          host: _hostIp!,
          port: _port,
          code: _pinCode!.value,
          sessionId: _sessionId,
          // Si el dispositivo tiene más de una interfaz local, el escáner
          // intentará la segunda dirección si la primera no es alcanzable.
          remoteHost: _allLocalIps.length > 1
              ? _allLocalIps.firstWhere((address) => address != _hostIp)
              : null,
          remotePort: _allLocalIps.length > 1 ? _port : null,
        ).toUri()
      : null;

  /// Inicia el servidor Jam y el beacon de descubrimiento.
  Future<void> start({
    required String sessionId,
    required JamCode pinCode,
    required String hostName,
    JamMode mode = JamMode.partySpeaker,
    bool allowGuestControls = true,
    bool allowGuestQueueManage = true,
    bool isPublic = true,
    int maxParticipants = 0,
    String? initialPlaylistId,
  }) async {
    await stop();

    _sessionId = sessionId;
    _pinCode = pinCode;
    _hostName = hostName;
    _mode = mode;
    _allowGuestControls = allowGuestControls;
    _allowGuestQueueManage = allowGuestQueueManage;
    _isPublic = isPublic;
    _maxParticipants = maxParticipants < 0 ? 0 : maxParticipants;
    _initialPlaylistId = initialPlaylistId;

    // El puerto conocido evita que un código QR o una regla de firewall cambie
    // en cada sesión. Si está ocupado, la sesión sigue funcionando con uno
    // dinámico que se anuncia en el QR y el radar.
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, kJamHostPort);
    } on SocketException {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
    _port = _server!.port;
    _allLocalIps = await _getAllLocalIps();
    _hostIp = _allLocalIps.isNotEmpty ? _allLocalIps.first : '127.0.0.1';

    debugPrint(
        'JamHostService: Server listening on $_hostIp:$_port (code: ${_pinCode?.value}, mode: $_mode)');

    _server!.listen(_handleHttpRequest);

    // En Android, Wi‑Fi puede filtrar paquetes broadcast/multicast aunque el
    // socket esté abierto. Se mantiene el lock durante toda la sesión host.
    await JamNetworkPlatform.acquireMulticastReception();
    _holdsMulticastReception = true;

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

  void updateSettings({
    JamMode? mode,
    bool? allowGuestControls,
    bool? allowGuestQueueManage,
    bool? isPublic,
    int? maxParticipants,
    String? initialPlaylistId,
  }) {
    if (mode != null) _mode = mode;
    if (allowGuestControls != null) {
      _allowGuestControls = allowGuestControls;
    }
    if (allowGuestQueueManage != null) {
      _allowGuestQueueManage = allowGuestQueueManage;
    }
    if (isPublic != null) _isPublic = isPublic;
    if (maxParticipants != null) {
      _maxParticipants = maxParticipants < 0 ? 0 : maxParticipants;
    }
    if (initialPlaylistId != null) _initialPlaylistId = initialPlaylistId;

    for (final participant in _participants.values.toList()) {
      _participants[participant.id] = participant.copyWith(
        canControlPlayback: _allowGuestControls,
        canManageQueue: _allowGuestQueueManage,
      );
    }
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
      (data) async {
        try {
          final raw = data is String ? data : utf8.decode(data as List<int>);
          final msg = jsonDecode(raw) as Map<String, dynamic>;
          final op = msg['op'] as String?;

          switch (op) {
            case 'join_request':
              if (participantId != null) {
                _rejectJoin(socket, 'Esta conexión ya está unida a la sesión.');
                return;
              }

              final rawPin = msg['pin'] as String?;
              final pin =
                  rawPin?.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
              if (pin == null || pin != _pinCode?.value) {
                _rejectJoin(socket, 'PIN incorrecto.');
                return;
              }

              // El anfitrión cuenta dentro del límite configurado.
              if (_maxParticipants > 0 &&
                  _participants.length + 1 >= _maxParticipants) {
                _rejectJoin(
                  socket,
                  'La sesión alcanzó el límite de $_maxParticipants participantes.',
                );
                return;
              }

              final requestedName = (msg['name'] as String?)?.trim() ?? '';
              final name = requestedName.isEmpty
                  ? 'Invitado'
                  : requestedName.length > 48
                      ? requestedName.substring(0, 48)
                      : requestedName;
              final color =
                  (msg['avatarColorValue'] as num?)?.toInt() ?? 0xFF10B981;
              // No se acepta un ID aportado por el cliente: de ese modo un
              // invitado no puede suplantar al host ni a otro participante.
              final id =
                  'guest_${DateTime.now().microsecondsSinceEpoch}_${socket.hashCode}';

              final participant = JamParticipant(
                id: id,
                name: name.isNotEmpty ? name : 'Invitado',
                avatarColorValue: color,
                isHost: false,
                joinedAt: DateTime.now(),
                canControlPlayback: _allowGuestControls,
                canManageQueue: _allowGuestQueueManage,
              );

              participantId = id;
              _clientSockets[id] = socket;
              _participants[id] = participant;

              if (onJoinRequested != null) {
                final accepted = await onJoinRequested!(participant, socket);
                if (!accepted) {
                  _removeParticipant(id);
                  _rejectJoin(socket, 'El anfitrión rechazó la solicitud.');
                }
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
                    'allowGuestQueueManage': _allowGuestQueueManage,
                    'isPublic': _isPublic,
                    'initialPlaylistId': _initialPlaylistId,
                    'maxParticipants': _maxParticipants,
                  },
                }));
              }
              break;

            case 'add_to_queue':
              if (participantId != null &&
                  _participants.containsKey(participantId)) {
                final participant = _participants[participantId]!;
                if (!participant.canManageQueue) {
                  _sendError(socket,
                      'El anfitrión ha deshabilitado la gestión de cola.');
                  return;
                }
                final rawTrack = msg['track'];
                if (rawTrack is! Map<String, dynamic>) {
                  _sendError(socket, 'La canción recibida no es válida.');
                  return;
                }
                final trackJson = rawTrack;
                final trackId = trackJson['id'] as String?;
                if (trackId == null || trackId.isEmpty) {
                  _sendError(
                      socket, 'La canción no tiene un identificador válido.');
                  return;
                }
                final track = Track(
                  id: trackId,
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
              if (participantId != null &&
                  _participants.containsKey(participantId)) {
                final participant = _participants[participantId]!;
                if (!participant.canManageQueue) {
                  _sendError(socket,
                      'El anfitrión ha deshabilitado la gestión de cola.');
                  return;
                }
                final queueItemId = msg['queueItemId'] as String?;
                if (queueItemId != null) {
                  onTrackRemoveRequested?.call(queueItemId, participant);
                }
              }
              break;

            case 'reorder_queue':
              if (participantId != null &&
                  _participants.containsKey(participantId)) {
                final participant = _participants[participantId]!;
                if (!participant.canManageQueue) {
                  _sendError(socket,
                      'El anfitrión ha deshabilitado la gestión de cola.');
                  return;
                }
                final oldIdx = (msg['oldIndex'] as num?)?.toInt();
                final newIdx = (msg['newIndex'] as num?)?.toInt();
                if (oldIdx != null && newIdx != null) {
                  onQueueReorderRequested?.call(oldIdx, newIdx, participant);
                }
              }
              break;

            case 'playback_control':
              if (participantId != null &&
                  _participants.containsKey(participantId)) {
                final participant = _participants[participantId]!;
                if (!participant.canControlPlayback) {
                  _sendError(socket,
                      'El anfitrión ha deshabilitado el control de reproducción.');
                  return;
                }
                final action = msg['action'] as String?;
                final posMs = (msg['positionMs'] as num?)?.toInt();
                const validActions = {
                  'toggle',
                  'play',
                  'pause',
                  'skip_next',
                  'skip_previous',
                  'seek',
                };
                if (action != null && validActions.contains(action)) {
                  onPlaybackControlRequested?.call(action, posMs, participant);
                } else {
                  _sendError(socket, 'La acción de reproducción no es válida.');
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

  void _rejectJoin(WebSocket socket, String reason) {
    socket.add(jsonEncode({
      'op': 'join_response',
      'accepted': false,
      'reason': reason,
    }));
    unawaited(socket.close());
  }

  void _sendError(WebSocket socket, String message) {
    if (socket.readyState == WebSocket.open) {
      socket.add(jsonEncode({'op': 'error', 'message': message}));
    }
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
      'track': track == null
          ? null
          : {
              'id': track.id,
              'title': track.title,
              'artist': track.artist,
              'album': track.album,
              'duration': track.duration,
              'albumArtUrl': track.albumArtUrl,
            },
      'addedBy': addedBy?.toJson(),
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
        reusePort: !Platform.isWindows,
      );
      _discoverySocket!.broadcastEnabled = true;
      final multicastGroup = InternetAddress(kJamDiscoveryMulticastGroup);
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      if (interfaces.isEmpty) {
        _discoverySocket!.joinMulticast(multicastGroup);
      } else {
        for (final interface in interfaces) {
          try {
            _discoverySocket!.joinMulticast(multicastGroup, interface);
          } catch (e) {
            debugPrint(
              'JamHostService: No se pudo unir al multicast en ${interface.name}: $e',
            );
          }
        }
      }
      _discoverySocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = _discoverySocket?.receive();
          if (dg != null) {
            _handleDiscoveryDatagram(dg);
          }
        }
      });
      // Anuncio periódico: el invitado escucha durante el escaneo aunque su
      // propia consulta UDP no llegue al host (routers que filtran broadcast
      // en un sentido). Solo sesiones públicas para no filtrar el PIN.
      _presenceTimer?.cancel();
      _presenceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        unawaited(_broadcastPresence());
      });
      debugPrint(
          'JamHostService: Discovery beacon bound on port $kJamDiscoveryPort');
    } catch (e) {
      debugPrint('JamHostService: Discovery beacon failed to bind: $e');
    }
  }

  /// Payload de presencia con IP principal y respaldo (segunda interfaz).
  Map<String, dynamic> _presencePayload() {
    final hasFallback = _allLocalIps.length > 1;
    return {
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
      'isPublic': _isPublic,
      if (hasFallback)
        'remoteHost': _allLocalIps.firstWhere((address) => address != _hostIp),
      if (hasFallback) 'remotePort': _port,
    };
  }

  /// Envía presencia a loopback, broadcast global, multicast y broadcasts
  /// por subred para atravesar routers que filtran alguna de esas vías.
  Future<void> _broadcastPresence() async {
    if (_server == null || _pinCode == null || !_isPublic) return;
    final socket = _discoverySocket;
    if (socket == null) return;
    try {
      final bytes = utf8.encode(jsonEncode(_presencePayload()));
      try {
        socket.send(bytes, InternetAddress.loopbackIPv4, kJamDiscoveryPort);
      } catch (_) {}
      try {
        socket.send(
            bytes, InternetAddress('255.255.255.255'), kJamDiscoveryPort);
      } catch (_) {}
      try {
        socket.send(bytes, InternetAddress(kJamDiscoveryMulticastGroup),
            kJamDiscoveryPort);
      } catch (_) {}

      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            try {
              socket.send(
                  bytes,
                  InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'),
                  kJamDiscoveryPort);
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
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
        shouldReply = _isPublic;
      } else if (op == 'find_jam' && pin != null) {
        shouldReply = pin.toUpperCase() == _pinCode!.value;
      }

      if (shouldReply) {
        final reply = jsonEncode(_presencePayload());

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
      // NetworkInterface.list no garantiza orden. Wi‑Fi/Ethernet deben ir
      // antes que VPN, Docker o adaptadores virtuales, porque la primera IP se
      // codifica en el QR.
      interfaces.sort(
        (a, b) => _interfacePriority(a.name).compareTo(
          _interfacePriority(b.name),
        ),
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

  int _interfacePriority(String name) {
    final normalized = name.toLowerCase();
    if (normalized.contains('wlan') ||
        normalized.contains('wifi') ||
        normalized.startsWith('wl') ||
        normalized.startsWith('eth') ||
        normalized.startsWith('enp') ||
        normalized.startsWith('eno') ||
        normalized.startsWith('enx') ||
        normalized == 'en0') {
      return 0;
    }
    if (normalized.contains('docker') ||
        normalized.contains('vbox') ||
        normalized.contains('vmnet') ||
        normalized.contains('virbr') ||
        normalized.startsWith('br-') ||
        normalized.startsWith('tun') ||
        normalized.startsWith('tap') ||
        normalized.startsWith('ppp') ||
        normalized.contains('tailscale') ||
        normalized.contains('zerotier')) {
      return 2;
    }
    return 1;
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

    _presenceTimer?.cancel();
    _presenceTimer = null;

    if (_holdsMulticastReception) {
      await JamNetworkPlatform.releaseMulticastReception();
      _holdsMulticastReception = false;
    }

    await _server?.close(force: true);
    _server = null;

    _sessionId = null;
    _pinCode = null;
    _hostIp = null;
    _allLocalIps = [];
    _port = 0;
    _currentTrackTitle = null;
    _currentTrackArtist = null;
    _albumArtUrl = null;
    _allowGuestControls = true;
    _allowGuestQueueManage = true;
    _isPublic = true;
    _maxParticipants = 0;
    _initialPlaylistId = null;
    debugPrint('JamHostService stopped');
  }
}
