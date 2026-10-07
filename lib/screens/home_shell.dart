import 'package:flutter/material.dart';
import '../utils/responsive.dart';
import '../utils/tv_mode.dart';
import 'home_screen.dart';
import 'mobile_home_screen.dart';

/// Selecciona la interfaz adecuada según el ancho de la pantalla:
/// - Teléfonos (ancho reducido): interfaz móvil.
/// - Escritorio / tablets (ancho amplio): interfaz de escritorio.
///
/// La decisión usa histéresis ([Responsive.hysteresis]): al redimensionar la
/// ventana alrededor del límite no se alterna entre interfaces en cada píxel
/// (cada cambio reconstruye la pantalla completa y pierde su estado).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  bool? _mobile;

  @override
  Widget build(BuildContext context) {
    // La tele siempre usa la interfaz amplia (se maneja con el control remoto).
    if (TvMode.isTv) return const HomeScreen();
    final width = MediaQuery.sizeOf(context).width;
    _mobile = Responsive.isMobileWidth(width,
        wasMobile: _mobile ?? width < Responsive.mobileBreakpoint);
    return _mobile! ? const MobileHomeScreen() : const HomeScreen();
  }
}
