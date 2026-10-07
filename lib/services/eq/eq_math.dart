// Matemática del ecualizador: coeficientes biquad (RBJ Audio EQ Cookbook) y
// respuesta en frecuencia. Es código Dart puro (sin Flutter) para poder:
//   * dibujar la curva real en la UI,
//   * calcular el preamp automático anti-clipping,
//   * traducir cualquier curva a los ecualizadores de bandas fijas de Android,
//   * convertir entre modos (simple → 10 bandas, paramétrico → 10 bandas).

import 'dart:math' as math;

import '../../models/eq_models.dart';

class Biquad {
  final double b0, b1, b2, a1, a2; // normalizados (a0 = 1)
  const Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  factory Biquad.fromBand(EqBand band, double sampleRate) {
    // Si la frecuencia supera Nyquist el filtro se vuelve inestable: se acota.
    final f0 = band.frequency.clamp(10.0, sampleRate * 0.49);
    final w0 = 2 * math.pi * f0 / sampleRate;
    final cosW = math.cos(w0);
    final sinW = math.sin(w0);
    final alpha = sinW / (2 * band.q);
    final a = math.pow(10, band.gainDb / 40).toDouble();
    final sqrtA2alpha = 2 * math.sqrt(a) * alpha;

    double b0, b1, b2, a0, a1, a2;
    switch (band.type) {
      case EqFilterType.peaking:
        b0 = 1 + alpha * a;
        b1 = -2 * cosW;
        b2 = 1 - alpha * a;
        a0 = 1 + alpha / a;
        a1 = -2 * cosW;
        a2 = 1 - alpha / a;
      case EqFilterType.lowShelf:
        b0 = a * ((a + 1) - (a - 1) * cosW + sqrtA2alpha);
        b1 = 2 * a * ((a - 1) - (a + 1) * cosW);
        b2 = a * ((a + 1) - (a - 1) * cosW - sqrtA2alpha);
        a0 = (a + 1) + (a - 1) * cosW + sqrtA2alpha;
        a1 = -2 * ((a - 1) + (a + 1) * cosW);
        a2 = (a + 1) + (a - 1) * cosW - sqrtA2alpha;
      case EqFilterType.highShelf:
        b0 = a * ((a + 1) + (a - 1) * cosW + sqrtA2alpha);
        b1 = -2 * a * ((a - 1) + (a + 1) * cosW);
        b2 = a * ((a + 1) + (a - 1) * cosW - sqrtA2alpha);
        a0 = (a + 1) - (a - 1) * cosW + sqrtA2alpha;
        a1 = 2 * ((a - 1) - (a + 1) * cosW);
        a2 = (a + 1) - (a - 1) * cosW - sqrtA2alpha;
      case EqFilterType.lowPass:
        b0 = (1 - cosW) / 2;
        b1 = 1 - cosW;
        b2 = (1 - cosW) / 2;
        a0 = 1 + alpha;
        a1 = -2 * cosW;
        a2 = 1 - alpha;
      case EqFilterType.highPass:
        b0 = (1 + cosW) / 2;
        b1 = -(1 + cosW);
        b2 = (1 + cosW) / 2;
        a0 = 1 + alpha;
        a1 = -2 * cosW;
        a2 = 1 - alpha;
      case EqFilterType.notch:
        b0 = 1;
        b1 = -2 * cosW;
        b2 = 1;
        a0 = 1 + alpha;
        a1 = -2 * cosW;
        a2 = 1 - alpha;
    }
    return Biquad(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0);
  }

  /// Magnitud en dB de este filtro a la frecuencia [f].
  double magnitudeDb(double f, double sampleRate) {
    final w = 2 * math.pi * f / sampleRate;
    final c1 = math.cos(w), s1 = math.sin(w);
    final c2 = math.cos(2 * w), s2 = math.sin(2 * w);
    final nr = b0 + b1 * c1 + b2 * c2;
    final ni = -(b1 * s1 + b2 * s2);
    final dr = 1 + a1 * c1 + a2 * c2;
    final di = -(a1 * s1 + a2 * s2);
    final num2 = nr * nr + ni * ni;
    final den2 = dr * dr + di * di;
    if (num2 <= 1e-30) return -120; // centro exacto de un notch
    return 10 * math.log(num2 / den2) / math.ln10;
  }
}

class EqMath {
  /// Frecuencia de muestreo de referencia para cálculos de UI. 48 kHz es la
  /// frecuencia nativa del mezclador en Android, iOS y la mayoría de PCs.
  static const double referenceSampleRate = 48000;

  /// Respuesta combinada (dB) de una cadena de filtros a la frecuencia [f].
  static double responseDb(
    List<EqBand> bands,
    double f, {
    double sampleRate = referenceSampleRate,
  }) {
    var total = 0.0;
    for (final b in bands) {
      if (!b.enabled) continue;
      total += Biquad.fromBand(b, sampleRate).magnitudeDb(f, sampleRate);
    }
    return total;
  }

  /// Rejilla logarítmica de 20 Hz a 20 kHz (para pintar y para buscar picos).
  static List<double> logGrid(
      {int points = 256, double lo = 20, double hi = 20000}) {
    final l0 = math.log(lo), l1 = math.log(hi);
    return List.generate(
      points,
      (i) => math.exp(l0 + (l1 - l0) * i / (points - 1)),
    );
  }

  /// Curva completa muestreada; útil para el `CustomPainter`.
  static List<double> curve(List<EqBand> bands, List<double> freqs) =>
      [for (final f in freqs) responseDb(bands, f)];

  /// Mayor realce de la curva en el rango audible (0 si sólo hay cortes).
  static double maxBoostDb(List<EqBand> bands) {
    if (bands.isEmpty) return 0;
    var peak = 0.0;
    for (final f in logGrid(points: 512)) {
      final v = responseDb(bands, f);
      if (v > peak) peak = v;
    }
    return peak;
  }

  /// Preamp anti-clipping: compensa exactamente el mayor realce más un margen
  /// de 0.3 dB para picos inter-muestra (true peak).
  static double autoPreampDb(List<EqBand> bands) {
    final boost = maxBoostDb(bands);
    if (boost <= 0.05) return 0;
    return -(boost + 0.3);
  }

  /// Ganancia final a aplicar delante de la cadena de filtros.
  static double effectivePreampDb(EqProfile p) =>
      p.autoPreamp ? autoPreampDb(p.effectiveBands) : p.preampDb;

  /// Convierte cualquier curva a un ecualizador gráfico de bandas fijas.
  ///
  /// No basta con "leer" la curva en cada centro: las campanas vecinas se
  /// solapan y el resultado tendría más realce del pedido. Se resuelve por
  /// iteración de punto fijo (5–8 pasadas convergen a < 0.2 dB).
  static List<EqBand> fitToGraphic(
    List<EqBand> source,
    List<double> centers, {
    double q = kOneOctaveQ,
    double minDb = -12,
    double maxDb = 12,
    int iterations = 8,
  }) {
    final target = [for (final f in centers) responseDb(source, f)];
    var gains = [...target];
    for (var it = 0; it < iterations; it++) {
      final bands = [
        for (var i = 0; i < centers.length; i++)
          EqBand.peaking(centers[i], gains[i], q: q),
      ];
      for (var i = 0; i < centers.length; i++) {
        final err = target[i] - responseDb(bands, centers[i]);
        gains[i] = (gains[i] + err * 0.8).clamp(minDb, maxDb);
      }
    }
    return [
      for (var i = 0; i < centers.length; i++)
        EqBand.peaking(centers[i], _round1(gains[i]), q: q),
    ];
  }

  static double _round1(double v) => (v * 10).roundToDouble() / 10;
}
