import 'dart:io' show Platform;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// Modo "mini reproductor" de escritorio: encoge la ventana a una tarjeta
/// compacta siempre visible encima de las demás y la restaura al salir.
class MiniPlayerController extends ChangeNotifier {
  /// Tamaño de la ventana en modo mini (incluye la barra de título de 34 px).
  static const Size miniSize = Size(420, 176);
  static const Size normalMinimumSize = Size(400, 500);

  bool _enabled = false;
  bool _busy = false;
  Size? _restoreSize;
  bool _restoreMaximized = false;

  bool get enabled => _enabled;

  /// Tamaño que tenía la ventana antes de entrar en modo mini. Sirve para que
  /// la interfaz oculta conserve su layout (y su estado) mientras tanto.
  Size? get restoreSize => _restoreSize;

  /// El modo mini solo existe en escritorio.
  static bool get isSupported =>
      !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

  Future<void> toggle() => _enabled ? exit() : enter();

  Future<void> enter() async {
    if (_enabled || _busy || !isSupported) return;
    _busy = true;
    try {
      _restoreMaximized = await windowManager.isMaximized();
      if (_restoreMaximized) await windowManager.unmaximize();
      _restoreSize = await windowManager.getSize();
      // Mostrar la vista mini antes de encoger evita comprimir la vista normal.
      _enabled = true;
      notifyListeners();
      // El mínimo se baja ANTES de encoger, si no la ventana no obedece.
      await windowManager.setMinimumSize(miniSize);
      await windowManager.setSize(miniSize);
      await windowManager.setAlwaysOnTop(true);
    } catch (e) {
      _enabled = false;
      notifyListeners();
      debugPrint('MiniPlayerController.enter: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> exit() async {
    if (!_enabled || _busy) return;
    _busy = true;
    try {
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setMinimumSize(normalMinimumSize);
      final size = _restoreSize;
      if (size != null) await windowManager.setSize(size);
      if (_restoreMaximized) await windowManager.maximize();
      _enabled = false;
      _restoreSize = null;
      notifyListeners();
    } catch (e) {
      debugPrint('MiniPlayerController.exit: $e');
    } finally {
      _busy = false;
    }
  }
}
