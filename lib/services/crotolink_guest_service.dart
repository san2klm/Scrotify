import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/crotolink_models.dart';
import 'crotolink_network_platform.dart';
import 'crotolink_clock.dart';
import 'crotolink_tls_identity.dart';
import 'navidrome_service.dart';

typedef OnGuestStateSync = void Function(CrotoLinkSessionState state);
typedef OnGuestPlaybackUpdated = void Function(
    Track? track,
    CrotoLinkParticipant? addedBy,
    bool isPlaying,
    int positionMs,
    int serverTimestamp);
typedef OnGuestQueueUpdated = void Function(List<CrotoLinkQueueItem> queue);
typedef OnGuestKicked = void Function(String reason);
typedef OnGuestSessionClosed = void Function(String reason);
typedef OnGuestError = void Function(String message);
typedef OnGuestNextTrackHint = void Function(Track track, int startAtServerMs);

/// Servicio de cliente CrotoLink para unirse a sesiones como Invitado (Guest).
///
/// Gestiona:
/// 1. Descubrimiento de sesiones activas en la LAN vía UDP (Radar de CrotoLink).
/// 2. Búsqueda directa por PIN de 6 caracteres.
/// 3. Conexión WebSocket al Host, sincronización de estado y despacho de acciones colaborativas.
class CrotoLinkGuestService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  CrotoLinkSessionState? _sessionState;
  CrotoLinkParticipant? _localParticipant;
  int _queueRevision = 0;
  bool _isConnected = false;
  CrotoLinkConnectionState _connectionState =
      CrotoLinkConnectionState.disconnected;

  String? _savedHost;
  int? _savedPort;
  String? _savedPin;
  String? _savedName;
  int? _savedAvatarColorValue;
  String? _savedParticipantId;
  String? _savedReconnectToken;
  String? _savedTlsFingerprint;

  bool _isExplicitDisconnect = false;
  bool _isReconnecting = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _silenceTimer;
  DateTime _lastHostActivity = DateTime.now();

  Duration hostSilenceTimeout = const Duration(seconds: 30);
  Duration silenceCheckInterval = const Duration(seconds: 5);

  OnGuestStateSync? onStateSync;
  OnGuestPlaybackUpdated? onPlaybackUpdated;
  OnGuestQueueUpdated? onQueueUpdated;
  OnGuestKicked? onKicked;
  OnGuestSessionClosed? onSessionClosed;
  OnGuestError? onError;
  OnGuestNextTrackHint? onNextTrackHint;
  void Function(String from, String emoji)? onReaction;
  void Function(String from, String text, int ts)? onChat;

  /// Offset local→host (la hora de referencia en LAN es la del host).
  final ClockOffsetEstimator clock = ClockOffsetEstimator();
  Timer? _clockTimer;

  void _startClockSync() {
    _clockTimer?.cancel();
    clock.clear();
    for (var i = 0; i < kCrotoLinkClockSamples; i++) {
      Future.delayed(Duration(milliseconds: 150 * i), () {
        if (_isConnected) {
          _send({
            'op': 'time_ping',
            'clientTs': crotoLinkMonotonicMs(),
          });
        }
      });
    }
    _clockTimer = Timer.periodic(kCrotoLinkClockResync, (_) {
      if (_isConnected) {
        _send({
          'op': 'time_ping',
          'clientTs': crotoLinkMonotonicMs(),
        });
      }
    });
  }

  void Function(CrotoLinkConnectionState state)? onConnectionStateChanged;

  bool get isConnected => _isConnected;
  CrotoLinkConnectionState get connectionState => _connectionState;
  CrotoLinkSessionState? get sessionState => _sessionState;
  CrotoLinkParticipant? get localParticipant => _localParticipant;
  int get queueRevision => _queueRevision;

  void _updateConnectionState(CrotoLinkConnectionState newState) {
    if (_connectionState != newState) {
      _connectionState = newState;
      onConnectionStateChanged?.call(_connectionState);
    }
  }

  /// Último motivo de fallo de [connect], en lenguaje legible para mostrar en UI.
  String? lastError;

  /// Código tipado del último rechazo del anfitrión (ver `_rejectJoin`).
  String? lastRejectCode;

  /// Desde cuándo se intenta reconectar; pasado [reconnectGiveUp] se renuncia.
  DateTime? _reconnectStartedAt;
  Duration reconnectGiveUp = const Duration(minutes: 5);

  /// Rechazos que no se arreglan reintentando.
  static const _terminalRejectCodes = {
    'bad_pin',
    'bad_password',
    'expired',
    'kicked',
    'full',
    'already_joined',
  };

  // ---------------------------------------------------------------------------
  // Descubrimiento UDP en Red Local (Radar)
  // ---------------------------------------------------------------------------

  /// Escanea la red local mediante broadcasts UDP en el puerto [kCrotoLinkDiscoveryPort] (47623).
  Future<List<DiscoveredCrotoLinkSession>> scanRadar({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final discovered = <String, DiscoveredCrotoLinkSession>{};
    final completer = Completer<List<DiscoveredCrotoLinkSession>>();
    RawDatagramSocket? socket;
    Timer? timeoutTimer;
    final retryTimers = <Timer>[];
    var holdsMulticastReception = false;

    try {
      await CrotoLinkNetworkPlatform.acquireMulticastReception();
      holdsMulticastReception = true;
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket?.receive();
          if (dg == null) return;
          try {
            final text = utf8.decode(dg.data);
            final json = jsonDecode(text) as Map<String, dynamic>;
            if (json['tag'] == kCrotoLinkDiscoveryAppTag &&
                json['op'] == 'crotolink_presence') {
              final session = DiscoveredCrotoLinkSession.fromJson(
                json,
                dg.address.address,
                preferFallbackHost: true,
              );
              if (session.port > 0) {
                final key = '${session.host}:${session.port}:${session.pin}';
                discovered[key] = session;
                debugPrint(
                  'CrotoLink radar: respuesta de ${dg.address.address} para ${session.host}:${session.port}',
                );
              }
            }
          } catch (_) {}
        }
      });

      final queryPayload = jsonEncode({
        'tag': kCrotoLinkDiscoveryAppTag,
        'op': 'discover_crotolink',
      });
      final bytes = utf8.encode(queryPayload);

      Future<void> sendBroadcasts() async {
        try {
          try {
            socket?.send(
                bytes, InternetAddress.loopbackIPv4, kCrotoLinkDiscoveryPort);
          } catch (_) {}
          try {
            socket?.send(bytes, InternetAddress('255.255.255.255'),
                kCrotoLinkDiscoveryPort);
          } catch (_) {}
          try {
            socket?.send(
              bytes,
              InternetAddress(kCrotoLinkDiscoveryMulticastGroup),
              kCrotoLinkDiscoveryPort,
            );
          } catch (_) {}

          final interfaces = await NetworkInterface.list(
            type: InternetAddressType.IPv4,
            includeLoopback: false,
          );
          for (final iface in interfaces) {
            for (final addr in iface.addresses) {
              final parts = addr.address.split('.');
              if (parts.length == 4) {
                final subnetBcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
                try {
                  socket?.send(bytes, InternetAddress(subnetBcast),
                      kCrotoLinkDiscoveryPort);
                } catch (_) {}
              }
            }
          }
        } catch (_) {}
      }

      unawaited(sendBroadcasts());
      retryTimers.add(Timer(const Duration(milliseconds: 500), () {
        unawaited(sendBroadcasts());
      }));
      retryTimers.add(Timer(const Duration(milliseconds: 1200), () {
        unawaited(sendBroadcasts());
      }));

      timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.complete(discovered.values.toList());
        }
      });

      final result = await completer.future;
      return result;
    } catch (e) {
      debugPrint('CrotoLinkGuestService.scanRadar error: $e');
      return discovered.values.toList();
    } finally {
      timeoutTimer?.cancel();
      for (final timer in retryTimers) {
        timer.cancel();
      }
      socket?.close();
      if (holdsMulticastReception) {
        await CrotoLinkNetworkPlatform.releaseMulticastReception();
      }
    }
  }

  /// Busca una sesión CrotoLink activa específica por su PIN de 6 caracteres.
  Future<DiscoveredCrotoLinkSession?> findByPin(
    String pin, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final cleanPin = pin.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final completer = Completer<DiscoveredCrotoLinkSession?>();
    RawDatagramSocket? socket;
    Timer? timeoutTimer;
    final retryTimers = <Timer>[];
    var holdsMulticastReception = false;

    try {
      await CrotoLinkNetworkPlatform.acquireMulticastReception();
      holdsMulticastReception = true;
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket?.receive();
          if (dg == null) return;
          try {
            final text = utf8.decode(dg.data);
            final json = jsonDecode(text) as Map<String, dynamic>;
            if (json['tag'] == kCrotoLinkDiscoveryAppTag &&
                json['op'] == 'crotolink_presence' &&
                (json['pin'] as String?)?.toUpperCase() == cleanPin) {
              final session = DiscoveredCrotoLinkSession.fromJson(
                json,
                dg.address.address,
                preferFallbackHost: true,
              );
              if (!completer.isCompleted) {
                completer.complete(session);
              }
            }
          } catch (_) {}
        }
      });

      final queryPayload = jsonEncode({
        'tag': kCrotoLinkDiscoveryAppTag,
        'op': 'find_crotolink',
        'pin': cleanPin,
      });
      final bytes = utf8.encode(queryPayload);

      Future<void> sendBroadcasts() async {
        try {
          try {
            socket?.send(
                bytes, InternetAddress.loopbackIPv4, kCrotoLinkDiscoveryPort);
          } catch (_) {}
          try {
            socket?.send(bytes, InternetAddress('255.255.255.255'),
                kCrotoLinkDiscoveryPort);
          } catch (_) {}
          try {
            socket?.send(
              bytes,
              InternetAddress(kCrotoLinkDiscoveryMulticastGroup),
              kCrotoLinkDiscoveryPort,
            );
          } catch (_) {}

          final interfaces = await NetworkInterface.list(
            type: InternetAddressType.IPv4,
            includeLoopback: false,
          );
          for (final iface in interfaces) {
            for (final addr in iface.addresses) {
              final parts = addr.address.split('.');
              if (parts.length == 4) {
                final subnetBcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
                try {
                  socket?.send(bytes, InternetAddress(subnetBcast),
                      kCrotoLinkDiscoveryPort);
                } catch (_) {}
              }
            }
          }
        } catch (_) {}
      }

      unawaited(sendBroadcasts());
      retryTimers.add(Timer(const Duration(milliseconds: 400), () {
        unawaited(sendBroadcasts());
      }));

      timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      });

      return await completer.future;
    } catch (e) {
      debugPrint('CrotoLinkGuestService.findByPin error: $e');
      return null;
    } finally {
      timeoutTimer?.cancel();
      for (final timer in retryTimers) {
        timer.cancel();
      }
      socket?.close();
      if (holdsMulticastReception) {
        await CrotoLinkNetworkPlatform.releaseMulticastReception();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Diagnóstico HTTP previo al WebSocket
  // ---------------------------------------------------------------------------

  /// Direct HTTP probing was intentionally removed: a manually entered host
  /// has no certificate pin and therefore cannot be authenticated safely.
  Future<String> testHostReachable(String host, int port) async =>
      'CrotoLink LAN segura requiere escanear el QR del anfitrión; el sondeo HTTP inseguro está deshabilitado.';

  String _describeSocketException(SocketException e, String host, int port) {
    final os = e.osError;
    final code = os?.errorCode;
    // 111 = connection refused (el host existe pero nada escucha / CrotoLink cerrado).
    // 113 = no route to host, 101 = network unreachable.
    if (code == 111) {
      return 'Conexión rechazada por $host:$port. El equipo existe pero el CrotoLink no está iniciado ahí (o cambió el puerto).';
    }
    if (code == 113 || code == 101 || code == 110) {
      return 'No hay ruta a $host:$port. Estás en otra red/VPN o el router aísla Wi-Fi de cable.';
    }
    final msg = e.message.isNotEmpty ? e.message : os?.message ?? e.toString();
    return 'Error de red a $host:$port: $msg';
  }

  // ---------------------------------------------------------------------------
  // Conexión y Gestión de Sesión WebSocket
  // ---------------------------------------------------------------------------

  /// Contraseña de sala a enviar al unirse (nunca se persiste ni se loguea).
  String? roomPassword;

  /// Cuánto se espera, al unirse, a la aceptación del anfitrión y a su primer
  /// estado de la sala. Ajustable solo para pruebas.
  @visibleForTesting
  Duration joinStateTimeout = const Duration(seconds: 5);

  Future<bool> connect({
    required String host,
    required int port,
    required String pin,
    required String name,
    required int avatarColorValue,
    required String tlsFingerprint,
    String? participantId,
  }) async {
    _isExplicitDisconnect = false;
    _reconnectAttempts = 0;
    _reconnectStartedAt = null;
    _isReconnecting = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    final ok = await _connectInternal(
      host: host,
      port: port,
      pin: pin,
      name: name,
      avatarColorValue: avatarColorValue,
      participantId: participantId,
      token: null,
      tlsFingerprint: tlsFingerprint,
      isReconnect: false,
    );

    if (ok) {
      _updateConnectionState(CrotoLinkConnectionState.connected);
    } else {
      _updateConnectionState(CrotoLinkConnectionState.failed);
    }
    return ok;
  }

  Future<bool> _connectInternal({
    required String host,
    required int port,
    required String pin,
    required String name,
    required int avatarColorValue,
    String? participantId,
    String? token,
    required String tlsFingerprint,
    required bool isReconnect,
  }) async {
    if (!isReconnect) {
      await disconnect();
      _isExplicitDisconnect = false;
    } else {
      await _subscription?.cancel();
      _subscription = null;
      await _channel?.sink.close();
      _channel = null;
      _isConnected = false;
    }
    lastError = null;
    lastRejectCode = null;

    if (host.trim().isEmpty || port <= 0 || port > 65535) {
      lastError = 'IP o puerto inválido.';
      return false;
    }
    if (!CrotoLinkTlsIdentity.isValidFingerprint(tlsFingerprint)) {
      lastError =
          'El CrotoLink no anunció un fingerprint TLS válido; se rechaza la conexión insegura.';
      return false;
    }

    final completer = Completer<bool>();
    // El anfitrión aceptó la unión (aún puede faltar su primer estado).
    var joinAccepted = false;
    final uri = Uri(
        scheme: 'wss', host: host.trim(), port: port, path: '/crotolink/ws');

    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5)
        ..badCertificateCallback = (certificate, _, __) =>
            CrotoLinkTlsIdentity.fingerprintForDer(certificate.der) ==
            tlsFingerprint;
      final ws = await WebSocket.connect(uri.toString(),
              customClient: client,
              compression: CompressionOptions.compressionOff)
          .timeout(const Duration(seconds: 5));
      _channel = IOWebSocketChannel(ws);
      _lastHostActivity = DateTime.now();
      lastError = null;

      _subscription = _channel!.stream.listen(
        (data) {
          try {
            _lastHostActivity = DateTime.now();
            final raw = data is String ? data : utf8.decode(data as List<int>);
            final msg = jsonDecode(raw) as Map<String, dynamic>;
            final op = msg['op'] as String?;

            switch (op) {
              case 'ping':
                _send({
                  'op': 'pong',
                  'timestamp':
                      msg['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
                });
                break;

              case 'pong':
                break;

              case 'time_pong':
                final sent = (msg['clientTs'] as num?)?.toInt();
                final server = (msg['serverNowMs'] as num?)?.toInt();
                if (sent != null && server != null) {
                  clock.add(CrotoLinkClockSample.fromExchange(
                    sentAt: sent,
                    receivedAt: crotoLinkMonotonicMs(),
                    receivedWallMs: DateTime.now().millisecondsSinceEpoch,
                    serverNow: server,
                  ));
                }
                break;

              case 'reaction':
                onReaction?.call(msg['from']?.toString() ?? '',
                    msg['emoji']?.toString() ?? '');
                break;

              case 'chat':
                onChat?.call(
                  msg['from']?.toString() ?? '',
                  msg['text']?.toString() ?? '',
                  (msg['ts'] as num?)?.toInt() ??
                      DateTime.now().millisecondsSinceEpoch,
                );
                break;

              case 'next_track_hint':
                final rawTrack = msg['track'];
                final startAt = (msg['startAtServerMs'] as num?)?.toInt();
                if (rawTrack is Map && startAt != null) {
                  try {
                    onNextTrackHint?.call(
                      Track.fromJson(Map<String, dynamic>.from(rawTrack)),
                      startAt,
                    );
                  } catch (e) {
                    debugPrint(
                        'CrotoLinkGuestService: aviso de pista siguiente ilegible: $e');
                  }
                }
                break;

              case 'join_response':
                final accepted = msg['accepted'] as bool? ?? false;
                if (accepted) {
                  joinAccepted = true;
                  lastRejectCode = null;
                  // Una respuesta tardía no debe dejar un reintento en marcha.
                  _reconnectTimer?.cancel();
                  final receivedToken = msg['token'] as String?;
                  if (receivedToken != null) {
                    _savedReconnectToken = receivedToken;
                  }
                  _savedHost = host;
                  _savedPort = port;
                  _savedPin = pin;
                  _savedName = name;
                  _savedAvatarColorValue = avatarColorValue;
                  _savedTlsFingerprint = tlsFingerprint;

                  CrotoLinkParticipant? assigned;
                  if (msg['assignedParticipant'] != null) {
                    assigned = CrotoLinkParticipant.fromJson(
                        msg['assignedParticipant'] as Map<String, dynamic>);
                    _localParticipant = assigned;
                    _savedParticipantId = assigned.id;
                  } else {
                    _savedParticipantId =
                        _localParticipant?.id ?? participantId;
                  }

                  if (msg['state'] != null) {
                    final snapshot = CrotoLinkSessionState.fromJson(
                        msg['state'] as Map<String, dynamic>);
                    debugPrint(
                      '[CROTOLINK] CrotoLinkGuestService parsed crotolink_state_snapshot: '
                      'rev=${snapshot.queueRevision} qLen=${snapshot.queue.length} '
                      'trackId=${snapshot.currentTrack?.id}',
                    );
                    _applyAuthoritativeSnapshot(snapshot,
                        assignedParticipant: assigned);
                    _send({'op': 'guest_ready'});
                  }

                  _isConnected = true;
                  _reconnectAttempts = 0;
                  _reconnectStartedAt = null;
                  _updateConnectionState(CrotoLinkConnectionState.connected);
                  _startSilenceDetection();
                  _startClockSync();

                  // La unión no está completa hasta tener el primer estado:
                  // si la aceptación no lo trae, llega en el mensaje siguiente
                  // (`crotolink_state_snapshot`) y es ese el que completa.
                  if (msg['state'] != null && !completer.isCompleted) {
                    completer.complete(true);
                  }
                  if (_sessionState != null) {
                    onStateSync?.call(_sessionState!);
                  }
                } else {
                  final reason = msg['reason'] as String? ??
                      'El anfitrión rechazó la conexión.';
                  lastError = reason;
                  lastRejectCode = msg['code'] as String?;
                  onError?.call(reason);
                  if (!completer.isCompleted) {
                    completer.complete(false);
                  }
                  if (isReconnect) {
                    _updateConnectionState(CrotoLinkConnectionState.failed);
                    _teardownSocket();
                  } else {
                    unawaited(disconnect());
                  }
                }
                break;

              case 'crotolink_state_snapshot':
                final stateJson = msg['state'] as Map<String, dynamic>?;
                if (stateJson != null) {
                  final snapshot = CrotoLinkSessionState.fromJson(stateJson);
                  debugPrint(
                    '[CROTOLINK] CrotoLinkGuestService parsed crotolink_state_snapshot: '
                    'rev=${snapshot.queueRevision} qLen=${snapshot.queue.length} '
                    'trackId=${snapshot.currentTrack?.id}',
                  );
                  CrotoLinkParticipant? assigned;
                  if (msg['assignedParticipant'] != null) {
                    assigned = CrotoLinkParticipant.fromJson(
                        msg['assignedParticipant'] as Map<String, dynamic>);
                  }
                  _applyAuthoritativeSnapshot(snapshot,
                      assignedParticipant: assigned);
                  _send({'op': 'guest_ready'});

                  _isConnected = true;
                  _reconnectAttempts = 0;
                  _reconnectStartedAt = null;
                  _updateConnectionState(CrotoLinkConnectionState.connected);
                  _startSilenceDetection();
                  _startClockSync();

                  if (!completer.isCompleted) {
                    completer.complete(true);
                  }
                  onStateSync?.call(_sessionState!);
                }
                break;

              case 'state_sync':
                if (msg['state'] != null) {
                  final incoming = CrotoLinkSessionState.fromJson(
                      msg['state'] as Map<String, dynamic>);
                  debugPrint(
                    '[CROTOLINK] CrotoLinkGuestService parsed state_sync: '
                    'rev=${incoming.queueRevision} qLen=${incoming.queue.length} '
                    'trackId=${incoming.currentTrack?.id}',
                  );
                  if (_sessionState != null &&
                      incoming.queueRevision < _queueRevision) {
                    _sessionState = incoming.copyWith(
                      queue: _sessionState!.queue,
                      queueRevision: _queueRevision,
                    );
                  } else {
                    _queueRevision = incoming.queueRevision;
                    _sessionState = incoming;
                  }
                  if (_localParticipant != null) {
                    final fromList = _sessionState!.participants
                        .where((p) => p.id == _localParticipant!.id)
                        .firstOrNull;
                    if (fromList != null) {
                      _localParticipant = fromList;
                    } else {
                      _localParticipant = _localParticipant!.copyWith(
                        canControlPlayback: _sessionState!.allowGuestControls,
                        canManageQueue: _sessionState!.allowGuestQueueManage,
                      );
                    }
                  }
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
                CrotoLinkParticipant? addedBy;
                if (msg['addedBy'] != null) {
                  addedBy = CrotoLinkParticipant.fromJson(
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
                    clearCurrentTrack:
                        msg.containsKey('track') && track == null,
                    clearCurrentTrackAddedBy:
                        msg.containsKey('addedBy') && addedBy == null,
                    isPlaying: isPlaying,
                    positionMs: posMs,
                    updatedAtMs: serverTs,
                  );
                }

                debugPrint(
                  '[CROTOLINK] CrotoLinkGuestService parsed playback_updated: '
                  'rev=${_sessionState?.queueRevision ?? _queueRevision} '
                  'qLen=${_sessionState?.queue.length ?? 0} '
                  'trackId=${track?.id}',
                );

                onPlaybackUpdated?.call(
                    track, addedBy, isPlaying, posMs, serverTs);
                break;

              case 'queue_updated':
                if (msg['queue'] != null) {
                  final incomingRev =
                      (msg['queueRevision'] as num?)?.toInt() ?? _queueRevision;
                  if (incomingRev >= _queueRevision) {
                    _queueRevision = incomingRev;
                    final qList = (msg['queue'] as List<dynamic>)
                        .map((e) => CrotoLinkQueueItem.fromJson(
                            e as Map<String, dynamic>))
                        .toList();
                    debugPrint(
                      '[CROTOLINK] CrotoLinkGuestService parsed queue_updated: '
                      'rev=$incomingRev '
                      'qLen=${qList.length} '
                      'trackId=${_sessionState?.currentTrack?.id}',
                    );
                    if (_sessionState != null) {
                      _sessionState = _sessionState!.copyWith(
                        queue: qList,
                        queueRevision: incomingRev,
                      );
                    }
                    onQueueUpdated?.call(qList);
                  }
                }
                break;

              case 'participant_left':
                final participantJson = msg['participant'];
                if (_sessionState != null &&
                    participantJson is Map<String, dynamic>) {
                  final participant =
                      CrotoLinkParticipant.fromJson(participantJson);
                  _sessionState = _sessionState!.copyWith(
                    participants: _sessionState!.participants
                        .where((p) => p.id != participant.id)
                        .toList(),
                  );
                  onStateSync?.call(_sessionState!);
                }
                break;

              case 'kicked':
                final reason = msg['reason'] as String? ?? 'Desconectado.';
                _isExplicitDisconnect = true;
                _savedParticipantId = null;
                _savedReconnectToken = null;
                _updateConnectionState(CrotoLinkConnectionState.disconnected);
                onKicked?.call(reason);
                unawaited(disconnect());
                break;

              case 'session_closed':
                final reason = msg['reason'] as String? ?? 'Sesión finalizada.';
                _isExplicitDisconnect = true;
                _savedParticipantId = null;
                _savedReconnectToken = null;
                _updateConnectionState(CrotoLinkConnectionState.disconnected);
                onSessionClosed?.call(reason);
                unawaited(disconnect());
                break;

              case 'error':
                final errorMsg = msg['message'] as String? ??
                    'El anfitrión no pudo procesar la acción.';
                lastError = errorMsg;
                onError?.call(errorMsg);
                break;
            }
          } catch (e) {
            debugPrint('CrotoLinkGuestService WebSocket parse error: $e');
          }
        },
        onDone: () {
          debugPrint('CrotoLinkGuestService: Connection closed');
          if (!completer.isCompleted) completer.complete(false);
          _handleUnexpectedDisconnect();
        },
        onError: (e) {
          debugPrint('CrotoLinkGuestService: Connection error $e');
          if (!completer.isCompleted) completer.complete(false);
          _handleUnexpectedDisconnect();
        },
      );

      // Enviar solicitud de unión inmediata
      _send({
        'op': 'join_request',
        'pin': pin,
        'name': name,
        'avatarColorValue': avatarColorValue,
        if (participantId != null) 'participantId': participantId,
        if (token != null) 'token': token,
        if (token == null && roomPassword != null) 'password': roomPassword,
      });

      final connected = await completer.future.timeout(
        joinStateTimeout,
        onTimeout: () {
          lastError ??= joinAccepted
              ? 'El anfitrión aceptó la unión pero no envió el estado de la '
                  'sala a tiempo.'
              : 'El host no respondió al PIN en 5s (red lenta o CrotoLink colgado).';
          return false;
        },
      );
      if (!connected && !isReconnect) {
        lastError ??= 'Conexión cerrada sin respuesta del host.';
        await disconnect();
      } else if (!connected) {
        // Vencido el plazo: no dejar vivo el socket del intento fallido.
        _teardownSocket();
      }
      return connected;
    } on TimeoutException {
      lastError = 'Timeout conectando a $host:$port. Firewall o IP incorrecta.';
      debugPrint('CrotoLinkGuestService.connect timeout: $host:$port');
      if (!isReconnect) await disconnect();
      return false;
    } on SocketException catch (e) {
      lastError = _describeSocketException(e, host, port);
      debugPrint('CrotoLinkGuestService.connect socket error: $e');
      if (!isReconnect) await disconnect();
      return false;
    } catch (e) {
      lastError = 'No se pudo conectar a $host:$port: $e';
      debugPrint('CrotoLinkGuestService.connect error: $e');
      if (!isReconnect) await disconnect();
      return false;
    }
  }

  void _applyAuthoritativeSnapshot(
    CrotoLinkSessionState snapshot, {
    CrotoLinkParticipant? assignedParticipant,
  }) {
    _sessionState = snapshot;
    _queueRevision = snapshot.queueRevision;

    if (assignedParticipant != null) {
      _localParticipant = assignedParticipant;
      _savedParticipantId = assignedParticipant.id;
    }

    if (_localParticipant != null) {
      final fromList = snapshot.participants
          .where((p) => p.id == _localParticipant!.id)
          .firstOrNull;
      if (fromList != null) {
        _localParticipant = fromList;
      } else {
        _localParticipant = _localParticipant!.copyWith(
          canControlPlayback: snapshot.allowGuestControls,
          canManageQueue: snapshot.allowGuestQueueManage,
        );
      }
    }
  }

  void _startSilenceDetection() {
    _silenceTimer?.cancel();
    _lastHostActivity = DateTime.now();
    _silenceTimer = Timer.periodic(silenceCheckInterval, (_) {
      checkHostSilence();
    });
  }

  void checkHostSilence([DateTime? nowTime]) {
    if (!_isConnected || _isExplicitDisconnect) return;
    final now = nowTime ?? DateTime.now();
    if (now.difference(_lastHostActivity) > hostSilenceTimeout) {
      debugPrint('CrotoLinkGuestService: Host silence detected');
      _handleUnexpectedDisconnect();
    }
  }

  void _teardownSocket() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_channel?.sink.close());
    _channel = null;
    _isConnected = false;
    _clockTimer?.cancel();
    _clockTimer = null;
  }

  void _handleUnexpectedDisconnect() {
    _teardownSocket();

    if (_isExplicitDisconnect) {
      _updateConnectionState(CrotoLinkConnectionState.disconnected);
      return;
    }

    if (_savedHost != null && _savedReconnectToken != null) {
      _updateConnectionState(CrotoLinkConnectionState.reconnecting);
      _scheduleReconnect();
    } else {
      _updateConnectionState(CrotoLinkConnectionState.disconnected);
    }
  }

  void _scheduleReconnect() {
    if (_isExplicitDisconnect || _isReconnecting) return;
    _reconnectTimer?.cancel();
    final startedAt = _reconnectStartedAt ??= DateTime.now();
    if (DateTime.now().difference(startedAt) > reconnectGiveUp) {
      lastError ??= 'No se pudo reconectar con el anfitrión.';
      _updateConnectionState(CrotoLinkConnectionState.failed);
      _teardownSocket();
      return;
    }

    final int baseSeconds;
    if (_reconnectAttempts < 5) {
      baseSeconds = 1 << _reconnectAttempts; // 1, 2, 4, 8, 16
    } else {
      baseSeconds = 30;
    }
    _reconnectAttempts++;

    final jitterMs = Random.secure().nextInt(1000);
    final delay = Duration(milliseconds: baseSeconds * 1000 + jitterMs);

    debugPrint(
        'CrotoLinkGuestService: Reconnecting in ${delay.inMilliseconds}ms (attempt $_reconnectAttempts)');
    _reconnectTimer = Timer(delay, () {
      unawaited(_performReconnect());
    });
  }

  @visibleForTesting
  Future<void> triggerReconnectForTesting() => _performReconnect();

  Future<void> _performReconnect() async {
    if (_isExplicitDisconnect ||
        _savedHost == null ||
        _savedPort == null ||
        _savedPin == null ||
        _savedReconnectToken == null ||
        _savedTlsFingerprint == null) {
      return;
    }

    _isReconnecting = true;
    _updateConnectionState(CrotoLinkConnectionState.reconnecting);

    final success = await _connectInternal(
      host: _savedHost!,
      port: _savedPort!,
      pin: _savedPin!,
      name: _savedName ?? 'Invitado',
      avatarColorValue: _savedAvatarColorValue ?? 0xFF10B981,
      participantId: _savedParticipantId,
      token: _savedReconnectToken,
      tlsFingerprint: _savedTlsFingerprint!,
      isReconnect: true,
    );

    _isReconnecting = false;
    if (success) {
      _reconnectAttempts = 0;
      _reconnectStartedAt = null;
      _updateConnectionState(CrotoLinkConnectionState.connected);
    } else if (!_isExplicitDisconnect) {
      final code = lastRejectCode;
      // Con código tipado se decide por él; el texto solo sirve de respaldo
      // con anfitriones antiguos que no lo envían.
      final terminal = code != null
          ? _terminalRejectCodes.contains(code)
          : (lastError != null &&
              (lastError!.contains('inválido') ||
                  lastError!.contains('expirada')));
      if (terminal) {
        _updateConnectionState(CrotoLinkConnectionState.failed);
      } else {
        _scheduleReconnect();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Acciones Colaborativas
  // ---------------------------------------------------------------------------

  /// Pista para `add_to_queue`: la carátula va sin `u`/`s`/`t`, que son la
  /// sesión Subsonic del invitado y no deben llegar al anfitrión.
  @visibleForTesting
  static Map<String, dynamic> addToQueueTrackJson(Track track) => {
        'id': track.id,
        'title': track.title,
        'artist': track.artist,
        'album': track.album,
        'duration': track.duration,
        'albumArtUrl': sanitizeArtUrl(track.albumArtUrl),
      };

  void addToQueue(Track track, {bool playNext = false}) {
    if (_localParticipant != null && !_localParticipant!.canManageQueue) {
      const msg = 'El anfitrión ha deshabilitado la gestión de cola.';
      lastError = msg;
      onError?.call(msg);
      return;
    }
    _send({
      'op': 'add_to_queue',
      'track': addToQueueTrackJson(track),
      'playNext': playNext,
    });
  }

  void removeFromQueue(String queueItemId) {
    if (_localParticipant != null && !_localParticipant!.canManageQueue) {
      const msg = 'El anfitrión ha deshabilitado la gestión de cola.';
      lastError = msg;
      onError?.call(msg);
      return;
    }
    _send({
      'op': 'remove_from_queue',
      'queueItemId': queueItemId,
    });
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (_localParticipant != null && !_localParticipant!.canManageQueue) {
      const msg = 'El anfitrión ha deshabilitado la gestión de cola.';
      lastError = msg;
      onError?.call(msg);
      return;
    }
    _send({
      'op': 'reorder_queue',
      'oldIndex': oldIndex,
      'newIndex': newIndex,
    });
  }

  void sendReaction(String emoji) => _send({'op': 'reaction', 'emoji': emoji});

  void sendChat(String text) => _send({'op': 'chat_message', 'text': text});

  void sendVote(String itemId, int value) {
    _send({'op': 'vote', 'itemId': itemId, 'value': value.clamp(-1, 1)});
  }

  void sendPlaybackControl(String action, {int? positionMs}) {
    if (_localParticipant != null && !_localParticipant!.canControlPlayback) {
      const msg = 'El anfitrión ha deshabilitado el control de reproducción.';
      lastError = msg;
      onError?.call(msg);
      return;
    }
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
      debugPrint('CrotoLinkGuestService send error: $e');
    }
  }

  Future<void> disconnect({bool isExplicit = true}) async {
    if (isExplicit) {
      _isExplicitDisconnect = true;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _isReconnecting = false;
    _reconnectAttempts = 0;
    _reconnectStartedAt = null;

    if (_isConnected) {
      try {
        _send({'op': 'leave'});
      } catch (_) {}
    }
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _sessionState = null;
    _localParticipant = null;
    _queueRevision = 0;
    if (isExplicit) {
      _savedHost = null;
      _savedPort = null;
      _savedPin = null;
      _savedName = null;
      _savedAvatarColorValue = null;
      _savedParticipantId = null;
      _savedReconnectToken = null;
      _savedTlsFingerprint = null;
      _updateConnectionState(CrotoLinkConnectionState.disconnected);
    }
  }
}
