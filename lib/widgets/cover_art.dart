import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

/// Carátula reutilizable con manejo de carga y errores.
///
/// Muestra la imagen de red cuando la URL es válida; si no hay URL o la
/// descarga falla, muestra un placeholder con un icono sobre el color de
/// fondo indicado, en lugar de dejar el espacio en blanco.
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    this.url,
    this.width,
    this.height,
    this.borderRadius = 8,
    this.circle = false,
    this.fallbackIcon = Icons.music_note,
    this.fallbackIconSize = 24,
    this.fallbackColor = const Color(0xFF2A2A2A),
  });

  final String? url;

  /// Dimensiones fijas. Si son `null`, la carátula ocupa el espacio disponible.
  final double? width;
  final double? height;
  final double borderRadius;
  final bool circle;
  final IconData fallbackIcon;
  final double fallbackIconSize;
  final Color fallbackColor;

  @override
  Widget build(BuildContext context) {
    final Widget placeholder = _placeholder(context);
    final bool hasUrl = url != null && url!.isNotEmpty;

    final Widget image = hasUrl
        ? Image.network(
            url!,
            width: width,
            height: height,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => placeholder,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : placeholder,
          )
        : placeholder;

    final Widget clipped = circle
        ? ClipOval(child: image)
        : ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: image,
          );

    return SizedBox(width: width, height: height, child: clipped);
  }

  Widget _placeholder(BuildContext context) {
    return ColoredBox(
      color: fallbackColor,
      child: Center(
        child: Icon(fallbackIcon, color: context.textMuted, size: fallbackIconSize),
      ),
    );
  }
}