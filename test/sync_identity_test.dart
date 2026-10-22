import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/sync_harness.dart';

const _url = 'https://musica.test';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sync_identity'));
  tearDown(() => tmp.deleteSync(recursive: true));

  SyncHarness device() =>
      SyncHarness(Directory(p.join(tmp.path, 'd'))..createSync());

  test('cambiar de cuenta en la misma instancia cambia de bóveda', () async {
    final h = device();
    await h.service
        .enableForAccount(url: _url, username: 'ana', password: 'clave-a');
    await h.idle();
    expect(h.service.keyText, await SyncHarness.keyOf(_url, 'ana', 'clave-a'));

    await h.service
        .enableForAccount(url: _url, username: 'beto', password: 'clave-b');
    await h.idle();

    final keyB = await SyncHarness.keyOf(_url, 'beto', 'clave-b');
    expect(h.service.enabled, isTrue);
    expect(h.service.keyText, keyB,
        reason: 'la bóveda de ana no puede seguir activa bajo beto');
    expect(h.storedKey, keyB, reason: 'la clave guardada es la de beto');
  });

  test('repetir la misma cuenta no cambia nada ni repite el trabajo', () async {
    final h = device();
    await h.service
        .enableForAccount(url: _url, username: 'ana', password: 'clave-a');
    await h.idle();
    final key = h.service.keyText;
    final crypto = h.service.crypto;

    await h.service
        .enableForAccount(url: '$_url/', username: 'ana', password: 'clave-a');
    await h.idle();

    expect(h.service.keyText, key);
    expect(identical(h.service.crypto, crypto), isTrue);
  });

  test('un ciclo en vuelo de la cuenta anterior no sube nada tras el cambio',
      () async {
    final h = device()..write('settings.json', '{"x":1}');
    final vaultA = await SyncHarness.vaultOf(_url, 'ana', 'clave-a');
    final vaultB = await SyncHarness.vaultOf(_url, 'beto', 'clave-b');
    final gate = h.listGate = Completer<void>();

    await h.service
        .enableForAccount(url: _url, username: 'ana', password: 'clave-a');
    await h.untilRequests(1);
    expect(h.requests.single.toString(), startsWith('GET $vaultA'),
        reason: 'el ciclo de ana está detenido en el listado');

    await h.service
        .enableForAccount(url: _url, username: 'beto', password: 'clave-b');
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await h.idle();

    final afterSwitch = h.requests.skip(1).toList();
    expect(afterSwitch.where((r) => r.vault == vaultA), isEmpty,
        reason: 'nada de ana puede salir después del cambio');
    expect(
        afterSwitch.any((r) => r.method == 'PUT' && r.vault == vaultB), isTrue,
        reason: 'los datos locales sí se suben a la bóveda de beto');
  });
}
