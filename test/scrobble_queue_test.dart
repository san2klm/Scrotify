import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:crotowave/services/navidrome_service.dart';
import 'package:crotowave/services/scrobble_queue.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('scrobble-'));
  tearDown(() async => await tmp.delete(recursive: true));

  test('la cola sobrevive a reiniciar y envía en orden hasta el primer fallo',
      () async {
    final file = File(p.join(tmp.path, 'q.json'));
    final q = ScrobbleQueue(file);
    await q.add('a', 100);
    await q.add('b', 200);
    await q.add('c', 300);

    final reopened = ScrobbleQueue(file);
    final sent = <String>[];
    final n = await reopened.flush((item) async {
      if (item.trackId == 'c') return false;
      sent.add('${item.trackId}@${item.timeMs}');
      return true;
    });
    expect(n, 2);
    expect(sent, ['a@100', 'b@200']);
    final again = ScrobbleQueue(file);
    final rest = <String>[];
    await again.flush((i) async {
      rest.add(i.trackId);
      return true;
    });
    expect(rest, ['c']);
  });

  test('tres escuchas sin conexión se envían al reconectar con su hora',
      () async {
    final requests = <Uri>[];
    var online = false;
    final client = MockClient((req) async {
      if (!online) throw const SocketException('sin red');
      requests.add(req.url);
      return http.Response('{"subsonic-response":{"status":"ok"}}', 200);
    });
    final nav = NavidromeService(httpClient: client)
      ..scrobbleQueueFileOverride = File(p.join(tmp.path, 'q.json'));
    nav.setConnectedForTesting(
        url: 'https://musica.example.invalid',
        username: 'ana',
        password: 'clave',
        client: client);

    await nav.scrobble('t1');
    await nav.scrobble('t2');
    await nav.scrobble('t3');
    expect(requests, isEmpty);

    online = true;
    final sent = await nav.flushScrobbles();
    expect(sent, 3);
    expect(requests.map((u) => u.queryParameters['id']), ['t1', 't2', 't3']);
    for (final u in requests) {
      expect(int.parse(u.queryParameters['time']!), greaterThan(0));
    }
  });
}
