import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/artist_screen.dart';
import '../services/navidrome_service.dart';
import '../utils/app_colors.dart';

/// Widget que convierte el campo `artist` de un track en enlaces interactivos.
///
/// Si la cadena contiene múltiples artistas separados por coma, punto y coma,
/// ampersand o "feat.", cada nombre se renderiza como un enlace individual que
/// navega a la página del artista correspondiente.
///
/// Uso: `InteractiveArtistText(artistString: track.artist, fontSize: 12)`
class InteractiveArtistText extends StatelessWidget {
  final String artistString;
  final double fontSize;
  final Color? color;
  final int maxLines;

  const InteractiveArtistText({
    super.key,
    required this.artistString,
    this.fontSize = 12,
    this.color,
    this.maxLines = 1,
  });

  /// Separadores conocidos en el campo "artist" de Navidrome/Subsonic.
  static final _splitPattern = RegExp(r'\s*[,;&]\s*|\s+feat\.?\s+', caseSensitive: false);

  @override
  Widget build(BuildContext context) {
    final textColor = color ?? context.textMuted;
    final parts = artistString.split(_splitPattern);

    // Si solo hay un artista, renderizar como texto simple clicable.
    if (parts.length <= 1) {
      return GestureDetector(
        onTap: () => _navigateToArtist(context, artistString.trim()),
        child: Text(
          artistString,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: textColor,
            fontSize: fontSize,
            decoration: TextDecoration.underline,
            decorationColor: textColor.withValues(alpha: 0.3),
            decorationStyle: TextDecorationStyle.dotted,
          ),
        ),
      );
    }

    // Múltiples artistas: reconstruir con separadores y hacer cada nombre
    // un enlace independiente.
    final spans = <InlineSpan>[];
    int searchStart = 0;
    for (var i = 0; i < parts.length; i++) {
      final name = parts[i].trim();
      if (name.isEmpty) continue;

      // Encontrar el separador original entre este artista y el siguiente.
      if (i > 0) {
        final prevEnd = artistString.indexOf(parts[i - 1], searchStart) +
            parts[i - 1].length;
        final nextStart = artistString.indexOf(name, prevEnd);
        final separator = artistString.substring(prevEnd, nextStart);
        if (separator.isNotEmpty) {
          spans.add(TextSpan(
            text: separator,
            style: TextStyle(color: textColor, fontSize: fontSize),
          ));
        }
      }

      searchStart = artistString.indexOf(name, searchStart);

      spans.add(TextSpan(
        text: name,
        style: TextStyle(
          color: textColor,
          fontSize: fontSize,
          decoration: TextDecoration.underline,
          decorationColor: textColor.withValues(alpha: 0.3),
          decorationStyle: TextDecorationStyle.dotted,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () => _navigateToArtist(context, name),
      ));
    }

    return RichText(
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans),
    );
  }

  Future<void> _navigateToArtist(BuildContext context, String name) async {
    final nav = context.read<NavidromeService>();
    try {
      final results = await nav.search(name);
      final match = results.artists.firstWhere(
        (a) => a.name.toLowerCase() == name.toLowerCase(),
        orElse: () => results.artists.isNotEmpty
            ? results.artists.first
            : Artist(id: '', name: name),
      );
      if (match.id.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se encontró al artista "$name"')),
          );
        }
        return;
      }
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ArtistScreen(artist: match)),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al buscar artista "$name"')),
        );
      }
    }
  }
}
