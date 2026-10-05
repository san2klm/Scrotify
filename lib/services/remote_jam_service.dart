import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/jam_models.dart';

typedef OnRemoteStateSync = void Function(Map<String, dynamic> state);
typedef OnRemoteGuestJoined = void Function(String guestName, int totalParticipants);
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

  OnRemoteStateSync? onStateSync;
  OnRemoteGuestJoined? onGuestJoined;
  OnRemoteGuestAction? onGuestAction;
  OnRemoteRoomClosed? onRoomClosed;
  OnRemoteError? onError;

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

  // ---------------------------------------------------------------------------
  // Host: Crear sala y publicar estado
  // ---------------------------------------------------------------------------

  /// Conecta como Host al servidor central y registra la sala Jam.
  Future<bool> createRoom({
    required String pin,
    required String hostName,
    required Map<String, dynamic> initialState,
    String? customEndpoint,
  }) async {
    await disconnect();
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

            if (json['status'] == 'room_created') {
              _isConnected = true;
              _isHost = true;
              _pin = normalizedPin;
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

            // Eventos recibidos por el host
            final event = json['event'];
            if (event == 'guest_joined') {
              final guestName = json['guestName']?.toString() ?? 'Invitado';
              final total = (json['totalParticipants'] as num?)?.toInt() ?? 1;
              onGuestJoined?.call(guestName, total);
            } else if (event == 'guest_action') {
              final from = json['guestName']?.toString() ?? 'Invitado';
              final actionType = json['actionType']?.toString() ?? '';
              final payload = json['payload'];
              onGuestAction?.call(from, actionType, payload);
            }
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
      _channel!.sink.add(jsonEncode({
        'action': 'create_room',
        'pin': normalizedPin,
        'hostName': hostName,
        'initialState': fitStateToMessageLimit(initialState),
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

            if (json['status'] == 'joined') {
              _isConnected = true;
              _isHost = false;
              _pin = normalizedPin;
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

            final event = json['event'];
            if (event == 'sync_state') {
              final state = json['state'] as Map<String, dynamic>? ?? {};
              onStateSync?.call(state);
            } else if (event == 'room_closed' || event == 'kicked') {
              final reason = json['message']?.toString() ??
                  (event == 'kicked'
                      ? 'Has sido expulsado de la sala por el anfitrión.'
                      : 'La sala Jam fue cerrada.');
              onRoomClosed?.call(reason);
              disconnect();
            }
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
      final httpUrl = target
          .replaceFirst('wss://', 'https://')
          .replaceFirst('ws://', 'http://');
      final uri = Uri.parse(httpUrl).replace(path: '/rooms');

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
            host: 'jam.templo.cloud',
            port: 443,
            pin: (m['pin'] as String?) ?? '',
            sessionTitle: (m['sessionTitle'] as String?) ??
                'Jam de ${(m['hostName'] as String?) ?? "Anfitrión"}',
            hostName: (m['hostName'] as String?) ?? 'Anfitrión',
            participantCount: (m['participantCount'] as num?)?.toInt() ?? 1,
            currentTrackTitle: m['currentTrackTitle'] as String?,
            currentTrackArtist: m['currentTrackArtist'] as String?,
            albumArtUrl: m['albumArtUrl'] as String?,
            mode: mode,
            remoteHost: 'jam.templo.cloud',
            remotePort: 443,
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

  Future<void> disconnect() async {
    _isConnected = false;
    _isHost = false;
    _pin = null;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }
}
