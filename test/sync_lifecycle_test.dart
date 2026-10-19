import 'dart:async';
import 'dart:io';

import 'package:crotowave/services/sync/sync_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/sync_harness.dart';

const _url = 'https://musica.test';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sync_lifecycle'));
  tearDown(() => tmp.deleteSync(recursive: true));

  SyncHarness device({
    String? storedKey,
    bool bound = false,
    bool manual = false,
    Duration requestTimeout = const Duration(seconds: 30),
  }) {
    final h = SyncHarness(Directory(p.join(tmp.path, 'd'))..createSync(),
        storedKey: storedKey, requestTimeout: requestTimeout);
    h.accountBound = bound;
    h.manualLinked = manual;
    return h;
  }

  group('cerrar sesión suspende sin ser un opt-out', () {
    test('suspende, no escribe opt-out y retoma la misma bóveda al volver',
        () async {
      final h = device();
      await h.service
          .enableForAccount(url: _url, username: 'ana', password: 'clave-a');
      await h.idle();
      final key = h.service.keyText;
      expect(key, isNotNull);

      await h.service.suspendForLogout();
      expect(h.service.enabled, isFalse);
      expect(h.optOut, isFalse, reason: 'cerrar sesión no es desactivar');
      expect(h.storedKey, key, reason: 'la clave se conserva en el equipo');
      final before = h.requests.length;
      await h.service.syncNow();
      expect(h.requests.length, before, reason: 'suspendido no sincroniza');

      await h.service
          .enableForAccount(url: _url, username: 'ana', password: 'clave-a');
      await h.idle();
      expect(h.service.enabled, isTrue);
      expect(h.service.keyText, key);
    });

    test('tras cerrar sesión otra cuenta no hereda la bóveda anterior',
        () async {
      final h = device();
      await h.service
          .enableForAccount(url: _url, username: 'ana', password: 'clave-a');
      await h.idle();
      await h.service.suspendForLogout();

      await h.service
          .enableForAccount(url: _url, username: 'beto', password: 'clave-b');
      await h.idle();
      expect(
          h.service.keyText, await SyncHarness.keyOf(_url, 'beto', 'clave-b'));
    });

    test('el opt-out explícito sigue mandando', () async {
      final h = device();
      await h.service
          .enableForAccount(url: _url, username: 'ana', password: 'clave-a');
      await h.idle();
      await h.service.disable();
      await h.service.suspendForLogout();
      await h.service
          .enableForAccount(url: _url, username: 'ana', password: 'clave-a');
      expect(h.service.enabled, isFalse);
      expect(h.optOut, isTrue);
    });

    test('una clave vinculada a mano no se suspende por cerrar sesión',
        () async {
      final h = device();
      final key = SyncKey.format(SyncKey.generate());
      expect(await h.service.link(key), isTrue);
      await h.idle();

      await h.service.suspendForLogout();
      expect(h.service.enabled, isTrue);
      await h.service
          .enableForAccount(url: _url, username: 'ana', password: 'clave-a');
      expect(h.service.keyText, key,
          reason: 'la clave manual gana a la derivada de la cuenta');
    });
  });

  group('una activación o ciclo anterior no puede actuar tras suspender', () {
    test('cerrar sesión durante la activación la cancela', () async {
      final h = device();
      final activating = h.service
          .enableForAccount(url: _url, username: 'ana', password: 'clave-a');
      await h.service.suspendForLogout();
      await activating;
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(h.service.enabled, isFalse);
      expect(h.storedKey, isNull, reason: 'no se guarda una clave tardía');
      expect(h.requests, isEmpty);
    });

    test('cerrar sesión con un ciclo en vuelo impide que suba o aplique',
        () async {
      final h = device()..write('settings.json', '{"x":1}');
      final gate = h.listGate = Completer<void>();
      await h.service
          .enableForAccount(url: _url, username: 'ana', password: 'clave-a');
      await h.untilRequests(1);

      await h.service.suspendForLogout();
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await h.idle();

      expect(h.requests, hasLength(1), reason: 'solo el listado ya enviado');
      expect(h.applied, isEmpty);
      expect(h.service.enabled, isFalse);
    });
  });

  group('restaurar una clave guardada', () {
    test('una clave de cuenta no sincroniza hasta confirmar la cuenta actual',
        () async {
      final keyA = await SyncHarness.keyOf(_url, 'ana', 'clave-a');
      final vaultA = await SyncHarness.vaultOf(_url, 'ana', 'clave-a');
      final h = device(storedKey: keyA, bound: true);

      await h.service.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(h.service.enabled, isFalse);
      expect(h.requests, isEmpty, reason: 'sin confirmar la cuenta no se sube');

      await h.service
          .enableForAccount(url: _url, username: 'beto', password: 'clave-b');
      await h.idle();
      expect(
          h.service.keyText, await SyncHarness.keyOf(_url, 'beto', 'clave-b'));
      expect(h.requests.where((r) => r.vault == vaultA), isEmpty);
    });

    test('con la misma cuenta se retoma la clave guardada', () async {
      final keyA = await SyncHarness.keyOf(_url, 'ana', 'clave-a');
      final h = device(storedKey: keyA, bound: true);

      await h.service.initialize();
      await h.service
          .enableForAccount(url: _url, username: 'ana', password: 'clave-a');
      await h.idle();

      expect(h.service.enabled, isTrue);
      expect(h.service.keyText, keyA);
    });

    test('una clave vinculada a mano de forma explícita se restaura', () async {
      final key = SyncKey.format(SyncKey.generate());
      final h = device(storedKey: key, manual: true);

      await h.service.initialize();
      expect(h.service.enabled, isTrue);
      expect(h.service.keyText, key);
      await h.idle();
    });

    test('vincular a mano deja el marcador explícito y reinicia como manual',
        () async {
      final h = device();
      final key = SyncKey.format(SyncKey.generate());
      expect(await h.service.link(key), isTrue);
      await h.idle();
      expect(h.manualLinked, isTrue);
      expect(h.accountBound, isFalse);

      final restarted =
          device(storedKey: h.storedKey, manual: h.manualLinked, bound: false);
      // misma carpeta: el segundo harness comparte los datos del primero
      await restarted.service.initialize();
      expect(restarted.service.enabled, isTrue);
      expect(restarted.service.keyText, key);
      await restarted.idle();
    });
  });

  group('clave guardada sin procedencia (instalación anterior)', () {
    test('no se da por manual: con otra cuenta no se usa y se conserva aparte',
        () async {
      final keyA = await SyncHarness.keyOf(_url, 'ana', 'clave-a');
      final vaultA = await SyncHarness.vaultOf(_url, 'ana', 'clave-a');
      final h = device(storedKey: keyA); // sin ningún marcador

      await h.service.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(h.service.enabled, isFalse, reason: 'no sincroniza al arrancar');
      expect(h.service.suspended, isTrue);
      expect(h.service.error, isNotNull, reason: 'la UI debe decir por qué');
      expect(h.requests, isEmpty);

      await h.service
          .enableForAccount(url: _url, username: 'beto', password: 'clave-b');
      await h.idle();

      expect(
          h.service.keyText, await SyncHarness.keyOf(_url, 'beto', 'clave-b'));
      expect(h.requests.where((r) => r.vault == vaultA), isEmpty);
      expect(h.legacyBackup, keyA,
          reason: 'la clave desconocida no se pierde en silencio');
      expect(h.accountBound, isTrue);
    });

    test('sin perfil no se activa aunque main llame a suspender', () async {
      final keyA = await SyncHarness.keyOf(_url, 'ana', 'clave-a');
      final h = device(storedKey: keyA);

      await h.service.initialize();
      await h.service.suspendForLogout();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(h.service.enabled, isFalse);
      expect(h.requests, isEmpty);
      expect(h.storedKey, keyA, reason: 'no se borra ni se reemplaza');
    });

    test('si coincide con la cuenta actual se reconoce y se retoma', () async {
      final keyA = await SyncHarness.keyOf(_url, 'ana', 'clave-a');
      final h = device(storedKey: keyA);

      await h.service.initialize();
      await h.service
          .enableForAccount(url: _url, username: 'ana', password: 'clave-a');
      await h.idle();

      expect(h.service.enabled, isTrue);
      expect(h.service.keyText, keyA);
      expect(h.accountBound, isTrue, reason: 'queda migrada');
      expect(h.legacyBackup, isNull);
    });
  });

  group('la última intención gana en la persistencia', () {
    test('una escritura de la cuenta A retenida no pisa a la cuenta B',
        () async {
      final h = device();
      final gate = h.writeKeyGate = Completer<void>();
      final first = h.service
          .enableForAccount(url: _url, username: 'ana', password: 'clave-a');
      for (var i = 0; i < 400 && h.writeKeyCalls == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(h.writeKeyCalls, 1, reason: 'la escritura de ana está retenida');

      final second = h.service
          .enableForAccount(url: _url, username: 'beto', password: 'clave-b');
      // Sin cola, la escritura de beto llegaría aquí (2.ª llamada) mientras la
      // de ana sigue retenida; con cola no llega hasta soltar la primera.
      for (var i = 0; i < 800 && h.writeKeyCalls < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      gate.complete();
      await first;
      await second;
      await h.idle();

      final keyB = await SyncHarness.keyOf(_url, 'beto', 'clave-b');
      expect(h.storedKey, keyB, reason: 'lo guardado debe ser lo de beto');
      expect(h.service.keyText, keyB);
    });

    test('desactivar durante una escritura retenida no se pierde', () async {
      final h = device();
      final gate = h.writeKeyGate = Completer<void>();
      final linking = h.service.link(SyncKey.format(SyncKey.generate()));
      for (var i = 0; i < 400 && h.writeKeyCalls == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final disabling = h.service.disable();
      // Que la limpieza llegue a escribir (si pudiera) antes de soltar la
      // escritura retenida: así se prueba el orden de terminación.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      gate.complete();
      expect(await linking, isFalse);
      await disabling;

      expect(h.storedKey, isNull, reason: 'la última intención fue desactivar');
      expect(h.optOut, isTrue);
      expect(h.service.enabled, isFalse);
    });

    test('vincular tras desactivar con la limpieza en cola deja la clave',
        () async {
      final h = device();
      final key = SyncKey.format(SyncKey.generate());
      expect(await h.service.link(SyncKey.format(SyncKey.generate())), isTrue);
      final gate = h.writeKeyGate = Completer<void>();
      final disabling = h.service.disable();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final linking = h.service.link(key);
      gate.complete();
      await disabling;
      expect(await linking, isTrue);
      await h.idle();

      expect(h.storedKey, key);
      expect(h.optOut, isFalse);
    });
  });

  test('un cuerpo de respuesta estancado no deja el ciclo colgado', () async {
    final h = device(requestTimeout: const Duration(milliseconds: 150));
    h.stallListBody = true;
    await h.service
        .enableForAccount(url: _url, username: 'ana', password: 'clave-a');
    await h.untilRequests(1);
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(h.service.syncing, isFalse);
    expect(h.service.error, isNotNull);
    // Una cuenta nueva puede arrancar su ciclo sin esperar al anterior.
    await h.service
        .enableForAccount(url: _url, username: 'beto', password: 'clave-b');
    await h.idle();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final vaultB = await SyncHarness.vaultOf(_url, 'beto', 'clave-b');
    expect(h.requests.any((r) => r.vault == vaultB), isTrue);
  });
}
