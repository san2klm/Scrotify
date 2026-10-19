import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:crotowave/services/navidrome_service.dart';
import 'package:crotowave/services/scrobble_queue.dart';
import 'package:path/path.dart' as p;

const _ok = '{"subsonic-response":{"status":"ok"}}';
const _rejected = '{"subsonic-response":{"status":"failed",'
    '"error":{"code":40,"message":"Wrong username or password"}}}';

List<Map<String, dynamic>> _stored(File file) => file.existsSync()
    ? (jsonDecode(file.readAsStringSync()) as List).cast<Map<String, dynamic>>()
    : const [];

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('scrobble-s-'));
  tearDown(() async => await tmp.delete(recursive: true));

  const urlA = 'https://musica.example.invalid';

  group('un envelope Subsonic rechazado no confirma el scrobble', () {
    test('HTTP 200 con status=failed deja el evento en la cola', () async {
      var reply = _rejected;
      final requests = <Uri>[];
      final client = MockClient((req) async {
        requests.add(req.url);
        return http.Response(reply, 200);
      });
      final file = File(p.join(tmp.path, 'q.json'));
      final nav = NavidromeService(httpClient: client)
        ..scrobbleQueueFileOverride = file;
      nav.setConnectedForTesting(
          url: urlA, username: 'ana', password: 'clave', client: client);

      await nav.scrobble('t1');
      expect(_stored(file).map((e) => e['id']), ['t1'],
          reason: 'el rechazo lógico no es un envío correcto');

      // Un cuerpo que no es un envelope tampoco cuenta.
      reply = 'ok';
      expect(await nav.flushScrobbles(), 0);
      expect(_stored(file).map((e) => e['id']), ['t1']);

      reply = _ok;
      expect(await nav.flushScrobbles(), 1);
      expect(_stored(file), isEmpty);
      expect(requests.map((u) => u.queryParameters['id']), ['t1', 't1', 't1']);
    });
  });

  group('un flush queda fijado a la sesión que lo inició', () {
    test('cambiar A→B a mitad de flush no envía lo pendiente de A como B',
        () async {
      final gate = Completer<void>();
      var online = false;
      final requests = <Map<String, String>>[];
      final client = MockClient((req) async {
        if (!online) throw const SocketException('sin red');
        requests.add(req.url.queryParameters);
        if (requests.length == 1) await gate.future;
        return http.Response(_ok, 200);
      });
      final fileA = File(p.join(tmp.path, 'a.json'));
      final fileB = File(p.join(tmp.path, 'b.json'));
      final nav = NavidromeService(httpClient: client)
        ..scrobbleQueueFileOverride = fileA;
      nav.setConnectedForTesting(
          url: urlA, username: 'ana', password: 'clave', client: client);
      await nav.scrobble('a1');
      await nav.scrobble('a2');
      await nav.scrobble('a3');
      expect(_stored(fileA), hasLength(3));

      online = true;
      final flushing = nav.flushScrobbles();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(requests, hasLength(1), reason: 'el primer envío está en vuelo');

      nav.scrobbleQueueFileOverride = fileB;
      nav.setConnectedForTesting(
          url: urlA, username: 'beto', password: 'otra', client: client);
      gate.complete();

      expect(await flushing, 1, reason: 'a1 sí llegó a ana');
      expect(requests.map((q) => q['u']), ['ana'],
          reason: 'nada de A puede salir con las credenciales de B');
      expect(requests.map((q) => q['id']), ['a1']);
      expect(_stored(fileA).map((e) => e['id']), ['a2', 'a3'],
          reason: 'lo pendiente se conserva en la cola original');
      expect(_stored(fileB), isEmpty);
    });

    test(
        'un scrobble con envío en vuelo que falla tras cambiar de cuenta '
        'queda en la cola de su cuenta', () async {
      final gate = Completer<void>();
      final client = MockClient((req) async {
        await gate.future;
        return http.Response(_rejected, 200);
      });
      final fileA = File(p.join(tmp.path, 'a.json'));
      final fileB = File(p.join(tmp.path, 'b.json'));
      final nav = NavidromeService(httpClient: client)
        ..scrobbleQueueFileOverride = fileA;
      nav.setConnectedForTesting(
          url: urlA, username: 'ana', password: 'clave', client: client);

      final scrobbling = nav.scrobble('a1');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      nav.scrobbleQueueFileOverride = fileB;
      nav.setConnectedForTesting(
          url: urlA, username: 'beto', password: 'otra', client: client);
      gate.complete();
      await scrobbling;

      expect(_stored(fileA).map((e) => e['id']), ['a1']);
      expect(_stored(fileB), isEmpty);
    });
  });

  group('ScrobbleQueue', () {
    test(
        'operaciones concurrentes sobre una cola recién abierta comparten '
        'la carga y conservan el orden', () async {
      final file = File(p.join(tmp.path, 'q.json'))
        ..writeAsStringSync(jsonEncode([
          {'id': 'a', 'time': 1},
          {'id': 'b', 'time': 2},
        ]));
      final queue = ScrobbleQueue(file);
      await Future.wait([queue.add('c', 3), queue.add('d', 4)]);

      expect(queue.length, 4);
      expect(_stored(file).map((e) => e['id']), ['a', 'b', 'c', 'd']);
    });

    test('un flush concurrente a add ve lo guardado en disco', () async {
      final file = File(p.join(tmp.path, 'q.json'))
        ..writeAsStringSync(jsonEncode([
          {'id': 'a', 'time': 1},
        ]));
      final queue = ScrobbleQueue(file);
      final sent = <String>[];
      final added = queue.add('b', 2);
      final flushed = queue.flush((item) async {
        sent.add(item.trackId);
        return true;
      });
      await added;
      await flushed;

      expect(sent, ['a', 'b']);
    });
  });
}
