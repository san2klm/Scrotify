import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/theme_controller.dart';
import '../services/windows_window_effects.dart';

class WindowsWindowEffectsSync extends StatefulWidget {
  final Widget child;
  const WindowsWindowEffectsSync({super.key, required this.child});

  @override
  State<WindowsWindowEffectsSync> createState() =>
      _WindowsWindowEffectsSyncState();
}

class _WindowsWindowEffectsSyncState extends State<WindowsWindowEffectsSync> {
  ({bool transparent, bool dark, Color background})? _requested;
  bool _applying = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!Platform.isWindows) return;
    final themes = context.watch<ThemeController>();
    final next = (
      transparent: themes.hasSurfaceEffects,
      dark: themes.active.isDark,
      background: themes.active.bgApp,
    );
    if (_requested == next) return;
    _requested = next;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_applyLatest());
    });
  }

  Future<void> _applyLatest() async {
    if (_applying) return;
    _applying = true;
    try {
      while (mounted) {
        final settings = _requested!;
        try {
          await WindowsWindowEffects.apply(
            transparent: settings.transparent,
            dark: settings.dark,
            background: settings.background,
          );
        } catch (error) {
          debugPrint('No se pudo aplicar el efecto de ventana: $error');
        }
        if (_requested == settings) break;
      }
    } finally {
      _applying = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
