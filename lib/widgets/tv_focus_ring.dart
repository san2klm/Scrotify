import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../utils/app_colors.dart';
import 'tv_keyboard.dart';

/// Marco de foco para manejar la app con el control remoto: dibuja un borde
/// bien visible alrededor del elemento enfocado, sea del tipo que sea (botón,
/// tarjeta, campo de texto, control deslizante…), y lo sigue si se desplaza.
class TvFocusRing extends StatefulWidget {
  const TvFocusRing({super.key, required this.child});

  final Widget child;

  @override
  State<TvFocusRing> createState() => _TvFocusRingState();
}

class _TvFocusRingState extends State<TvFocusRing>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _stackKey = GlobalKey();
  Rect? _rect;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _sync())..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _sync() {
    final next = _focusedRect();
    if (next != _rect) setState(() => _rect = next);
  }

  Rect? _focusedRect() {
    final node = FocusManager.instance.primaryFocus;
    final stack = _stackKey.currentContext?.findRenderObject();
    final target = node?.context?.findRenderObject();
    if (node == null ||
        node is FocusScopeNode ||
        stack is! RenderBox ||
        target is! RenderBox ||
        !target.attached ||
        !target.hasSize ||
        !stack.hasSize) {
      return null;
    }
    final topLeft = stack.globalToLocal(target.localToGlobal(Offset.zero));
    final rect = topLeft & target.size;
    // Un contenedor que ocupa casi toda la pantalla no es un objetivo de foco.
    if (rect.width * rect.height > stack.size.width * stack.size.height * 0.6) {
      return null;
    }
    // Fuera de la pantalla (p. ej. dentro de una lista desplazada): sin marco.
    if (!(Offset.zero & stack.size).overlaps(rect)) return null;
    return rect;
  }

  @override
  Widget build(BuildContext context) {
    final rect = _rect;
    return Stack(
      key: _stackKey,
      fit: StackFit.expand,
      children: [
        widget.child,
        if (rect != null)
          Positioned.fromRect(
            rect: rect.inflate(3),
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.accent, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: context.accent.withValues(alpha: 0.35),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Teclas del control remoto dentro de los campos de texto en una tele:
///
/// - Arriba/abajo mueven el foco al elemento vecino (no el cursor): sin esto el
///   foco queda atrapado y Flutter lanza una aserción al mover el cursor en
///   vertical.
/// - OK/Enter abre el teclado en pantalla propio ([showTvKeyboard]); el
///   teclado del sistema de Google TV pide conectar el teléfono.
/// - Un teclado físico sigue funcionando: sin teclado del sistema, los
///   caracteres se insertan desde el propio evento de tecla.
class TvTextFieldNavigation extends StatelessWidget {
  const TvTextFieldNavigation({super.key, required this.child});

  final Widget child;

  static final _activate = {
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
  };

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: child,
    );
  }

  static KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final focused = FocusManager.instance.primaryFocus;
    final state =
        focused?.context?.findAncestorStateOfType<EditableTextState>();
    if (focused == null || state == null) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      focused.focusInDirection(key == LogicalKeyboardKey.arrowDown
          ? TraversalDirection.down
          : TraversalDirection.up);
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && _activate.contains(key)) {
      if (state.widget.readOnly) return KeyEventResult.ignored;
      unawaited(_openKeyboard(state));
      return KeyEventResult.handled;
    }
    // Teclado físico: inserta el carácter tecleado.
    final char = event.character;
    final keyboard = HardwareKeyboard.instance;
    if (char != null &&
        char.isNotEmpty &&
        char.codeUnitAt(0) >= 0x20 &&
        char.codeUnitAt(0) != 0x7f &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed &&
        !state.widget.readOnly) {
      final value = state.textEditingValue;
      final sel = value.selection.isValid
          ? value.selection
          : TextSelection.collapsed(offset: value.text.length);
      final text = value.text.replaceRange(sel.start, sel.end, char);
      state.userUpdateTextEditingValue(
        TextEditingValue(
            text: text,
            selection:
                TextSelection.collapsed(offset: sel.start + char.length)),
        SelectionChangedCause.keyboard,
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static Future<void> _openKeyboard(EditableTextState state) async {
    final decoration = state.context
        .findAncestorWidgetOfExactType<InputDecorator>()
        ?.decoration;
    final result = await showTvKeyboard(
      state.context,
      initial: state.textEditingValue.text,
      label: decoration?.labelText ?? decoration?.hintText,
      obscure: state.widget.obscureText,
      numeric: state.widget.keyboardType == TextInputType.number,
    );
    if (result == null || !state.mounted) return;
    state.userUpdateTextEditingValue(
      TextEditingValue(
          text: result,
          selection: TextSelection.collapsed(offset: result.length)),
      SelectionChangedCause.keyboard,
    );
  }
}

/// Sustituye el teclado del sistema por nada: la tele usa [showTvKeyboard].
class NoSystemKeyboard with TextInputControl {}
