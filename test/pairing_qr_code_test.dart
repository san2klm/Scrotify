import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/widgets/pairing_qr_code.dart';
import 'package:qr_flutter/qr_flutter.dart';

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
}
