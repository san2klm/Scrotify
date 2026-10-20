import 'package:flutter/material.dart';

/// Muestra los mismos colores sólidos de la tarjeta del tema.
class ThemeColorPreview extends StatelessWidget {
  final Color background;
  final Color accent;
  final Color accent2;

  const ThemeColorPreview({
    super.key,
    required this.background,
    required this.accent,
    required this.accent2,
  });

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 80,
          child: Column(children: [
            Expanded(
              child: SizedBox(
                  width: double.infinity, child: ColoredBox(color: background)),
            ),
            SizedBox(
                height: 8,
                width: double.infinity,
                child: ColoredBox(color: accent)),
            SizedBox(
                height: 8,
                width: double.infinity,
                child: ColoredBox(color: accent2)),
          ]),
        ),
      );
}
