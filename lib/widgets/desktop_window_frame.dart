import 'dart:io' show Platform;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../services/connect/connect_protocol.dart';
import '../services/connect/connect_service.dart';
import '../services/crotolink_controller.dart';
import '../services/mini_player_controller.dart';
import '../services/player_controller.dart';
import '../services/window_controls.dart';
import 'mini_player_view.dart';

/// Marco de ventana propio para escritorio, inspirado en la barra compacta de
/// Discord. Sólo se monta en Linux, Windows y macOS.
///
/// La ventana no tiene decoración nativa, así que este marco aporta:
/// * bordes y esquinas arrastrables para **redimensionar**;
/// * botón de **maximizar / restaurar** la ventana;
/// * atajos de **pantalla completa** (`F11`; `Esc` para salir). El botón de
///   pantalla completa vive en el reproductor grande, no en esta barra;
/// * botón del modo mini reproductor.
class DesktopWindowFrame extends StatefulWidget {
  final Widget child;

  const DesktopWindowFrame({super.key, required this.child});

  @override
  State<DesktopWindowFrame> createState() => _DesktopWindowFrameState();
}

class _DesktopWindowFrameState extends State<DesktopWindowFrame>
    with WindowListener {
  static const _mouseChannel =
      MethodChannel('com.crotowave/global_mouse_hotkeys');

  bool _maximized = false;
  bool _fullScreen = false;

  @override
  void initState() {
    super.initState();
    if (WindowControls.isDesktop) {
      windowManager.addListener(this);
      _syncState();
      if (Platform.isWindows) {
        _mouseChannel.setMethodCallHandler((call) async {
          if (!mounted) return;
          if (call.method == 'togglePlayPause') {
            _togglePlayPause(context);
          } else if (call.method == 'skipNext') {
            _skipNext(context);
          } else if (call.method == 'skipPrevious') {
            _skipPrevious(context);
          }
        });
      }
    }
  }

  @override
  void dispose() {
    if (WindowControls.isDesktop) {
      windowManager.removeListener(this);
      _mouseChannel.setMethodCallHandler(null);
    }
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
    final player = context.watch<PlayerController>();
    if (Platform.isWindows) {
      _mouseChannel
          .invokeMethod('setPlaying', player.playing)
          .catchError((_) {});
    }

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
                      'assets/icons/crotowave_app_icon.png',
                      width: 15,
                      height: 15,
                      semanticLabel: 'Logo de CrotoWave',
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'CrotoWave',
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
        const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () =>
            _togglePlayPause(context),
        const SingleActivator(LogicalKeyboardKey.mediaPlay): () =>
            _togglePlayPause(context),
        const SingleActivator(LogicalKeyboardKey.mediaPause): () =>
            _togglePlayPause(context),
        const SingleActivator(LogicalKeyboardKey.mediaTrackNext): () =>
            _skipNext(context),
        const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): () =>
            _skipPrevious(context),
        const SingleActivator(LogicalKeyboardKey.browserForward): () =>
            _skipNext(context),
        const SingleActivator(LogicalKeyboardKey.browserBack): () =>
            _togglePlayPause(context),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () =>
            _skipNext(context),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () =>
            _skipPrevious(context),
        const SingleActivator(LogicalKeyboardKey.audioVolumeUp): () =>
            _changeVolume(context, 0.04),
        const SingleActivator(LogicalKeyboardKey.audioVolumeDown): () =>
            _changeVolume(context, -0.04),
        const SingleActivator(LogicalKeyboardKey.goBack): () =>
            _togglePlayPause(context),
      },
      child: Focus(
        autofocus: true,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerSignal: (event) {
            // Atajo global con rueda del mouse: si se mantiene Alt o Ctrl pulsado
            // en cualquier parte de la ventana, la rueda sube/baja volumen (+-4%).
            if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
              final isModifier = HardwareKeyboard.instance.isAltPressed ||
                  HardwareKeyboard.instance.isControlPressed;
              if (isModifier) {
                final delta = event.scrollDelta.dy < 0 ? 0.04 : -0.04;
                _changeVolume(context, delta);
              }
            }
          },
          onPointerDown: (event) {
            // Botones laterales del mouse (XBUTTON1 y XBUTTON2):
            // Back (0x08) -> alternar reproducir / pausar
            // Forward (0x10) -> siguiente canción
            if ((event.buttons & kBackMouseButton) != 0) {
              _togglePlayPause(context);
            } else if ((event.buttons & kForwardMouseButton) != 0) {
              _skipNext(context);
            }
          },
          child: framed,
        ),
      ),
    );
  }

  void _changeVolume(BuildContext context, double delta) {
    try {
      final connect = context.read<ConnectService>();
      if (connect.controlled != null) {
        final current = connect.controlledState?.volume ?? 1.0;
        final next = (current + delta).clamp(0.0, 1.0);
        connect.command(ConnectCommand.volume, next);
        return;
      }
      final player = context.read<PlayerController>();
      final next = (player.volume + delta).clamp(0.0, 1.0);
      player.setVolume(next);
    } catch (e) {
      debugPrint('[DesktopWindowFrame] changeVolume error: $e');
    }
  }

  DateTime? _lastSkipTime;

  bool _canSkip() {
    final now = DateTime.now();
    if (_lastSkipTime != null &&
        now.difference(_lastSkipTime!).inMilliseconds < 250) {
      return false;
    }
    _lastSkipTime = now;
    return true;
  }

  void _togglePlayPause(BuildContext context) {
    if (!_canSkip()) return;
    try {
      final connect = context.read<ConnectService>();
      if (connect.controlled != null) {
        connect.command(ConnectCommand.toggle);
        return;
      }
      final crotoLink = context.read<CrotoLinkController>();
      if (crotoLink.isGuest &&
          !(crotoLink.localParticipant?.canControlPlayback ?? false)) {
        return;
      }
      if (crotoLink.inCrotoLink) {
        crotoLink.playbackAction('toggle');
        return;
      }
      final player = context.read<PlayerController>();
      player.togglePlay();
    } catch (e) {
      debugPrint('[DesktopWindowFrame] togglePlayPause error: $e');
    }
  }

  void _skipNext(BuildContext context) {
    if (!_canSkip()) return;
    try {
      final connect = context.read<ConnectService>();
      if (connect.controlled != null) {
        connect.command(ConnectCommand.next);
        return;
      }
      final crotoLink = context.read<CrotoLinkController>();
      if (crotoLink.isGuest &&
          !(crotoLink.localParticipant?.canControlPlayback ?? false)) {
        return;
      }
      if (crotoLink.inCrotoLink) {
        crotoLink.playbackAction('skip_next');
        return;
      }
      final player = context.read<PlayerController>();
      player.skipNext();
    } catch (e) {
      debugPrint('[DesktopWindowFrame] skipNext error: $e');
    }
  }

  void _skipPrevious(BuildContext context) {
    if (!_canSkip()) return;
    try {
      final connect = context.read<ConnectService>();
      if (connect.controlled != null) {
        connect.command(ConnectCommand.previous);
        return;
      }
      final crotoLink = context.read<CrotoLinkController>();
      if (crotoLink.isGuest &&
          !(crotoLink.localParticipant?.canControlPlayback ?? false)) {
        return;
      }
      if (crotoLink.inCrotoLink) {
        crotoLink.playbackAction('skip_previous');
        return;
      }
      final player = context.read<PlayerController>();
      player.skipPrevious();
    } catch (e) {
      debugPrint('[DesktopWindowFrame] skipPrevious error: $e');
    }
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
