import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/sync/sync_crypto.dart';

void main() {
  test('la clave se formatea y se vuelve a leer igual', () {
    final secret = SyncKey.generate(Random(1));
    final text = SyncKey.format(secret);
    expect(text, matches(RegExp(r'^([A-Z2-7]{4}-){12}[A-Z2-7]{4}$')));
    expect(SyncKey.parse(text), secret);
    expect(SyncKey.parse(text.toLowerCase().replaceAll('-', ' ')), secret);
  });

  test('rechaza claves mal formadas', () {
    expect(SyncKey.parse(''), isNull);
    expect(SyncKey.parse('ABCD-EFGH'), isNull);
    expect(SyncKey.parse('1' * 52), isNull);
  });

  test('la misma clave deriva siempre lo mismo y valores distintos entre sí',
      () async {
    final secret = Uint8List.fromList(List.generate(32, (i) => i));
    final a = await SyncCrypto.fromSecret(secret);
    final b = await SyncCrypto.fromSecret(secret);
    expect(a.vaultId, b.vaultId);
    expect(a.authToken, b.authToken);
    expect(a.vaultId, hasLength(64));
    expect(a.vaultId, isNot(a.authToken));
  });

  test('cifra y descifra; otra clave o documento no puede leerlo', () async {
    final a = await SyncCrypto.fromSecret(SyncKey.generate(Random(1)));
    final other = await SyncCrypto.fromSecret(SyncKey.generate(Random(2)));
    final plain = utf8.encode('{"cancion-secreta":1}');
    final blob = await a.encrypt(plain, docKey: 'settings');
    expect(utf8.decode(base64.decode(blob), allowMalformed: true),
        isNot(contains('secreta')));
    expect(await a.decrypt(blob, docKey: 'settings'), plain);
    expect(() => other.decrypt(blob, docKey: 'settings'),
        throwsA(isA<FormatException>()));
    expect(() => a.decrypt(blob, docKey: 'themes'),
        throwsA(isA<FormatException>()));
    expect(() => a.decrypt('no-es-base64!', docKey: 'settings'),
        throwsA(isA<FormatException>()));
  });
}
