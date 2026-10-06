import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/jam_models.dart';
import 'jam_network_platform.dart';
import 'jam_tls_identity.dart';
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
typedef OnJamVoteRequested = void Function(
    String itemId, int value, JamParticipant participant);
typedef OnJamParticipantLeft = void Function(JamParticipant participant);

/// Limitador de tasa con ventana deslizante y memoria acotada.
class JamRateLimiter {
  final int maxEvents;
  final Duration window;
  final List<int> _timestampsMs = [];

  JamRateLimiter({required this.maxEvents, required this.window});

  List<int> get timestamps => List.unmodifiable(_timestampsMs);

  bool tryAcquire([int? nowMs]) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final windowMs = window.inMilliseconds;
    _timestampsMs.removeWhere((ts) => now - ts >= windowMs);
    if (_timestampsMs.length >= maxEvents) {
      return false;
    }
    _timestampsMs.add(now);
    return true;
  }

  void reset() {
    _timestampsMs.clear();
  }
}

class _ParticipantThrottles {
  final JamRateLimiter playbackLimiter;
  final JamRateLimiter queueLimiter;

  _ParticipantThrottles({
    JamRateLimiter? playback,
    JamRateLimiter? queue,
  })  : playbackLimiter = playback ??
            JamRateLimiter(maxEvents: 4, window: const Duration(seconds: 2)),
        queueLimiter = queue ??
            JamRateLimiter(maxEvents: 10, window: const Duration(seconds: 10));
}

/// Servidor de sesión Jam que corre en el dispositivo Anfitrión (Host).
///
/// Gestiona:
/// 1. Servidor WebSocket para comunicación bidireccional en tiempo real con invitados.
/// 2. Beacon UDP en puerto [kJamDiscoveryPort] (47623) para descubrimiento en red local (Radar).
/// 3. Registro de participantes, control de permisos y difusión de estado.
class JamHostService {
  HttpServer? _server;
  JamTlsIdentity? _tlsIdentity;
  RawDatagramSocket? _discoverySocket;
  Timer? _presenceTimer;
  bool _holdsMulticastReception = false;

  final Map<String, WebSocket> _clientSockets = {};
  final Map<String, JamParticipant> _participants = {};
  final Map<String, String> _participantTokens = {};
  final Map<String, DateTime> _lastInboundActivity = {};
  final Map<String, _ParticipantThrottles> _rateLimiters = {};
  final Map<String, Timer> _graceTimers = {};
  JamSessionState? _lastSessionState;
  JamParticipant? hostParticipant;
  Duration disconnectGracePeriod = const Duration(seconds: 30);
  JamSessionState Function()? getCurrentSessionState;

  /// Genera un token CSPRNG opaco de 128 bits (32 caracteres hexadecimales).
  static String generateReconnectToken([Random? random]) {
    final rnd = random ?? Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String? getTokenForParticipant(String participantId) =>
      _participantTokens[participantId];

  Map<String, dynamic> attachToken(
      String participantId, Map<String, dynamic> response) {
    final token = _participantTokens[participantId];
    if (token != null) {
      response['token'] = token;
    }
    return response;
  }

  Duration pingInterval = const Duration(seconds: 15);
  Duration pongTimeout = const Duration(seconds: 10);
  Timer? _heartbeatTimer;

  List<InternetAddress> _cachedBroadcastAddresses = [];
  final List<Timer> _discoveryBurstTimers = [];

  String? _sessionId;
  JamCode? _pinCode;
  String _hostName = '';
  String? _hostIp;
  List<String> _allLocalIps = [];
  int _port = 0;
  JamMode _mode = JamMode.synchronizedListening;
  final Set<String> _kickedNames = {};
  final Set<String> _kickedParticipantIds = {};
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
  OnJamVoteRequested? onVoteRequested;
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
  String? get tlsFingerprint => _tlsIdentity?.fingerprintSha256;
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
          tlsFingerprint: _tlsIdentity?.fingerprintSha256,
        ).toUri()
      : null;

  /// Inicia el servidor Jam y el beacon de descubrimiento.
  Future<void> start({
    required String sessionId,
    required JamCode pinCode,
    required String hostName,
    JamMode mode = JamMode.synchronizedListening,
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

    hostParticipant = JamParticipant(
      id: 'host_local',
      name: hostName,
      avatarColorValue: 0xFFA855F7,
      isHost: true,
      joinedAt: DateTime.now(),
      canControlPlayback: true,
      canManageQueue: true,
    );

    _tlsIdentity =
        JamTlsIdentity.generate(commonName: 'Scrotify Jam $sessionId');
    final securityContext = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(_tlsIdentity!.certificatePem)
      ..usePrivateKeyBytes(_tlsIdentity!.privateKeyPem);

    // El puerto conocido evita que un código QR o una regla de firewall cambie
    // en cada sesión. Si está ocupado, la sesión sigue funcionando con uno
    // dinámico que se anuncia en el QR y el radar.
    try {
      _server = await HttpServer.bindSecure(
        InternetAddress.anyIPv4,
        kJamHostPort,
        securityContext,
      );
    } on SocketException {
      _server = await HttpServer.bindSecure(
        InternetAddress.anyIPv4,
        0,
        securityContext,
      );
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

    // Iniciar monitoreo de heartbeat y pings periódicos
    _startHeartbeatTimer();
  }

  void updateTrackMetadata({
    String? title,
    String? artist,
    String? albumArtUrl,
  }) {
    _currentTrackTitle = title;
    _currentTrackArtist = artist;
    _albumArtUrl = sanitizeArtUrl(albumArtUrl);
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

          if (participantId != null) {
            _lastInboundActivity[participantId!] = DateTime.now();
          }

          if (participantId != null &&
              _clientSockets[participantId] != socket) {
            // Socket was superseded by a reconnect or replaced. Close and ignore.
            try {
              socket.close();
            } catch (_) {}
            return;
          }

          switch (op) {
            case 'ping':
              socket.add(jsonEncode({
                'op': 'pong',
                'timestamp':
                    msg['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
              }));
              break;

            case 'pong':
              // Inbound liveness ya actualizada
              break;

            case 'guest_ready':
              if (participantId != null) {
                _lastInboundActivity[participantId!] = DateTime.now();
              }
              break;

            case 'join_request':
              final rawPin = msg['pin'] as String?;
              final pin =
                  rawPin?.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
              if (pin == null || pin != _pinCode?.value) {
                _rejectJoin(socket, 'PIN incorrecto.');
                return;
              }

              final token = msg['token'] as String?;
              final reconnectParticipantId = msg['participantId'] as String?;

              // Ruta de reconexión de participante existente
              if (token != null || reconnectParticipantId != null) {
                final storedToken = reconnectParticipantId != null
                    ? _participantTokens[reconnectParticipantId]
                    : null;
                if (reconnectParticipantId != null &&
                    _participants.containsKey(reconnectParticipantId) &&
                    token != null &&
                    storedToken != null &&
                    token == storedToken) {
                  _graceTimers[reconnectParticipantId]?.cancel();
                  _graceTimers.remove(reconnectParticipantId);

                  final oldSocket = _clientSockets[reconnectParticipantId];
                  if (oldSocket != null && oldSocket != socket) {
                    try {
                      oldSocket.close();
                    } catch (_) {}
                  }
                  _clientSockets[reconnectParticipantId] = socket;
                  participantId = reconnectParticipantId;
                  _lastInboundActivity[reconnectParticipantId] = DateTime.now();

                  final existingParticipant =
                      _participants[reconnectParticipantId]!;
                  final currentSessionState =
                      getCurrentSessionState?.call() ?? _lastSessionState;
                  final stateMap = currentSessionState?.toJson() ??
                      _defaultSessionStateJson();
                  socket.add(jsonEncode({
                    'op': 'join_response',
                    'accepted': true,
                    'token': token,
                    'assignedParticipant': existingParticipant.toJson(),
                  }));
                  socket.add(jsonEncode({
                    'op': 'jam_state_snapshot',
                    'sessionId': _sessionId,
                    'state': stateMap,
                    'assignedParticipant': existingParticipant.toJson(),
                    'queueRevision': currentSessionState?.queueRevision ?? 0,
                  }));
                  return;
                } else {
                  _rejectJoin(socket,
                      'Token de reconexión inválido o sesión expirada.');
                  return;
                }
              }

              if (participantId != null) {
                _rejectJoin(socket, 'Esta conexión ya está unida a la sesión.');
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
              if (_kickedNames.contains(name.toLowerCase())) {
                _rejectJoin(socket, 'Has sido expulsado de esta sesión.');
                return;
              }
              final color =
                  (msg['avatarColorValue'] as num?)?.toInt() ?? 0xFF10B981;
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

              final assignedToken = generateReconnectToken();
              participantId = id;
              _clientSockets[id] = socket;
              _participants[id] = participant;
              _participantTokens[id] = assignedToken;
              _lastInboundActivity[id] = DateTime.now();

              if (onJoinRequested != null) {
                final accepted = await onJoinRequested!(participant, socket);
                if (!accepted) {
                  _removeParticipant(id);
                  _rejectJoin(socket, 'El anfitrión rechazó la solicitud.');
                } else {
                  final currentSessionState =
                      getCurrentSessionState?.call() ?? _lastSessionState;
                  final stateMap = currentSessionState?.toJson() ??
                      _defaultSessionStateJson();
                  socket.add(jsonEncode({
                    'op': 'join_response',
                    'accepted': true,
                    'token': assignedToken,
                    'assignedParticipant': participant.toJson(),
                  }));
                  socket.add(jsonEncode({
                    'op': 'jam_state_snapshot',
                    'sessionId': _sessionId,
                    'state': stateMap,
                    'assignedParticipant': participant.toJson(),
                    'queueRevision': currentSessionState?.queueRevision ?? 0,
                  }));
                }
              } else {
                final currentSessionState =
                    getCurrentSessionState?.call() ?? _lastSessionState;
                final stateMap =
                    currentSessionState?.toJson() ?? _defaultSessionStateJson();
                socket.add(jsonEncode({
                  'op': 'join_response',
                  'accepted': true,
                  'token': assignedToken,
                  'assignedParticipant': participant.toJson(),
                }));
                socket.add(jsonEncode({
                  'op': 'jam_state_snapshot',
                  'sessionId': _sessionId,
                  'state': stateMap,
                  'assignedParticipant': participant.toJson(),
                  'queueRevision': currentSessionState?.queueRevision ?? 0,
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
                final throttles = _rateLimiters.putIfAbsent(
                    participantId!, () => _ParticipantThrottles());
                if (!throttles.queueLimiter.tryAcquire()) {
                  _sendError(socket,
                      'Límite de tasa excedido: máximo 10 modificaciones a la cola cada 10 segundos.');
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
                final throttles = _rateLimiters.putIfAbsent(
                    participantId!, () => _ParticipantThrottles());
                if (!throttles.queueLimiter.tryAcquire()) {
                  _sendError(socket,
                      'Límite de tasa excedido: máximo 10 modificaciones a la cola cada 10 segundos.');
                  return;
                }
                final queueItemId = msg['queueItemId'] as String?;
                if (queueItemId != null && queueItemId.trim().isNotEmpty) {
                  onTrackRemoveRequested?.call(queueItemId, participant);
                } else {
                  _sendError(socket, 'Identificador de cola inválido.');
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
                final throttles = _rateLimiters.putIfAbsent(
                    participantId!, () => _ParticipantThrottles());
                if (!throttles.queueLimiter.tryAcquire()) {
                  _sendError(socket,
                      'Límite de tasa excedido: máximo 10 modificaciones a la cola cada 10 segundos.');
                  return;
                }
                final oldIdx = (msg['oldIndex'] as num?)?.toInt();
                final newIdx = (msg['newIndex'] as num?)?.toInt();
                if (oldIdx != null &&
                    newIdx != null &&
                    oldIdx >= 0 &&
                    newIdx >= 0) {
                  onQueueReorderRequested?.call(oldIdx, newIdx, participant);
                } else {
                  _sendError(socket, 'Índices de reordenamiento inválidos.');
                }
              }
              break;

            case 'vote':
              // Votar no requiere gestión de cola; sí pasa por el limitador.
              if (participantId != null &&
                  _participants.containsKey(participantId)) {
                final participant = _participants[participantId]!;
                final throttles = _rateLimiters.putIfAbsent(
                    participantId!, () => _ParticipantThrottles());
                if (!throttles.queueLimiter.tryAcquire()) {
                  _sendError(socket,
                      'Límite de tasa excedido: máximo 10 modificaciones a la cola cada 10 segundos.');
                  return;
                }
                final itemId = msg['itemId'];
                final value = msg['value'];
                if (itemId is String && itemId.isNotEmpty && value is num) {
                  onVoteRequested?.call(
                      itemId, value.toInt().clamp(-1, 1), participant);
                } else {
                  _sendError(socket, 'Voto inválido.');
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
                final throttles = _rateLimiters.putIfAbsent(
                    participantId!, () => _ParticipantThrottles());
                if (!throttles.playbackLimiter.tryAcquire()) {
                  _sendError(socket,
                      'Límite de tasa excedido: máximo 4 controles de reproducción cada 2 segundos.');
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
                  if (action == 'seek' && (posMs == null || posMs < 0)) {
                    _sendError(socket, 'Posición de reproducción inválida.');
                    return;
                  }
                  onPlaybackControlRequested?.call(action, posMs, participant);
                } else {
                  _sendError(socket, 'La acción de reproducción no es válida.');
                }
              }
              break;

            case 'leave':
              _graceTimers[participantId]?.cancel();
              _graceTimers.remove(participantId);
              _removeParticipant(participantId);
              break;
          }
        } catch (e) {
          debugPrint('JamHostService WebSocket error parsing msg: $e');
        }
      },
      onDone: () => _handleSocketDisconnect(participantId, socket),
      onError: (_) => _handleSocketDisconnect(participantId, socket),
    );
  }

  void _handleSocketDisconnect(String? id, WebSocket socket) {
    if (id == null) return;
    if (_clientSockets[id] == socket) {
      _clientSockets.remove(id);
      if (_participants.containsKey(id) && !_graceTimers.containsKey(id)) {
        _graceTimers[id] = Timer(disconnectGracePeriod, () {
          _graceTimers.remove(id);
          _removeParticipant(id);
        });
      }
    }
  }

  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(pingInterval, (_) {
      checkHeartbeatAndPing();
    });
  }

  void checkHeartbeatAndPing([DateTime? nowTime]) {
    final now = nowTime ?? DateTime.now();
    final timeoutThreshold = pingInterval + pongTimeout;

    for (final id in _participants.keys.toList()) {
      final lastSeen = _lastInboundActivity[id] ?? now;
      if (now.difference(lastSeen) > timeoutThreshold) {
        debugPrint(
            'JamHostService: Desalojando participante $id por inactividad de heartbeat');
        _removeParticipant(id);
      }
    }

    final pingMsg = jsonEncode({
      'op': 'ping',
      'timestamp': now.millisecondsSinceEpoch,
    });
    for (final socket in _clientSockets.values) {
      try {
        if (socket.readyState == WebSocket.open) {
          socket.add(pingMsg);
        }
      } catch (_) {}
    }
  }

  Map<String, dynamic> _defaultSessionStateJson() => {
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
        'participants': [
          if (hostParticipant != null) hostParticipant!.toJson(),
          ..._participants.values.map((e) => e.toJson()),
        ],
        'allowGuestControls': _allowGuestControls,
        'allowGuestQueueManage': _allowGuestQueueManage,
        'isPublic': _isPublic,
        'initialPlaylistId': _initialPlaylistId,
        'maxParticipants': _maxParticipants,
        'queueRevision': _lastSessionState?.queueRevision ?? 0,
      };

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
    _graceTimers[id]?.cancel();
    _graceTimers.remove(id);
    _lastInboundActivity.remove(id);
    _participantTokens.remove(id);
    _rateLimiters.remove(id);
    final participant = _participants.remove(id);
    final socket = _clientSockets.remove(id);
    try {
      socket?.close();
    } catch (_) {}
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

  void broadcastSessionState(
    JamSessionState state, {
    String? excludeParticipantId,
  }) {
    _lastSessionState = state;
    final encoded = jsonEncode({
      'op': 'state_sync',
      'state': state.toJson(),
    });
    for (final entry in _clientSockets.entries) {
      if (entry.key == excludeParticipantId) continue;
      try {
        if (entry.value.readyState == WebSocket.open) {
          entry.value.add(encoded);
        }
      } catch (_) {}
    }
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
              'albumArtUrl': sanitizeArtUrl(track.albumArtUrl),
            },
      'addedBy': addedBy?.toJson(),
      'isPlaying': isPlaying,
      'positionMs': positionMs,
      'serverTimestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void broadcastQueueUpdate(List<JamQueueItem> queue, {int? queueRevision}) {
    final rev = queueRevision ?? _lastSessionState?.queueRevision ?? 0;
    broadcastMessage({
      'op': 'queue_updated',
      'queue': queue.map((e) => e.toJson()).toList(),
      'queueRevision': rev,
    });
  }

  void sendToClient(String participantId, Map<String, dynamic> message) {
    if (message['op'] == 'join_response' && !message.containsKey('token')) {
      final token = _participantTokens[participantId];
      if (token != null) {
        message['token'] = token;
      }
    }
    final socket = _clientSockets[participantId];
    if (socket != null && socket.readyState == WebSocket.open) {
      socket.add(jsonEncode(message));
    }
  }

  void kickParticipant(String participantId) {
    _graceTimers[participantId]?.cancel();
    _graceTimers.remove(participantId);
    final p = _participants[participantId];
    if (p != null) {
      _kickedNames.add(p.name.trim().toLowerCase());
    }
    _kickedParticipantIds.add(participantId);
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

      // Cachear direcciones de difusión para no llamar NetworkInterface.list en cada ciclo
      await _updateCachedBroadcastAddresses();

      // Ráfaga inmediata de tres pulsos al inicio
      _broadcastPresence();
      _discoveryBurstTimers.add(Timer(const Duration(milliseconds: 250), () {
        _broadcastPresence();
      }));
      _discoveryBurstTimers.add(Timer(const Duration(milliseconds: 500), () {
        _broadcastPresence();
      }));

      // Anuncio periódico a ritmo constante de 8 segundos sin NetworkInterface.list
      _presenceTimer?.cancel();
      _presenceTimer = Timer.periodic(const Duration(seconds: 8), (_) {
        _broadcastPresence();
      });
      debugPrint(
          'JamHostService: Discovery beacon bound on port $kJamDiscoveryPort');
    } catch (e) {
      debugPrint('JamHostService: Discovery beacon failed to bind: $e');
    }
  }

  Future<void> _updateCachedBroadcastAddresses() async {
    final targets = <InternetAddress>[
      InternetAddress.loopbackIPv4,
      InternetAddress('255.255.255.255'),
      InternetAddress(kJamDiscoveryMulticastGroup),
    ];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            try {
              targets.add(
                InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'),
              );
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    _cachedBroadcastAddresses = targets;
  }

  /// Payload de presencia con IP principal y respaldo (segunda interfaz).
  Map<String, dynamic> _presencePayload() {
    final hasFallback = _allLocalIps.length > 1;
    return {
      'tag': kJamDiscoveryAppTag,
      'op': 'jam_presence',
      'host': _hostIp,
      'port': _port,
      'transport': 'wss',
      'tlsFingerprint': _tlsIdentity?.fingerprintSha256,
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

  /// Envía presencia a las direcciones de destino cacheadas (loopback, broadcast, multicast, subred).
  void _broadcastPresence() {
    if (_server == null ||
        _pinCode == null ||
        _tlsIdentity == null ||
        !_isPublic) {
      return;
    }
    final socket = _discoverySocket;
    if (socket == null) return;
    try {
      final bytes = utf8.encode(jsonEncode(_presencePayload()));
      for (final target in _cachedBroadcastAddresses) {
        try {
          socket.send(bytes, target, kJamDiscoveryPort);
        } catch (_) {}
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

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    for (final timer in _graceTimers.values) {
      timer.cancel();
    }
    _graceTimers.clear();
    _kickedNames.clear();
    _kickedParticipantIds.clear();
    hostParticipant = null;
    _lastInboundActivity.clear();
    _participantTokens.clear();
    _rateLimiters.clear();
    _lastSessionState = null;

    for (final socket in List.of(_clientSockets.values)) {
      try {
        await socket.close();
      } catch (_) {}
    }
    _clientSockets.clear();
    _participants.clear();

    _discoverySocket?.close();
    _discoverySocket = null;

    for (final timer in _discoveryBurstTimers) {
      timer.cancel();
    }
    _discoveryBurstTimers.clear();
    _cachedBroadcastAddresses.clear();

    _presenceTimer?.cancel();
    _presenceTimer = null;

    if (_holdsMulticastReception) {
      await JamNetworkPlatform.releaseMulticastReception();
      _holdsMulticastReception = false;
    }

    await _server?.close(force: true);
    _server = null;
    _tlsIdentity = null;

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
