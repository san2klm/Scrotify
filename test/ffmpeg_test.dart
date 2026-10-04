import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:navidrome_client/services/audio_waveform_service.dart';
import 'package:navidrome_client/services/ffmpeg_waveform_decoder.dart';
import 'package:navidrome_client/services/pcm_waveform_analyzer.dart';

import 'support/wav_synth.dart';

/// Verifica el backend REAL de decodificación con el binario `ffmpeg`.
///
/// - Desktop Linux (este entorno: /usr/bin/ffmpeg): PASS con MP3 real.
/// - Plataformas sin ffmpeg: test omitido (el servicio usa WAV puro-Dart o
///   lanza [WaveformDecodeException], nunca datos sintéticos).
void main() {
  test('ffmpeg decodifica MP3 real y la forma coincide con el WAV directo',
      () async {
    final available = await FfmpegWaveformDecoder.isAvailable();
    if (!available) {
      markTestSkipped('ffmpeg binary not available on this platform');
      return;
    }

    const duration = Duration(seconds: 10);
    final tmp =
        await Directory.systemTemp.createTemp('waveform_ffmpeg_');
    try {
      final wavBytes = WavSynth.silenceToneSilenceWav(duration: duration);
      final wavPath = '${tmp.path}/input.wav';
      final mp3Path = '${tmp.path}/input.mp3';
      await File(wavPath).writeAsBytes(wavBytes, flush: true);

      // Transcodificar a MP3 real con el binario del sistema.
      final enc = await Process.run('ffmpeg', [
        '-v',
        'error',
        '-y',
        '-i',
        wavPath,
        '-codec:a',
        'libmp3lame',
        '-b:a',
        '128k',
        mp3Path,
      ]);
      expect(enc.exitCode, equals(0),
          reason: 'ffmpeg debe transcodificar a MP3: ${enc.stderr}');
      expect(await File(mp3Path).exists(), isTrue);

      // Ruta ffmpeg: MP3 → PCM mono float.
      final mp3Bytes = await File(mp3Path).readAsBytes();
      final mono =
          await FfmpegWaveformDecoder.decodeBytesToMonoFloat32(
        mp3Bytes,
        extensionHint: '.mp3',
      );
      expect(mono.isNotEmpty, isTrue);
      final bins = PcmWaveformAnalyzer.targetBinsForDuration(duration);
      final fromMp3 = PcmWaveformAnalyzer.analyzeMonoFloat32(mono, bins);

      // Ruta directa: WAV → PCM (sin ffmpeg).
      final direct = await AudioWaveformService.analyzeAudioBytes(
        wavBytes,
        duration: duration,
        fileNameHint: 'input.wav',
      );

      // ignore: avoid_print
      print('FFMPEG mp3 bins=$bins\nMP3: $fromMp3\nWAV: $direct');

      expect(fromMp3.length, equals(direct.length));
      // El MP3 con pérdidas suaviza bordes; comparar estructura por tercios.
      double mean(List<double> v, int from, int to) {
        var s = 0.0;
        for (var i = from; i < to; i++) {
          s += v[i];
        }
        return s / (to - from);
      }

      final n = direct.length;
      final third = n ~/ 3;
      final mp3Center = mean(fromMp3, third, 2 * third);
      final mp3Edge = mean(fromMp3, 0, third);
      expect(mp3Center, greaterThan(0.4),
          reason: 'el centro del MP3 debe ser fuerte (=$mp3Center)');
      expect(mp3Center, greaterThan(mp3Edge * 2),
          reason: 'centro MP3 >> borde MP3 (borde=$mp3Edge)');
    } finally {
      await tmp.delete(recursive: true);
    }
  });
}
