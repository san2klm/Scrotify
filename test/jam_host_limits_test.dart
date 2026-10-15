import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/models/jam_models.dart';
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
}
