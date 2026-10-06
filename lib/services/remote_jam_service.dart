import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/jam_models.dart';
import 'jam_clock.dart';

typedef OnRemoteStateSync = void Function(Map<String, dynamic> state);
typedef OnRemoteGuestJoined = void Function(String guestName, int totalParticipants);

/// El relay cambió de anfitrión (transferencia o failover). [state]/[guests]
/// solo vienen para el nuevo anfitrión.
typedef OnRemoteHostChanged = void Function(
  bool youAreHost,
  String hostName,
  Map<String, dynamic>? state,
  List<Map<String, dynamic>> guests,
);
typedef OnRemoteGuestAction = void Function(String fromGuest, String actionType, dynamic payload);
typedef OnRemoteRoomClosed = void Function(String reason);
typedef OnRemoteError = void Function(String error);

/// Tamaño máximo de mensaje que acepta el servidor central (`MAX_MESSAGE_BYTES`).
/// Superarlo hace que el servidor cierre el socket (1009) y, si era el del
/// anfitrión, que la sala desaparezca.
const int kRemoteJamMaxMessageBytes = 16384;

/// Servicio cliente WebSocket para conectar con el servidor central de Scrotify Jam en la nube
/// (por defecto `wss://jam.templo.cloud/`).
///
/// Permite que un Anfitrión (Host) publique su sala globalmente y que Invitados (Guests)
/// se conecten por datos móviles (4G/5G) o desde cualquier red sin depender de LAN ni UPnP.
class RemoteJamService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _isConnected = false;
  bool _isHost = false;
  String? _pin;
  String _endpoint = kDefaultRemoteJamEndpoint;
  String? _lastError;

  /// Contraseña de sala (anfitrión al crear / invitado al unirse). Viaja solo
  /// por canal TLS (`wss://`); el servidor guarda únicamente su hash.
  String? roomPassword;

  OnRemoteStateSync? onStateSync;
  OnRemoteGuestJoined? onGuestJoined;
  OnRemoteGuestAction? onGuestAction;
  OnRemoteRoomClosed? onRoomClosed;
  OnRemoteError? onError;
  OnRemoteHostChanged? onHostChanged;
  void Function(int failoverMs)? onHostAway;
  void Function()? onHostBack;
  void Function(String from, String emoji)? onReaction;
  void Function(String from, String text, int ts)? onChat;
  void Function(bool enabled)? onChatState;

  /// Pistas para continuidad (Fase 7): token del anfitrión (128 bits, solo en
  /// RAM), token de propietario de sala persistente y failover automático.
  String? hostToken;
  String? ownerToken;
  bool failoverEnabled = false;

  /// IDs que el relay asigna a los invitados (por nombre), para transferir.
  final Map<String, String> guestIds = {};

  bool get isConnected => _isConnected;
  bool get isHost => _isHost;
  String? get pin => _pin;
  String get endpoint => _endpoint;
  String? get lastError => _lastError;

  /// Devuelve [state] con `queue` recortada al prefijo que cabe en un mensaje.
  /// Se recorta por el final para que los índices que usa el invitado al
  /// reordenar o quitar sigan coincidiendo con los del anfitrión.
  static Map<String, dynamic> fitStateToMessageLimit(
    Map<String, dynamic> state, {
    int maxBytes = kRemoteJamMaxMessageBytes - 512,
  }) {
    final queue = state['queue'];
    if (queue is! List) return state;
    int sizeOf(Object? value) => utf8.encode(jsonEncode(value)).length;

    final fitted = <dynamic>[];
    var used = sizeOf({...state, 'queue': const []});
    for (final item in queue) {
      final itemBytes = sizeOf(item) + 1; // coma separadora
      if (used + itemBytes > maxBytes) break;
      used += itemBytes;
      fitted.add(item);
    }
    if (fitted.length == queue.length) return state;
    debugPrint(
        'RemoteJamService: cola recortada a ${fitted.length}/${queue.length} para el servidor central');
    return {...state, 'queue': fitted};
  }

  void setEndpoint(String endpoint) {
    if (endpoint.trim().isNotEmpty) {
      _endpoint = endpoint.trim();
    }
  }

  /// Comprueba `GET /health` del servidor [endpoint]. Devuelve `null` si
  /// responde `{"status":"ok"}`, o el motivo del fallo para mostrar en UI.
  static Future<String?> testConnection(String endpoint) async {
    final parsed = JamServerEndpoint.parse(endpoint);
    if (!parsed.isValid) return parsed.error;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request =
          await client.getUrl(parsed.httpBase.replace(path: '/health'));
      final response =
          await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) {
        return 'El servidor respondió ${response.statusCode}.';
      }
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      return data is Map && data['status'] == 'ok'
          ? null
          : 'La respuesta no parece de un servidor Jam.';
    } on TimeoutException {
      return 'Tiempo de espera agotado.';
    } catch (e) {
      return 'No se pudo conectar: $e';
    } finally {
      client.close(force: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Host: Crear sala y publicar estado
  // ---------------------------------------------------------------------------

  /// Conecta como Host al servidor central y registra la sala Jam.
  Future<bool> createRoom({
    required String pin,
    required String hostName,
    required Map<String, dynamic> initialState,
    String? customEndpoint,
    bool resume = false,
  }) async {
    final keepToken = resume ? hostToken : null;
    await disconnect();
    hostToken = keepToken;
    _lastError = null;
    final targetEndpoint = customEndpoint ?? _endpoint;
    final normalizedPin = pin.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

    try {
      final uri = Uri.parse(targetEndpoint);
      _channel = WebSocketChannel.connect(uri);
      final completer = Completer<bool>();
      Timer? timeoutTimer;

      _subscription = _channel!.stream.listen(
        (data) {
          try {
            final text = data is List<int> ? utf8.decode(data) : data.toString();
            final json = jsonDecode(text) as Map<String, dynamic>;
            if (_handleClockMessage(json)) return;

            if (json['status'] == 'room_created' ||
                json['status'] == 'host_resumed') {
              if (json['hostToken'] is String) hostToken = json['hostToken'] as String;
              _isConnected = true;
              _isHost = true;
              _pin = normalizedPin;
              _startClockSync();
              timeoutTimer?.cancel();
              if (!completer.isCompleted) completer.complete(true);
              debugPrint('RemoteJamService: Sala creada exitosamente en $targetEndpoint con PIN $normalizedPin');
              return;
            }

            if (json['status'] == 'error') {
              debugPrint('RemoteJamService error: ${json['message']}');
              _lastError = json['message']?.toString() ?? 'Error al crear la sala';
              onError?.call(_lastError!);
              timeoutTimer?.cancel();
              if (!completer.isCompleted) completer.complete(false);
              return;
            }

            _dispatchEvent(json);
          } catch (e) {
            debugPrint('RemoteJamService parsing error: $e');
          }
        },
        onError: (err) {
          debugPrint('RemoteJamService host WS error: $err');
          _isConnected = false;
          _lastError ??= 'Error de conexión con el servidor Jam central.';
          timeoutTimer?.cancel();
          if (!completer.isCompleted) completer.complete(false);
        },
        onDone: () {
          debugPrint('RemoteJamService host WS closed');
          _isConnected = false;
          timeoutTimer?.cancel();
          if (!completer.isCompleted) completer.complete(false);
        },
        cancelOnError: false,
      );

      // Enviar create_room
      _channel!.sink.add(jsonEncode(resume && keepToken != null
          ? {'action': 'resume_host', 'pin': normalizedPin, 'hostToken': keepToken}
          : {
              'action': 'create_room',
              'pin': normalizedPin,
              'hostName': hostName,
              'initialState': fitStateToMessageLimit(initialState),
              if (roomPassword != null && roomPassword!.isNotEmpty)
                'roomPassword': roomPassword,
              if (failoverEnabled) 'failover': true,
              if (ownerToken != null && ownerToken!.isNotEmpty)
                'ownerToken': ownerToken,
            }));

      timeoutTimer = Timer(const Duration(seconds: 6), () {
        if (!completer.isCompleted) {
          debugPrint('RemoteJamService: timeout al crear sala');
          _lastError ??= 'Tiempo de espera agotado al conectar con el servidor Jam central.';
          completer.complete(false);
        }
      });

      return await completer.future;
    } catch (e) {
      debugPrint('RemoteJamService.createRoom exception: $e');
      _isConnected = false;
      _lastError = 'Excepción al conectar con el servidor central: $e';
      return false;
    }
  }

  /// Actualiza el estado de reproducción en la sala remota (sólo Host).
  void updateState(Map<String, dynamic> state) {
    if (!_isConnected || !_isHost || _channel == null || _pin == null) return;
    try {
      _channel!.sink.add(jsonEncode({
        'action': 'update_state',
        'pin': _pin,
        'state': fitStateToMessageLimit(state),
      }));
    } catch (e) {
      debugPrint('RemoteJamService.updateState error: $e');
    }
  }

  /// Expulsa a un invitado de la sala remota (sólo Host).
  void kickGuest(String guestName) {
    if (!_isConnected || !_isHost || _channel == null || _pin == null) return;
    try {
      _channel!.sink.add(jsonEncode({
        'action': 'kick_guest',
        'pin': _pin,
        'guestName': guestName,
        if (roomPassword != null && roomPassword!.isNotEmpty)
          'roomPassword': roomPassword,
      }));
    } catch (e) {
      debugPrint('RemoteJamService.kickGuest error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Guest: Unirse a una sala remota
  // ---------------------------------------------------------------------------

  /// Conecta como Invitado (Guest) a una sala remota mediante su PIN.
  Future<Map<String, dynamic>?> joinRoom({
    required String pin,
    required String guestName,
    String? customEndpoint,
  }) async {
    await disconnect();
    _lastError = null;
    final targetEndpoint = customEndpoint ?? _endpoint;
    final normalizedPin = pin.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

    try {
      final uri = Uri.parse(targetEndpoint);
      _channel = WebSocketChannel.connect(uri);
      final completer = Completer<Map<String, dynamic>?>();
      Timer? timeoutTimer;

      _subscription = _channel!.stream.listen(
        (data) {
          try {
            final text = data is List<int> ? utf8.decode(data) : data.toString();
            final json = jsonDecode(text) as Map<String, dynamic>;
            if (_handleClockMessage(json)) return;

            if (json['status'] == 'joined') {
              _isConnected = true;
              _isHost = false;
              _pin = normalizedPin;
              _startClockSync();
              timeoutTimer?.cancel();
              final state = json['state'] as Map<String, dynamic>? ?? {};
              if (!completer.isCompleted) completer.complete(state);
              onStateSync?.call(state);
              return;
            }

            if (json['status'] == 'error') {
              debugPrint('RemoteJamService join error: ${json['message']}');
              _lastError = json['message']?.toString() ?? 'Error al unirse';
              onError?.call(_lastError!);
              timeoutTimer?.cancel();
              if (!completer.isCompleted) completer.complete(null);
              return;
            }

            _dispatchEvent(json);
          } catch (e) {
            debugPrint('RemoteJamService guest message parsing error: $e');
          }
        },
        onError: (err) {
          debugPrint('RemoteJamService guest WS error: $err');
          _isConnected = false;
          _lastError ??= 'Error de conexión con el servidor Jam central.';
          timeoutTimer?.cancel();
          if (!completer.isCompleted) completer.complete(null);
        },
        onDone: () {
          debugPrint('RemoteJamService guest WS closed');
          _isConnected = false;
          timeoutTimer?.cancel();
          if (!completer.isCompleted) completer.complete(null);
        },
        cancelOnError: false,
      );

      // Enviar join_room
      _channel!.sink.add(jsonEncode({
        'action': 'join_room',
        'pin': normalizedPin,
        'guestName': guestName,
      }));

      timeoutTimer = Timer(const Duration(seconds: 6), () {
        if (!completer.isCompleted) {
          debugPrint('RemoteJamService: timeout al unirse a la sala');
          _lastError ??= 'Tiempo de espera agotado al conectar a la sala remota.';
          completer.complete(null);
        }
      });

      return await completer.future;
    } catch (e) {
      debugPrint('RemoteJamService.joinRoom exception: $e');
      _isConnected = false;
      _lastError = 'Excepción al unirse a la sala remota: $e';
      return null;
    }
  }

  /// Envía una acción de invitado (reproducir, pausar, añadir a cola) al Host.
  void sendGuestAction(String actionType, dynamic payload) {
    if (!_isConnected || _isHost || _channel == null) return;
    try {
      _channel!.sink.add(jsonEncode({
        'action': 'guest_action',
        'actionType': actionType,
        'payload': payload,
      }));
    } catch (e) {
      debugPrint('RemoteJamService.sendGuestAction error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Utilidad: Consultar existencia de sala
  // ---------------------------------------------------------------------------

  /// Consulta al servidor si una sala con [pin] está activa sin unirse formalmente.
  Future<Map<String, dynamic>?> checkRoom(String pin, {String? customEndpoint}) async {
    final targetEndpoint = customEndpoint ?? _endpoint;
    final normalizedPin = pin.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

    try {
      final uri = Uri.parse(targetEndpoint);
      final tempChannel = WebSocketChannel.connect(uri);
      final completer = Completer<Map<String, dynamic>?> ();
      Timer? timeoutTimer;
      StreamSubscription? tempSub;

      tempSub = tempChannel.stream.listen(
        (data) {
          try {
            final text = data is List<int> ? utf8.decode(data) : data.toString();
            final json = jsonDecode(text) as Map<String, dynamic>;
            if (_handleClockMessage(json)) return;

            if (json['status'] == 'room_found') {
              timeoutTimer?.cancel();
              if (!completer.isCompleted) completer.complete(json);
            } else {
              timeoutTimer?.cancel();
              if (!completer.isCompleted) completer.complete(null);
            }
          } catch (_) {
            timeoutTimer?.cancel();
            if (!completer.isCompleted) completer.complete(null);
          }
        },
        onError: (_) {
          timeoutTimer?.cancel();
          if (!completer.isCompleted) completer.complete(null);
        },
        onDone: () {
          timeoutTimer?.cancel();
          if (!completer.isCompleted) completer.complete(null);
        },
      );

      tempChannel.sink.add(jsonEncode({
        'action': 'check_room',
        'pin': normalizedPin,
      }));

      timeoutTimer = Timer(const Duration(seconds: 3), () {
        if (!completer.isCompleted) completer.complete(null);
      });

      final result = await completer.future;
      await tempSub.cancel();
      await tempChannel.sink.close();
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Obtiene la lista de salas Jam activas y públicas desde el servidor central HTTP (`/rooms`).
  Future<List<DiscoveredJamSession>> getActiveRooms({String? customEndpoint}) async {
    final target = customEndpoint ?? _endpoint;
    try {
      final parsed = JamServerEndpoint.parse(target);
      if (!parsed.isValid) return [];
      final uri = parsed.httpBase.replace(path: '/rooms');

      final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final request = await client.getUrl(uri);
      final response =
          await request.close().timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final list = jsonDecode(body) as List<dynamic>;

        return list.map((item) {
          final m = item as Map<String, dynamic>;
          final modeName = (m['mode'] as String?) ?? JamMode.partySpeaker.name;
          final mode = JamMode.values.firstWhere(
            (val) => val.name == modeName,
            orElse: () => JamMode.partySpeaker,
          );

          return DiscoveredJamSession(
            host: parsed.host,
            port: parsed.port,
            pin: (m['pin'] as String?) ?? '',
            sessionTitle: (m['sessionTitle'] as String?) ??
                'Jam de ${(m['hostName'] as String?) ?? "Anfitrión"}',
            hostName: (m['hostName'] as String?) ?? 'Anfitrión',
            participantCount: (m['participantCount'] as num?)?.toInt() ?? 1,
            currentTrackTitle: m['currentTrackTitle'] as String?,
            currentTrackArtist: m['currentTrackArtist'] as String?,
            albumArtUrl: m['albumArtUrl'] as String?,
            mode: mode,
            remoteHost: parsed.host,
            remotePort: parsed.port,
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('RemoteJamService.getActiveRooms error: $e');
    }
    return [];
  }

  // ---------------------------------------------------------------------------
  // Desconexión
  // ---------------------------------------------------------------------------

  /// Eventos del relay válidos para cualquier rol: el rol puede cambiar a mitad
  /// de sesión (transferencia/failover) sin reabrir el socket.
  void _dispatchEvent(Map<String, dynamic> json) {
    final event = json['event'];
    switch (event) {
      case 'guest_joined':
        final guestName = json['guestName']?.toString() ?? 'Invitado';
        final id = json['guestId']?.toString();
        if (id != null) guestIds[guestName] = id;
        onGuestJoined?.call(
            guestName, (json['totalParticipants'] as num?)?.toInt() ?? 1);
      case 'guest_action':
        onGuestAction?.call(
          json['guestName']?.toString() ?? 'Invitado',
          json['actionType']?.toString() ?? '',
          json['payload'],
        );
      case 'sync_state':
        onStateSync?.call(json['state'] as Map<String, dynamic>? ?? {});
      case 'host_changed':
        final youAreHost = json['youAreHost'] == true;
        _isHost = youAreHost;
        if (youAreHost && json['hostToken'] is String) {
          hostToken = json['hostToken'] as String;
        } else if (!youAreHost) {
          hostToken = null;
        }
        guestIds.clear();
        final guests = <Map<String, dynamic>>[
          for (final g in (json['guests'] as List? ?? const []))
            if (g is Map) Map<String, dynamic>.from(g),
        ];
        for (final g in guests) {
          final name = g['name']?.toString();
          final id = g['id']?.toString();
          if (name != null && id != null) guestIds[name] = id;
        }
        onHostChanged?.call(
          youAreHost,
          json['hostName']?.toString() ?? 'Anfitrión',
          json['state'] is Map
              ? Map<String, dynamic>.from(json['state'] as Map)
              : null,
          guests,
        );
      case 'host_away':
        onHostAway?.call((json['failoverMs'] as num?)?.toInt() ?? 0);
      case 'host_back':
        onHostBack?.call();
      case 'reaction':
        onReaction?.call(json['from']?.toString() ?? '', json['emoji']?.toString() ?? '');
      case 'chat':
        onChat?.call(
          json['from']?.toString() ?? '',
          json['text']?.toString() ?? '',
          (json['ts'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        );
      case 'chat_state':
        onChatState?.call(json['enabled'] != false);
      case 'room_closed' || 'kicked':
        final reason = json['message']?.toString() ??
            (event == 'kicked'
                ? 'Has sido expulsado de la sala por el anfitrión.'
                : 'La sala Jam fue cerrada.');
        onRoomClosed?.call(reason);
        disconnect();
    }
  }

  void _sendAction(Map<String, dynamic> msg) {
    if (!_isConnected) return;
    try {
      _channel?.sink.add(jsonEncode(msg));
    } catch (_) {}
  }

  void sendReaction(String emoji) =>
      _sendAction({'action': 'reaction', 'emoji': emoji});

  void sendChat(String text) =>
      _sendAction({'action': 'chat_message', 'text': text});

  void setChatEnabled(bool enabled) =>
      _sendAction({'action': 'set_chat', 'enabled': enabled});

  /// Funciones que el admin del relay permite (`GET /api/capabilities`).
  /// `null` si el servidor es antiguo o no responde (usar valores por defecto).
  static Future<({bool reactions, bool chat})?> fetchCapabilities(
      String endpoint) async {
    final parsed = JamServerEndpoint.parse(endpoint);
    if (!parsed.isValid) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client
          .getUrl(parsed.httpBase.replace(path: '/api/capabilities'));
      final res = await req.close().timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(await res.transform(utf8.decoder).join());
      final f = data is Map ? data['features'] : null;
      if (f is! Map) return null;
      return (reactions: f['reactions'] != false, chat: f['chat'] == true);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Cede el control de la sala a un invitado (por nombre). Devuelve `false`
  /// si no se conoce su ID en el relay.
  bool transferHost(String guestName) {
    final id = guestIds[guestName];
    final p = _pin;
    if (!_isHost || id == null || p == null) return false;
    try {
      _channel?.sink.add(jsonEncode(
          {'action': 'transfer_host', 'pin': p, 'toGuestId': id}));
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Reloj de referencia (el relay): `time_ping` / `time_pong`
  // ---------------------------------------------------------------------------

  /// Offset local→relay estimado. Sin muestras (relay antiguo o sin pong) los
  /// consumidores degradan al comportamiento previo.
  final ClockOffsetEstimator clock = ClockOffsetEstimator();
  Timer? _clockTimer;

  void _sendTimePing() {
    try {
      _channel?.sink.add(jsonEncode({
        'action': 'time_ping',
        'clientTs': DateTime.now().millisecondsSinceEpoch,
      }));
    } catch (_) {}
  }

  void _startClockSync() {
    _clockTimer?.cancel();
    clock.clear();
    for (var i = 0; i < kJamClockSamples; i++) {
      Future.delayed(Duration(milliseconds: 150 * i), () {
        if (_isConnected) _sendTimePing();
      });
    }
    _clockTimer = Timer.periodic(kJamClockResync, (_) {
      if (_isConnected) _sendTimePing();
    });
  }

  bool _handleClockMessage(Map<String, dynamic> json) {
    if (json['status'] != 'time_pong') return false;
    final sent = (json['clientTs'] as num?)?.toInt();
    final server = (json['serverNowMs'] as num?)?.toInt();
    if (sent != null && server != null) {
      clock.add(JamClockSample.fromExchange(
        sentAt: sent,
        receivedAt: DateTime.now().millisecondsSinceEpoch,
        serverNow: server,
      ));
    }
    return true;
  }

  Future<void> disconnect() async {
    _clockTimer?.cancel();
    _clockTimer = null;
    _isConnected = false;
    _isHost = false;
    _pin = null;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }
}
