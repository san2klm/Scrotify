import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:navidrome_client/services/app_theme.dart';
import 'package:navidrome_client/services/sync/sync_key_link.dart';
import 'package:navidrome_client/services/sync/sync_service.dart';
import 'package:navidrome_client/services/theme_controller.dart';
import 'package:navidrome_client/widgets/pairing_qr_code.dart';
import 'package:navidrome_client/widgets/sync_settings.dart';
import 'package:provider/provider.dart';

class _Themes extends ThemeController {
  @override
  AppTheme get active => AppTheme.fixedThemes.first;
  @override
  bool get loading => false;
  @override
  Future<void> rescan() async {}
}

void main() {
  late Directory tmp;
  late SyncService sync;
  String? stored;
  late String key;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sync_qr');
    stored = null;
    sync = SyncService(
      dataDir: () async => Directory('${tmp.path}/data')..createSync(),
      themeImportsDir: () async =>
          Directory('${tmp.path}/themes')..createSync(),
      serverBase: () => null, // sin red: la sincronización solo avisa
      client: MockClient((_) async => throw StateError('sin red')),
      interval: const Duration(days: 1),
      readKey: () async => stored,
      writeKey: (v) async => stored = v,
      readOptOut: () async => false,
      writeOptOut: (_) async {},
    );
  });

  tearDown(() {
    sync.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester,
      {bool enabled = true,
      Future<bool> Function()? authorize,
      bool canScan = false}) async {
    if (enabled) {
      await tester.runAsync(() async => key = await sync.enableNew());
    }
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: _Themes()),
        ChangeNotifierProvider<SyncService>.value(value: sync),
      ],
      child: MaterialApp(
        theme: AppTheme.fixedThemes.first.toThemeData(),
        home: Scaffold(
            body: SingleChildScrollView(
                child: SyncSettings(authorize: authorize, canScan: canScan))),
      ),
    ));
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(sync.disable); // cancela el temporizador
  }

  testWidgets('el QR no aparece sin confirmar y cancelar no pide identidad',
      (tester) async {
    var asked = 0;
    await pump(tester, authorize: () async {
      asked++;
      return true;
    });
    await tester.tap(find.text('Mostrar QR'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Quien lo escanee'), findsOneWidget);
    expect(find.byType(PairingQrCode), findsNothing);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byType(PairingQrCode), findsNothing);
    expect(asked, 0);
    await finish(tester);
  });

  testWidgets('tras confirmar y autorizar muestra el QR con la clave',
      (tester) async {
    await pump(tester, authorize: () async => true);
    await tester.tap(find.text('Mostrar QR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mostrar'));
    await tester.pumpAndSettle();

    final qr = tester.widget<PairingQrCode>(find.byType(PairingQrCode));
    expect(qr.data, SyncKeyLink.build(key));
    expect(SyncKeyLink.parse(qr.data), key);
    await finish(tester);
  });

  testWidgets('si la identidad no se confirma no se muestra el QR',
      (tester) async {
    await pump(tester, authorize: () async => false);
    await tester.tap(find.text('Mostrar QR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mostrar'));
    await tester.pumpAndSettle();
    expect(find.byType(PairingQrCode), findsNothing);
    await finish(tester);
  });

  testWidgets('escanear QR solo se ofrece donde hay cámara', (tester) async {
    await pump(tester, enabled: false, canScan: false);
    await tester.tap(find.textContaining('Ya tengo una clave'));
    await tester.pumpAndSettle();
    expect(find.text('Escanear QR'), findsNothing);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    await finish(tester);

    await pump(tester, enabled: false, canScan: true);
    await tester.tap(find.textContaining('Ya tengo una clave'));
    await tester.pumpAndSettle();
    expect(find.text('Escanear QR'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('la clave se puede pegar como enlace scrotify-sync://',
      (tester) async {
    final other = SyncKeyLink.build(
        'ABCD-EFGH-IJKL-MNOP-QRST-UVWX-YZ23-4567-ABCD-EFGH-IJKL-MNOP-QRST');
    await pump(tester, enabled: false);
    await tester.tap(find.textContaining('Ya tengo una clave'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), other!);
    await tester.runAsync(() async {
      await tester.tap(find.text('Vincular'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(sync.enabled, isTrue);
    expect(stored, SyncKeyLink.parse(other));
    await finish(tester);
  });
}
