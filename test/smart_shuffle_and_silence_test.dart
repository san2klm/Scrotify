import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/navidrome_service.dart';
import 'package:navidrome_client/services/player_controller.dart';
import 'package:navidrome_client/services/settings_controller.dart';
import 'package:navidrome_client/services/waveform_service.dart';

import 'support/app_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Track makeTrack(String id, String artist, {String? artistId}) {
    return Track(
      id: id,
      title: 'Title $id',
      artist: artist,
      artistId: artistId ?? 'aid_$artist',
      album: 'Album $id',
      albumId: 'alb_$id',
      duration: '3:00',
    );
  }

  group('Fase 7: Smart Shuffle (Mezcla Inteligente)', () {
    late SettingsController settings;
    late FakeNavidrome navService;
    late PlayerController player;

    setUp(() {
      settings = SettingsController();
      navService = FakeNavidrome();
      player = PlayerController(navService, settings);
    });

    test('preserves keepIndex at current position', () {
      final tracks = [
        makeTrack('1', 'Artist A'),
        makeTrack('2', 'Artist B'),
        makeTrack('3', 'Artist C'),
        makeTrack('4', 'Artist D'),
        makeTrack('5', 'Artist E'),
      ];
      player.setQueueForTesting(tracks);
      settings.setSmartMixEnabled(true);

      const keepIndex = 2;
      final order = player.randomOrderKeepingForTesting(keepIndex, tracks.length);

      expect(order.length, tracks.length);
      expect(order[keepIndex], keepIndex);
      expect(order.toSet(), {0, 1, 2, 3, 4});
    });

    test('avoids repeating the same artist within window M=2 when alternatives exist', () {
      // 3 tracks of Artist A, 3 of Artist B, 3 of Artist C (9 tracks total)
      final tracks = [
        makeTrack('1', 'Taylor Swift', artistId: 'taylor'),
        makeTrack('2', 'Taylor Swift', artistId: 'taylor'),
        makeTrack('3', 'Taylor Swift', artistId: 'taylor'),
        makeTrack('4', 'Daft Punk', artistId: 'daft'),
        makeTrack('5', 'Daft Punk', artistId: 'daft'),
        makeTrack('6', 'Daft Punk', artistId: 'daft'),
        makeTrack('7', 'Paramore', artistId: 'paramore'),
        makeTrack('8', 'Paramore', artistId: 'paramore'),
        makeTrack('9', 'Paramore', artistId: 'paramore'),
      ];
      player.setQueueForTesting(tracks);
      settings.setSmartMixEnabled(true);

      // Run multiple iterations to test against various random seeds
      for (int seed = 0; seed < 10; seed++) {
        final order = player.randomOrderKeepingForTesting(0, tracks.length);
        expect(order.length, tracks.length);
        expect(order.toSet().length, tracks.length);

        // Check the sequence starting from keepIndex (0) onwards in order
        final artistSequence = order.map((idx) => tracks[idx].artistId).toList();
        for (int i = 0; i < artistSequence.length - 1; i++) {
          final current = artistSequence[i];
          final next1 = artistSequence[i + 1];
          expect(current != next1, isTrue,
              reason: 'Adjacent tracks at $i and ${i + 1} both have artist $current');
          if (i < artistSequence.length - 2) {
            final next2 = artistSequence[i + 2];
            // In a balanced 3x3 queue, with M=2 window, no artist should repeat at i and i+2
            expect(current != next2, isTrue,
                reason: 'Tracks at $i and ${i + 2} both have artist $current');
          }
        }
      }
    });

    test('completes gracefully without infinite loop when one artist dominates', () {
      // 8 tracks of Artist A and 1 track of Artist B
      final tracks = [
        makeTrack('1', 'Artist A'),
        makeTrack('2', 'Artist A'),
        makeTrack('3', 'Artist A'),
        makeTrack('4', 'Artist A'),
        makeTrack('5', 'Artist A'),
        makeTrack('6', 'Artist A'),
        makeTrack('7', 'Artist A'),
        makeTrack('8', 'Artist A'),
        makeTrack('9', 'Artist B'),
      ];
      player.setQueueForTesting(tracks);
      settings.setSmartMixEnabled(true);

      final order = player.randomOrderKeepingForTesting(0, tracks.length);
      expect(order.length, 9);
      expect(order.toSet().length, 9);
    });

    test('respects isSmartMixEnabled toggle in settings', () {
      settings.setSmartMixEnabled(false);
      expect(settings.isSmartMixEnabled, isFalse);

      settings.setSmartMixEnabled(true);
      expect(settings.isSmartMixEnabled, isTrue);
    });
  });

  group('Fase 7: Silence Detection (Eliminación de Silencios)', () {
    late SettingsController settings;
    late FakeNavidrome navService;
    late PlayerController player;

    setUp(() {
      settings = SettingsController();
      navService = FakeNavidrome();
      player = PlayerController(navService, settings);
    });

    test('detects useful start and end bounds when leading and trailing silence exists', () {
      // 10 bins, 100 seconds (10s per bin)
      // Bins 0, 1: silence (0.005 < 0.01)
      // Bins 2..7: audio (0.50 > 0.01)
      // Bins 8, 9: silence (0.002 < 0.01)
      final amplitudes = [
        0.002, 0.005, // 0..20s silence
        0.4, 0.6, 0.8, 0.7, 0.5, 0.4, // 20..80s audio
        0.003, 0.0, // 80..100s silence
      ];
      final waveform = WaveformData(
        trackId: 't1',
        amplitudes: amplitudes,
        duration: const Duration(seconds: 100),
      );

      player.computeSilenceBoundsForTesting(waveform);

      expect(player.usefulStartForTesting, isNotNull);
      expect(player.usefulEndForTesting, isNotNull);
      // firstIdx is 2 -> 2 * 10s = 20s
      expect(player.usefulStartForTesting!.inSeconds, 20);
      // lastIdx is 7 -> (7 + 1) * 10s = 80s (end of audio section)
      expect(player.usefulEndForTesting!.inSeconds, 80);
    });

    test('returns null bounds when entire track is silence', () {
      final amplitudes = [0.0, 0.001, 0.005, 0.002, 0.0];
      final waveform = WaveformData(
        trackId: 't2',
        amplitudes: amplitudes,
        duration: const Duration(seconds: 50),
      );

      player.computeSilenceBoundsForTesting(waveform);

      expect(player.usefulStartForTesting, isNull);
      expect(player.usefulEndForTesting, isNull);
    });

    test('returns null bounds when amplitude data is empty', () {
      const waveform = WaveformData(
        trackId: 't3',
        amplitudes: [],
        duration: Duration(seconds: 50),
      );

      player.computeSilenceBoundsForTesting(waveform);

      expect(player.usefulStartForTesting, isNull);
      expect(player.usefulEndForTesting, isNull);
    });

    test('sets start at zero when no leading silence is present', () {
      final amplitudes = [0.8, 0.6, 0.5, 0.0, 0.0];
      final waveform = WaveformData(
        trackId: 't4',
        amplitudes: amplitudes,
        duration: const Duration(seconds: 50),
      );

      player.computeSilenceBoundsForTesting(waveform);

      expect(player.usefulStartForTesting, Duration.zero);
      expect(player.usefulEndForTesting!.inSeconds, 30);
    });

    test('respects silenceRemovalEnabled setting toggle', () {
      settings.setSilenceRemovalEnabled(true);
      expect(settings.silenceRemovalEnabled, isTrue);

      settings.setSilenceRemovalEnabled(false);
      expect(settings.silenceRemovalEnabled, isFalse);
    });
  });
}
