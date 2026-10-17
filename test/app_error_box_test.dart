import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/widgets/app_error_box.dart';

class _Boom extends StatelessWidget {
  const _Boom();

  @override
  Widget build(BuildContext context) => throw StateError('fallo de prueba');
}

void main() {
  testWidgets('un widget que falla deja un recuadro y el resto sigue visible',
      (tester) async {
    final previous = ErrorWidget.builder;
    AppErrorBox.install();

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Text('antes'),
          SizedBox(height: 120, child: _Boom()),
          Text('después'),
        ]),
      ),
    ));
    expect(tester.takeException(), isStateError);

    expect(find.text('Esta parte no se pudo mostrar'), findsOneWidget);
    expect(find.text('antes'), findsOneWidget);
    expect(find.text('después'), findsOneWidget);
    // Ocupa su hueco, no la ventana entera.
    expect(tester.getSize(find.byType(AppErrorBox)).height, 120);
    // El framework exige dejarlo como estaba antes de terminar el test.
    ErrorWidget.builder = previous;
  });

  testWidgets('se dibuja sin tema ni Directionality y sin desbordar',
      (tester) async {
    final details = FlutterErrorDetails(exception: StateError('x' * 4000));
    for (final verbose in [true, false]) {
      await tester.pumpWidget(Center(
        child: SizedBox(
          width: 60,
          height: 24,
          child: AppErrorBox(details: details, showDetails: verbose),
        ),
      ));
      expect(tester.takeException(), isNull, reason: 'verbose=$verbose');
    }
  });

  testWidgets('en release no enseña el texto técnico', (tester) async {
    final details =
        FlutterErrorDetails(exception: StateError('secreto interno'));
    await tester.pumpWidget(AppErrorBox(details: details, showDetails: false));
    expect(find.textContaining('secreto interno'), findsNothing);
    expect(find.textContaining('Diagnóstico'), findsOneWidget);
  });
}
