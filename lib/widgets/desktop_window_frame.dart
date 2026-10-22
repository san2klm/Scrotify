import '../utils/app_colors.dart';
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
import '../services/settings_controller.dart';
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
  PlayerController? _playerSub;
  SettingsController? _settingsSub;

  @override
  void initState() {
    super.initState();
    if (WindowControls.isDesktop) {
      windowManager.addListener(this);
      _syncState();
      if (Platform.isWindows) {
        _mouseChannel.setMethodCallHandler((call) async {
          if (!mounted) return;
          switch (call.method) {
            case 'togglePlayPause':
              _togglePlayPause(context);
              break;
            case 'skipNext':
              _skipNext(context);
              break;
            case 'skipPrevious':
              _skipPrevious(context);
              break;
            case 'volumeUp':
              _changeVolume(context, 0.04);
              break;
            case 'volumeDown':
              _changeVolume(context, -0.04);
              break;
            case 'onShortcutCaptured':
              final raw = call.arguments as String?;
              if (raw == 'cancel') {
                _settingsSub?.stopShortcutCapture();
              } else if (raw != null && raw.isNotEmpty) {
                _settingsSub?.handleCapturedShortcut(raw);
              }
              break;
          }
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (WindowControls.isDesktop && Platform.isWindows) {
      final player = context.read<PlayerController>();
      if (_playerSub != player) {
        _playerSub?.removeListener(_syncNativePlaybackState);
        _playerSub = player;
        _playerSub?.addListener(_syncNativePlaybackState);
        _syncNativePlaybackState();
      }
      final settings = context.read<SettingsController>();
      if (_settingsSub != settings) {
        _settingsSub?.removeListener(_syncNativeMouseSettings);
        _settingsSub = settings;
        _settingsSub?.addListener(_syncNativeMouseSettings);
        _syncNativeMouseSettings();
      }
    }
  }

  void _syncNativePlaybackState() {
    final p = _playerSub;
    if (p == null || !Platform.isWindows) return;
    _mouseChannel.invokeMethod('setPlaying', p.playing).catchError((_) {});
  }

  void _syncNativeMouseSettings() {
    final s = _settingsSub;
    if (s == null || !Platform.isWindows) return;
    _mouseChannel.invokeMethod('setMouseConfig', {
      'enabled': s.mouseControlsEnabled && !s.isCapturingShortcut,
      'capturing': s.isCapturingShortcut,
      'global': s.mouseGlobalEnabled,
      'middleClick': s.mouseMiddleClickEnabled,
      'closeToTray': s.closeToTray,
      'playPauseType': s.playPauseBinding.nativeType,
      'playPauseVk': s.playPauseBinding.vkCode,
      'nextTrackType': s.nextTrackBinding.nativeType,
      'nextTrackVk': s.nextTrackBinding.vkCode,
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _playerSub?.removeListener(_syncNativePlaybackState);
    _settingsSub?.removeListener(_syncNativeMouseSettings);
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
    final settings = context.watch<SettingsController>();

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
              color: context.bgSidebar,
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
                      'CrotoWave (Scrotify)',
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
                      tooltip: settings.closeToTray
                          ? 'Minimizar a segundo plano (Bandeja)'
                          : 'Cerrar',
                      icon: Icons.close_rounded,
                      danger: true,
                      onPressed: () async {
                        if (Platform.isWindows && settings.closeToTray) {
                          try {
                            await _mouseChannel.invokeMethod('hideToTray');
                            return;
                          } catch (_) {}
                        }
                        await windowManager.close();
                      },
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
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final settings = context.read<SettingsController>();
          if (!settings.mouseControlsEnabled || settings.isCapturingShortcut) {
            return KeyEventResult.ignored;
          }

          final primaryFocus = FocusManager.instance.primaryFocus;
          final isEditingText =
              primaryFocus?.context?.widget is EditableText ||
                  primaryFocus?.context
                          ?.findAncestorWidgetOfExactType<EditableText>() !=
                      null;

          final keyId = event.logicalKey.keyId;
          final isPrintableKey = (keyId >= 0x20 && keyId <= 0x7E);
          if (isEditingText && isPrintableKey) {
            return KeyEventResult.ignored;
          }

          final pressed = ShortcutBinding.fromLogicalKey(event.logicalKey);
          final pressedVk = pressed?.vkCode ?? 0;

          final playBind = settings.playPauseBinding;
          if (playBind.isKey &&
              ((playBind.logicalKeyId != 0 && keyId == playBind.logicalKeyId) ||
                  (playBind.vkCode != 0 && playBind.vkCode == pressedVk))) {
            _togglePlayPause(context);
            return KeyEventResult.handled;
          }

          final nextBind = settings.nextTrackBinding;
          if (nextBind.isKey &&
              ((nextBind.logicalKeyId != 0 && keyId == nextBind.logicalKeyId) ||
                  (nextBind.vkCode != 0 && nextBind.vkCode == pressedVk))) {
            _skipNext(context);
            return KeyEventResult.handled;
          }

          return KeyEventResult.ignored;
        },
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerSignal: (event) {
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
            final settings = context.read<SettingsController>();
            if (!settings.mouseControlsEnabled ||
                settings.isCapturingShortcut) {
              return;
            }

            String? pressedMouseType;
            if ((event.buttons & kBackMouseButton) != 0) {
              pressedMouseType = 'mouse_xb1';
            } else if ((event.buttons & kForwardMouseButton) != 0) {
              pressedMouseType = 'mouse_xb2';
            } else if ((event.buttons & kMiddleMouseButton) != 0) {
              pressedMouseType = 'mouse_middle';
            } else if ((event.buttons & kSecondaryMouseButton) != 0) {
              pressedMouseType = 'mouse_right';
            }
            if (pressedMouseType == null) return;

            final playType = settings.playPauseBinding.nativeType;
            final nextType = settings.nextTrackBinding.nativeType;

            if (pressedMouseType == playType) {
              if (pressedMouseType == 'mouse_xb1' ||
                  pressedMouseType == 'mouse_xb2') {
                final now = DateTime.now();
                if (_lastBackClickTime != null &&
                    now.difference(_lastBackClickTime!).inMilliseconds < 380) {
                  _lastBackClickTime = null;
                  _skipPrevious(context);
                } else {
                  _lastBackClickTime = now;
                  _togglePlayPause(context);
                }
              } else {
                _togglePlayPause(context);
              }
            } else if (pressedMouseType == nextType) {
              _skipNext(context);
            } else if (pressedMouseType == 'mouse_middle' &&
                settings.mouseMiddleClickEnabled) {
              _togglePlayPause(context);
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

  DateTime? _lastPlayPauseTime;
  DateTime? _lastNextTime;
  DateTime? _lastPrevTime;
  DateTime? _lastBackClickTime;

  bool _canTrigger(DateTime? last, [int cooldownMs = 200]) {
    final now = DateTime.now();
    if (last != null && now.difference(last).inMilliseconds < cooldownMs) {
      return false;
    }
    return true;
  }

  void _togglePlayPause(BuildContext context) {
    if (!_canTrigger(_lastPlayPauseTime, 200)) return;
    _lastPlayPauseTime = DateTime.now();
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
    if (!_canTrigger(_lastNextTime, 200)) return;
    _lastNextTime = DateTime.now();
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
    if (!_canTrigger(_lastPrevTime, 200)) return;
    _lastPrevTime = DateTime.now();
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
      if (!player.playing) {
        player.play();
      }
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
