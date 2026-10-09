import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/connect/connect_protocol.dart';
import 'package:navidrome_client/services/connect/connect_service.dart';
import 'package:navidrome_client/services/connect/connect_transport.dart';
import 'package:navidrome_client/services/settings_controller.dart';
import 'package:navidrome_client/services/sync/sync_crypto.dart';

import 'support/app_fakes.dart';

class _Net implements ConnectTransport {
  _Net(this.name);
  final String name;
  bool stopped = false;
  @override
  Stream<List<ConnectDevice>> get devices => const Stream.empty();
  @override
  Stream<({String from, String blob})> get messages => const Stream.empty();
  @override
  String? get problem => null;
  @override
  bool canReach(String deviceId) => false;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async => stopped = true;
  @override
  Future<void> send(String? deviceId, String blob) async {}
}

void main() {
  group('normalizeDeviceName', () {
    test('recorta, colapsa espacios y limita a 40 caracteres', () {
      expect(SettingsController.normalizeDeviceName('  Sala   de  estar '),
          'Sala de estar');
      expect(SettingsController.normalizeDeviceName('x' * 80)!.length, 40);
    });

    test('vacío o solo espacios significa "usar el nombre por defecto"', () {
      expect(SettingsController.normalizeDeviceName('   '), isNull);
      expect(SettingsController.normalizeDeviceName(''), isNull);
    });

    test('descarta caracteres de control', () {
      expect(SettingsController.normalizeDeviceName('Sa\u0000la\n1'), 'Sala 1');
    });
  });

  group('ConnectService.rename', () {
    test('guarda el nombre y recrea los transportes con el nuevo', () async {
      final created = <_Net>[];
      var current = 'Antes';
      final saved = <String?>[];
      final connect = ConnectService(
        port: IdleConnectPort(),
        selfId: 'me-000001',
        selfName: 'Antes',
        persistName: (name) async {
          saved.add(name);
          current = name ?? 'Antes';
        },
        transportsFor: (_) {
          final net = _Net(current);
          created.add(net);
          return [net];
        },
      );
      addTearDown(connect.dispose);
      await connect
          .configure(await SyncCrypto.fromSecret(SyncKey.generate(Random(1))));
      expect(created.map((n) => n.name), ['Antes']);

      await connect.rename('  Salón ');

      expect(saved, ['Salón']);
      expect(connect.selfName, 'Salón');
      expect(created.map((n) => n.name), ['Antes', 'Salón']);
      expect(created.first.stopped, isTrue);
    });

    test('un nombre idéntico no reinicia nada', () async {
      var builds = 0;
      final connect = ConnectService(
        port: IdleConnectPort(),
        selfId: 'me-000001',
        selfName: 'Igual',
        persistName: (_) async {},
        transportsFor: (_) {
          builds++;
          return [_Net('Igual')];
        },
      );
      addTearDown(connect.dispose);
      await connect
          .configure(await SyncCrypto.fromSecret(SyncKey.generate(Random(1))));
      await connect.rename('Igual');
      expect(builds, 1);
    });

    test('vaciar el nombre vuelve al de por defecto', () async {
      final saved = <String?>[];
      final connect = ConnectService(
        port: IdleConnectPort(),
        selfId: 'me-000001',
        selfName: 'Personal',
        defaultName: 'Mi-PC',
        persistName: (n) async => saved.add(n),
        transportsFor: (_) => [_Net('x')],
      );
      addTearDown(connect.dispose);
      await connect.rename('   ');
      expect(saved, [null]);
      expect(connect.selfName, 'Mi-PC');
    });
  });
}
