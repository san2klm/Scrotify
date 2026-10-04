import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/equalizer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EqualizerService', () {
    test('initializes with 10 bands and default flat gains', () {
      final eq = EqualizerService();

      expect(EqualizerService.bandCount, 10);
      expect(EqualizerService.bandFrequencies, [
        31,
        62,
        125,
        250,
        500,
        1000,
        2000,
        4000,
        8000,
        16000,
      ]);
      expect(EqualizerService.bandLabels.length, 10);
      expect(eq.gains.length, 10);
      expect(eq.gains.every((g) => g == 0.0), isTrue);
      expect(eq.currentPreset, 'Flat');
      expect(eq.enabled, isFalse);
    });

    test('clamps band gains between -12.0 dB and +12.0 dB', () {
      final eq = EqualizerService();

      eq.setBandGain(0, 15.5);
      expect(eq.gains[0], 12.0);

      eq.setBandGain(1, -25.0);
      expect(eq.gains[1], -12.0);

      eq.setBandGain(2, 4.5);
      expect(eq.gains[2], 4.5);

      // Invalid index does not crash or modify
      eq.setBandGain(-1, 5.0);
      eq.setBandGain(10, 5.0);
      expect(eq.gains.length, 10);
    });

    test('applies presets correctly and detects custom edits', () {
      final eq = EqualizerService();

      eq.applyPreset('Bass Boost');
      expect(eq.currentPreset, 'Bass Boost');
      expect(eq.gains, EqualizerService.presets['Bass Boost']);

      eq.applyPreset('Vocal');
      expect(eq.currentPreset, 'Vocal');
      expect(eq.gains, EqualizerService.presets['Vocal']);

      eq.applyPreset('Treble Boost');
      expect(eq.currentPreset, 'Treble Boost');
      expect(eq.gains, EqualizerService.presets['Treble Boost']);

      // Modifying one band marks it as Personalizado
      eq.setBandGain(0, 1.0);
      expect(eq.currentPreset, 'Personalizado');

      // Reset restores Flat preset
      eq.reset();
      expect(eq.currentPreset, 'Flat');
      expect(eq.gains.every((g) => g == 0.0), isTrue);
    });

    test('toggles enabled state and bypass correctly', () {
      final eq = EqualizerService();

      expect(eq.enabled, isFalse);
      eq.setEnabled(true);
      expect(eq.enabled, isTrue);

      eq.toggleEnabled();
      expect(eq.enabled, isFalse);

      eq.toggleEnabled();
      expect(eq.enabled, isTrue);

      eq.bypass();
      expect(eq.enabled, isFalse);
    });

    test('honestly reports that real-time backend DSP is not active', () {
      final eq = EqualizerService();

      expect(eq.isBackendSupported, isFalse);
      expect(eq.backendStatusMessage, contains('just_audio'));
      expect(eq.backendStatusMessage, contains('media_kit'));
    });
  });
}
