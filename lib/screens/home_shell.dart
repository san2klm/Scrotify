import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'mobile_home_screen.dart';

/// Selecciona la interfaz adecuada según el ancho de la pantalla:
/// - Teléfonos (ancho reducido): interfaz móvil.
/// - Escritorio / tablets (ancho amplio): interfaz de escritorio.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  static const double _mobileBreakpoint = 700;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < _mobileBreakpoint;
    return isMobile ? const MobileHomeScreen() : const HomeScreen();
  }
}