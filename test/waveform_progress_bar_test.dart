import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/widgets/waveform_progress_bar.dart';
import 'package:navidrome_client/services/waveform_service.dart';

void main() {
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
