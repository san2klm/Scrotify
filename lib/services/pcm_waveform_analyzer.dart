import 'dart:math' as math;

/// Analizador PCM puro (sin IO, sin dependencias): convierte samples mono en
/// amplitudes por ventana temporal.
///
/// Algoritmo REAL por ventana:
///   rms  = sqrt(sum(sample^2) / n)
///   peak = max(abs(sample))
///   amplitude = rms * 0.75 + peak * 0.25
///
/// Después se normaliza por el máximo global para mapear a 0.0..1.0.
/// El silencio digital permanece en ~0.0 (no se amplifica ruido).
///
/// NO usa Random, hash, sin/cos ni curvas inventadas: la salida depende
/// únicamente de los samples de entrada.
class PcmWaveformAnalyzer {
  static const double rmsWeight = 0.75;
  static const double peakWeight = 0.25;

  /// Analiza [monoSamples] (rango esperado -1.0..1.0) en [targetBins] ventanas.
  static List<double> analyzeMonoFloat32(
    List<double> monoSamples,
    int targetBins,
  ) {
    final bins = targetBins.clamp(16, 2048);
    if (monoSamples.isEmpty) {
      return List<double>.filled(bins, 0.0);
    }
    final total = monoSamples.length;
    final out = List<double>.filled(bins, 0.0);

    for (var i = 0; i < bins; i++) {
      final start = (i * total / bins).floor();
      final end = (((i + 1) * total) / bins).floor().clamp(0, total);
      if (end <= start) {
        final s = monoSamples[start.clamp(0, total - 1)].clamp(-1.0, 1.0);
        out[i] = s.abs();
        continue;
      }
      var sumSq = 0.0;
      var peak = 0.0;
      for (var j = start; j < end; j++) {
        final s = monoSamples[j].clamp(-1.0, 1.0);
        final a = s.abs();
        sumSq += s * s;
        if (a > peak) peak = a;
      }
      final count = end - start;
      final rms = math.sqrt(sumSq / count);
      out[i] = (rms * rmsWeight + peak * peakWeight).clamp(0.0, 1.0);
    }

    return _normalize(out);
  }

  /// Calcula el número de bins objetivo para una duración dada.
  ///
  /// ~1 bin cada 50 ms, limitado a [16, 2048].
  static int targetBinsForDuration(Duration duration) {
    return (duration.inMilliseconds ~/ 50).clamp(16, 2048);
  }

  static List<double> _normalize(List<double> values) {
    var maxVal = 0.0;
    for (final v in values) {
      if (v > maxVal) maxVal = v;
    }
    // Silencio digital: no amplificar ruido residual.
    if (maxVal < 1e-6) {
      return List<double>.filled(values.length, 0.0);
    }
    return values.map((v) => (v / maxVal).clamp(0.0, 1.0)).toList();
  }
}
