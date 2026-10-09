import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/replay_gain.dart';

void main() {
  group('ReplayGainMode', () {
    test('fromString reconoce los modos y cae en "off" con cualquier otra cosa',
        () {
      expect(ReplayGainMode.fromString('track'), ReplayGainMode.track);
      expect(ReplayGainMode.fromString('album'), ReplayGainMode.album);
      expect(ReplayGainMode.fromString('off'), ReplayGainMode.off);
      expect(ReplayGainMode.fromString(null), ReplayGainMode.off);
      expect(ReplayGainMode.fromString('TRACK'), ReplayGainMode.off);
      expect(ReplayGainMode.fromString(''), ReplayGainMode.off);
    });

    test('cada modo tiene un nombre y una descripción distintos y no vacíos',
        () {
      final labels = {for (final m in ReplayGainMode.values) m.label};
      final subtitles = {for (final m in ReplayGainMode.values) m.subtitle};
      expect(labels, hasLength(ReplayGainMode.values.length));
      expect(subtitles, hasLength(ReplayGainMode.values.length));
      expect(labels.every((l) => l.isNotEmpty), isTrue);
      expect(subtitles.every((l) => l.isNotEmpty), isTrue);
    });

    test('name y fromString son inversos', () {
      for (final m in ReplayGainMode.values) {
        expect(ReplayGainMode.fromString(m.name), m);
      }
    });
  });

  group('ReplayGainMetadata (serialización e igualdad)', () {
    test('toJson omite lo que falta y conserva el 0.0 explícito', () {
      const meta = ReplayGainMetadata(trackGain: 0.0, albumPeak: 0.98);
      expect(meta.toJson(), {'trackGain': 0.0, 'albumPeak': 0.98});
      expect(const ReplayGainMetadata().toJson(), isEmpty);
    });

    test('toJson y fromJson son inversos', () {
      const meta = ReplayGainMetadata(
          trackGain: -7.5,
          albumGain: -6.2,
          trackPeak: 0.988,
          albumPeak: 1.02,
          baseGain: 0.0,
          fallbackGain: -3.0);
      expect(ReplayGainMetadata.fromJson(meta.toJson()), meta);
    });

    test('isEmpty solo es cierto si no hay ningún dato (el 0.0 cuenta)', () {
      expect(const ReplayGainMetadata().isEmpty, isTrue);
      expect(const ReplayGainMetadata(trackGain: 0.0).isEmpty, isFalse);
      expect(const ReplayGainMetadata(fallbackGain: -1).isEmpty, isFalse);
    });

    test('== y hashCode comparan todos los campos', () {
      const a = ReplayGainMetadata(trackGain: -1, albumGain: -2);
      const same = ReplayGainMetadata(trackGain: -1, albumGain: -2);
      const other = ReplayGainMetadata(trackGain: -1, albumGain: -3);
      expect(a, same);
      expect(a.hashCode, same.hashCode);
      expect(a == other, isFalse);
      expect(a == const ReplayGainMetadata(trackGain: -1), isFalse);
      expect(a.toString(), contains('trackGain: -1.0'));
    });
  });

  group('ReplayGainResult (igualdad y texto)', () {
    ReplayGainResult compute(ReplayGainMode mode, double gain) =>
        computeReplayGain(
          mode: mode,
          replayGain: ReplayGainMetadata(trackGain: gain, trackPeak: 0.5),
          preampDb: 0,
          preventClipping: true,
        );

    test('resultados iguales son iguales y tienen el mismo hashCode', () {
      final a = compute(ReplayGainMode.track, -6);
      final b = compute(ReplayGainMode.track, -6);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == compute(ReplayGainMode.track, -3), isFalse);
    });

    test('toString incluye los indicadores', () {
      final text = compute(ReplayGainMode.track, -6).toString();
      expect(text, contains('gainDb'));
      expect(text, contains('multiplier'));
    });

    test('androidBoostDb es siempre 0 (sin boost nativo)', () {
      expect(compute(ReplayGainMode.track, 6).androidBoostDb, 0.0);
      expect(compute(ReplayGainMode.off, 6).androidBoostDb, 0.0);
    });
  });
}
