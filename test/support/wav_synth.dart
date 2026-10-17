import 'dart:math' as math;
import 'dart:typed_data';

/// Síntesis de WAV PCM 16-bit mono para tests de waveform real.
///
/// Genera audio REAL en memoria (sin Random para la forma: tono senoidal
/// determinista + silencios exactos), de modo que las pruebas A/B/C validan
/// que la waveform deriva del contenido y no del trackId.
class WavSynth {
  static const int sampleRate = 8000;

  /// Tono senoidal puro.
  static List<double> sineTone({
    required int numSamples,
    double freq = 440.0,
    double amplitude = 0.5,
    int sampleRate = sampleRate,
  }) {
    final out = List<double>.filled(numSamples, 0.0);
    for (var i = 0; i < numSamples; i++) {
      out[i] = amplitude * math.sin(2 * math.pi * freq * i / sampleRate);
    }
    return out;
  }

  /// WAV A: tono constante durante toda la duración.
  static Uint8List constantToneWav({
    required Duration duration,
    double freq = 440.0,
    double amplitude = 0.5,
    int sampleRate = sampleRate,
  }) {
    final n = (duration.inMilliseconds * sampleRate / 1000).round();
    return samplesToWavMono16(
      sineTone(numSamples: n, freq: freq, amplitude: amplitude),
      sampleRate: sampleRate,
    );
  }

  /// WAV B: silencio + tono fuerte + silencio.
  ///
  /// Por defecto 30 % silencio / 40 % tono / 30 % silencio.
  static Uint8List silenceToneSilenceWav({
    required Duration duration,
    double edgeFraction = 0.3,
    double freq = 440.0,
    double amplitude = 0.5,
    int sampleRate = sampleRate,
  }) {
    final n = (duration.inMilliseconds * sampleRate / 1000).round();
    final edge = (n * edgeFraction).round();
    final tone = sineTone(numSamples: n, freq: freq, amplitude: amplitude);
    final out = List<double>.filled(n, 0.0);
    for (var i = edge; i < n - edge; i++) {
      out[i] = tone[i];
    }
    // Silencios exactos en los bordes (los primeros/últimos [edge] samples
    // ya son 0.0).
    return samplesToWavMono16(out, sampleRate: sampleRate);
  }

  /// Empaqueta samples mono -1..1 en un WAV PCM 16-bit.
  static Uint8List samplesToWavMono16(
    List<double> samples, {
    int sampleRate = sampleRate,
  }) {
    const numChannels = 1;
    const bitsPerSample = 16;
    final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    const blockAlign = numChannels * bitsPerSample ~/ 8;
    final dataSize = samples.length * 2;
    final total = 44 + dataSize;
    final bytes = Uint8List(total);
    final bd = ByteData.sublistView(bytes);

    void writeString(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        bytes[offset + i] = s.codeUnitAt(i);
      }
    }

    writeString(0, 'RIFF');
    bd.setUint32(4, total - 8, Endian.little);
    writeString(8, 'WAVE');
    writeString(12, 'fmt ');
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little); // PCM
    bd.setUint16(22, numChannels, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, byteRate, Endian.little);
    bd.setUint16(32, blockAlign, Endian.little);
    bd.setUint16(34, bitsPerSample, Endian.little);
    writeString(36, 'data');
    bd.setUint32(40, dataSize, Endian.little);

    for (var i = 0; i < samples.length; i++) {
      final v = samples[i].clamp(-1.0, 1.0);
      bd.setInt16(44 + i * 2, (v * 32767).round(), Endian.little);
    }
    return bytes;
  }
}
