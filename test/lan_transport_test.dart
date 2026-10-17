import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/connect/connect_protocol.dart';
import 'package:crotowave/services/connect/lan_transport.dart';
import 'package:crotowave/services/sync/sync_crypto.dart';

LanTransport make(SyncCrypto crypto, String id, String name, ConnectKind kind,
    {required int listen, required List<int> talkTo}) {
  return LanTransport(
    crypto: crypto,
    selfId: id,
    selfName: name,
    selfKind: kind,
    beaconPort: listen,
    beaconInterval: const Duration(milliseconds: 100),
    helloTimeout: const Duration(milliseconds: 600),
    useMulticastLock: false,
    // Las pruebas hablan por loopback, cada una con su puerto de baliza.
    beaconTargets: (_) async => [
      for (final p in talkTo) (address: InternetAddress.loopbackIPv4, port: p),
    ],
  );
}

Future<T> within<T>(Future<T> f) => f.timeout(const Duration(seconds: 5));

void main() {
  late SyncCrypto crypto;
  setUp(() async {
    crypto = await SyncCrypto.fromSecret(SyncKey.generate(Random(5)));
  });

  test('dos dispositivos del mismo grupo se descubren y se envían mensajes',
      () async {
    final a = make(crypto, 'phone-aaaa1', 'Teléfono', ConnectKind.phone,
        listen: 47731, talkTo: [47732]);
    final b = make(crypto, 'desktop-bbb', 'PC', ConnectKind.desktop,
        listen: 47732, talkTo: [47731]);
    final seenByA =
        a.devices.firstWhere((l) => l.any((d) => d.id == 'desktop-bbb'));
    final seenByB =
        b.devices.firstWhere((l) => l.any((d) => d.id == 'phone-aaaa1'));
    final atB = b.messages.first;
    final atA = a.messages.first;
    await a.start();
    await b.start();

    final aSees = await within(seenByA);
    final bSees = await within(seenByB);
    expect(aSees.single.name, 'PC');
    expect(aSees.single.viaLan, isTrue);
    expect(bSees.single.kind, ConnectKind.phone);

    await a.send('desktop-bbb', 'de-a');
    await b.send('phone-aaaa1', 'de-b');
    expect((await within(atB)).blob, 'de-a');
    expect((await within(atA)).from, 'desktop-bbb');
    expect(a.canReach('desktop-bbb'), isTrue);

    await a.stop();
    await b.stop();
  });

  test('un dispositivo con otra clave no entra en el grupo', () async {
    final other = await SyncCrypto.fromSecret(SyncKey.generate(Random(77)));
    final a = make(crypto, 'phone-aaaa1', 'Teléfono', ConnectKind.phone,
        listen: 47741, talkTo: [47742]);
    final stranger = make(other, 'desktop-bbb', 'Intruso', ConnectKind.desktop,
        listen: 47742, talkTo: [47741]);
    await a.start();
    await stranger.start();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(a.canReach('desktop-bbb'), isFalse);
    expect(stranger.canReach('phone-aaaa1'), isFalse);
    await a.stop();
    await stranger.stop();
  });

  test('un socket que no manda saludo cifrado se cierra', () async {
    final a = make(crypto, 'phone-aaaa1', 'Teléfono', ConnectKind.phone,
        listen: 47751, talkTo: []);
    await a.start();
    final socket = await WebSocket.connect('ws://127.0.0.1:${a.port}/connect');
    socket.listen((_) {}); // sin oyente el cierre no se completa
    socket.add('{"hello":"no-es-un-saludo-valido"}');
    await within(socket.done);
    expect(a.canReach('x'), isFalse);
    await a.stop();
  });

  test('al cerrarse un dispositivo desaparece del otro', () async {
    final a = make(crypto, 'phone-aaaa1', 'Teléfono', ConnectKind.phone,
        listen: 47761, talkTo: [47762]);
    final b = make(crypto, 'desktop-bbb', 'PC', ConnectKind.desktop,
        listen: 47762, talkTo: [47761]);
    final joined =
        a.devices.firstWhere((l) => l.any((d) => d.id == 'desktop-bbb'));
    await a.start();
    await b.start();
    await within(joined);
    final gone = a.devices.firstWhere((l) => l.isEmpty);
    await b.stop();
    await within(gone);
    expect(a.canReach('desktop-bbb'), isFalse);
    await a.stop();
  });
}
