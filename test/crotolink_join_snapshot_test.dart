// La unión de un invitado LAN solo se da por hecha cuando llega el primer
// estado de la sala (crotolink_state_snapshot), no con la simple aceptación
// (join_response). Se usa un anfitrión falso con TLS para controlar el orden y
// el momento de cada mensaje.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/models/crotolink_models.dart';
import 'package:crotowave/services/crotolink_controller.dart';
import 'package:crotowave/services/crotolink_guest_service.dart';
import 'package:crotowave/services/crotolink_tls_identity.dart';

import 'support/app_fakes.dart';

/// Cómo contesta el anfitrión falso a `join_request`.
enum _Script {
  /// join_response sin estado y, tras una pausa, el snapshot.
  responseThenDelayedSnapshot,

  /// join_response con el estado dentro.
  responseWithState,

  /// join_response sin estado y nunca llega el snapshot.
  responseOnly,

  /// join_response rechazando.
  reject,
}

class _FakeHost {
  _FakeHost(this.script, {this.snapshotDelay = Duration.zero});

  final _Script script;
  final Duration snapshotDelay;
  late final HttpServer server;
  late final CrotoLinkTlsIdentity identity;
  final received = <String>[];
  final sockets = <WebSocket>[];

  int get port => server.port;
  String get fingerprint => identity.fingerprintSha256;

  static const participant = {
    'id': 'p1',
    'name': 'Lucía',
    'avatarColorValue': 0xFF10B981,
    'isHost': false,
    'joinedAt': '2026-10-09T12:00:00.000',
    'canControlPlayback': true,
    'canManageQueue': true,
  };

  Map<String, dynamic> state() => CrotoLinkSessionState(
        sessionId: 's1',
        pinCode: 'JK94MN',
        hostName: 'Host',
        hostIp: '127.0.0.1',
        port: port,
        mode: CrotoLinkMode.partySpeaker,
        isPlaying: false,
        positionMs: 0,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        queue: const [],
        participants: [CrotoLinkParticipant.fromJson(participant)],
      ).toJson();

  Future<void> start() async {
    identity = CrotoLinkTlsIdentity.generate();
    final context = SecurityContext()
      ..useCertificateChainBytes(identity.certificatePem)
      ..usePrivateKeyBytes(identity.privateKeyPem);
    server =
        await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
    server.listen((request) async {
      if (request.uri.path != '/crotolink/ws') {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((data) {
        final message = jsonDecode(data as String) as Map<String, dynamic>;
        received.add(message['op'] as String);
        if (message['op'] == 'join_request') _answer(socket);
      });
    });
  }

  void _answer(WebSocket socket) {
    if (script == _Script.reject) {
      socket.add(jsonEncode({
        'op': 'join_response',
        'accepted': false,
        'reason': 'PIN no válido'
      }));
      return;
    }
    socket.add(jsonEncode({
      'op': 'join_response',
      'accepted': true,
      'token': 'tok',
      'assignedParticipant': participant,
      if (script == _Script.responseWithState) 'state': state(),
    }));
    if (script == _Script.responseThenDelayedSnapshot) {
      Timer(snapshotDelay, () {
        if (socket.readyState == WebSocket.open) {
          socket.add(jsonEncode({
            'op': 'crotolink_state_snapshot',
            'sessionId': 's1',
            'state': state(),
            'assignedParticipant': participant,
            'queueRevision': 0,
          }));
        }
      });
    }
  }

  Future<void> stop() async {
    for (final s in sockets) {
      await s.close();
    }
    await server.close(force: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // El binding de pruebas simula HTTP; aquí se necesita el socket real.
  setUpAll(() => HttpOverrides.global = null);

  late _FakeHost host;
  late CrotoLinkGuestService guest;

  Future<_FakeHost> start(_Script script,
      {Duration snapshotDelay = Duration.zero}) async {
    host = _FakeHost(script, snapshotDelay: snapshotDelay);
    await host.start();
    return host;
  }

  setUp(() => guest = CrotoLinkGuestService());
  tearDown(() async {
    await guest.disconnect();
    await host.stop();
  });

  Future<bool> connect() => guest.connect(
        host: '127.0.0.1',
        port: host.port,
        pin: 'JK94MN',
        name: 'Lucía',
        avatarColorValue: 0xFF10B981,
        tlsFingerprint: host.fingerprint,
      );

  group('CrotoLinkGuestService.connect', () {
    test('espera al primer snapshot aunque la aceptación llegue antes',
        () async {
      await start(_Script.responseThenDelayedSnapshot,
          snapshotDelay: const Duration(milliseconds: 400));
      final synced = <CrotoLinkSessionState>[];
      guest.onStateSync = synced.add;

      final started = DateTime.now();
      final ok = await connect();
      final took = DateTime.now().difference(started);

      expect(ok, isTrue);
      expect(took, greaterThanOrEqualTo(const Duration(milliseconds: 350)),
          reason: 'no debe devolver antes de tener el estado');
      expect(guest.sessionState, isNotNull,
          reason: 'al devolver true ya hay sesión');
      expect(guest.sessionState!.hostName, 'Host');
      expect(synced, isNotEmpty);
      expect(guest.isConnected, isTrue);
    });

    test('si la aceptación ya trae el estado no espera más', () async {
      await start(_Script.responseWithState);
      final started = DateTime.now();
      final ok = await connect();
      expect(ok, isTrue);
      expect(DateTime.now().difference(started),
          lessThan(const Duration(seconds: 2)));
      expect(guest.sessionState, isNotNull);
    });

    test('si el estado nunca llega falla limpio, con un motivo claro',
        () async {
      await start(_Script.responseOnly);
      guest.joinStateTimeout = const Duration(milliseconds: 400);

      final ok = await connect();

      expect(ok, isFalse);
      expect(guest.lastError, contains('estado de la sala'));
      expect(guest.isConnected, isFalse, reason: 'queda desconectado');
      expect(guest.sessionState, isNull);
    });

    test('un rechazo sigue devolviendo false enseguida con su motivo',
        () async {
      await start(_Script.reject);
      final started = DateTime.now();
      final ok = await connect();
      expect(ok, isFalse);
      expect(guest.lastError, 'PIN no válido');
      expect(DateTime.now().difference(started),
          lessThan(const Duration(seconds: 2)));
    });
  });

  group('CrotoLinkController.joinSession', () {
    test('al terminar la unión la sesión ya existe', () async {
      await start(_Script.responseThenDelayedSnapshot,
          snapshotDelay: const Duration(milliseconds: 300));
      final controller = CrotoLinkController(IdlePlayer(), FakeNavidrome());
      addTearDown(() async {
        await controller.leaveOrEndSession();
        controller.dispose();
      });

      final joined = await controller.joinSession(
        host: '127.0.0.1',
        port: host.port,
        pin: 'JK94MN',
        customName: 'Lucía',
        tlsFingerprint: host.fingerprint,
      );

      expect(joined, isTrue);
      expect(controller.session, isNotNull,
          reason: 'justo tras unirse debe haber estado');
      expect(controller.notificationInfo, isNotNull);
      expect(controller.notificationInfo!.hostName, 'Host');
    });

    test(
        'si el anfitrión no manda estado, la unión falla y no deja sala a medias',
        () async {
      await start(_Script.responseOnly);
      final controller = CrotoLinkController(IdlePlayer(), FakeNavidrome());
      addTearDown(() async {
        await controller.leaveOrEndSession();
        controller.dispose();
      });

      final joined = await controller.joinSession(
        host: '127.0.0.1',
        port: host.port,
        pin: 'JK94MN',
        customName: 'Lucía',
        tlsFingerprint: host.fingerprint,
      );

      expect(joined, isFalse);
      expect(controller.session, isNull);
      expect(controller.inCrotoLink, isFalse);
      expect(controller.lastJoinError, isNotNull);
    }, timeout: const Timeout(Duration(seconds: 40)));
  });
}
