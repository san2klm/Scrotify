import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/local_music_service.dart';
import 'package:crotowave/widgets/local_music_settings.dart';

void main() {
  test('cada etapa tiene su texto', () {
    expect(
        scanProgressLabel(const LocalScanProgress(LocalScanPhase.listing, 7)),
        'Buscando archivos… 7');
    expect(
        scanProgressLabel(
            const LocalScanProgress(LocalScanPhase.files, 12, 340)),
        'Leyendo archivos… 12 de 340');
    expect(
        scanProgressLabel(const LocalScanProgress(LocalScanPhase.catalog, 0)),
        contains('catálogo'));
    expect(
        scanProgressLabel(
            const LocalScanProgress(LocalScanPhase.matching, 3, 9)),
        'Identificando canciones… 3 de 9');
  });

  test('la fracción solo existe con total conocido y nunca pasa de 1', () {
    expect(const LocalScanProgress(LocalScanPhase.listing, 5).fraction, isNull);
    expect(const LocalScanProgress(LocalScanPhase.files, 1, 4).fraction, 0.25);
    expect(const LocalScanProgress(LocalScanPhase.files, 9, 4).fraction, 1.0);
  });

  testWidgets('muestra el avance y el botón Cancelar avisa', (tester) async {
    var cancelled = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ScanProgressView(
                progress: const LocalScanProgress(LocalScanPhase.files, 1, 2),
                onCancel: () => cancelled++))));
    expect(find.text('Leyendo archivos… 1 de 2'), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        0.5);
    await tester.tap(find.text('Cancelar'));
    expect(cancelled, 1);
  });
}
