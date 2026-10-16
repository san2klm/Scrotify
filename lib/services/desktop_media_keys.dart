import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'player_controller.dart';

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
      final hotKey = HotKey(key: entry.key, scope: HotKeyScope.system);
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
