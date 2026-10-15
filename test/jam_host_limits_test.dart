import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/models/jam_models.dart';
import 'package:navidrome_client/services/jam_guest_service.dart';
import 'package:navidrome_client/services/jam_host_service.dart';

void main() {
  late JamHostService host;

  setUp(() async {
    host = JamHostService();
    await host.start(
        sessionId: 's', pinCode: JamCode('JK94MN'), hostName: 'Host');
  });

  tearDown(() async => host.stop());

  Future<WebSocket> open() {
    final client = HttpClient()..badCertificateCallback = (_, __, ___) => true;
    return WebSocket.connect('wss://127.0.0.1:${host.port}/jam/ws',
        customClient: client);
  }

  Future<int?> closeCodeOf(WebSocket socket, Duration limit) async {
    final done = Completer<int?>();
    socket.listen((_) {}, onDone: () => done.complete(socket.closeCode));
    return done.future.timeout(limit, onTimeout: () => null);
  }

  test('un frame de 1 MB cierra el socket y el anfitrión sigue atendiendo',
      () async {
    final big = await open();
    big.add('x' * (1024 * 1024));
    expect(await closeCodeOf(big, const Duration(seconds: 3)),
        WebSocketStatus.messageTooBig);

    final ok = await open();
    ok.add(jsonEncode({'op': 'time_ping', 'clientTs': 1}));
    final reply = await ok.first.timeout(const Duration(seconds: 3));
    expect(jsonDecode(reply as String)['op'], 'time_pong');
    await ok.close();
  });

  test('un socket que no saluda en pocos segundos se cierra', () async {
    final idle = await open();
    final code = await closeCodeOf(idle, const Duration(seconds: 8));
    expect(code, WebSocketStatus.policyViolation);
  });

  Future<Map<String, dynamic>> joinWith(WebSocket socket, String pin) async {
    final reply = socket
        .map((d) => jsonDecode(d as String) as Map<String, dynamic>)
        .firstWhere((m) => m['op'] == 'join_response');
    socket.add(jsonEncode({
      'op': 'join_request',
      'pin': pin,
      'name': 'Ana',
      'avatarColorValue': 0xFF10B981,
    }));
    return reply.timeout(const Duration(seconds: 3));
  }

  test('un PIN erróneo se rechaza con código tipado bad_pin', () async {
    final socket = await open();
    final reply = await joinWith(socket, 'ZZZZZZ');
    expect(reply['accepted'], isFalse);
    expect(reply['code'], 'bad_pin');
  });

  test('un invitado en gracia no es desalojado por el heartbeat', () async {
    final socket = await open();
    final reply = await joinWith(socket, 'JK94MN');
    expect(reply['accepted'], isTrue);
    expect(host.participants, hasLength(1));

    await socket.close();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    // Pasan 40 s: más que ping + pong (25 s), menos que la gracia efectiva.
    host.checkHeartbeatAndPing(DateTime.now().add(const Duration(seconds: 40)));
    expect(host.participants, hasLength(1));
  });

  test('la gracia del anfitrión cubre el silencio que tolera el invitado', () {
    // Si la gracia fuera menor, el anfitrión descartaría al invitado mientras
    // éste aún está reconectando.
    expect(host.disconnectGracePeriod,
        greaterThanOrEqualTo(JamGuestService().hostSilenceTimeout));
  });

  test('un elemento mal formado no descarta el snapshot entero', () {
    final state = JamSessionState.fromJson({
      'sessionId': 's',
      'pinCode': 'JK94MN',
      'participants': [
        {'id': 'p1', 'name': 'Ana'},
        {'id': 7, 'name': null}, // mal formado
        {'id': 'p2', 'name': 'Luis'},
      ],
      'queue': [
        'basura',
        {
          'queueItemId': 'q1',
          'track': {'id': 't1', 'title': 'T'}
        },
      ],
    });
    expect(state.participants.map((p) => p.id), ['p1', 'p2']);
  });
}
