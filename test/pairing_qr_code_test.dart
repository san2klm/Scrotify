import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:navidrome_client/models/pairing_models.dart';
import 'package:navidrome_client/services/pairing_server.dart';
import 'package:navidrome_client/services/theme_controller.dart';
import 'package:navidrome_client/widgets/pairing_panel.dart';
import 'package:navidrome_client/widgets/pairing_qr_code.dart';
import 'package:qr_flutter/qr_flutter.dart';

class _WaitingPairingServer extends PairingServer {
  _WaitingPairingServer() : super(useRelay: false);

  @override
  PairingStatus get status => PairingStatus.waiting;

  @override
  bool get isActive => false;

  @override
  String? get currentCode => 'ABC123';

  @override
  String? get qrDataUri =>
      'scrotify://pair?topic=scrotify-1234567890abcdef1234567890abcdef&code=ABC123';

  @override
  String get deviceName => 'PC de prueba';

  @override
  int get remainingSeconds => 300;
}

void main() {
  testWidgets('uses a fixed white surface and black QR modules',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PairingQrCode(
            data:
                'scrotify://pair?topic=scrotify-1234567890abcdef1234567890abcdef&code=ABC123',
            size: 160,
          ),
        ),
      ),
    );

    final qr = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(qr.backgroundColor, Colors.white);
    expect(qr.eyeStyle.color, Colors.black);
    expect(qr.dataModuleStyle.color, Colors.black);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a bounded message when QR data is missing',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PairingQrCode(data: '', size: 160)),
      ),
    );

    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('No se pudo generar el código QR'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the QR and PIN in a bounded desktop pairing panel',
      (tester) async {
    final server = _WaitingPairingServer();
    const code = 'ABC123';

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeController(),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 380,
                child: PairingSharePanel(
                  compact: true,
                  server: server,
                  onGetCredentials: () async => null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text(code.substring(0, 3)), findsOneWidget);
    expect(find.text(code.substring(3)), findsOneWidget);
    expect(tester.getSize(find.byType(PairingSharePanel)).width, 380);
    expect(tester.takeException(), isNull);
  });
}
