import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Marco de ventana propio para escritorio, inspirado en la barra compacta de
/// Discord. Sólo se monta en Linux, Windows y macOS.
class DesktopWindowFrame extends StatelessWidget {
  final Widget child;

  const DesktopWindowFrame({super.key, required this.child});

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) return child;
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        SizedBox(
          height: 34,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => windowManager.startDragging(),
            onDoubleTap: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
            child: Material(
              color: colors.surface,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border:
                      Border(bottom: BorderSide(color: colors.outlineVariant)),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Icon(Icons.graphic_eq_rounded,
                        size: 15, color: colors.primary),
                    const SizedBox(width: 7),
                    Text(
                      'Scrotify',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    _WindowButton(
                      tooltip: 'Minimizar',
                      icon: Icons.remove_rounded,
                      onPressed: windowManager.minimize,
                    ),
                    _WindowButton(
                      tooltip: 'Maximizar',
                      icon: Icons.crop_square_rounded,
                      onPressed: () async {
                        if (await windowManager.isMaximized()) {
                          await windowManager.unmaximize();
                        } else {
                          await windowManager.maximize();
                        }
                      },
                    ),
                    _WindowButton(
                      tooltip: 'Cerrar',
                      icon: Icons.close_rounded,
                      danger: true,
                      onPressed: windowManager.close,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _WindowButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Future<void> Function() onPressed;
  final bool danger;

  const _WindowButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // El frame vive por encima del Navigator para envolver toda la app; en
    // ese nivel todavía no existe un Overlay donde Tooltip pueda mostrarse.
    // Semantics conserva el nombre accesible sin introducir ese acoplamiento.
    return Semantics(
      button: true,
      label: tooltip,
      child: SizedBox(
        width: 42,
        height: 34,
        child: IconButton(
          splashRadius: 18,
          iconSize: 17,
          color: danger ? colors.error : colors.onSurfaceVariant,
          icon: Icon(icon),
          onPressed: () => onPressed(),
        ),
      ),
    );
  }
}
