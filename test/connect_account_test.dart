import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' show md5;
import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/connect/connect_account.dart';

void main() {
  test('el token es el de Subsonic: md5(clave + salt) con salt nuevo', () {
    const account = ConnectAccount(user: 'admin', password: 'secreta');
    final a = account.authToken(Random(1));
    final b = account.authToken(Random(2));
    expect(a.salt, matches(RegExp(r'^[a-z0-9]{16}$')));
    expect(a.salt, isNot(b.salt));
    expect(a.token, md5.convert(utf8.encode('secreta${a.salt}')).toString());
    expect(a.token, isNot(contains('secreta')));
  });

  test('la clave de cifrado depende de usuario y clave, no de mayúsculas',
      () async {
    final admin = await const ConnectAccount(user: 'admin', password: 'x1')
        .deriveCrypto();
    final again = await const ConnectAccount(user: ' Admin ', password: 'x1')
        .deriveCrypto();
    final other = await const ConnectAccount(user: 'maria', password: 'x1')
        .deriveCrypto();
    final wrongPassword =
        await const ConnectAccount(user: 'admin', password: 'x2')
            .deriveCrypto();
    expect(again.vaultId, admin.vaultId);
    expect(other.vaultId, isNot(admin.vaultId));
    expect(wrongPassword.vaultId, isNot(admin.vaultId));
    // Dos dispositivos del mismo usuario se entienden; otro usuario no.
    final blob = await admin.encrypt([1, 2, 3], docKey: 'connect');
    expect(await again.decrypt(blob, docKey: 'connect'), [1, 2, 3]);
    expect(() => other.decrypt(blob, docKey: 'connect'),
        throwsA(isA<FormatException>()));
  });
}
