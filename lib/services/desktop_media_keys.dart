import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'player_controller.dart';

// Keep the Windows startup fix from the previous local build. The plugin
// requires non-null modifiers and native VK codes for next/previous.
class _WindowsMediaHotKey extends HotKey {
  _WindowsMediaHotKey(PhysicalKeyboardKey key)
      : super(key: key, modifiers: const [], scope: HotKeyScope.system);

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'keyCode': {
          PhysicalKeyboardKey.mediaPlayPause: 0xB3,
          PhysicalKeyboardKey.mediaTrackNext: 0xB0,
          PhysicalKeyboardKey.mediaTrackPrevious: 0xB1,
        }[key]!,
      };
}

/// Teclas multimedia globales (reproducir/pausa, siguiente, anterior) en
/// escritorio, incluso con la ventana en segundo plano.
///
/// En Linux las cubre además MPRIS; aquí se registran igualmente porque no
/// todos los entornos reenvían las teclas multimedia al reproductor.
class DesktopMediaKeys {
  DesktopMediaKeys(this._player);

  final PlayerController _player;
  final List<HotKey> _registered = [];
  bool _started = false;

  static bool get isSupported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> start() async {
    if (!isSupported || _started) return;
    _started = true;
    final bindings = <PhysicalKeyboardKey, Future<void> Function()>{
      PhysicalKeyboardKey.mediaPlayPause: _player.togglePlay,
      PhysicalKeyboardKey.mediaTrackNext: _player.skipNext,
      PhysicalKeyboardKey.mediaTrackPrevious: _player.skipPrevious,
    };
    for (final entry in bindings.entries) {
      final hotKey = Platform.isWindows
          ? _WindowsMediaHotKey(entry.key)
          : HotKey(
              key: entry.key, modifiers: const [], scope: HotKeyScope.system);
      try {
        await hotKeyManager.register(hotKey,
            keyDownHandler: (_) => unawaited(entry.value()));
        _registered.add(hotKey);
      } catch (e) {
        // Otra aplicación ya tiene esa tecla: se sigue con las demás.
        debugPrint('DesktopMediaKeys: no se pudo registrar ${entry.key} ($e)');
      }
    }
  }

  Future<void> stop() async {
    for (final hotKey in _registered) {
      try {
        await hotKeyManager.unregister(hotKey);
      } catch (_) {}
    }
    _registered.clear();
    _started = false;
  }
}
