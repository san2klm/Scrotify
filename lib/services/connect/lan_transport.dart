import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../jam_network_platform.dart';
import '../sync/sync_crypto.dart';
import 'connect_protocol.dart';
import 'connect_transport.dart';

/// Puerto UDP de las balizas de descubrimiento de Connect (Jam usa 47623).
const int kConnectLanPort = 47624;

typedef BeaconTarget = ({InternetAddress address, int port});

/// Descubre y habla con los dispositivos de la misma red local, sin pasar por
/// internet: cada equipo anuncia una baliza UDP y los pares abren un
/// WebSocket directo. Solo se aceptan pares que demuestran tener la clave de
/// sincronización (el saludo va cifrado), igual que en el relé.
class LanTransport implements ConnectTransport {
  LanTransport({
    required this.crypto,
    required this.selfId,
    required this.selfName,
    required this.selfKind,
    this.beaconPort = kConnectLanPort,
    this.beaconInterval = const Duration(seconds: 3),
    this.helloTimeout = const Duration(seconds: 5),
    Future<List<BeaconTarget>> Function(int port)? beaconTargets,
    this.useMulticastLock = true,
  }) : _targets = beaconTargets ?? _broadcastTargets;

  static const _helloKey = 'connect-lan-hello';
  static const _maxFrameChars = 256 * 1024;
  static const _maxPending = 8;

  final SyncCrypto crypto;
  final String selfId;
  final String selfName;
  final ConnectKind selfKind;
  final int beaconPort;
  final Duration beaconInterval;
  final Duration helloTimeout;
  final bool useMulticastLock;
  final Future<List<BeaconTarget>> Function(int port) _targets;

  final _devices = StreamController<List<ConnectDevice>>.broadcast();
  final _messages = StreamController<({String from, String blob})>.broadcast();
  final _peers = <String, _Peer>{};
  final _dialing = <String>{};
  final _beaconsHeard = <String, int>{};
  int _pending = 0;
  HttpServer? _server;
  RawDatagramSocket? _udp;
  Timer? _beaconTimer;
  bool _running = false;
  bool _lockHeld = false;
  String? _problem;

  /// Etiqueta de grupo de las balizas: no revela la clave ni el id de bóveda.
  late final String _tag = sha256
      .convert(utf8.encode('scrotify-connect-lan|${crypto.vaultId}'))
      .toString()
      .substring(0, 16);

  @override
  Stream<List<ConnectDevice>> get devices => _devices.stream;

  @override
  Stream<({String from, String blob})> get messages => _messages.stream;

  @override
  String? get problem => _problem;

  @override
  bool canReach(String deviceId) => _peers.containsKey(deviceId);

  /// Puerto TCP en el que escucha este dispositivo (para pruebas).
  int? get port => _server?.port;

  @override
  Future<void> start() async {
    if (_running) return;
    _running = true;
    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _server = server;
      server.listen(_onRequest, onError: (_) {});
      if (useMulticastLock) {
        _lockHeld = true;
        await JamNetworkPlatform.acquireMulticastReception();
      }
      final udp = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4, beaconPort,
          reuseAddress: true, reusePort: !Platform.isWindows);
      udp.broadcastEnabled = true;
      _udp = udp;
      udp.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = udp.receive()) != null) {
          _onBeacon(datagram!);
        }
      });
      _beaconTimer =
          Timer.periodic(beaconInterval, (_) => unawaited(_sendBeacon()));
      unawaited(_sendBeacon());
    } catch (error) {
      debugPrint('connect/lan: $error');
      _problem = 'No se pudo buscar dispositivos en la red local.';
      await stop();
      _running = false;
    }
  }

  @override
  Future<void> stop() async {
    _running = false;
    _beaconTimer?.cancel();
    _udp?.close();
    _udp = null;
    final server = _server;
    _server = null;
    await server?.close(force: true);
    for (final peer in _peers.values.toList()) {
      await peer.socket.close();
    }
    _peers.clear();
    _dialing.clear();
    _beaconsHeard.clear();
    _pending = 0;
    if (_lockHeld) {
      _lockHeld = false;
      await JamNetworkPlatform.releaseMulticastReception();
    }
    _devices.add(const []);
  }

  // ---------------------------------------------------------------------------
  // Baliza UDP
  // ---------------------------------------------------------------------------

  Future<void> _sendBeacon() async {
    final udp = _udp;
    final server = _server;
    if (udp == null || server == null) return;
    final payload = utf8.encode(jsonEncode({
      'app': 'scrotify-connect',
      'tag': _tag,
      'id': selfId,
      'name': selfName,
      'kind': selfKind.name,
      'port': server.port,
    }));
    for (final target in await _targets(beaconPort)) {
      try {
        udp.send(payload, target.address, target.port);
      } catch (_) {}
    }
  }

  static Future<List<BeaconTarget>> _broadcastTargets(int port) async {
    final targets = <BeaconTarget>[
      (address: InternetAddress('255.255.255.255'), port: port),
    ];
    try {
      final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            targets.add((
              address:
                  InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'),
              port: port,
            ));
          }
        }
      }
    } catch (_) {}
    return targets;
  }

  void _onBeacon(Datagram datagram) {
    if (!_running) return;
    try {
      final data =
          jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      if (data['app'] != 'scrotify-connect' || data['tag'] != _tag) return;
      final id = data['id'];
      final port = data['port'];
      if (id is! String || id == selfId || port is! int) return;
      if (_peers.containsKey(id) || _dialing.contains(id)) return;
      // Marca quién llama: el de id menor; el otro solo si la baliza del menor
      // no le llega (red asimétrica) tras varias balizas sin conexión.
      final heard = _beaconsHeard[id] = (_beaconsHeard[id] ?? 0) + 1;
      if (selfId.compareTo(id) < 0 || heard >= 4) {
        unawaited(_dial(datagram.address, port, id));
      }
    } catch (_) {
      // Baliza ajena o malformada.
    }
  }

  // ---------------------------------------------------------------------------
  // Conexiones directas
  // ---------------------------------------------------------------------------

  void _onRequest(HttpRequest request) async {
    if (request.uri.path != '/connect' ||
        !WebSocketTransformer.isUpgradeRequest(request) ||
        _pending >= _maxPending) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    try {
      final socket = await WebSocketTransformer.upgrade(request);
      _adopt(socket, outgoing: false);
    } catch (_) {}
  }

  Future<void> _dial(InternetAddress address, int port, String id) async {
    _dialing.add(id);
    try {
      final socket =
          await WebSocket.connect('ws://${address.address}:$port/connect')
              .timeout(const Duration(seconds: 5));
      if (!_running) {
        await socket.close();
        return;
      }
      _adopt(socket, outgoing: true);
    } catch (_) {
      // Se reintentará con la siguiente baliza.
    } finally {
      _dialing.remove(id);
    }
  }

  void _adopt(WebSocket socket, {required bool outgoing}) {
    socket.pingInterval = const Duration(seconds: 5);
    _pending++;
    var pendingCounted = true;
    void settle() {
      if (pendingCounted) {
        pendingCounted = false;
        _pending--;
      }
    }

    _Peer? peer;
    final timeout = Timer(helloTimeout, () {
      if (peer != null) return;
      // Un cliente que no lee no completa el cierre: se libera el cupo ya.
      settle();
      socket.close();
    });

    unawaited(() async {
      socket.add(jsonEncode({
        'hello': await crypto.encrypt(
            utf8.encode(jsonEncode(
                {'id': selfId, 'name': selfName, 'kind': selfKind.name})),
            docKey: _helloKey),
      }));
    }());

    // Los frames se procesan en serie: uno que llega mientras se descifra el
    // `hello` esperaba con `peer == null` y cerraba el socket.
    var chain = Future<void>.value();
    Future<void> handle(dynamic raw) async {
      if (raw is! String || raw.length > _maxFrameChars) {
        await socket.close();
        return;
      }
      try {
        final frame = jsonDecode(raw) as Map<String, dynamic>;
        if (peer == null) {
          final hello = frame['hello'];
          if (hello is! String) {
            await socket.close();
            return;
          }
          final info = jsonDecode(
                  utf8.decode(await crypto.decrypt(hello, docKey: _helloKey)))
              as Map<String, dynamic>;
          final id = info['id'];
          if (id is! String || id == selfId) {
            await socket.close();
            return;
          }
          timeout.cancel();
          settle();
          peer = _Peer(
            id,
            (info['name'] as String?) ?? 'Dispositivo',
            connectKindFrom(info['kind'] as String?),
            socket,
            outgoing,
          );
          _register(peer!);
        } else if (frame['msg'] is String) {
          _messages.add((from: peer!.id, blob: frame['msg'] as String));
        }
      } catch (_) {
        await socket.close(); // No es de nuestro grupo o está corrupto.
      }
    }

    socket.listen(
      (raw) {
        chain = chain.then((_) => handle(raw));
      },
      onDone: () {
        timeout.cancel();
        settle();
        final p = peer;
        if (p != null && identical(_peers[p.id], p)) {
          _peers.remove(p.id);
          _publish();
        }
      },
      onError: (_) => socket.close(),
      cancelOnError: true,
    );
  }

  /// Si ya hay una conexión con ese dispositivo se queda la iniciada por el
  /// de id menor (así los dos extremos eligen la misma y ninguno cierra la
  /// de ambos); si ambas son del mismo lado, la más reciente.
  void _register(_Peer candidate) {
    final existing = _peers[candidate.id];
    if (existing != null) {
      String dialer(_Peer p) => p.outgoing ? selfId : p.id;
      final keepCandidate = dialer(existing) == dialer(candidate) ||
          dialer(candidate).compareTo(dialer(existing)) < 0;
      if (!keepCandidate) {
        candidate.socket.close();
        return;
      }
      existing.socket.close();
    }
    _peers[candidate.id] = candidate;
    _beaconsHeard.remove(candidate.id);
    _publish();
  }

  void _publish() {
    _devices.add([
      for (final p in _peers.values)
        ConnectDevice(id: p.id, name: p.name, kind: p.kind, viaLan: true),
    ]);
  }

  @override
  Future<void> send(String? deviceId, String blob) async {
    final frame = jsonEncode({'msg': blob});
    if (deviceId == null) {
      for (final p in _peers.values) {
        p.socket.add(frame);
      }
    } else {
      _peers[deviceId]?.socket.add(frame);
    }
  }
}

class _Peer {
  _Peer(this.id, this.name, this.kind, this.socket, this.outgoing);
  final String id;
  final String name;
  final ConnectKind kind;
  final WebSocket socket;
  final bool outgoing;
}
