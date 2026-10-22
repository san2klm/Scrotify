import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/theme_controller.dart';

/// Fondo compartido por las pantallas. El filtro afecta al fondo y mantiene
/// nítidos el texto, las portadas y los controles de la interfaz.
class AppThemeBackground extends StatelessWidget {
  final Widget child;
  const AppThemeBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final themes = context.watch<ThemeController>();
    if (!themes.hasSurfaceEffects) {
      return child;
    }
    final theme = themes.active;
    if (Platform.isWindows) {
      // Una sola capa de tinte; Windows compone el escritorio detrás.
      return ColoredBox(
        color: themes.surfaceColor(theme.bgApp),
        child: child,
      );
    }
    return Stack(fit: StackFit.expand, children: [
      Positioned.fill(
        child: IgnorePointer(
          child: ClipRect(
            child: CustomPaint(
              painter: _ThemeBackgroundPainter(theme.bgApp, theme.accent,
                  theme.accent2, themes.surfaceTransparency),
            ),
          ),
        ),
      ),
      child,
    ]);
  }
}

class _ThemeBackgroundPainter extends CustomPainter {
  final Color background;
  final Color accent;
  final Color accent2;
  final double transparency;
  const _ThemeBackgroundPainter(
      this.background, this.accent, this.accent2, this.transparency);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPaint(Paint()..color = background);
    final band = Path()
      ..moveTo(size.width * 0.12, 0)
      ..lineTo(size.width * 0.62, 0)
      ..lineTo(size.width * 0.88, size.height)
      ..lineTo(size.width * 0.38, size.height)
      ..close();
    canvas.drawPath(band, Paint()..color = accent);
    canvas.drawOval(
        Rect.fromLTWH(size.width * 0.58, size.height * 0.22, size.width * 0.65,
            size.height * 0.95),
        Paint()..color = accent2);
    canvas.drawPaint(
        Paint()..color = background.withValues(alpha: 1 - transparency));
  }

  @override
  bool shouldRepaint(_ThemeBackgroundPainter oldDelegate) =>
      background != oldDelegate.background ||
      accent != oldDelegate.accent ||
      accent2 != oldDelegate.accent2 ||
      transparency != oldDelegate.transparency;
}
