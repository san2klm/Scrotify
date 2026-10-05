import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../services/mini_player_controller.dart';
import '../services/window_controls.dart';
import 'mini_player_view.dart';

/// Marco de ventana propio para escritorio, inspirado en la barra compacta de
/// Discord. Sólo se monta en Linux, Windows y macOS.
///
/// La ventana no tiene decoración nativa, así que este marco aporta:
/// * bordes y esquinas arrastrables para **redimensionar**;
/// * botón de **maximizar / restaurar** la ventana;
/// * **pantalla completa** real (botón, `F11`; `Esc` para salir);
/// * botón del modo mini reproductor.
class DesktopWindowFrame extends StatefulWidget {
  final Widget child;

  const DesktopWindowFrame({super.key, required this.child});

  @override
  State<DesktopWindowFrame> createState() => _DesktopWindowFrameState();
}

class _DesktopWindowFrameState extends State<DesktopWindowFrame>
    with WindowListener {
  bool _maximized = false;
  bool _fullScreen = false;

  @override
  void initState() {
    super.initState();
    if (WindowControls.isDesktop) {
      windowManager.addListener(this);
      _syncState();
    }
  }

  @override
  void dispose() {
    if (WindowControls.isDesktop) windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _syncState() async {
    final maximized = await windowManager.isMaximized();
    final fullScreen = await windowManager.isFullScreen();
    if (!mounted) return;
    setState(() {
      _maximized = maximized;
      _fullScreen = fullScreen;
    });
  }

  // El estado se relee del sistema: así los atajos del gestor de ventanas
  // (doble clic, Super+flecha, etc.) también mantienen los iconos al día.
  @override
  void onWindowMaximize() => _syncState();
  @override
  void onWindowUnmaximize() => _syncState();
  @override
  void onWindowEnterFullScreen() => _syncState();
  @override
  void onWindowLeaveFullScreen() => _syncState();
  @override
  void onWindowRestore() => _syncState();

  @override
  Widget build(BuildContext context) {
    if (!WindowControls.isDesktop) return widget.child;
    final colors = Theme.of(context).colorScheme;
    final mini = context.watch<MiniPlayerController>();

    final content = Column(
      children: [
        SizedBox(
          height: 34,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) {
              if (!_fullScreen) windowManager.startDragging();
            },
            onDoubleTap: mini.enabled ? null : WindowControls.toggleMaximize,
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
                    Image.asset(
                      'assets/icons/scrotify_app_icon.png',
                      width: 15,
                      height: 15,
                      semanticLabel: 'Logo de Scrotify',
                    ),
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
                      tooltip: mini.enabled
                          ? 'Salir del modo mini'
                          : 'Modo mini reproductor',
                      icon: mini.enabled
                          ? Icons.open_in_full_rounded
                          : Icons.picture_in_picture_alt_rounded,
                      onPressed: mini.toggle,
                    ),
                    _WindowButton(
                      tooltip: 'Minimizar',
                      icon: Icons.remove_rounded,
                      onPressed: windowManager.minimize,
                    ),
                    if (!mini.enabled) ...[
                      _WindowButton(
                        tooltip: _maximized ? 'Restaurar' : 'Maximizar',
                        icon: _maximized
                            ? Icons.filter_none_rounded
                            : Icons.crop_square_rounded,
                        onPressed: WindowControls.toggleMaximize,
                      ),
                    ],
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
        Expanded(
          child: mini.enabled
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    // La interfaz normal sigue montada (conserva su estado y
                    // pila de navegación) pero oculta, con el tamaño que tenía.
                    Offstage(
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: mini.restoreSize?.width ?? 0,
                        maxWidth: mini.restoreSize?.width ?? double.infinity,
                        minHeight: mini.restoreSize?.height ?? 0,
                        maxHeight: mini.restoreSize?.height ?? double.infinity,
                        child: widget.child,
                      ),
                    ),
                    const Positioned.fill(child: MiniPlayerView()),
                  ],
                )
              : widget.child,
        ),
      ],
    );

    // Bordes de redimensionado: no tienen sentido en pantalla completa ni
    // maximizada (la ventana ocupa todo el escritorio).
    final canResize = !_fullScreen && !_maximized;
    final framed = canResize
        ? DragToResizeArea(resizeEdgeSize: 6, child: content)
        : content;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f11):
            WindowControls.toggleFullScreen,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_fullScreen) WindowControls.setFullScreen(false);
        },
      },
      child: Focus(autofocus: true, child: framed),
    );
  }
}

class _WindowButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Future<void> Function() onPressed;
  final bool danger;
  final double iconSize;

  const _WindowButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.danger = false,
    this.iconSize = 17,
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
          iconSize: iconSize,
          color: danger ? colors.error : colors.onSurfaceVariant,
          icon: Icon(icon),
          onPressed: () => onPressed(),
        ),
      ),
    );
  }
}
