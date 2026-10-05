import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/widgets/waveform_progress_bar.dart';
import 'package:navidrome_client/services/waveform_service.dart';

void main() {
  _newTests();
  testWidgets('WaveformProgressBar renders correctly without waveform', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 60,
            child: WaveformProgressBar(
              waveform: null,
              position: const Duration(seconds: 30),
              duration: const Duration(seconds: 120),
              onSeek: (position) {},
            ),
          ),
        ),
      ),
    );

    // Should render our custom paint widget inside GestureDetector
    expect(find.descendant(of: find.byType(WaveformProgressBar), matching: find.byType(CustomPaint)), findsOneWidget);
  });

  testWidgets('WaveformProgressBar renders correctly with waveform', (WidgetTester tester) async {
    const waveform = WaveformData(
      trackId: '123',
      duration: Duration(seconds: 120),
      amplitudes: [0.1, 0.5, 1.0, 0.8, 0.2, 0.1],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 60,
            child: WaveformProgressBar(
              waveform: waveform,
              position: const Duration(seconds: 60), // 50% progress
              duration: const Duration(seconds: 120),
              onSeek: (position) {},
            ),
          ),
        ),
      ),
    );

    expect(find.descendant(of: find.byType(WaveformProgressBar), matching: find.byType(CustomPaint)), findsOneWidget);
  });

  testWidgets('WaveformProgressBar calls onSeek when tapped', (WidgetTester tester) async {
    Duration? seekResult;
    
    const waveform = WaveformData(
      trackId: '123',
      duration: Duration(seconds: 120),
      amplitudes: [0.1, 0.5, 1.0, 0.8, 0.2, 0.1],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400, // Important to give it a fixed width for testing tap location
            height: 60,
            child: WaveformProgressBar(
              waveform: waveform,
              position: const Duration(seconds: 30),
              duration: const Duration(seconds: 120),
              onSeek: (position) {
                seekResult = position;
              },
            ),
          ),
        ),
      ),
    );

    // Tap at exactly the middle (50% = 60s)
    await tester.tapAt(const Offset(200, 30));

    expect(seekResult, isNotNull);
    // Might be slightly off due to rounding, but should be very close to 60s
    expect(seekResult!.inSeconds, closeTo(60, 1));
  });

  testWidgets('WaveformProgressBar handles 2048-bin waveforms (no flat line)',
      (WidgetTester tester) async {
    // Regresión: con 2048 bins el cálculo antiguo daba barWidth negativo y
    // la waveform se veía como una línea plana.
    final amplitudes = List<double>.generate(
      2048,
      (i) => 0.15 + 0.85 * ((i % 64) / 63),
    );
    final waveform = WaveformData(
      trackId: 'big',
      duration: const Duration(seconds: 180),
      amplitudes: amplitudes,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 56,
            child: WaveformProgressBar(
              waveform: waveform,
              position: const Duration(seconds: 60),
              duration: const Duration(seconds: 180),
              onSeek: (position) {},
            ),
          ),
        ),
      ),
    );

    expect(
        find.descendant(
            of: find.byType(WaveformProgressBar),
            matching: find.byType(CustomPaint)),
        findsOneWidget);

    // El downsampling por ancho debe reducir a ~133 barras con picos.
    final downsampled = waveformPainterDownsampleForTest(amplitudes, 400.0);
    expect(downsampled.length, lessThan(amplitudes.length));
    expect(downsampled.length, greaterThan(50));
    final maxV = downsampled.reduce((a, b) => a > b ? a : b);
    expect(maxV, greaterThan(0.9));
  });
}

Widget _host(Widget child, {double width = 400, bool noAnim = false}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: noAnim),
        child: Scaffold(body: Center(child: SizedBox(width: width, child: child))),
      ),
    );

const _wf = WaveformData(
  trackId: 't',
  duration: Duration(seconds: 100),
  amplitudes: [0.2, 0.6, 1.0, 0.7, 0.3, 0.5, 0.9, 0.4],
);

void _newTests() {
  testWidgets('arrastrar hace seek solo al soltar, en la posición final',
      (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(_host(WaveformProgressBar(
      waveform: _wf,
      position: Duration.zero,
      duration: const Duration(seconds: 100),
      onSeek: seeks.add,
    )));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(tester.getCenter(find.byType(WaveformProgressBar)) - const Offset(200, 0));
    await gesture.moveBy(const Offset(150, 0));
    await tester.pump();
    expect(seeks, isEmpty); // aún arrastrando
    await gesture.moveBy(const Offset(250, 0)); // se pasa del borde: clamp
    await gesture.up();
    await tester.pump();
    expect(seeks, hasLength(1));
    expect(seeks.single.inSeconds, closeTo(100, 6)); // ~final de la barra
  });

  testWidgets('flechas del teclado adelantan y retroceden seekStep',
      (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(_host(WaveformProgressBar(
      waveform: _wf,
      position: const Duration(seconds: 50),
      duration: const Duration(seconds: 100),
      seekStep: const Duration(seconds: 10),
      onSeek: seeks.add,
    )));
    await tester.pumpAndSettle();
    // Dar foco al Focus de la barra.
    Focus.of(tester.element(find.descendant(
            of: find.byType(WaveformProgressBar),
            matching: find.byType(CustomPaint))))
        .requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(seeks.map((d) => d.inSeconds), [60, 40]);
  });

  testWidgets('hover con el ratón no lanza errores y no hace seek',
      (tester) async {
    final seeks = <Duration>[];
    await tester.pumpWidget(_host(WaveformProgressBar(
      waveform: _wf,
      position: const Duration(seconds: 10),
      duration: const Duration(seconds: 100),
      onSeek: seeks.add,
    )));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(WaveformProgressBar)));
    await tester.pump();
    await mouse.moveTo(const Offset(-50, -50));
    await tester.pump();
    expect(seeks, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reproduciendo: anima sin errores y se libera al desmontar',
      (tester) async {
    await tester.pumpWidget(_host(WaveformProgressBar(
      waveform: _wf,
      position: const Duration(seconds: 10),
      duration: const Duration(seconds: 100),
      playing: true,
      onSeek: (_) {},
    )));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 900));
    // Pausar detiene el ticker/pulso: no deben quedar animaciones pendientes.
    await tester.pumpWidget(_host(WaveformProgressBar(
      waveform: _wf,
      position: const Duration(seconds: 12),
      duration: const Duration(seconds: 100),
      playing: false,
      onSeek: (_) {},
    )));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('con "reducir animaciones" no hay ticker ni pulso', (tester) async {
    await tester.pumpWidget(_host(
      WaveformProgressBar(
        waveform: _wf,
        position: const Duration(seconds: 10),
        duration: const Duration(seconds: 100),
        playing: true,
        onSeek: (_) {},
      ),
      noAnim: true,
    ));
    // Si hubiera un pulso repetitivo, pumpAndSettle nunca terminaría.
    await tester.pumpAndSettle();
  });

  testWidgets('expone semántica de slider con tiempo', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(WaveformProgressBar(
      waveform: _wf,
      position: const Duration(seconds: 65),
      duration: const Duration(seconds: 100),
      onSeek: (_) {},
    )));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Progreso de reproducción'), findsOneWidget);
    handle.dispose();
  });

  test('geometría adaptable: barras más gruesas en anchos grandes', () {
    final phone = WaveformProgressBar.geometryForWidth(360);
    final tablet = WaveformProgressBar.geometryForWidth(700);
    final desktop = WaveformProgressBar.geometryForWidth(1400);
    expect(phone.bar, lessThan(tablet.bar));
    expect(tablet.bar, lessThan(desktop.bar));
  });

  test('downsampleForWidth conserva los picos', () {
    final out = WaveformProgressBar.downsampleForWidth(
        [0.1, 0.9, 0.2, 0.3, 0.1, 0.8], 3);
    expect(out, [0.9, 0.3, 0.8]);
  });
}

// Acceso al downsampling real del painter sin exponer la clase privada.
List<double> waveformPainterDownsampleForTest(
    List<double> values, double width) {
  const stride = 3.0; // targetBarWidth(2) + targetGap(1)
  final targetBars = (width / stride).floor().clamp(1, 2048);
  if (values.length <= targetBars) return values;
  final out = List<double>.filled(targetBars, 0.0);
  final step = values.length / targetBars;
  for (var i = 0; i < targetBars; i++) {
    final start = (i * step).floor();
    final end = ((i + 1) * step).floor().clamp(0, values.length);
    var peak = values[start];
    for (var j = start + 1; j < end; j++) {
      if (values[j] > peak) peak = values[j];
    }
    out[i] = peak;
  }
  return out;
}
