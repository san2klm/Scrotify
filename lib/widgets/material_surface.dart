import 'package:flutter/material.dart';

import '../utils/app_colors.dart';

/// Superficie común para secciones y tarjetas; mantiene visibles las tintas Material.
class MaterialSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final double radius;

  const MaterialSurface(
      {super.key,
      required this.child,
      this.padding = EdgeInsets.zero,
      this.color,
      this.borderColor,
      this.radius = 16});

  @override
  Widget build(BuildContext context) {
    final baseColor = color ?? context.bgCard;
    final surface = Material(
      color: baseColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: borderColor ?? context.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
    return surface;
  }
}

/// Tarjeta interactiva con estados de foco, mouse y pulsación del tema activo.
class AppContentCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final EdgeInsetsGeometry padding;

  const AppContentCard(
      {super.key,
      required this.child,
      this.onTap,
      this.onLongPress,
      this.selected = false,
      this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    return MaterialSurface(
      borderColor: selected ? accent : context.borderSubtle,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        customBorder: shape,
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused) ||
              states.contains(WidgetState.pressed)) {
            return accent.withValues(alpha: 0.14);
          }
          if (states.contains(WidgetState.hovered)) {
            return accent.withValues(alpha: 0.08);
          }
          return null;
        }),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Cabecera de colecciones con acciones en una segunda fila en ventanas estrechas.
class CollectionHeader extends StatelessWidget {
  final Widget artwork;
  final Widget content;
  final Widget? actions;

  const CollectionHeader(
      {super.key, required this.artwork, required this.content, this.actions});

  @override
  Widget build(BuildContext context) => MaterialSurface(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(builder: (context, constraints) {
          final narrow = constraints.maxWidth < 600;
          final details = Row(children: [
            artwork,
            const SizedBox(width: 16),
            Expanded(child: content),
            if (!narrow && actions != null) actions!,
          ]);
          if (!narrow || actions == null) return details;
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                details,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: actions),
              ]);
        }),
      );
}
