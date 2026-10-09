import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/theme_controller.dart';
import 'package:navidrome_client/widgets/cleartext_url_warning.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('aparece y desaparece según lo que se escribe', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeController(),
        child: MaterialApp(
          home: Scaffold(body: CleartextUrlWarning(controller: controller)),
        ),
      ),
    );
    expect(find.textContaining('sin cifrar'), findsNothing);

    controller.text = 'http://navidrome.ejemplo.com';
    await tester.pump();
    expect(find.textContaining('sin cifrar'), findsOneWidget);

    controller.text = 'http://192.168.1.25:4533';
    await tester.pump();
    expect(find.textContaining('sin cifrar'), findsNothing);

    controller.text = 'https://navidrome.ejemplo.com';
    await tester.pump();
    expect(find.textContaining('sin cifrar'), findsNothing);
  });
}
