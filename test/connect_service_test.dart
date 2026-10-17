import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/connect/connect_protocol.dart';
import 'package:crotowave/services/connect/connect_service.dart';
import 'package:crotowave/services/connect/connect_transport.dart';
import 'package:crotowave/services/sync/sync_crypto.dart';

/// Red en memoria: entrega mensajes entre transportes del mismo "medio".
class FakeNetwork {
  final transports = <String, FakeTransport>{};
  final devices = <String, ConnectDevice>{};

  FakeTransport join(String id, String name, ConnectKind kind,
      {bool lan = false}) {
    final transport = FakeTransport(this, id, lan: lan);
    transports[id] = transport;
    devices[id] = ConnectDevice(
        id: id, name: name, kind: kind, viaLan: lan, viaRelay: !lan);
    return transport;
  }

  void refresh() {
    for (final t in transports.values) {
      if (!t.running) continue;
      t._devices.add([
        for (final d in devices.values)
          if (d.id != t.id && transports[d.id]!.running) d,
      ]);
    }
  }
}

class FakeTransport implements ConnectTransport {
  FakeTransport(this.network, this.id, {required this.lan});
  final FakeNetwork network;
  final String id;
  final bool lan;
  bool running = false;
  final _devices = StreamController<List<ConnectDevice>>.broadcast();
  final _messages = StreamController<({String from, String blob})>.broadcast();
  final sent = <String>[];

  @override
  Stream<List<ConnectDevice>> get devices => _devices.stream;
  @override
  Stream<({String from, String blob})> get messages => _messages.stream;
  @override
  String? get problem => null;
  @override
  bool canReach(String deviceId) =>
      running && (network.transports[deviceId]?.running ?? false);
  @override
  Future<void> start() async {
    running = true;
    network.refresh();
  }

  @override
  Future<void> stop() async {
    running = false;
    network.refresh();
  }

  @override
  Future<void> send(String? deviceId, String blob) async {
    sent.add(blob);
    for (final peer in network.transports.values) {
      if (peer.id == id || !peer.running) continue;
      if (deviceId == null || deviceId == peer.id) {
        scheduleMicrotask(() => peer._messages.add((from: id, blob: blob)));
      }
    }
  }
}

class FakePort extends ChangeNotifier implements ConnectPlayerPort {
  FakePort(this.scope);
  @override
  String? scope;
  Map<String, dynamic>? track;
  bool playing = false;
  int positionMs = 0;
  double volume = 1;
  final applied = <String>[];
  final appliedData = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> queue = [];
  int queueIndex = 0;
  int queueSerial = 0;
  bool pausedLocal = false;
  bool failAdopt = false;

  /// Cola completa que exporta al transferir (si no, solo la pista actual).
  List<Map<String, dynamic>>? exportQueue;
  int adoptedCount = 0;
  final appendedSeqs = <int>[];
  final queueIds = <String>[];
  final _chunks = ConnectQueueReceiver();

  @override
  Map<String, dynamic>? snapshot() => track == null
      ? null
      : {
          'scope': scope,
          'track': track,
          'playing': playing,
          'positionMs': positionMs,
          'durationMs': 200000,
          'volume': volume,
          'queue': queue,
          'queueSig': '$queueSerial',
          'offset': 3,
          'index': queueIndex,
          'shuffle': false,
          'repeat': 'off',
        };

  @override
  ConnectTransfer? exportTransfer() => track == null
      ? null
      : ConnectTransfer(
          scope: scope!,
          tracks: exportQueue ?? [track!],
          index: 0,
          positionMs: positionMs,
          playing: playing);

  @override
  Future<void> adopt(ConnectTransfer transfer) async {
    if (failAdopt) throw StateError('no se pudo');
    track = transfer.tracks[transfer.index];
    adoptedCount = transfer.tracks.length;
    queueIds
      ..clear()
      ..addAll([for (final t in transfer.tracks) t['id'] as String]);
    _chunks.expect(transfer.xfer, transfer.more);
    positionMs = transfer.positionMs;
    playing = transfer.playing;
    pausedLocal = false;
    notifyListeners();
  }

  @override
  Future<void> apply(
      String command, num? value, Map<String, dynamic> data) async {
    applied.add(value == null ? command : '$command:$value');
    if (data.isNotEmpty) appliedData.add(data);
    if (command == ConnectCommand.queueAppend) {
      final more = _chunks.accept(data, scope);
      if (more != null) {
        appendedSeqs.add(data['seq'] as int);
        queueIds.addAll([for (final t in more) t['id'] as String]);
      }
    }
    if (command == ConnectCommand.toggle) playing = !playing;
    notifyListeners();
  }

  @override
  Future<void> pauseLocal() async {
    playing = false;
    pausedLocal = true;
    notifyListeners();
  }
}

class Node {
  Node(this.network, String id, String name, ConnectKind kind, this.port,
      {bool lan = false, SyncCrypto? crypto}) {
    transport = network.join(id, name, kind, lan: lan);
    service = ConnectService(
      port: port,
      selfId: id,
      transportsFor: (_) => [transport],
      ackTimeout: const Duration(milliseconds: 300),
      stateInterval: const Duration(days: 1),
    );
  }
  final FakeNetwork network;
  late final FakeTransport transport;
  late final ConnectService service;
  final FakePort port;
}

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }
}

const song = {'id': 's1', 'title': 'SUTRA', 'artist': 'Sebastian Yatra'};

void main() {
  late SyncCrypto crypto;
  late FakeNetwork net;
  late Node phone;
  late Node pc;

  setUp(() async {
    crypto = await SyncCrypto.fromSecret(SyncKey.generate(Random(7)));
    net = FakeNetwork();
    phone = Node(
        net, 'phone-0001', 'Teléfono', ConnectKind.phone, FakePort('srv-1'));
    pc = Node(net, 'desktop-001', 'PC', ConnectKind.desktop, FakePort('srv-1'));
    await phone.service.configure(crypto);
    await pc.service.configure(crypto);
    await settle();
  });

  test('los dispositivos se descubren entre sí', () {
    expect(phone.service.devices.map((d) => d.name), ['PC']);
    expect(pc.service.devices.map((d) => d.name), ['Teléfono']);
    expect(phone.service.devices.single.kind, ConnectKind.desktop);
  });

  test('transferir mueve la cola, pausa el origen y deja de mando', () async {
    phone.port
      ..track = {...song}
      ..playing = true
      ..positionMs = 42000;
    await phone.service.transferTo('desktop-001');
    await settle();

    expect(pc.port.track?['id'], 's1');
    expect(pc.port.playing, isTrue);
    expect(pc.port.positionMs, 42000);
    expect(phone.port.pausedLocal, isTrue);
    expect(phone.service.controlled?.id, 'desktop-001');
    // El PC publica lo que suena y el teléfono lo muestra.
    expect(phone.service.controlledState?.track?.title, 'SUTRA');
    expect(phone.service.controlledState?.playing, isTrue);
  });

  test('los comandos del controlador se ejecutan en el dispositivo remoto',
      () async {
    phone.port
      ..track = {...song}
      ..playing = true;
    await phone.service.transferTo('desktop-001');
    await settle();

    phone.service
      ..command(ConnectCommand.next)
      ..command(ConnectCommand.seek, 90000)
      ..command(ConnectCommand.volume, 0.4)
      ..command('rm -rf'); // desconocido: no se envía
    await settle();
    expect(pc.port.applied, ['next', 'seek:90000', 'volume:0.4']);
    expect(phone.port.applied, isEmpty);
  });

  test('traer de vuelta recupera la reproducción en este dispositivo',
      () async {
    phone.port
      ..track = {...song}
      ..playing = true;
    await phone.service.transferTo('desktop-001');
    await settle();
    pc.port.positionMs = 120000;

    await phone.service.bringHere();
    await settle();

    expect(phone.service.controlled, isNull);
    expect(phone.port.playing, isTrue);
    expect(phone.port.positionMs, 120000);
    expect(pc.port.pausedLocal, isTrue);
  });

  test('con otro servidor Navidrome no se transfiere y el origen sigue sonando',
      () async {
    pc.port.scope = 'srv-2';
    phone.port
      ..track = {...song}
      ..playing = true;
    await phone.service.transferTo('desktop-001');
    await settle();

    expect(phone.service.controlled, isNull);
    expect(phone.port.pausedLocal, isFalse);
    expect(phone.port.playing, isTrue);
    expect(phone.service.lastError, contains('no respondió'));
  });

  test('si el destino no responde se avisa y no se pierde la reproducción',
      () async {
    await pc.service.configure(null); // el PC deja de escuchar
    await settle();
    phone.port
      ..track = {...song}
      ..playing = true;
    // El PC desapareció de la lista: no hay a quién transferir.
    await phone.service.transferTo('desktop-001');
    expect(phone.port.pausedLocal, isFalse);
  });

  test('ignora mensajes de otra clave y repeticiones', () async {
    final stranger = await SyncCrypto.fromSecret(SyncKey.generate(Random(99)));
    final blob = await stranger.encrypt(
        [...'{"t":"cmd","cmd":"next","n":5}'.codeUnits],
        docKey: 'connect');
    pc.transport._messages.add((from: 'phone-0001', blob: blob));
    await settle();
    expect(pc.port.applied, isEmpty);

    // Un mensaje legítimo capturado y reenviado se aplica una sola vez.
    phone.port
      ..track = {...song}
      ..playing = true;
    await phone.service.transferTo('desktop-001');
    await settle();
    phone.service.command(ConnectCommand.next);
    await settle();
    final captured = phone.transport.sent.last;
    pc.transport._messages.add((from: 'phone-0001', blob: captured));
    await settle();
    expect(pc.port.applied, ['next']);
  });

  test('si el dispositivo controlado desaparece se libera el control',
      () async {
    phone.port
      ..track = {...song}
      ..playing = true;
    await phone.service.transferTo('desktop-001');
    await settle();
    await pc.service.configure(null);
    await settle();
    expect(phone.service.controlled, isNull);
    expect(phone.service.lastError, contains('Se perdió'));
  });

  test('la cola viaja solo cuando cambia y se conserva en el controlador',
      () async {
    pc.port
      ..track = {...song}
      ..playing = true
      ..queue = [
        {'id': 'q1', 'title': 'Uno'},
        {'id': 'q2', 'title': 'Dos'},
      ]
      ..queueIndex = 1;
    phone.port
      ..track = {...song}
      ..playing = true;
    await phone.service.transferTo('desktop-001');
    await settle();
    final first = phone.service.controlledState!;
    expect(first.queue.map((t) => t['id']), ['q1', 'q2']);
    expect(first.queueOffset, 3);
    expect(first.index, 1);

    // Mismo contenido: el estado siguiente no trae la cola pero se conserva.
    pc.port
      ..positionMs = 5000
      ..queueIndex = 0;
    pc.port.notifyListeners();
    await settle();
    final second = phone.service.controlledState!;
    expect(second.queue.map((t) => t['id']), ['q1', 'q2']);
    expect(second.index, 0);
    expect(second.positionMs, 5000);

    // Cola nueva: reemplaza la anterior.
    pc.port
      ..queue = [
        {'id': 'q9', 'title': 'Nueve'}
      ]
      ..queueSerial = 1;
    pc.port.notifyListeners();
    await settle();
    expect(phone.service.controlledState!.queue.single['id'], 'q9');
  });

  test('los comandos de cola llegan con sus datos al dispositivo remoto',
      () async {
    phone.port
      ..track = {...song}
      ..playing = true;
    await phone.service.transferTo('desktop-001');
    await settle();
    phone.service
      ..command(ConnectCommand.playQueue, null, {
        'scope': 'srv-1',
        'tracks': [song],
        'index': 0
      })
      ..command(ConnectCommand.queueMove, null, {'from': 4, 'to': 6})
      ..command(ConnectCommand.queueRemove, 7)
      ..command(ConnectCommand.shuffle);
    await settle();
    expect(pc.port.applied,
        ['play_queue', 'queue_move', 'queue_remove:7', 'shuffle']);
    expect(pc.port.appliedData[1], {'from': 4, 'to': 6});
  });

  test('un dispositivo por LAN y por relé aparece una sola vez', () async {
    final lanNet = FakeNetwork();
    final a = Node(
        lanNet, 'phone-0001', 'Teléfono', ConnectKind.phone, FakePort('s'));
    final lanDevices = StreamController<List<ConnectDevice>>.broadcast();
    // Servicio con dos transportes que ven al mismo dispositivo.
    final service = ConnectService(
      port: a.port,
      selfId: 'phone-0001',
      transportsFor: (_) =>
          [_Static(lanDevices.stream, lan: true), _Static(lanDevices.stream)],
    );
    await service.configure(crypto);
    lanDevices.add([
      const ConnectDevice(
          id: 'desktop-001',
          name: 'PC',
          kind: ConnectKind.desktop,
          viaLan: true),
    ]);
    await settle();
    expect(service.devices, hasLength(1));
    expect(service.devices.single.viaLan, isTrue);
  });
}

class _Static implements ConnectTransport {
  _Static(this._stream, {this.lan = false});
  final Stream<List<ConnectDevice>> _stream;
  final bool lan;
  @override
  Stream<List<ConnectDevice>> get devices => _stream;
  @override
  Stream<({String from, String blob})> get messages => const Stream.empty();
  @override
  String? get problem => null;
  @override
  bool canReach(String deviceId) => false;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> send(String? deviceId, String blob) async {}
}
