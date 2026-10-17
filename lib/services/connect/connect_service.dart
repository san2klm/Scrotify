import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../settings_controller.dart';
import '../sync/sync_crypto.dart';
import 'connect_protocol.dart';
import 'connect_transport.dart';

/// Lo que `ConnectService` necesita del reproductor local.
abstract class ConnectPlayerPort implements Listenable {
  /// Servidor Navidrome activo; las colas solo se transfieren entre
  /// dispositivos conectados al mismo servidor.
  String? get scope;

  /// Estado a publicar (`scope`, `track`, `playing`, `positionMs`,
  /// `durationMs`, `volume`, `queue`, `queueSig`, `offset`, `index`,
  /// `shuffle`, `repeat`), o `null` si no hay nada cargado.
  Map<String, dynamic>? snapshot();

  /// Cola y posición actuales, o `null` si no hay nada que transferir.
  ConnectTransfer? exportTransfer();

  /// Carga la cola recibida y la reproduce (o la deja en pausa).
  Future<void> adopt(ConnectTransfer transfer);

  /// Ejecuta un comando de [ConnectCommand] en este dispositivo.
  Future<void> apply(String command, num? value, Map<String, dynamic> data);

  /// Pausa la reproducción local (tras transferirla a otro dispositivo).
  Future<void> pauseLocal();
}

/// CrotoWave Connect: ver los demás dispositivos del usuario (por LAN y por el
/// servidor CrotoLink), usarlos como altavoz y controlarlos a distancia, como
/// Spotify Connect. Todos los mensajes van cifrados con la clave de
/// sincronización, así que solo los dispositivos del mismo grupo se entienden.
class ConnectService extends ChangeNotifier {
  ConnectService({
    required this.port,
    required this.selfId,
    required this.transportsFor,
    String selfName = 'Esta computadora',
    String? defaultName,
    this.persistName,
    DateTime Function()? now,
    this.ackTimeout = const Duration(seconds: 6),
    this.stateInterval = const Duration(seconds: 3),
  })  : _selfName = selfName,
        defaultName = defaultName ?? selfName,
        _now = now ?? DateTime.now;

  static const _docKey = 'connect';

  final ConnectPlayerPort port;
  final String selfId;
  final List<ConnectTransport> Function(SyncCrypto crypto) transportsFor;
  final Duration ackTimeout;
  final Duration stateInterval;
  final DateTime Function() _now;

  /// Nombre del sistema, al que se vuelve si el usuario borra el suyo.
  final String defaultName;

  /// Guarda el nombre elegido (`null` = el de por defecto).
  final Future<void> Function(String? name)? persistName;
  String _selfName;

  SyncCrypto? _crypto;
  List<ConnectTransport> _transports = [];
  final _subscriptions = <StreamSubscription<dynamic>>[];
  List<Map<String, ConnectDevice>> _perTransport = [];
  List<ConnectDevice> _devices = const [];
  final _states = <String, ConnectRemoteState>{};
  final _lastCounter = <String, int>{};
  final _acks = <String, Completer<bool>>{};
  int _counter = 0;
  String? _controlledId;
  String? _error;
  Timer? _stateDebounce;
  Timer? _stateTimer;
  bool _listening = false;
  String? _lastQueueSig;
  bool _forceQueue = true;
  int _publishes = 0;

  /// Nombre con el que este dispositivo aparece en los demás.
  String get selfName => _selfName;

  /// Cambia el nombre visible y lo reanuncia: los transportes se recrean para
  /// que LAN y relé usen el nuevo nombre enseguida.
  Future<void> rename(String input) async {
    final name = SettingsController.normalizeDeviceName(input);
    final next = name ?? defaultName;
    if (next == _selfName) return;
    _selfName = next;
    notifyListeners();
    await persistName?.call(name);
    final crypto = _crypto;
    if (crypto != null) {
      await _stop();
      await _start(crypto);
    }
  }

  /// Dispositivos del mismo usuario visibles ahora mismo.
  List<ConnectDevice> get devices => _devices;

  /// `true` si hay clave de sincronización y Connect está en marcha.
  bool get active => _crypto != null;

  /// Dispositivo al que se controla a distancia (`null` = este).
  ConnectDevice? get controlled {
    for (final d in _devices) {
      if (d.id == _controlledId) return d;
    }
    return null;
  }

  ConnectRemoteState? get controlledState =>
      _controlledId == null ? null : _states[_controlledId];

  ConnectRemoteState? stateOf(String deviceId) => _states[deviceId];

  String? get lastError => _error;

  String? get problem {
    for (final t in _transports) {
      if (t.problem != null && _devices.isEmpty) return t.problem;
    }
    return null;
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Ciclo de vida
  // ---------------------------------------------------------------------------

  /// Arranca Connect con la clave de sincronización, o lo detiene con `null`.
  Future<void> configure(SyncCrypto? crypto) async {
    if (identical(crypto, _crypto)) return;
    await _stop();
    _crypto = crypto;
    if (crypto == null) {
      notifyListeners();
      return;
    }
    await _start(crypto);
  }

  Future<void> _start(SyncCrypto crypto) async {
    _transports = transportsFor(crypto);
    _perTransport = [for (final _ in _transports) {}];
    for (var i = 0; i < _transports.length; i++) {
      final transport = _transports[i];
      _subscriptions
        ..add(transport.devices.listen((list) => _onDevices(i, list)))
        ..add(transport.messages.listen(_onMessage));
    }
    if (!_listening) {
      port.addListener(_scheduleState);
      _listening = true;
    }
    _stateTimer = Timer.periodic(stateInterval, (_) => _publishState());
    for (final transport in _transports) {
      unawaited(transport.start().catchError((Object e) {
        debugPrint('connect: no se pudo iniciar el transporte: $e');
      }));
    }
    notifyListeners();
  }

  Future<void> _stop() async {
    _stateTimer?.cancel();
    _stateDebounce?.cancel();
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();
    for (final t in _transports) {
      await t.stop();
    }
    _transports = [];
    _perTransport = [];
    _devices = const [];
    _states.clear();
    _lastCounter.clear();
    for (final c in _acks.values) {
      if (!c.isCompleted) c.complete(false);
    }
    _acks.clear();
    _controlledId = null;
    if (_listening) {
      port.removeListener(_scheduleState);
      _listening = false;
    }
  }

  @override
  void dispose() {
    unawaited(_stop());
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Dispositivos
  // ---------------------------------------------------------------------------

  void _onDevices(int index, List<ConnectDevice> list) {
    _perTransport[index] = {for (final d in list) d.id: d};
    final merged = <String, ConnectDevice>{};
    for (final map in _perTransport) {
      for (final d in map.values) {
        final known = merged[d.id];
        merged[d.id] = known == null
            ? d
            : known.copyWith(
                viaLan: known.viaLan || d.viaLan,
                viaRelay: known.viaRelay || d.viaRelay);
      }
    }
    final before = _devices.map((d) => d.id).toSet();
    _devices = merged.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _states.removeWhere((id, _) => !merged.containsKey(id));
    if (_controlledId != null && !merged.containsKey(_controlledId)) {
      _controlledId = null;
      _error = 'Se perdió la conexión con el dispositivo.';
    }
    notifyListeners();
    // Un dispositivo nuevo debe enterarse de lo que está sonando aquí.
    if (_devices.any((d) => !before.contains(d.id))) {
      _forceQueue = true;
      _publishState();
    }
  }

  // ---------------------------------------------------------------------------
  // Acciones del usuario
  // ---------------------------------------------------------------------------

  /// Pasa la reproducción de este dispositivo a [deviceId] y lo controla desde
  /// aquí. Si ya se controlaba otro, ese le entrega su cola directamente.
  Future<void> transferTo(String deviceId) async {
    final target = _devices.where((d) => d.id == deviceId).firstOrNull;
    if (target == null) return;
    _error = null;
    if (_controlledId != null && _controlledId != deviceId) {
      final previous = _controlledId!;
      final ok = await _request(deviceId,
          () => _send(previous, ConnectMessage.handoff, {'to': deviceId}));
      if (!ok) return _fail('No se pudo mover la reproducción.');
      _controlledId = deviceId;
      notifyListeners();
      return;
    }
    final transfer = port.exportTransfer();
    if (transfer == null) {
      _controlledId = deviceId; // Sin nada sonando: solo se queda de mando.
      notifyListeners();
      return;
    }
    final ok = await _deliver(deviceId, transfer);
    if (!ok) return _fail('${target.name} no respondió.');
    await port.pauseLocal();
    _controlledId = deviceId;
    notifyListeners();
  }

  /// Vuelve a reproducir en este dispositivo lo que sonaba en el controlado.
  Future<void> bringHere() async {
    final id = _controlledId;
    if (id == null) return;
    _error = null;
    final ok = await _request(
        id, () => _send(id, ConnectMessage.handoff, {'to': selfId}));
    if (!ok) {
      _fail('No se pudo traer la reproducción.');
      return;
    }
    _controlledId = null;
    notifyListeners();
  }

  /// Deja de controlar el dispositivo remoto sin traer la reproducción.
  void releaseControl() {
    if (_controlledId == null) return;
    _controlledId = null;
    notifyListeners();
  }

  /// Envía un comando al dispositivo controlado (si lo hay).
  void command(String command, [num? value, Map<String, dynamic>? data]) {
    final id = _controlledId;
    if (id == null || !ConnectCommand.all.contains(command)) return;
    unawaited(_send(id, ConnectMessage.command, {
      'cmd': command,
      if (value != null) 'value': value,
      if (data != null) 'data': data,
    }));
  }

  /// Envía varios comandos seguidos al dispositivo controlado, esperando a
  /// que cada uno salga antes del siguiente para que lleguen en orden.
  Future<void> commandSequence(
      List<({String command, Map<String, dynamic> data})> steps) async {
    final id = _controlledId;
    if (id == null) return;
    for (final step in steps) {
      if (_controlledId != id || !ConnectCommand.all.contains(step.command)) {
        return;
      }
      await _send(
          id, ConnectMessage.command, {'cmd': step.command, 'data': step.data});
    }
  }

  /// Entrega una cola a [to]: la primera parte en el `transfer` (que espera su
  /// `ack`) y, si hay más, el resto en trozos ordenados una vez adoptada.
  Future<bool> _deliver(String to, ConnectTransfer transfer) async {
    final split = ConnectQueueChunks.split(transfer.tracks);
    final head = transfer.headOf(split);
    final ok = await _request(
        to, () => _send(to, ConnectMessage.transfer, head.toJson()));
    if (ok && split.rest.isNotEmpty) {
      unawaited(() async {
        for (var seq = 0; seq < split.rest.length; seq++) {
          await _send(to, ConnectMessage.command, {
            'cmd': ConnectCommand.queueAppend,
            'data': split.appendData(transfer.scope, seq),
          });
        }
      }());
    }
    return ok;
  }

  void _fail(String message) {
    _error = message;
    notifyListeners();
  }

  /// Espera el `ack` de [from] tras lanzar [action]; `false` si no llega.
  Future<bool> _request(String from, Future<void> Function() action) async {
    final completer = Completer<bool>();
    _acks[from]?.complete(false);
    _acks[from] = completer;
    await action();
    final result =
        await completer.future.timeout(ackTimeout, onTimeout: () => false);
    if (identical(_acks[from], completer)) _acks.remove(from);
    return result;
  }

  // ---------------------------------------------------------------------------
  // Envío y recepción
  // ---------------------------------------------------------------------------

  Future<void> _send(String? to, String type, Map<String, dynamic> body) async {
    final crypto = _crypto;
    if (crypto == null) return;
    _counter = max(_counter + 1, _now().microsecondsSinceEpoch);
    final blob = await crypto
        .encrypt(ConnectMessage(type, body).encode(_counter), docKey: _docKey);
    if (to == null) {
      // A todos: cada camino entrega y el receptor descarta el duplicado.
      for (final t in _transports) {
        await t.send(null, blob);
      }
      return;
    }
    final transport = _transports.where((t) => t.canReach(to)).firstOrNull;
    await transport?.send(to, blob);
  }

  void _scheduleState() {
    _stateDebounce?.cancel();
    _stateDebounce = Timer(const Duration(milliseconds: 250), _publishState);
  }

  void _publishState() {
    if (_crypto == null || _devices.isEmpty) return;
    final snapshot = port.snapshot();
    if (snapshot == null) return;
    // La cola solo viaja cuando cambia, a un dispositivo nuevo y cada ~15 s
    // por si algún mensaje se perdió.
    final sig = snapshot['queueSig'];
    _publishes++;
    if (!_forceQueue && sig == _lastQueueSig && _publishes % 5 != 0) {
      snapshot.remove('queue');
    } else {
      _lastQueueSig = sig as String?;
      _forceQueue = false;
    }
    snapshot.remove('queueSig');
    unawaited(_send(null, ConnectMessage.state, snapshot));
  }

  Future<void> _onMessage(({String from, String blob}) raw) async {
    final crypto = _crypto;
    if (crypto == null) return;
    final IncomingConnectMessage message;
    try {
      final plain = await crypto.decrypt(raw.blob, docKey: _docKey);
      final body = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
      message = IncomingConnectMessage(
          raw.from, body['t'] as String, body, (body['n'] as num).toInt());
    } catch (_) {
      return; // No es de nuestro grupo o está corrupto.
    }
    final last = _lastCounter[message.from] ?? 0;
    if (message.counter <= last) return; // Repetido o fuera de orden.
    _lastCounter[message.from] = message.counter;
    switch (message.type) {
      case ConnectMessage.state:
        _states[message.from] = ConnectRemoteState.fromJson(
            message.body, _now(),
            previous: _states[message.from]);
        notifyListeners();
      case ConnectMessage.command:
        final cmd = message.body['cmd'];
        if (cmd is String && ConnectCommand.all.contains(cmd)) {
          final data = message.body['data'];
          await port.apply(cmd, message.body['value'] as num?,
              data is Map ? Map<String, dynamic>.from(data) : const {});
          _publishState();
        }
      case ConnectMessage.transfer:
        await _onTransfer(message);
      case ConnectMessage.handoff:
        await _onHandoff(message);
      case ConnectMessage.ack:
        final pending = _acks[message.from];
        if (pending != null && !pending.isCompleted) {
          pending.complete(message.body['ok'] == true);
        }
    }
  }

  Future<void> _onTransfer(IncomingConnectMessage message) async {
    final transfer = ConnectTransfer.tryParse(message.body);
    if (transfer == null || transfer.scope != port.scope) {
      await _send(message.from, ConnectMessage.ack, {'ok': false});
      return;
    }
    try {
      await port.adopt(transfer);
    } catch (error) {
      debugPrint('connect: no se pudo adoptar la cola: $error');
      await _send(message.from, ConnectMessage.ack, {'ok': false});
      return;
    }
    await _send(message.from, ConnectMessage.ack, {'ok': true});
    if (_controlledId == message.from) {
      _controlledId = null; // Nos devolvieron la reproducción.
      notifyListeners();
    }
    _publishState();
  }

  /// Otro dispositivo pide que le entreguemos (o entreguemos a un tercero) lo
  /// que suena aquí.
  Future<void> _onHandoff(IncomingConnectMessage message) async {
    final to = message.body['to'];
    final transfer = port.exportTransfer();
    if (to is! String || transfer == null) {
      await _send(message.from, ConnectMessage.ack, {'ok': to is String});
      return;
    }
    if (to == selfId) return;
    final ok = await _deliver(to, transfer);
    if (ok) await port.pauseLocal();
    await _send(message.from, ConnectMessage.ack, {'ok': ok});
  }
}
