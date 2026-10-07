// Curva de respuesta real del ecualizador (calculada con los mismos biquads
// que se aplican al audio). Se usa en los tres modos.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/eq_models.dart';
import '../services/eq/eq_math.dart';

class EqResponseCurve extends StatelessWidget {
  final List<EqBand> bands;
  final double preampDb;
  final double rangeDb;
  final int? highlightedBand;
  final double height;

  const EqResponseCurve({
    super.key,
    required this.bands,
    required this.preampDb,
    this.rangeDb = 15,
    this.highlightedBand,
    this.height = 160,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _CurvePainter(
            bands: bands,
            preampDb: preampDb,
            rangeDb: rangeDb,
            highlighted: highlightedBand,
            accent: cs.primary,
            grid: cs.onSurface.withValues(alpha: 0.12),
            label: cs.onSurface.withValues(alpha: 0.55),
            preampColor: cs.tertiary,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  final List<EqBand> bands;
  final double preampDb, rangeDb;
  final int? highlighted;
  final Color accent, grid, label, preampColor;

  _CurvePainter({
    required this.bands,
    required this.preampDb,
    required this.rangeDb,
    required this.highlighted,
    required this.accent,
    required this.grid,
    required this.label,
    required this.preampColor,
  });

  static const _lo = 20.0, _hi = 20000.0;

  double _x(double f, double w) =>
      w * (math.log(f / _lo) / math.log(_hi / _lo));
  double _y(double db, double h) =>
      h / 2 - (db.clamp(-rangeDb, rangeDb) / rangeDb) * (h / 2 - 6);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;

    // Rejilla de frecuencias y etiquetas.
    const marks = <(double, String)>[
      (50.0, '50'),
      (100.0, '100'),
      (500.0, '500'),
      (1000.0, '1k'),
      (5000.0, '5k'),
      (10000.0, '10k'),
    ];
    for (final e in marks) {
      final x = _x(e.$1, w);
      canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaint);
      final tp = TextPainter(
        text: TextSpan(text: e.$2, style: TextStyle(fontSize: 9, color: label)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + 2, h - tp.height - 1));
    }
    // Línea de 0 dB.
    canvas.drawLine(
        Offset(0, _y(0, h)), Offset(w, _y(0, h)), gridPaint..strokeWidth = 1.5);

    final freqs = EqMath.logGrid(points: math.max(64, (w / 3).round()));

    // Banda resaltada (modo profesional).
    if (highlighted != null && highlighted! < bands.length) {
      final single = EqMath.curve([bands[highlighted!]], freqs);
      final p = Path()..moveTo(0, _y(0, h));
      for (var i = 0; i < freqs.length; i++) {
        p.lineTo(_x(freqs[i], w), _y(single[i], h));
      }
      p.lineTo(w, _y(0, h));
      canvas.drawPath(p, Paint()..color = accent.withValues(alpha: 0.18));
    }

    // Curva total (sin preamp: lo que el usuario "pidió").
    final total = EqMath.curve(bands, freqs);
    final path = Path();
    for (var i = 0; i < freqs.length; i++) {
      final pt = Offset(_x(freqs[i], w), _y(total[i], h));
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round,
    );

    // Preamp: línea discontinua que muestra cuánto se baja para no saturar.
    if (preampDb.abs() >= 0.1) {
      final y = _y(preampDb, h);
      final dash = Paint()
        ..color = preampColor
        ..strokeWidth = 1.2;
      for (double x = 0; x < w; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, w), y), dash);
      }
    }

    // Puntos de control.
    for (var i = 0; i < bands.length; i++) {
      final b = bands[i];
      if (!b.enabled) continue;
      final c = Offset(_x(b.frequency.clamp(_lo, _hi), w),
          _y(b.type.usesGain ? b.gainDb : 0, h));
      canvas.drawCircle(c, i == highlighted ? 6 : 4, Paint()..color = accent);
    }
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) =>
      old.bands != bands ||
      old.preampDb != preampDb ||
      old.highlighted != highlighted ||
      old.accent != accent;
}
