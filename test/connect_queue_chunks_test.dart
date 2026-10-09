import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/connect/connect_protocol.dart';
import 'package:navidrome_client/services/sync/sync_crypto.dart';

import 'connect_service_test.dart' show FakeNetwork, FakePort, Node, settle;

List<Map<String, dynamic>> _songs(int n) => [
      for (var i = 0; i < n; i++) {'id': 's$i', 'title': 'T$i', 'artist': 'A'},
    ];

void main() {
  group('ConnectQueueChunks.split', () {
    test('una cola corta viaja entera, sin trozos ni identificador', () {
      final split = ConnectQueueChunks.split(_songs(30));
      expect(split.head, hasLength(30));
      expect(split.rest, isEmpty);
      expect(split.xfer, isNull);
      expect(split.more, 0);
    });

    test('una cola larga se reparte y se puede recomponer en orden', () {
      final all = _songs(500);
      final split = ConnectQueueChunks.split(all, random: Random(1));
      expect(split.head, hasLength(ConnectQueueChunks.firstChunk));
      expect(split.xfer, isNotNull);
      expect(split.rest.every((c) => c.length <= ConnectQueueChunks.chunkSize),
          isTrue);
      final joined = [...split.head, for (final c in split.rest) ...c];
      expect([for (final t in joined) t['id']], [for (final t in all) t['id']]);
      expect(split.more, 500 - ConnectQueueChunks.firstChunk);
    });

    test('tiene un tope total para que nadie sature al receptor', () {
      final split = ConnectQueueChunks.split(_songs(5000));
      final total =
          split.head.length + split.rest.fold<int>(0, (a, c) => a + c.length);
      expect(total, ConnectQueueChunks.maxTotal);
    });
  });

  group('ConnectTransfer con trozos', () {
    test('conserva identificador y cantidad pendiente al viajar', () {
      final t = ConnectTransfer(
          scope: 'srv',
          tracks: _songs(3),
          index: 1,
          positionMs: 5,
          playing: true,
          xfer: 'abc123',
          more: 460);
      final back = ConnectTransfer.tryParse(t.toJson())!;
      expect(back.xfer, 'abc123');
      expect(back.more, 460);
    });

    test('un identificador raro se descarta', () {
      final back = ConnectTransfer.tryParse({
        'scope': 'srv',
        'tracks': _songs(1),
        'xfer': '<script>',
        'more': 5,
      })!;
      expect(back.xfer, isNull);
      expect(back.more, 0);
    });

    test('un transfer antiguo (sin campos nuevos) sigue funcionando', () {
      final back = ConnectTransfer.tryParse(
          {'scope': 'srv', 'tracks': _songs(2), 'index': 0})!;
      expect(back.xfer, isNull);
      expect(back.more, 0);
    });
  });

  group('ConnectQueueReceiver', () {
    Map<String, dynamic> chunk(String xfer, int seq, int n, {String? scope}) =>
        {
          'scope': scope ?? 'srv',
          'xfer': xfer,
          'seq': seq,
          'tracks': _songs(n)
        };

    test('acepta los trozos en orden y se cierra al completar', () {
      final r = ConnectQueueReceiver()..expect('abcd1234', 100);
      expect(r.accept(chunk('abcd1234', 0, 80), 'srv'), hasLength(80));
      expect(r.accept(chunk('abcd1234', 1, 20), 'srv'), hasLength(20));
      expect(r.accept(chunk('abcd1234', 2, 5), 'srv'), isNull);
    });

    test('un hueco detiene la recepción: nunca queda una cola con huecos', () {
      final r = ConnectQueueReceiver()..expect('abcd1234', 160);
      expect(r.accept(chunk('abcd1234', 1, 80), 'srv'), isNull);
      expect(r.accept(chunk('abcd1234', 0, 80), 'srv'), hasLength(80));
    });

    test('rechaza otra transferencia, otro servidor o repetidos', () {
      final r = ConnectQueueReceiver()..expect('abcd1234', 160);
      expect(r.accept(chunk('zzzz9999', 0, 80), 'srv'), isNull);
      expect(r.accept(chunk('abcd1234', 0, 80), 'otro'), isNull);
      expect(r.accept(chunk('abcd1234', 0, 80), 'srv'), isNotNull);
      expect(r.accept(chunk('abcd1234', 0, 80), 'srv'), isNull);
    });

    test('rechaza trozos que superan lo anunciado o el tamaño máximo', () {
      final r = ConnectQueueReceiver()..expect('abcd1234', 50);
      expect(r.accept(chunk('abcd1234', 0, 51), 'srv'), isNull);
      final big = ConnectQueueReceiver()..expect('abcd1234', 1000);
      expect(big.accept(chunk('abcd1234', 0, 81), 'srv'), isNull);
    });

    test('caduca pasado el tiempo límite', () {
      var now = DateTime(2026, 10, 9, 12);
      final r = ConnectQueueReceiver(now: () => now)..expect('abcd1234', 160);
      now = now.add(const Duration(minutes: 6));
      expect(r.accept(chunk('abcd1234', 0, 80), 'srv'), isNull);
    });

    test('adoptar otra cola invalida los trozos de la anterior', () {
      final r = ConnectQueueReceiver()..expect('abcd1234', 160);
      r.expect(null, 0);
      expect(r.accept(chunk('abcd1234', 0, 80), 'srv'), isNull);
    });

    test('entradas con tipos inesperados no lanzan', () {
      final r = ConnectQueueReceiver()..expect('abcd1234', 160);
      expect(r.accept({'scope': 'srv', 'xfer': 'abcd1234', 'seq': 'x'}, 'srv'),
          isNull);
      expect(
          r.accept({
            'scope': 'srv',
            'xfer': 'abcd1234',
            'seq': 0,
            'tracks': [1, 2]
          }, 'srv'),
          isNull);
    });
  });

  group('transferir una cola larga entre dispositivos', () {
    late SyncCrypto crypto;
    late FakeNetwork net;
    late Node phone;
    late Node pc;

    setUp(() async {
      crypto = await SyncCrypto.fromSecret(SyncKey.generate(Random(9)));
      net = FakeNetwork();
      phone = Node(
          net, 'phone-0001', 'Teléfono', ConnectKind.phone, FakePort('srv-1'));
      pc = Node(
          net, 'desktop-001', 'PC', ConnectKind.desktop, FakePort('srv-1'));
      await phone.service.configure(crypto);
      await pc.service.configure(crypto);
      await settle();
    });

    test('llegan primero 40 y después el resto, en orden y sin huecos',
        () async {
      phone.port
        ..track = _songs(1).first
        ..playing = true
        ..exportQueue = _songs(300);
      await phone.service.transferTo('desktop-001');
      await settle();

      expect(pc.port.adoptedCount, ConnectQueueChunks.firstChunk);
      expect(pc.port.appendedSeqs, isNotEmpty);
      expect(pc.port.appendedSeqs,
          List.generate(pc.port.appendedSeqs.length, (i) => i));
      expect(pc.port.queueIds, [for (var i = 0; i < 300; i++) 's$i']);
    });

    test('una cola corta no manda trozos', () async {
      phone.port
        ..track = _songs(1).first
        ..exportQueue = _songs(10);
      await phone.service.transferTo('desktop-001');
      await settle();
      expect(pc.port.appendedSeqs, isEmpty);
      expect(pc.port.adoptedCount, 10);
    });
  });
}
