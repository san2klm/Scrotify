import 'package:flutter/material.dart';
import '../services/waveform_service.dart';
import '../utils/app_colors.dart';

class WaveformProgressBar extends StatefulWidget {
  final WaveformData? waveform;
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final Color? activeColor;
  final Color? inactiveColor;

  const WaveformProgressBar({
    super.key,
    this.waveform,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.activeColor,
    this.inactiveColor,
  });

  @override
  State<WaveformProgressBar> createState() => _WaveformProgressBarState();
}

class _WaveformProgressBarState extends State<WaveformProgressBar> {
  double? _dragPosition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color activeColor;
    Color inactiveColor;

    if (widget.activeColor != null) {
      activeColor = widget.activeColor!;
    } else {
      try {
        activeColor = context.waveformPlayed;
      } catch (_) {
        activeColor = theme.colorScheme.primary;
      }
    }

    if (widget.inactiveColor != null) {
      inactiveColor = widget.inactiveColor!;
    } else {
      try {
        inactiveColor = context.waveformUnplayed;
      } catch (_) {
        inactiveColor =
            theme.colorScheme.onSurface.withValues(alpha: 0.3);
      }
    }

    final double currentPositionMs = _dragPosition != null
        ? _dragPosition!
        : widget.position.inMilliseconds.toDouble();
    final double durationMs = widget.duration.inMilliseconds.toDouble();
    final double progress =
        durationMs == 0 ? 0 : (currentPositionMs / durationMs).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        // Altura dentro del rango visible 48-64 px.
        const double height = 56.0;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (details) {
            final double x = details.localPosition.dx;
            final double pct = (x / width).clamp(0.0, 1.0);
            setState(() {
              _dragPosition = pct * durationMs;
            });
          },
          onPanEnd: (_) {
            if (_dragPosition != null) {
              widget.onSeek(Duration(milliseconds: _dragPosition!.round()));
              setState(() {
                _dragPosition = null;
              });
            }
          },
          onTapDown: (details) {
            final double x = details.localPosition.dx;
            final double pct = (x / width).clamp(0.0, 1.0);
            widget.onSeek(Duration(milliseconds: (pct * durationMs).round()));
          },
          child: CustomPaint(
            size: Size(width, height),
            painter: _WaveformPainter(
              waveform: widget.waveform,
              progress: progress,
              activeColor: activeColor,
              inactiveColor: inactiveColor,
            ),
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final WaveformData? waveform;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  // Geometría objetivo: barras de ~2 px con gap de ~1 px.
  static const double targetBarWidth = 2.0;
  static const double targetGap = 1.0;

  _WaveformPainter({
    this.waveform,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  /// Downsampling por peak para ajustar [values] a [targetLength].
  /// Visible para tests.
  static List<double> downsampleForWidth(
      List<double> values, int targetLength) {
    if (values.length <= targetLength || targetLength <= 0) return values;
    final out = List<double>.filled(targetLength, 0.0);
    final step = values.length / targetLength;
    for (var i = 0; i < targetLength; i++) {
      final start = (i * step).floor();
      final end = ((i + 1) * step).floor().clamp(0, values.length);
      if (end <= start) {
        out[i] = values[start.clamp(0, values.length - 1)];
        continue;
      }
      var peak = values[start];
      for (var j = start + 1; j < end; j++) {
        if (values[j] > peak) peak = values[j];
      }
      out[i] = peak;
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform == null || waveform!.amplitudes.isEmpty) {
      // Sin datos reales todavía: línea neutra (nunca sintética).
      final paint = Paint()
        ..color = inactiveColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(0, size.height / 2),
          Offset(size.width, size.height / 2), paint);
      return;
    }

    // Número de barras que caben con la geometría objetivo.
    const stride = targetBarWidth + targetGap;
    final targetBars = (size.width / stride).floor().clamp(1, 2048);
    final List<double> amplitudes =
        downsampleForWidth(waveform!.amplitudes, targetBars);
    final int n = amplitudes.length;

    const double gap = targetGap;
    double barWidth = (size.width - (n - 1) * gap) / n;
    // Evitar barras gigantes cuando hay pocos bins (tests con 6 valores):
    // se limitan y se centran.
    double startX = 0.0;
    if (barWidth > 6.0) {
      barWidth = 6.0;
      final totalW = n * barWidth + (n - 1) * gap;
      startX = ((size.width - totalW) / 2).clamp(0.0, size.width);
    }
    barWidth = barWidth.clamp(1.0, size.width);

    // Altura: mínimo visible 3 px, máximo ~90 % del widget.
    final double maxHeight = size.height * 0.9;
    const double minHeight = 3.0;
    final double centerY = size.height / 2;

    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < n; i++) {
      final double amplitude = amplitudes[i].clamp(0.0, 1.0);
      final double barHeight =
          minHeight + amplitude * (maxHeight - minHeight);
      final double x = startX + i * (barWidth + gap);

      // La forma NO cambia con el progreso; solo el color.
      final bool isPlayed = ((i + 0.5) / n) <= progress;
      paint.color = isPlayed ? activeColor : inactiveColor;

      final rect = Rect.fromLTWH(
        x,
        centerY - barHeight / 2,
        barWidth,
        barHeight,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(barWidth / 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.waveform != waveform ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}
