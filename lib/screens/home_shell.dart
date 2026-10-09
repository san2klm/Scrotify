import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/navidrome_service.dart';
import '../utils/responsive.dart';
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

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(context.read<NavidromeService>().recoverConnection());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool? _mobile;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    _mobile = Responsive.isMobileWidth(width,
        wasMobile: _mobile ?? width < Responsive.mobileBreakpoint);
    return _mobile! ? const MobileHomeScreen() : const HomeScreen();
  }
}
