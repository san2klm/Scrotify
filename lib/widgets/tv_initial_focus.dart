import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/tv_mode.dart';

/// En una tele, lleva el foco inicial al primer elemento enfocable de
/// [child] (el contenido de la pantalla) en vez de dejarlo en la barra
/// superior.
///
/// El contenido suele llegar tarde (listas que se cargan del servidor), así
/// que reintenta cada 100 ms hasta 3 s. Se rinde en cuanto el usuario pulsa
/// una tecla (ya está navegando), si el foco ya está dentro, si hay otra ruta
/// encima (un diálogo) o si no hay nada que enfocar. Fuera de una tele no hace
/// nada.
class TvInitialFocus extends StatefulWidget {
  const TvInitialFocus({super.key, required this.child});

  final Widget child;

  @override
  State<TvInitialFocus> createState() => _TvInitialFocusState();
}

class _TvInitialFocusState extends State<TvInitialFocus> {
  static const _interval = Duration(milliseconds: 100);
  static const _maxAttempts = 30;

  final _node = FocusNode(
      debugLabel: 'TvInitialFocus',
      canRequestFocus: false,
      skipTraversal: true);
  Timer? _timer;
  int _attempts = 0;

  @override
  void initState() {
    super.initState();
    if (!TvMode.isTv) return;
    HardwareKeyboard.instance.addHandler(_onKey);
    _timer = Timer.periodic(_interval, (_) => _tryFocus());
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent) _stop();
    return false; // solo observa: nunca consume la tecla
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    HardwareKeyboard.instance.removeHandler(_onKey);
  }

  void _tryFocus() {
    if (!mounted || ++_attempts > _maxAttempts) return _stop();
    if (ModalRoute.of(context)?.isCurrent == false) return _stop();
    if (_node.hasFocus) return _stop();
    for (final candidate in _node.traversalDescendants) {
      if (candidate.canRequestFocus && !candidate.skipTraversal) {
        candidate.requestFocus();
        return _stop();
      }
    }
  }

  @override
  void dispose() {
    _stop();
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: _node, child: widget.child);
}
