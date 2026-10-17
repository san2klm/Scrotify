import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/app_theme.dart';
import 'package:crotowave/services/connect/connect_protocol.dart';
import 'package:crotowave/services/connect/connect_service.dart';
import 'package:crotowave/services/connect/connect_transport.dart';
import 'package:crotowave/services/navidrome_service.dart';
import 'package:crotowave/services/player_controller.dart';
import 'package:crotowave/services/sync/sync_crypto.dart';
import 'package:crotowave/services/theme_controller.dart';
import 'package:crotowave/widgets/connect_panel.dart';
import 'package:provider/provider.dart';

import 'support/app_fakes.dart';

class _Themes extends ThemeController {
  @override
  AppTheme get active => AppTheme.fixedThemes.first;
  @override
  bool get loading => false;
  @override
  Future<void> rescan() async {}
}

class _Nav extends FakeNavidrome {
  _Nav(this.signedIn);
  final bool signedIn;
  @override
  bool get connected => signedIn;
}

class _Net implements ConnectTransport {
  final _devices = StreamController<List<ConnectDevice>>.broadcast();
  @override
  Stream<List<ConnectDevice>> get devices => _devices.stream;
  @override
  Stream<({String from, String blob})> get messages => const Stream.empty();
  @override
  String? get problem => null;
  @override
  bool canReach(String deviceId) => false;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> send(String? deviceId, String blob) async {}
  void show(List<ConnectDevice> list) => _devices.add(list);
}

void main() {
  late _Net net;
  late ConnectService connect;

  Future<void> pump(WidgetTester tester, {required bool signedIn}) async {
    net = _Net();
    connect = ConnectService(
        port: IdleConnectPort(),
        selfId: 'me-000001',
        transportsFor: (_) => [net]);
    addTearDown(connect.dispose);
    // La criptografía usa futuros reales: fuera del reloj simulado del test.
    await tester.runAsync(() async {
      await connect
          .configure(await SyncCrypto.fromSecret(SyncKey.generate(Random(2))));
    });
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: _Themes()),
        ChangeNotifierProvider<ConnectService>.value(value: connect),
        ChangeNotifierProvider<NavidromeService>.value(value: _Nav(signedIn)),
        ChangeNotifierProvider<PlayerController>(create: (_) => IdlePlayer()),
      ],
      child: MaterialApp(
          theme: AppTheme.fixedThemes.first
              .toThemeData()
              .copyWith(platform: TargetPlatform.linux),
          home: const Scaffold(body: ConnectPanel())),
    ));
    await tester.pump();
  }

  testWidgets('sin sesión explica cómo ver los dispositivos', (tester) async {
    await pump(tester, signedIn: false);
    expect(find.textContaining('Inicia sesión'), findsOneWidget);
    expect(find.text('Esta computadora'), findsOneWidget);
  });

  testWidgets('sin otros dispositivos muestra el estado vacío', (tester) async {
    await pump(tester, signedIn: true);
    expect(find.text('No se encontraron otros dispositivos'), findsOneWidget);
  });

  testWidgets('lista dispositivos por LAN e Internet y distingue iguales',
      (tester) async {
    await pump(tester, signedIn: true);
    net.show(const [
      ConnectDevice(
          id: 'aaaa1111',
          name: 'Teléfono',
          kind: ConnectKind.phone,
          viaLan: true),
      ConnectDevice(
          id: 'bbbb2222',
          name: 'Teléfono',
          kind: ConnectKind.phone,
          viaRelay: true),
      ConnectDevice(
          id: 'cccc3333',
          name: 'Sala',
          kind: ConnectKind.desktop,
          viaRelay: true),
    ]);
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 20))); // entrega del stream (zona real)
    await tester.pump();
    expect(find.text('Teléfono (aaaa)'), findsOneWidget);
    expect(find.text('Teléfono (bbbb)'), findsOneWidget);
    expect(find.text('Sala'), findsOneWidget);
    expect(find.text('Red local'), findsOneWidget);
    expect(find.text('Internet'), findsNWidgets(2));
    expect(find.byIcon(Icons.smartphone), findsNWidgets(2));
  });

  testWidgets('el nombre del dispositivo se puede cambiar desde el panel',
      (tester) async {
    await pump(tester, signedIn: true);
    await tester.tap(find.byTooltip('Cambiar nombre del dispositivo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Salón');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(connect.selfName, 'Salón');
    expect(find.text('Salón'), findsOneWidget);
  });
}
