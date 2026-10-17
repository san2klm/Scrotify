import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/connect/connect_account.dart';
import 'package:navidrome_client/services/connect/connect_protocol.dart';
import 'package:navidrome_client/services/connect/relay_transport.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Extremo del servidor en memoria: lo que el cliente envía llega a [sent] y lo
/// que se mete en [fromServer] lo recibe el cliente.
class _FakeChannel implements WebSocketChannel {
  final fromServer = StreamController<dynamic>();
  final sent = <Map<String, dynamic>>[];
  bool sinkClosed = false;
  @override
  int? closeCode;
  @override
  String? closeReason;

  late final _sink = _FakeSink(this);

  @override
  Stream<dynamic> get stream => fromServer.stream;

  @override
  WebSocketSink get sink => _sink;

  /// El servidor cierra la conexión con un código.
  Future<void> serverClose(int code, [String reason = '']) async {
    closeCode = code;
    closeReason = reason;
    await fromServer.close();
  }

  void serverSends(Map<String, dynamic> message) =>
      fromServer.add(jsonEncode(message));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this.channel);
  final _FakeChannel channel;

  @override
  void add(dynamic data) =>
      channel.sent.add(jsonDecode(data as String) as Map<String, dynamic>);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    channel.sinkClosed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> pumpEvents() => Future<void>.delayed(Duration.zero);

void main() {
  const account = ConnectAccount(user: 'Ana', password: 'clave');
  final server = Uri.parse('wss://jam.test/');
  late List<_FakeChannel> channels;
  late List<Uri> dialed;
  var connectThrows = false;

  RelayTransport make({Duration retry = const Duration(milliseconds: 20)}) =>
      RelayTransport(
        account: account,
        serverUrl: server,
        selfId: 'me-0001',
        selfName: 'Mi PC',
        selfKind: ConnectKind.desktop,
        retryDelay: retry,
        connect: (uri) {
          dialed.add(uri);
          if (connectThrows) throw StateError('sin red');
          final channel = _FakeChannel();
          channels.add(channel);
          return channel;
        },
      );

  setUp(() {
    channels = [];
    dialed = [];
    connectThrows = false;
  });

  test('al arrancar se une con la cuenta, el id y el nombre del dispositivo',
      () async {
    final relay = make();
    await relay.start();
    addTearDown(relay.stop);

    expect(dialed, [server]);
    final join = channels.single.sent.single;
    expect(join['action'], 'connect_join');
    expect(join['user'], 'Ana');
    expect(join['deviceId'], 'me-0001');
    expect(join['name'], 'Mi PC');
    expect(join['kind'], 'desktop');
    // Se envía un token con salt (nunca la contraseña).
    final salt = join['salt'] as String;
    expect(join['token'], md5.convert(utf8.encode('clave$salt')).toString());
    expect(jsonEncode(join), isNot(contains('"clave"')));
  });

  test('publica los demás dispositivos, sin el propio, y los marca como relé',
      () async {
    final relay = make();
    final lists = <List<ConnectDevice>>[];
    relay.devices.listen(lists.add);
    await relay.start();
    addTearDown(relay.stop);

    channels.single.serverSends({
      'status': 'connect_joined',
      'devices': [
        {'deviceId': 'me-0001', 'name': 'Mi PC', 'kind': 'desktop'},
        {'deviceId': 'tel-0002', 'name': 'Teléfono', 'kind': 'phone'},
        {'deviceId': 'raro-3', 'kind': 'nave'},
        {'name': 'sin id'},
        'basura',
      ],
    });
    await pumpEvents();

    final devices = lists.last;
    expect(devices.map((d) => d.id), ['tel-0002', 'raro-3']);
    expect(devices.first.name, 'Teléfono');
    expect(devices.first.kind, ConnectKind.phone);
    expect(devices.every((d) => d.viaRelay && !d.viaLan), isTrue);
    expect(devices.last.name, 'Dispositivo', reason: 'nombre por defecto');
    expect(devices.last.kind, ConnectKind.other, reason: 'tipo desconocido');
    expect(relay.problem, isNull);
  });

  test('connect_devices actualiza la lista y canReach la refleja', () async {
    final relay = make();
    await relay.start();
    addTearDown(relay.stop);
    final channel = channels.single;
    expect(relay.canReach('tel-0002'), isFalse, reason: 'aún sin unirse');

    channel.serverSends({
      'event': 'connect_devices',
      'devices': [
        {'deviceId': 'tel-0002', 'name': 'T', 'kind': 'phone'}
      ],
    });
    await pumpEvents();
    expect(relay.canReach('tel-0002'), isTrue);
    expect(relay.canReach('otro'), isFalse);

    channel.serverSends({'event': 'connect_devices', 'devices': []});
    await pumpEvents();
    expect(relay.canReach('tel-0002'), isFalse);
  });

  test('send reparte a un dispositivo o a todos y no envía antes de unirse',
      () async {
    final relay = make();
    await relay.start();
    addTearDown(relay.stop);
    final channel = channels.single;

    await relay.send('tel-0002', 'blob-a');
    expect(channel.sent.length, 1, reason: 'solo el join: aún no unido');

    channel.serverSends({'status': 'connect_joined', 'devices': []});
    await pumpEvents();
    await relay.send('tel-0002', 'blob-b');
    await relay.send(null, 'blob-c');

    expect(channel.sent[1],
        {'action': 'connect_send', 'to': 'tel-0002', 'blob': 'blob-b'});
    expect(channel.sent[2],
        {'action': 'connect_send', 'to': '*', 'blob': 'blob-c'});
  });

  test('entrega los mensajes cifrados recibidos y descarta los mal formados',
      () async {
    final relay = make();
    final received = <({String from, String blob})>[];
    relay.messages.listen(received.add);
    await relay.start();
    addTearDown(relay.stop);
    final channel = channels.single;

    channel.serverSends({'event': 'connect_msg', 'from': 'tel', 'blob': 'xyz'});
    channel.serverSends({'event': 'connect_msg', 'from': 5, 'blob': 'xyz'});
    channel.serverSends({'event': 'connect_msg', 'from': 'tel'});
    channel.fromServer.add('esto no es json');
    channel.fromServer.add(42);
    channel.serverSends({'event': 'otra_cosa'});
    await pumpEvents();

    expect(received, [(from: 'tel', blob: 'xyz')]);
  });

  test('connect_error muestra el motivo y vacía la lista', () async {
    final relay = make();
    final lists = <List<ConnectDevice>>[];
    relay.devices.listen(lists.add);
    await relay.start();
    addTearDown(relay.stop);

    channels.single.serverSends(
        {'status': 'connect_error', 'message': 'Credenciales rechazadas'});
    await pumpEvents();
    expect(relay.problem, 'Credenciales rechazadas');
    expect(lists.last, isEmpty);

    channels.single.serverSends({'status': 'connect_error'});
    await pumpEvents();
    expect(relay.problem, 'El servidor rechazó Connect.');
  });

  test('si el servidor se cae reintenta y limpia dispositivos y problema',
      () async {
    final relay = make();
    final lists = <List<ConnectDevice>>[];
    relay.devices.listen(lists.add);
    await relay.start();
    addTearDown(relay.stop);
    channels.single.serverSends({
      'status': 'connect_joined',
      'devices': [
        {'deviceId': 'tel-0002', 'name': 'T', 'kind': 'phone'}
      ],
    });
    await pumpEvents();
    expect(relay.canReach('tel-0002'), isTrue);

    await channels.single.serverClose(1006);
    await pumpEvents();
    expect(relay.canReach('tel-0002'), isFalse);
    expect(lists.last, isEmpty);
    expect(relay.problem, 'Sin conexión con el servidor CrotoLink.');

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(channels.length, greaterThanOrEqualTo(2), reason: 'reconectó');
    expect(channels.last.sent.single['action'], 'connect_join');

    channels.last.serverSends({'status': 'connect_joined', 'devices': []});
    await pumpEvents();
    expect(relay.problem, isNull, reason: 'al unirse se borra el problema');
  });

  test('el código 4000 (otra ventana) no reintenta y explica por qué',
      () async {
    final relay = make();
    await relay.start();
    addTearDown(relay.stop);

    await channels.single.serverClose(4000, 'desplazado');
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(channels.length, 1, reason: 'sin pelea entre ventanas');
    expect(relay.problem, contains('otra ventana'));
  });

  test('si no se puede ni abrir el canal reintenta con la espera indicada',
      () async {
    connectThrows = true;
    final relay = make(retry: const Duration(milliseconds: 15));
    await relay.start();
    addTearDown(relay.stop);
    await Future<void>.delayed(const Duration(milliseconds: 90));

    expect(dialed.length, greaterThanOrEqualTo(3));
    expect(relay.problem, 'Sin conexión con el servidor CrotoLink.');

    connectThrows = false;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(channels, isNotEmpty, reason: 'termina conectando al volver la red');
  });

  test('stop cierra, vacía la lista y no vuelve a conectar', () async {
    final relay = make();
    final lists = <List<ConnectDevice>>[];
    relay.devices.listen(lists.add);
    await relay.start();
    final channel = channels.single;
    channel.serverSends({
      'status': 'connect_joined',
      'devices': [
        {'deviceId': 'tel-0002', 'name': 'T', 'kind': 'phone'}
      ],
    });
    await pumpEvents();

    await relay.stop();
    await pumpEvents(); // los streams entregan en el turno siguiente
    expect(channel.sinkClosed, isTrue);
    expect(lists.last, isEmpty);
    expect(relay.canReach('tel-0002'), isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(channels.length, 1);
    await relay.send(null, 'x'); // no lanza ni envía
    expect(channel.sent.length, 1);
  });

  test('stop durante una espera de reintento cancela el reintento', () async {
    final relay = make(retry: const Duration(milliseconds: 30));
    await relay.start();
    await channels.single.serverClose(1006);
    await pumpEvents();
    await relay.stop();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(channels.length, 1);
  });

  test('el reintento crece de forma exponencial, con jitter y tope de 60 s', () {
    final relay = make(retry: const Duration(seconds: 5));
    final waits = [for (var i = 0; i < 8; i++) relay.nextRetryDelay()];
    expect(waits.first.inMilliseconds, inInclusiveRange(5000, 7500));
    expect(waits[1].inMilliseconds, inInclusiveRange(10000, 12500));
    expect(waits[2].inMilliseconds, inInclusiveRange(20000, 22500));
    for (final w in waits) {
      expect(w.inMilliseconds, lessThanOrEqualTo(60000 + 2500));
    }
    expect(waits.last.inMilliseconds, greaterThanOrEqualTo(60000));
  });
}
