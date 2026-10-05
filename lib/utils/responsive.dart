import 'package:flutter/widgets.dart';

/// Clases de tamaño de ventana (similares a las de Material 3).
enum ScreenSize {
  /// Teléfonos: < 700 px. Interfaz móvil.
  compact,

  /// Ventanas/tablets estrechas de escritorio: 700–1000 px.
  medium,

  /// Escritorio estándar: 1000–1400 px.
  expanded,

  /// Pantallas grandes: ≥ 1400 px.
  large;

  bool get isCompact => this == ScreenSize.compact;
  bool get isAtLeastExpanded =>
      this == ScreenSize.expanded || this == ScreenSize.large;
}

/// Puntos de corte y utilidades compartidas por las pantallas.
class Responsive {
  Responsive._();

  static const double mobileBreakpoint = 700;

  /// Margen de histéresis: la interfaz móvil→escritorio solo cambia al
  /// superar `mobileBreakpoint + hysteresis`, para que redimensionar la
  /// ventana cerca del límite no alterne (y destruya el estado) en cada píxel.
  static const double hysteresis = 40;

  static const double mediumBreakpoint = 1000;
  static const double largeBreakpoint = 1400;

  /// Ancho a partir del cual cabe el panel lateral "Escuchando ahora".
  static const double sidePanelBreakpoint = 1240;

  /// Ancho máximo del contenido en pantallas muy grandes.
  static const double maxContentWidth = 1600;

  static ScreenSize classify(double width) {
    if (width < mobileBreakpoint) return ScreenSize.compact;
    if (width < mediumBreakpoint) return ScreenSize.medium;
    if (width < largeBreakpoint) return ScreenSize.expanded;
    return ScreenSize.large;
  }

  /// Decide móvil/escritorio con histéresis. [wasMobile] es la decisión
  /// anterior.
  static bool isMobileWidth(double width, {required bool wasMobile}) {
    if (wasMobile) return width < mobileBreakpoint + hysteresis;
    return width < mobileBreakpoint;
  }

  /// Columnas de una cuadrícula para que cada celda mida al menos
  /// [minTileWidth], limitadas a [min]..[max].
  static int columnsFor(double width,
      {double minTileWidth = 220, int min = 1, int max = 6}) {
    return (width / minTileWidth).floor().clamp(min, max);
  }
}

extension ResponsiveContext on BuildContext {
  ScreenSize get screenSize =>
      Responsive.classify(MediaQuery.sizeOf(this).width);
}

/// Centra [child] y limita su ancho en pantallas muy anchas, para que el
/// contenido no se estire a lo largo de monitores ultra panorámicos.
class ConstrainedContent extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ConstrainedContent({
    super.key,
    required this.child,
    this.maxWidth = Responsive.maxContentWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
