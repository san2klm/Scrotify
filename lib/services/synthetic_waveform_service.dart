import 'dart:math';

import 'waveform_service.dart';

/// Generador SINTÉTICO determinista (hash del trackId + Random con seed).
///
/// ⚠️ SOLO para tests aislados de UI que necesiten un [WaveformData] dummy
/// sin audio real. NUNCA debe usarse para reproducción real: la waveform de
/// producción proviene de [AudioWaveformService], que analiza el PCM real.
///
/// Se conserva con este nombre explícito para que ningún revisor confunda
/// datos pseudoaleatorios con una waveform real.
class SyntheticWaveformService implements WaveformService {
  Future<WaveformData> generateWaveform(
      String trackId, Duration duration) async {
    await Future.delayed(const Duration(milliseconds: 10));
    final seed = _hash(trackId);
    final rng = Random(seed);
    const sampleIntervalMs = 20;
    final sampleCount = (duration.inMilliseconds / sampleIntervalMs).ceil();
    const maxSamples = 2048;
    final actualSampleCount = sampleCount.clamp(1, maxSamples);
    final amplitudes = <double>[];
    for (var i = 0; i < actualSampleCount; i++) {
      final base = rng.nextDouble();
      final variation = rng.nextDouble() * 0.3;
      final position = i / actualSampleCount;
      final envelope = 0.3 + 0.7 * position * (1.0 - position) * 4.0;
      final value = (base * 0.4 + variation * 0.6) * envelope;
      amplitudes.add(value.clamp(0.0, 1.0));
      if (i > 0) {
        amplitudes[i] = amplitudes[i - 1] * 0.3 + amplitudes[i] * 0.7;
      }
    }
    final maxVal =
        amplitudes.isEmpty ? 1.0 : amplitudes.reduce(max);
    if (maxVal > 0) {
      for (var i = 0; i < amplitudes.length; i++) {
        amplitudes[i] = amplitudes[i] / maxVal;
      }
    }
    return WaveformData(
        trackId: trackId, duration: duration, amplitudes: amplitudes);
  }

  int _hash(String input) {
    var hash = 0;
    for (var i = 0; i < input.length; i++) {
      hash = ((hash << 5) - hash + input.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    return hash;
  }

  @override
  Future<WaveformData> getWaveform(
      String trackId, String streamUrl, Duration duration) {
    // El streamUrl se ignora a propósito: es sintético (solo tests).
    return generateWaveform(trackId, duration);
  }
}
