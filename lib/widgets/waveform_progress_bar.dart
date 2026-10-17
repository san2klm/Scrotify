import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';

import '../services/waveform_service.dart';
import '../utils/app_colors.dart';
import '../utils/playback_time.dart';

/// Barra de progreso con la forma de onda real de la pista.
///
/// Rendimiento:
/// * Las barras se rasterizan UNA vez en dos `Picture` (reproducido / sin
///   reproducir) que solo se regeneran si cambia la onda, el tamaño o los
///   colores. Cada frame solo se dibuja la imagen cacheada recortada por el
///   progreso (2 draw calls), en vez de cientos de `RRect`.
/// * El progreso se interpola a la frecuencia de la pantalla con un `Ticker`
///   propio: no depende de reconstruir el árbol ni de la frecuencia con la
///   que el backend emite la posición.
/// * Hover, arrastre, revelado y pulso repintan solo el `CustomPaint`
///   (`ChangeNotifier`s como `repaint`), sin `setState`.
///
/// Animaciones (se desactivan con `MediaQuery.disableAnimations`):
/// * Revelado: las barras crecen de izquierda a derecha al cargar la onda.
/// * Pulso: el cabezal "respira" mientras [playing] es `true`.
class WaveformProgressBar extends StatefulWidget {
  final WaveformData? waveform;
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final Color? activeColor;
  final Color? inactiveColor;

  /// Alto de la barra. Pensado para adaptarse: compacta en la barra del
  /// reproductor de escritorio, más alta en la pantalla completa.
  final double height;

  /// Si la reproducción está en curso: interpola el progreso y anima el pulso.
  final bool playing;

  /// Salto de las flechas del teclado y de los gestos de accesibilidad.
  final Duration seekStep;

  const WaveformProgressBar({
    super.key,
    this.waveform,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.activeColor,
    this.inactiveColor,
    this.height = 56.0,
    this.playing = false,
    this.seekStep = const Duration(seconds: 5),
  });

  /// Geometría de barras según el ancho disponible: más gruesas en anchos
  /// grandes, finas en teléfonos. Visible para tests.
  @visibleForTesting
  static ({double bar, double gap}) geometryForWidth(double width) {
    if (width < 420) return (bar: 2.0, gap: 1.0);
    if (width < 900) return (bar: 3.0, gap: 1.5);
    return (bar: 4.0, gap: 2.0);
  }

  /// Downsampling por peak para ajustar [values] a [targetLength].
  /// Visible para tests.
  @visibleForTesting
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
  State<WaveformProgressBar> createState() => _WaveformProgressBarState();
}

class _WaveformProgressBarState extends State<WaveformProgressBar>
    with TickerProviderStateMixin {
  late final AnimationController _reveal;
  late final AnimationController _pulse;
  late final Ticker _ticker;

  /// Fracción 0..1 mostrada (interpolada).
  final ValueNotifier<double> _progress = ValueNotifier(0);

  /// Fracción bajo el dedo/ratón mientras se arrastra, o `null`.
  final ValueNotifier<double?> _drag = ValueNotifier(null);

  /// Fracción bajo el puntero (solo ratón), o `null`.
  final ValueNotifier<double?> _hover = ValueNotifier(null);

  // Ancla de la interpolación: posición del backend + cronómetro desde ella.
  double _anchorMs = 0;
  final Stopwatch _clock = Stopwatch();

  _BarsCache? _cache;
  final Map<String, TextPainter> _labels = {};

  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  double get _durationMs => widget.duration.inMilliseconds.toDouble();

  @override
  void initState() {
    super.initState();
    _reveal = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600));
    _ticker = createTicker(_onTick);
    _anchorMs = widget.position.inMilliseconds.toDouble();
    _publishProgress();
    if (widget.waveform != null) _reveal.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant WaveformProgressBar old) {
    super.didUpdateWidget(old);

    final changedTrack = old.waveform?.trackId != widget.waveform?.trackId ||
        (old.waveform == null) != (widget.waveform == null);
    if (changedTrack && widget.waveform != null) {
      _reveal.forward(from: 0);
    }

    _reanchor();
    _syncMotion();
  }

  /// Re-ancla con la posición del backend. Si la interpolación va bien
  /// encaminada (< 400 ms de diferencia) se conserva, para evitar saltitos.
  void _reanchor() {
    final target = widget.position.inMilliseconds.toDouble();
    final extrapolating = _ticker.isActive;
    final estimate = _estimateMs();
    if (!extrapolating || (target - estimate).abs() > 400) {
      _anchorMs = target;
      _clock
        ..reset()
        ..start();
    }
    _publishProgress();
  }

  void _syncMotion() {
    final animate = widget.playing && !_reduceMotion && _durationMs > 0;
    if (animate) {
      if (!_clock.isRunning) {
        _anchorMs = widget.position.inMilliseconds.toDouble();
        _clock
          ..reset()
          ..start();
      }
      if (!_ticker.isActive) _ticker.start();
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      if (_ticker.isActive) _ticker.stop();
      _clock.stop();
      _pulse
        ..stop()
        ..value = 0;
      _anchorMs = widget.position.inMilliseconds.toDouble();
      _publishProgress();
    }
    if (_reduceMotion) _reveal.value = 1;
  }

  double _estimateMs() {
    if (!_ticker.isActive) return widget.position.inMilliseconds.toDouble();
    final est = _anchorMs + _clock.elapsedMilliseconds;
    return _durationMs > 0 ? est.clamp(0.0, _durationMs) : est;
  }

  void _onTick(Duration _) => _publishProgress();

  void _publishProgress() {
    final d = _durationMs;
    final next = d <= 0 ? 0.0 : (_estimateMs() / d).clamp(0.0, 1.0);
    if (next != _progress.value) _progress.value = next;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _reveal.dispose();
    _pulse.dispose();
    _progress.dispose();
    _drag.dispose();
    _hover.dispose();
    _cache?.dispose();
    for (final p in _labels.values) {
      p.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Interacción
  // ---------------------------------------------------------------------------

  double _fractionAt(double dx, double width) =>
      width <= 0 ? 0 : (dx / width).clamp(0.0, 1.0);

  void _seekFraction(double fraction) {
    if (_durationMs <= 0) return;
    widget.onSeek(Duration(milliseconds: (fraction * _durationMs).round()));
  }

  void _seekBy(Duration delta) {
    if (_durationMs <= 0) return;
    final target =
        (widget.position + delta).inMilliseconds.clamp(0, _durationMs.round());
    widget.onSeek(Duration(milliseconds: target));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _seekBy(widget.seekStep);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-widget.seekStep);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  TextPainter _labelFor(String text, Color color) {
    final key = '$text|${color.toARGB32()}';
    return _labels.putIfAbsent(key, () {
      if (_labels.length > 64) {
        for (final p in _labels.values) {
          p.dispose();
        }
        _labels.clear();
      }
      return TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

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
        inactiveColor = theme.colorScheme.onSurface.withValues(alpha: 0.3);
      }
    }
    final labelColor = theme.colorScheme.onInverseSurface;
    final labelBg = theme.colorScheme.inverseSurface;

    final posLabel = formatPlaybackTime(widget.position);
    final durLabel = formatPlaybackTime(widget.duration);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 300.0;
        final height = widget.height;

        _cache = _BarsCache.obtain(
          previous: _cache,
          waveform: widget.waveform,
          width: width,
          height: height,
          activeColor: activeColor,
          inactiveColor: inactiveColor,
        );

        return Semantics(
          label: 'Progreso de reproducción',
          value: '$posLabel de $durLabel',
          slider: true,
          increasedValue: formatPlaybackTime(widget.position + widget.seekStep),
          decreasedValue: formatPlaybackTime(widget.position > widget.seekStep
              ? widget.position - widget.seekStep
              : Duration.zero),
          onIncrease: () => _seekBy(widget.seekStep),
          onDecrease: () => _seekBy(-widget.seekStep),
          child: Focus(
            onKeyEvent: _onKey,
            child: MouseRegion(
              cursor: _durationMs > 0
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              onHover: (e) =>
                  _hover.value = _fractionAt(e.localPosition.dx, width),
              onExit: (_) => _hover.value = null,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Arrastre solo horizontal: no compite con el scroll vertical.
                onHorizontalDragStart: (d) =>
                    _drag.value = _fractionAt(d.localPosition.dx, width),
                onHorizontalDragUpdate: (d) =>
                    _drag.value = _fractionAt(d.localPosition.dx, width),
                onHorizontalDragEnd: (_) => _finishDrag(),
                onHorizontalDragCancel: () => _drag.value = null,
                onTapUp: (d) =>
                    _seekFraction(_fractionAt(d.localPosition.dx, width)),
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: Size(width, height),
                    painter: _WaveformPainter(
                      cache: _cache!,
                      progress: _progress,
                      drag: _drag,
                      hover: _hover,
                      reveal: _reveal,
                      pulse: _pulse,
                      activeColor: activeColor,
                      inactiveColor: inactiveColor,
                      durationMs: _durationMs,
                      labelFor: _labelFor,
                      labelColor: labelColor,
                      labelBackground: labelBg,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _finishDrag() {
    final f = _drag.value;
    _drag.value = null;
    if (f != null) {
      _seekFraction(f);
      // Mantener el cabezal donde se soltó hasta que llegue la posición real.
      _anchorMs = f * _durationMs;
      _clock
        ..reset()
        ..start();
      _progress.value = f;
    }
  }
}

// =============================================================================
// Caché de barras
// =============================================================================

/// Barras ya calculadas y rasterizadas para un (onda, tamaño, colores).
class _BarsCache {
  final WaveformData? waveform;
  final double width;
  final double height;
  final Color activeColor;
  final Color inactiveColor;

  final List<double> amplitudes;
  final double barWidth;
  final double gap;
  final double startX;
  final ui.Picture? played;
  final ui.Picture? unplayed;

  _BarsCache._({
    required this.waveform,
    required this.width,
    required this.height,
    required this.activeColor,
    required this.inactiveColor,
    required this.amplitudes,
    required this.barWidth,
    required this.gap,
    required this.startX,
    required this.played,
    required this.unplayed,
  });

  static const double _minHeight = 3.0;

  bool matches(WaveformData? wf, double w, double h, Color a, Color i) =>
      identical(waveform, wf) &&
      width == w &&
      height == h &&
      activeColor == a &&
      inactiveColor == i;

  static _BarsCache obtain({
    required _BarsCache? previous,
    required WaveformData? waveform,
    required double width,
    required double height,
    required Color activeColor,
    required Color inactiveColor,
  }) {
    if (previous != null &&
        previous.matches(waveform, width, height, activeColor, inactiveColor)) {
      return previous;
    }
    previous?.dispose();

    if (waveform == null || waveform.amplitudes.isEmpty || width <= 0) {
      return _BarsCache._(
        waveform: waveform,
        width: width,
        height: height,
        activeColor: activeColor,
        inactiveColor: inactiveColor,
        amplitudes: const [],
        barWidth: 0,
        gap: 0,
        startX: 0,
        played: null,
        unplayed: null,
      );
    }

    final geo = WaveformProgressBar.geometryForWidth(width);
    final stride = geo.bar + geo.gap;
    final targetBars = (width / stride).floor().clamp(1, 2048);
    final amps =
        WaveformProgressBar.downsampleForWidth(waveform.amplitudes, targetBars);
    final n = amps.length;

    final gap = geo.gap;
    var barWidth = (width - (n - 1) * gap) / n;
    var startX = 0.0;
    // Pocas barras (p. ej. tests con 6 valores): limitar y centrar.
    if (barWidth > 6.0 + geo.bar) {
      barWidth = 6.0;
      final totalW = n * barWidth + (n - 1) * gap;
      startX = ((width - totalW) / 2).clamp(0.0, width);
    }
    barWidth = barWidth.clamp(1.0, width);

    final cache = _BarsCache._(
      waveform: waveform,
      width: width,
      height: height,
      activeColor: activeColor,
      inactiveColor: inactiveColor,
      amplitudes: amps,
      barWidth: barWidth,
      gap: gap,
      startX: startX,
      played: _record(amps, width, height, barWidth, gap, startX, activeColor),
      unplayed:
          _record(amps, width, height, barWidth, gap, startX, inactiveColor),
    );
    return cache;
  }

  static ui.Picture _record(List<double> amps, double width, double height,
      double barWidth, double gap, double startX, Color color) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final path = buildPath(amps, height, barWidth, gap, startX, 1.0);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color
        ..isAntiAlias = true,
    );
    return recorder.endRecording();
  }

  /// Camino con todas las barras. [reveal] < 1 escalona su altura de
  /// izquierda a derecha (animación de entrada).
  static Path buildPath(List<double> amps, double height, double barWidth,
      double gap, double startX, double reveal) {
    final n = amps.length;
    final maxHeight = height * 0.9;
    final centerY = height / 2;
    final radius = Radius.circular(barWidth / 2);
    final path = Path();
    for (var i = 0; i < n; i++) {
      var k = 1.0;
      if (reveal < 1.0) {
        // Cada barra arranca un poco después que la anterior.
        final local = (reveal * 1.6 - (i / n) * 0.6).clamp(0.0, 1.0);
        k = Curves.easeOutCubic.transform(local);
      }
      final a = amps[i].clamp(0.0, 1.0);
      final h = _minHeight + a * (maxHeight - _minHeight) * k;
      final x = startX + i * (barWidth + gap);
      path.addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(x, centerY - h / 2, barWidth, h),
        radius,
      ));
    }
    return path;
  }

  /// Las `Picture` se liberan por GC: liberarlas a mano podría hacerlo
  /// mientras el frame anterior aún las usa.
  void dispose() {}
}

// =============================================================================
// Painter
// =============================================================================

class _WaveformPainter extends CustomPainter {
  final _BarsCache cache;
  final ValueListenable<double> progress;
  final ValueListenable<double?> drag;
  final ValueListenable<double?> hover;
  final Animation<double> reveal;
  final Animation<double> pulse;
  final Color activeColor;
  final Color inactiveColor;
  final double durationMs;
  final TextPainter Function(String text, Color color) labelFor;
  final Color labelColor;
  final Color labelBackground;

  _WaveformPainter({
    required this.cache,
    required this.progress,
    required this.drag,
    required this.hover,
    required this.reveal,
    required this.pulse,
    required this.activeColor,
    required this.inactiveColor,
    required this.durationMs,
    required this.labelFor,
    required this.labelColor,
    required this.labelBackground,
  }) : super(repaint: Listenable.merge([progress, drag, hover, reveal, pulse]));

  @override
  void paint(Canvas canvas, Size size) {
    final dragging = drag.value;
    final fraction = (dragging ?? progress.value).clamp(0.0, 1.0);
    final playheadX = size.width * fraction;
    final centerY = size.height / 2;

    if (cache.amplitudes.isEmpty) {
      _paintNeutralLine(canvas, size, playheadX);
    } else {
      final revealValue = reveal.value;
      if (revealValue < 1.0) {
        // Animación de entrada: se construye el camino escalonado (solo
        // durante ~0,7 s; después se usa la imagen cacheada).
        final path = _BarsCache.buildPath(cache.amplitudes, size.height,
            cache.barWidth, cache.gap, cache.startX, revealValue);
        canvas.drawPath(path, Paint()..color = inactiveColor);
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(0, 0, playheadX, size.height));
        canvas.drawPath(path, Paint()..color = activeColor);
        canvas.restore();
      } else {
        // La forma NO cambia con el progreso; solo el recorte de color.
        canvas.drawPicture(cache.unplayed!);
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(0, 0, playheadX, size.height));
        canvas.drawPicture(cache.played!);
        canvas.restore();
      }
    }

    // Cabezal con pulso suave.
    if (durationMs > 0) {
      final p = pulse.value; // 0..1
      final ringAlpha = 0.18 + 0.22 * p;
      canvas.drawLine(
        Offset(playheadX, size.height * 0.08),
        Offset(playheadX, size.height * 0.92),
        Paint()
          ..color = activeColor
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(Offset(playheadX, centerY), 7 + 3 * p,
          Paint()..color = activeColor.withValues(alpha: ringAlpha));
      canvas.drawCircle(
          Offset(playheadX, centerY), 3.5, Paint()..color = activeColor);
    }

    // Hover / arrastre: línea guía y tiempo.
    final hoverFraction = dragging ?? hover.value;
    if (hoverFraction != null && durationMs > 0) {
      final x = size.width * hoverFraction;
      if (dragging == null) {
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          Paint()
            ..color = activeColor.withValues(alpha: 0.45)
            ..strokeWidth = 1,
        );
      }
      final text = formatPlaybackTime(
          Duration(milliseconds: (hoverFraction * durationMs).round()));
      final tp = labelFor(text, labelColor);
      const padH = 6.0, padV = 2.0;
      final w = tp.width + padH * 2;
      final h = tp.height + padV * 2;
      final left =
          (x - w / 2).clamp(0.0, math.max(0.0, size.width - w)).toDouble();
      final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(left, 0, w, h), const Radius.circular(4));
      canvas.drawRRect(rect, Paint()..color = labelBackground);
      tp.paint(canvas, Offset(left + padH, padV));
    }
  }

  /// Sin datos reales todavía: línea neutra (nunca sintética) con el tramo
  /// reproducido resaltado, para que el progreso se vea igualmente.
  void _paintNeutralLine(Canvas canvas, Size size, double playheadX) {
    final y = size.height / 2;
    final base = Paint()
      ..color = inactiveColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), base);
    if (playheadX > 0) {
      canvas.drawLine(
          Offset(0, y), Offset(playheadX, y), base..color = activeColor);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      !identical(old.cache, cache) ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor ||
      old.durationMs != durationMs ||
      old.labelColor != labelColor ||
      old.labelBackground != labelBackground;
}
