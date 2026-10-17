import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crotowave/services/audio_waveform_service.dart';
import 'package:crotowave/services/pcm_waveform_analyzer.dart';
import 'package:crotowave/services/waveform_service.dart';

import 'support/wav_synth.dart';

/// Validación de la WAVEFORM TEMPORAL REAL (Fase 6 corregida).
///
/// La forma deriva del audio REAL: PCM → ventanas → RMS/peak → normalización.
/// El trackId solo es clave de caché, nunca fuente de la forma.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const duration = Duration(seconds: 10);

  group('PRUEBA C — silencio + tono (estructura real)', () {
    test('el centro es fuerte y los bordes son silencio', () async {
      final dir = await Directory.systemTemp.createTemp('waveform_test_c_');
      final service = AudioWaveformService(cacheDirOverride: dir);
      try {
        final wavB = WavSynth.silenceToneSilenceWav(duration: duration);
        final wave = await service.getWaveformForBytes(
          'test-track-c',
          wavB,
          duration: duration,
          fileNameHint: 'b.wav',
        );

        expect(wave.amplitudes.isNotEmpty, isTrue);
        final n = wave.amplitudes.length;
        final third = n ~/ 3;
        double mean(int from, int to) {
          var s = 0.0;
          for (var i = from; i < to; i++) {
            s += wave.amplitudes[i];
          }
          return s / (to - from);
        }

        final start = mean(0, third);
        final center = mean(third, 2 * third);
        final end = mean(2 * third, n);

        // ignore: avoid_print
        print('PRUEBA C: n=$n start=$start center=$center end=$end');
        // ignore: avoid_print
        print('PRUEBA C waveform: ${wave.amplitudes}');

        expect(center, greaterThan(0.5),
            reason: 'el tono central debe ser fuerte (centro=$center)');
        expect(start, lessThan(0.2),
            reason:
                'el silencio inicial debe dar barras bajas (inicio=$start)');
        expect(end, lessThan(0.2),
            reason: 'el silencio final debe dar barras bajas (final=$end)');
        expect(center, greaterThan(start * 3), reason: 'centro >> inicio');
        expect(center, greaterThan(end * 3), reason: 'centro >> final');
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('tono constante produce barras altas y parejas', () async {
      final dir = await Directory.systemTemp.createTemp('waveform_test_const_');
      final service = AudioWaveformService(cacheDirOverride: dir);
      try {
        final wavA = WavSynth.constantToneWav(duration: duration);
        final wave = await service.getWaveformForBytes(
          'test-track-const',
          wavA,
          duration: duration,
          fileNameHint: 'a.wav',
        );
        final mean =
            wave.amplitudes.reduce((a, b) => a + b) / wave.amplitudes.length;
        // ignore: avoid_print
        print('CONST: mean=$mean wave=${wave.amplitudes}');
        expect(mean, greaterThan(0.7),
            reason: 'tono constante → ▄▄▄▄▄▄▄▄▄▄ (mean=$mean)');
        for (final a in wave.amplitudes) {
          expect(a, inInclusiveRange(0.0, 1.0));
        }
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('PRUEBA A — mismo trackId, audio diferente → waveforms DIFERENTES', () {
    test('la forma depende del AUDIO, no del trackId', () async {
      final dir = await Directory.systemTemp.createTemp('waveform_test_a_');
      final service = AudioWaveformService(cacheDirOverride: dir);
      try {
        const trackId = 'test-track';
        final wavA = WavSynth.constantToneWav(duration: duration);
        final wavB = WavSynth.silenceToneSilenceWav(duration: duration);

        final waveA = await service.getWaveformForBytes(
          trackId,
          wavA,
          duration: duration,
          fileNameHint: 'a.wav',
        );
        final waveB = await service.getWaveformForBytes(
          trackId,
          wavB,
          duration: duration,
          fileNameHint: 'b.wav',
        );

        // ignore: avoid_print
        print('PRUEBA A waveform A: ${waveA.amplitudes}');
        // ignore: avoid_print
        print('PRUEBA A waveform B: ${waveB.amplitudes}');

        expect(waveA.amplitudes.length, equals(waveB.amplitudes.length));
        var maxDiff = 0.0;
        var meanDiff = 0.0;
        for (var i = 0; i < waveA.amplitudes.length; i++) {
          final d = (waveA.amplitudes[i] - waveB.amplitudes[i]).abs();
          meanDiff += d;
          if (d > maxDiff) maxDiff = d;
        }
        meanDiff /= waveA.amplitudes.length;
        // ignore: avoid_print
        print(
            'PRUEBA A: maxDiff=$maxDiff meanDiff=$meanDiff → PASS=${maxDiff > 0.3}');
        expect(maxDiff, greaterThan(0.3),
            reason:
                'mismo ID con audio distinto debe dar formas distintas (maxDiff=$maxDiff)');
        expect(meanDiff, greaterThan(0.1),
            reason: 'diferencia estructural media (meanDiff=$meanDiff)');
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('PRUEBA B — mismo audio, trackId diferente → waveforms EQUIVALENTES',
      () {
    test('distinto ID con mismo audio produce la misma forma', () async {
      final dir = await Directory.systemTemp.createTemp('waveform_test_b_');
      final service = AudioWaveformService(cacheDirOverride: dir);
      try {
        final wav = WavSynth.silenceToneSilenceWav(duration: duration);
        final waveA = await service.getWaveformForBytes(
          'track-id-1',
          wav,
          duration: duration,
          fileNameHint: 'same.wav',
        );
        final waveB = await service.getWaveformForBytes(
          'track-id-2',
          wav,
          duration: duration,
          fileNameHint: 'same.wav',
        );

        // ignore: avoid_print
        print('PRUEBA B waveform A: ${waveA.amplitudes}');
        // ignore: avoid_print
        print('PRUEBA B waveform B: ${waveB.amplitudes}');

        expect(waveA.amplitudes.length, equals(waveB.amplitudes.length));
        var maxDiff = 0.0;
        for (var i = 0; i < waveA.amplitudes.length; i++) {
          final d = (waveA.amplitudes[i] - waveB.amplitudes[i]).abs();
          if (d > maxDiff) maxDiff = d;
        }
        // ignore: avoid_print
        print('PRUEBA B: maxDiff=$maxDiff → PASS=${maxDiff < 0.01}');
        expect(maxDiff, lessThan(0.01),
            reason:
                'mismo audio con distinto ID debe ser equivalente (maxDiff=$maxDiff)');
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('archivos locales + caché v2', () {
    test('getWaveformForFile analiza el archivo real', () async {
      final dir = await Directory.systemTemp.createTemp('waveform_file_');
      final service = AudioWaveformService(cacheDirOverride: dir);
      try {
        final wav = WavSynth.silenceToneSilenceWav(duration: duration);
        final file = File('${dir.path}/tone.wav');
        await file.writeAsBytes(wav, flush: true);
        final wave = await service.getWaveformForFile(
          'file-track',
          file.path,
          duration: duration,
        );
        expect(wave.amplitudes.length, greaterThan(16));
        final maxAmp = wave.amplitudes.reduce((a, b) => a > b ? a : b);
        expect(maxAmp, lessThanOrEqualTo(1.0));
        expect(maxAmp, greaterThan(0.9));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('la caché v2 guarda version=2 y el contenido analizado', () async {
      final dir = await Directory.systemTemp.createTemp('waveform_cache_');
      final service = AudioWaveformService(cacheDirOverride: dir);
      try {
        final wav = WavSynth.constantToneWav(duration: duration);
        final first = await service.getWaveformForBytes(
          'cached-track',
          wav,
          duration: duration,
          fileNameHint: 'a.wav',
        );
        final second = await service.getWaveformForBytes(
          'cached-track',
          wav,
          duration: duration,
          fileNameHint: 'a.wav',
        );
        expect(second.amplitudes, equals(first.amplitudes));

        final entries = dir.listSync().whereType<File>().toList();
        expect(entries.isNotEmpty, isTrue,
            reason: 'debe existir al menos un JSON de caché');
        var foundV2 = false;
        for (final f in entries) {
          final content = await f.readAsString();
          if (content.contains('"version":2') &&
              content.contains('cached-track')) {
            foundV2 = true;
          }
        }
        expect(foundV2, isTrue,
            reason: 'la caché debe tener version 2 y el trackId');
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('criterio 4 — sin fuentes sintéticas en el pipeline real', () {
    test('el código real no usa Random/hash/sin/cos para la amplitud', () {
      final libDir = Directory('lib/services');
      const realFiles = [
        'audio_waveform_service.dart',
        'pcm_waveform_analyzer.dart',
        'wav_decoder.dart',
        'ffmpeg_waveform_decoder.dart',
      ];
      final forbidden = [
        RegExp(r'\bRandom\s*\('),
        RegExp(r'\.hashCode'),
        RegExp(r'\bRandom\.secure'),
        RegExp(r'\bsin\s*\('),
        RegExp(r'\bcos\s*\('),
      ];
      for (final name in realFiles) {
        final content = File('${libDir.path}/$name').readAsStringSync();
        for (final pattern in forbidden) {
          expect(pattern.hasMatch(content), isFalse,
              reason: '$name contiene patrón prohibido: ${pattern.pattern}');
        }
      }
    });

    test('PcmWaveformAnalyzer: silencio → 0, tono → 1 (sin normalizar ruido)',
        () {
      final silence = List<double>.filled(8000, 0.0);
      final out0 = PcmWaveformAnalyzer.analyzeMonoFloat32(silence, 64);
      expect(out0.every((v) => v == 0.0), isTrue);

      final tone = WavSynth.sineTone(numSamples: 8000, amplitude: 0.5);
      final out1 = PcmWaveformAnalyzer.analyzeMonoFloat32(tone, 64);
      final maxV = out1.reduce((a, b) => a > b ? a : b);
      expect(maxV, closeTo(1.0, 0.0001));
    });
  });

  group('WaveformData', () {
    test('downsample por peak reduce y preserva picos', () {
      const waveform = WaveformData(
        trackId: '123',
        duration: Duration(seconds: 10),
        amplitudes: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8],
      );
      final downsampled = waveform.downsample(4);
      expect(downsampled.amplitudes.length, equals(4));
      // Peak por ventana de 2: [0.2, 0.4, 0.6, 0.8].
      expect(downsampled.amplitudes[0], closeTo(0.2, 0.001));
      expect(downsampled.amplitudes[1], closeTo(0.4, 0.001));
      expect(downsampled.amplitudes[2], closeTo(0.6, 0.001));
      expect(downsampled.amplitudes[3], closeTo(0.8, 0.001));
    });
  });
}
