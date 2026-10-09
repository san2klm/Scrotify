import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/player_controller.dart';
import 'package:navidrome_client/widgets/player_position_builder.dart';

/// Fake mínimo: solo lo que usa PlayerPositionBuilder.
class _FakePlayer extends ChangeNotifier implements PlayerController {
  final positions = StreamController<Duration>.broadcast();
  Duration currentPosition = Duration.zero;
  bool isPlaying = false;

  @override
  Stream<Duration> get positionStream => positions.stream;

  @override
  Duration get position => currentPosition;

  @override
  bool get playing => isPlaying;

  @override
  bool karaokeMode = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('PlayerPositionBuilder.advance', () {
    test('en pausa no avanza', () {
      expect(
        PlayerPositionBuilder.advance(
          current: const Duration(seconds: 10),
          step: const Duration(milliseconds: 250),
          playing: false,
        ),
        const Duration(seconds: 10),
      );
    });

    test('sonando avanza un paso', () {
      expect(
        PlayerPositionBuilder.advance(
          current: const Duration(seconds: 10),
          step: const Duration(milliseconds: 250),
          playing: true,
        ),
        const Duration(milliseconds: 10250),
      );
    });

    test('no avanza más allá de la duración', () {
      expect(
        PlayerPositionBuilder.advance(
          current: const Duration(milliseconds: 199900),
          step: const Duration(milliseconds: 250),
          playing: true,
          duration: const Duration(seconds: 200),
        ),
        const Duration(seconds: 200),
      );
    });
  });

  testWidgets('avanza entre eventos del backend (móvil ~1 Hz)',
      (WidgetTester tester) async {
    final fake = _FakePlayer();
    Duration? shown;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerPositionBuilder(
            player: fake,
            duration: const Duration(seconds: 200),
            builder: (context, position) {
              shown = position;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(shown, Duration.zero);

    // Un solo evento del backend y luego silencio total (caso Android).
    fake.isPlaying = true;
    fake.currentPosition = const Duration(seconds: 10);
    fake.positions.add(const Duration(seconds: 10));
    await tester.pump();
    expect(shown, const Duration(seconds: 10));

    // 1 segundo sin eventos nuevos: 4 ticks de 250 ms → 11 s exactos.
    await tester.pump(const Duration(seconds: 1));
    expect(shown, const Duration(seconds: 11));

    // Pausa: queda congelado aunque pase el tiempo.
    fake.isPlaying = false;
    await tester.pump(const Duration(seconds: 2));
    expect(shown, const Duration(seconds: 11));

    await fake.positions.close();
  });

  testWidgets('en segundo plano no reconstruye y al volver se re-ancla',
      (WidgetTester tester) async {
    final fake = _FakePlayer()
      ..isPlaying = true
      ..currentPosition = const Duration(seconds: 10);
    var builds = 0;
    Duration? shown;
    addTearDown(() => tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed));

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPositionBuilder(
          player: fake,
          duration: const Duration(seconds: 200),
          builder: (context, position) {
            builds++;
            shown = position;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(shown, const Duration(seconds: 10));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final before = builds;
    // El backend sigue emitiendo y el tiempo pasa, pero nadie mira la barra.
    fake.currentPosition = const Duration(seconds: 40);
    fake.positions.add(const Duration(seconds: 40));
    await tester.pump(const Duration(seconds: 5));
    expect(builds, before, reason: 'sin reconstrucciones en segundo plano');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    fake.currentPosition = const Duration(seconds: 42);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(shown, const Duration(seconds: 42),
        reason: 'toma la posición real, no la estimada antes de ocultarse');

    await fake.positions.close();
  });
}
