import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/navidrome_service.dart';
import 'package:crotowave/services/player_controller.dart';

void main() {
  group('ReplayGainMetadata.fromJson', () {
    test('parses empty or null json gracefully', () {
      final nullData = ReplayGainMetadata.fromJson(null);
      expect(nullData.isEmpty, isTrue);
      expect(nullData.trackGain, isNull);

      final emptyData = ReplayGainMetadata.fromJson(const {});
      expect(emptyData.isEmpty, isTrue);
    });

    test('parses numeric values correctly', () {
      final data = ReplayGainMetadata.fromJson({
        'trackGain': -7.5,
        'albumGain': -6.2,
        'trackPeak': 0.988,
        'albumPeak': 1.02,
        'baseGain': 0.5,
        'fallbackGain': -4.0,
      });

      expect(data.trackGain, -7.5);
      expect(data.albumGain, -6.2);
      expect(data.trackPeak, 0.988);
      expect(data.albumPeak, 1.02);
      expect(data.baseGain, 0.5);
      expect(data.fallbackGain, -4.0);
    });

    test('parses string values with dB suffix and trimming', () {
      final data = ReplayGainMetadata.fromJson({
        'trackGain': ' -8.3 dB ',
        'albumGain': '-5.1dB',
        'trackPeak': '0.95',
        'baseGain': '+1.2 db',
        'fallbackGain': '-3.0 dB',
      });

      expect(data.trackGain, closeTo(-8.3, 0.001));
      expect(data.albumGain, closeTo(-5.1, 0.001));
      expect(data.trackPeak, closeTo(0.95, 0.001));
      expect(data.baseGain, closeTo(1.2, 0.001));
      expect(data.fallbackGain, closeTo(-3.0, 0.001));
    });

    test('explicit 0 and 0.0 are valid and preserved (not null or empty)', () {
      final data = ReplayGainMetadata.fromJson({
        'trackGain': 0,
        'albumGain': 0.0,
        'trackPeak': 0.0,
        'baseGain': '0 dB',
        'fallbackGain': 0.0,
      });

      expect(data.isEmpty, isFalse);
      expect(data.trackGain, 0.0);
      expect(data.albumGain, 0.0);
      expect(data.trackPeak, 0.0);
      expect(data.baseGain, 0.0);
      expect(data.fallbackGain, 0.0);
    });

    test('rejects invalid doubles such as NaN, Infinity, and malformed strings',
        () {
      final data = ReplayGainMetadata.fromJson({
        'trackGain': double.nan,
        'albumGain': double.infinity,
        'trackPeak': -1.0, // negative peak invalid
        'albumPeak': 'not_a_number dB',
        'baseGain': '---',
      });

      expect(data.isEmpty, isTrue);
      expect(data.trackGain, isNull);
      expect(data.albumGain, isNull);
      expect(data.trackPeak, isNull);
      expect(data.albumPeak, isNull);
      expect(data.baseGain, isNull);
    });

    test('parses nested replayGain key defensively', () {
      final nested = ReplayGainMetadata.fromJson({
        'replayGain': {
          'trackGain': -4.5,
          'trackPeak': 0.89,
        }
      });

      expect(nested.trackGain, -4.5);
      expect(nested.trackPeak, 0.89);
    });
  });

  group('Track.fromJson ReplayGain integration', () {
    test('parses nested replayGain object in canonical Track', () {
      final track = Track.fromJson({
        'id': 't1',
        'title': 'Song 1',
        'artist': 'Artist 1',
        'album': 'Album 1',
        'duration': '180',
        'replayGain': {
          'trackGain': -6.5,
          'albumGain': -5.0,
          'trackPeak': 0.99,
          'fallbackGain': -4.0,
        },
      });

      expect(track.replayGain, isNotNull);
      expect(track.replayGain!.trackGain, -6.5);
      expect(track.replayGain!.albumGain, -5.0);
      expect(track.replayGain!.trackPeak, 0.99);
      expect(track.replayGain!.fallbackGain, -4.0);
    });

    test('Track without replayGain has null replayGain', () {
      final track = Track.fromJson({
        'id': 't2',
        'title': 'Song 2',
        'artist': 'Artist 2',
        'album': 'Album 2',
        'duration': '200',
      });

      expect(track.replayGain, isNull);
    });
  });

  group('computeReplayGain pure helper', () {
    const sampleMetadata = ReplayGainMetadata(
      trackGain: -6.0,
      albumGain: -3.0,
      trackPeak: 0.95,
      albumPeak: 1.0,
      baseGain: 0.5,
      fallbackGain: -4.0,
    );

    test('Off mode returns neutral gain and multiplier 1.0', () {
      final res = computeReplayGain(
        replayGain: sampleMetadata,
        mode: ReplayGainMode.off,
      );

      expect(res.gainDb, 0.0);
      expect(res.appliedGainDb, 0.0);
      expect(res.multiplier, 1.0);
      expect(res.isApplied, isFalse);
      expect(res.isMissingData, isFalse);
      expect(res.hasPositiveBoost, isFalse);
    });

    test('Null metadata returns neutral gain and multiplier 1.0', () {
      final res = computeReplayGain(
        replayGain: null,
        mode: ReplayGainMode.track,
      );

      expect(res.gainDb, 0.0);
      expect(res.multiplier, 1.0);
      expect(res.isApplied, isFalse);
      expect(res.isMissingData, isFalse);
    });

    test('Track mode chooses trackGain and adds baseGain', () {
      // rawGain (-6.0) + baseGain (0.5) + preamp (0.0) = -5.5 dB
      final res = computeReplayGain(
        replayGain: sampleMetadata,
        mode: ReplayGainMode.track,
      );

      expect(res.gainDb, closeTo(-5.5, 0.001));
      expect(res.appliedGainDb, closeTo(-5.5, 0.001));
      // multiplier = 10^(-5.5/20) ≈ 0.53088
      expect(res.multiplier, closeTo(0.53088, 0.001));
      expect(res.isApplied, isTrue);
      expect(res.isMissingData, isFalse);
    });

    test('Album mode chooses albumGain and adds baseGain', () {
      // rawGain (-3.0) + baseGain (0.5) + preamp (0.0) = -2.5 dB
      final res = computeReplayGain(
        replayGain: sampleMetadata,
        mode: ReplayGainMode.album,
      );

      expect(res.gainDb, closeTo(-2.5, 0.001));
      expect(res.appliedGainDb, closeTo(-2.5, 0.001));
      // multiplier = 10^(-2.5/20) ≈ 0.74989
      expect(res.multiplier, closeTo(0.74989, 0.001));
      expect(res.isApplied, isTrue);
    });

    test('Fallback gain is used when requested gain is missing', () {
      const fallbackOnly = ReplayGainMetadata(
        fallbackGain: -4.0,
        trackPeak: 0.9,
      );

      final trackRes = computeReplayGain(
        replayGain: fallbackOnly,
        mode: ReplayGainMode.track,
      );
      expect(trackRes.gainDb, -4.0);
      expect(trackRes.isMissingData, isFalse);

      final albumRes = computeReplayGain(
        replayGain: fallbackOnly,
        mode: ReplayGainMode.album,
      );
      expect(albumRes.gainDb, -4.0);
      expect(albumRes.isMissingData, isFalse);
    });

    test('Explicit 0 dB is valid and correctly computed', () {
      const zeroGain = ReplayGainMetadata(
        trackGain: 0.0,
        trackPeak: 0.8,
      );

      final res = computeReplayGain(
        replayGain: zeroGain,
        mode: ReplayGainMode.track,
      );

      expect(res.gainDb, 0.0);
      expect(res.appliedGainDb, 0.0);
      expect(res.multiplier, 1.0);
      expect(res.isMissingData, isFalse);
    });

    test('Missing data flags isMissingData and returns neutral multiplier', () {
      const emptyMeta = ReplayGainMetadata();

      final res = computeReplayGain(
        replayGain: emptyMeta,
        mode: ReplayGainMode.track,
      );

      expect(res.isMissingData, isTrue);
      expect(res.gainDb, 0.0);
      expect(res.multiplier, 1.0);
      expect(res.isApplied, isFalse);
    });

    test('Preamp is added and bounded to [-12, 12] dB', () {
      const meta = ReplayGainMetadata(trackGain: -5.0);

      // Normal preamp +3 dB -> -5.0 + 3.0 = -2.0 dB
      final res1 = computeReplayGain(
        replayGain: meta,
        mode: ReplayGainMode.track,
        preampDb: 3.0,
        preventClipping: false,
      );
      expect(res1.gainDb, -2.0);

      // Preamp > 12 clamped to 12 -> -5.0 + 12.0 = 7.0 dB
      final res2 = computeReplayGain(
        replayGain: meta,
        mode: ReplayGainMode.track,
        preampDb: 25.0,
        preventClipping: false,
      );
      expect(res2.gainDb, 7.0);

      // Preamp < -12 clamped to -12 -> -5.0 - 12.0 = -17.0 dB
      final res3 = computeReplayGain(
        replayGain: meta,
        mode: ReplayGainMode.track,
        preampDb: -30.0,
        preventClipping: false,
      );
      expect(res3.gainDb, -17.0);
    });

    test(
        'Peak clipping cap = -20 * log10(peak) limits gain when preventClipping=true',
        () {
      // peak = 1.25 -> cap = -20 * log10(1.25) ≈ -1.9382 dB
      const highPeak = ReplayGainMetadata(
        trackGain: 0.0,
        trackPeak: 1.25,
      );

      final res = computeReplayGain(
        replayGain: highPeak,
        mode: ReplayGainMode.track,
        preventClipping: true,
      );

      expect(res.isClipped, isTrue);
      expect(res.gainDb, closeTo(-1.9382, 0.001));
      expect(res.appliedGainDb, closeTo(-1.9382, 0.001));
    });

    test(
        'When peak is absent, positive boost is prohibited and capped to 0.0 dB',
        () {
      const noPeak = ReplayGainMetadata(
        trackGain: 4.0, // positive gain
        trackPeak: null, // absent peak
      );

      final res = computeReplayGain(
        replayGain: noPeak,
        mode: ReplayGainMode.track,
        preventClipping: true,
      );

      expect(res.isClipped, isTrue);
      expect(res.gainDb, 0.0);
      expect(res.appliedGainDb, 0.0);
      expect(res.multiplier, 1.0);
    });

    test(
        'Positive gain in attenuation-only backend exposes hasPositiveBoost without faking amplification',
        () {
      // preventClipping=false allows gainDb > 0
      const positiveMeta = ReplayGainMetadata(
        trackGain: 3.5,
        trackPeak: 0.5,
      );

      final res = computeReplayGain(
        replayGain: positiveMeta,
        mode: ReplayGainMode.track,
        preventClipping: false,
      );

      // gainDb preserves the calculated +3.5 dB
      expect(res.gainDb, 3.5);
      // but appliedGainDb is clamped to 0.0 dB
      expect(res.appliedGainDb, 0.0);
      // multiplier is strictly <= 1.0 (1.0)
      expect(res.multiplier, 1.0);
      expect(res.hasPositiveBoost, isTrue);
    });

    test('Invalid doubles (NaN, Infinity) are safely rejected', () {
      const meta = ReplayGainMetadata(trackGain: -6.0);

      final res = computeReplayGain(
        replayGain: meta,
        mode: ReplayGainMode.track,
        preampDb: double.nan,
      );

      // NaN preamp falls back to 0.0 dB -> -6.0 dB
      expect(res.gainDb, -6.0);
      expect(res.appliedGainDb, -6.0);
    });
  });

  group('Karaoke mode ReplayGain volume integration', () {
    test('computes unattenuated volume when ReplayGain is off or null', () {
      final volNull = PlayerController.computeEffectiveKaraokeVolume(
        baseVolume: 0.8,
        gainResult: null,
      );
      expect(volNull, closeTo(80.0, 0.001));

      const meta = ReplayGainMetadata(trackGain: -6.0);
      final offResult = computeReplayGain(
        replayGain: meta,
        mode: ReplayGainMode.off,
      );
      final volOff = PlayerController.computeEffectiveKaraokeVolume(
        baseVolume: 0.8,
        gainResult: offResult,
      );
      expect(volOff, closeTo(80.0, 0.001));
    });

    test('applies attenuation multiplier to media_kit 0..100 scale', () {
      const meta = ReplayGainMetadata(trackGain: -6.0);
      final res = computeReplayGain(
        replayGain: meta,
        mode: ReplayGainMode.track,
      );
      // multiplier = 10^(-6/20) ≈ 0.501187
      // 0.8 * 100 * 0.501187 ≈ 40.095
      final vol = PlayerController.computeEffectiveKaraokeVolume(
        baseVolume: 0.8,
        gainResult: res,
      );
      expect(vol, closeTo(40.095, 0.01));
    });

    test(
        'preserves attenuation-only guarantee without inventing boost for positive gain',
        () {
      const meta = ReplayGainMetadata(trackGain: 6.0, trackPeak: 0.5);
      final res = computeReplayGain(
        replayGain: meta,
        mode: ReplayGainMode.track,
        preventClipping: false,
      );
      // multiplier should be 1.0 (attenuation-only)
      expect(res.multiplier, 1.0);
      expect(res.hasPositiveBoost, isTrue);
      final vol = PlayerController.computeEffectiveKaraokeVolume(
        baseVolume: 0.8,
        gainResult: res,
      );
      // Volume should remain 80.0, never boosted above baseVolume * 100
      expect(vol, closeTo(80.0, 0.001));
    });

    test('clamps volume strictly within 0..100 bounds', () {
      final volMax = PlayerController.computeEffectiveKaraokeVolume(
        baseVolume: 1.5,
        gainResult: null,
      );
      expect(volMax, 100.0);

      final volMin = PlayerController.computeEffectiveKaraokeVolume(
        baseVolume: -0.5,
        gainResult: null,
      );
      expect(volMin, 0.0);
    });

    test('recomputes karaoke volume when ReplayGain settings change', () {
      const meta = ReplayGainMetadata(trackGain: -4.0);

      // Mode: off -> 100% of user volume
      final resOff = computeReplayGain(
        replayGain: meta,
        mode: ReplayGainMode.off,
        preampDb: 0.0,
      );
      expect(
        PlayerController.computeEffectiveKaraokeVolume(
          baseVolume: 0.7,
          gainResult: resOff,
        ),
        closeTo(70.0, 0.001),
      );

      // Mode changed to track -> attenuation applied
      final resTrack = computeReplayGain(
        replayGain: meta,
        mode: ReplayGainMode.track,
        preampDb: 0.0,
      );
      final volTrack = PlayerController.computeEffectiveKaraokeVolume(
        baseVolume: 0.7,
        gainResult: resTrack,
      );
      // 0.7 * 100 * 10^(-4/20) ≈ 70 * 0.630957 ≈ 44.167
      expect(volTrack, closeTo(44.167, 0.01));

      // Preamp changed from 0 to -3 dB -> total gain -7 dB
      final resPreamp = computeReplayGain(
        replayGain: meta,
        mode: ReplayGainMode.track,
        preampDb: -3.0,
      );
      final volPreamp = PlayerController.computeEffectiveKaraokeVolume(
        baseVolume: 0.7,
        gainResult: resPreamp,
      );
      // 70 * 10^(-7/20) ≈ 70 * 0.44668 ≈ 31.268
      expect(volPreamp, closeTo(31.268, 0.01));
    });
  });
}
