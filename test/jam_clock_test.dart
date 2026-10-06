import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/jam_clock.dart';

void main() {
  test('sample math: symmetric path recovers the true offset', () {
    // Offset real = +1000 (servidor adelantado). RTT 100: ida 50, vuelta 50.
    final s = JamClockSample.fromExchange(
        sentAt: 10000, receivedAt: 10100, serverNow: 10050 + 1000);
    expect(s.rttMs, 100);
    expect(s.offsetMs, 1000);
  });

  test('median of lowest-RTT samples ignores jittery outliers', () {
    final rnd = Random(7);
    const trueOffset = -2500;
    final e = ClockOffsetEstimator();
    for (var i = 0; i < 10; i++) {
      // Muestras buenas: RTT bajo, error simétrico pequeño.
      final rtt = 40 + rnd.nextInt(20);
      e.add(JamClockSample(rtt, trueOffset + rnd.nextInt(5) - 2));
    }
    for (var i = 0; i < 2; i++) {
      // Outliers: RTT enorme y offset muy sesgado (trayecto asimétrico).
      e.add(const JamClockSample(900, trueOffset + 400));
    }
    expect((e.offsetMs! - trueOffset).abs(), lessThanOrEqualTo(3));
  });

  test('keeps only the last maxSamples and drops negative RTTs', () {
    final e = ClockOffsetEstimator(maxSamples: 3, bestCount: 3);
    e.add(const JamClockSample(10, 999));
    for (var i = 0; i < 3; i++) {
      e.add(const JamClockSample(20, 5));
    }
    e.add(const JamClockSample(-5, 12345));
    expect(e.sampleCount, 3);
    expect(e.offsetMs, 5);
  });

  test('no samples: identity conversion and null offset', () {
    final e = ClockOffsetEstimator();
    expect(e.isReady, isFalse);
    expect(e.offsetMs, isNull);
    expect(e.toReference(123), 123);
    expect(e.toLocal(123), 123);
  });

  test('toReference/toLocal are inverse', () {
    final e = ClockOffsetEstimator()..add(const JamClockSample(30, 700));
    expect(e.toLocal(e.toReference(5000)), 5000);
  });

  group('decideDriftCorrection', () {
    test('ignores small drift', () {
      expect(decideDriftCorrection(30).action, JamDriftAction.none);
      expect(decideDriftCorrection(-50).action, JamDriftAction.none);
    });
    test('nudges speed in the right direction', () {
      final behind = decideDriftCorrection(200);
      expect(behind.action, JamDriftAction.nudge);
      expect(behind.speed, closeTo(1.02, 1e-9));
      expect(decideDriftCorrection(-200).speed, closeTo(0.98, 1e-9));
    });
    test('seeks beyond 450 ms', () {
      expect(decideDriftCorrection(451).action, JamDriftAction.seek);
      expect(decideDriftCorrection(-451).action, JamDriftAction.seek);
      expect(decideDriftCorrection(450).action, JamDriftAction.nudge);
    });
    test('hysteresis: keeps nudging until drift < 25 ms, then restores 1.0', () {
      expect(decideDriftCorrection(40, currentSpeed: 1.02).action, JamDriftAction.nudge);
      final done = decideDriftCorrection(20, currentSpeed: 1.02);
      expect(done.action, JamDriftAction.none);
      expect(done.speed, 1.0);
    });
  });
}
