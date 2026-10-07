import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../utils/app_colors.dart';

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

/// Con el control remoto, arriba/abajo dentro de un campo de texto deben mover
/// el foco al elemento vecino (como en cualquier formulario de tele), no el
/// cursor del texto: sin esto el foco queda atrapado en el campo y Flutter
/// lanza una aserción al intentar mover el cursor en vertical.
class TvTextFieldNavigation extends StatelessWidget {
  const TvTextFieldNavigation({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        final direction = key == LogicalKeyboardKey.arrowDown
            ? TraversalDirection.down
            : key == LogicalKeyboardKey.arrowUp
                ? TraversalDirection.up
                : null;
        final focused = FocusManager.instance.primaryFocus;
        final inText =
            focused?.context?.findAncestorWidgetOfExactType<EditableText>() !=
                null;
        if (direction == null || focused == null || !inText) {
          return KeyEventResult.ignored;
        }
        focused.focusInDirection(direction);
        return KeyEventResult.handled;
      },
      child: child,
    );
  }
}
