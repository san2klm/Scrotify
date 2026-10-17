import 'dart:math';
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
/// Al pasar el mouse sobre un nombre de artista, el cursor cambia a mano y el
/// texto se resalta en el color accent de la app. Si hay varios artistas, cada
/// uno se resalta de forma independiente.
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
  static final _splitPattern =
      RegExp(r'\s*[,;&]\s*|\s+feat\.?\s+', caseSensitive: false);

  @override
  Widget build(BuildContext context) {
    final baseColor = color ?? context.textMuted;
    final parts = artistString.split(_splitPattern);

    if (parts.length <= 1) {
      // Un solo artista — WidgetSpan con MouseRegion para hover individual.
      return _SingleArtistLink(
        name: artistString.trim(),
        fontSize: fontSize,
        baseColor: baseColor,
        maxLines: maxLines,
      );
    }

    // Múltiples artistas: reconstruir con separadores, cada nombre con hover
    // independiente usando WidgetSpan.
    final spans = <InlineSpan>[];
    int searchStart = 0;
    for (var i = 0; i < parts.length; i++) {
      final name = parts[i].trim();
      if (name.isEmpty) continue;

      // Separador original entre este artista y el anterior.
      if (i > 0) {
        final prev = parts[i - 1].trim();
        final prevEnd =
            artistString.indexOf(prev, max(0, searchStart - prev.length - 3)) +
                prev.length;
        final nextStart = artistString.indexOf(name, prevEnd);
        if (nextStart > prevEnd) {
          final separator = artistString.substring(prevEnd, nextStart);
          if (separator.isNotEmpty) {
            spans.add(TextSpan(
              text: separator,
              style: TextStyle(color: baseColor, fontSize: fontSize),
            ));
          }
        }
      }

      searchStart = artistString.indexOf(name, searchStart) + name.length;

      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: _ArtistHoverLink(
          name: name,
          fontSize: fontSize,
          baseColor: baseColor,
        ),
      ));
    }

    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// ---------------------------------------------------------------------------
// Artista único — envuelto en MouseRegion para hover.
// ---------------------------------------------------------------------------

class _SingleArtistLink extends StatefulWidget {
  final String name;
  final double fontSize;
  final Color baseColor;
  final int maxLines;

  const _SingleArtistLink({
    required this.name,
    required this.fontSize,
    required this.baseColor,
    required this.maxLines,
  });

  @override
  State<_SingleArtistLink> createState() => _SingleArtistLinkState();
}

class _SingleArtistLinkState extends State<_SingleArtistLink> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final color = _hovering ? context.accent : widget.baseColor;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: () => _navigateToArtist(context, widget.name),
        child: Text(
          widget.name,
          maxLines: widget.maxLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: widget.fontSize,
            decoration: TextDecoration.underline,
            decorationColor: _hovering ? color : color.withValues(alpha: 0.3),
            decorationStyle: _hovering
                ? TextDecorationStyle.solid
                : TextDecorationStyle.dotted,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Artista individual dentro de un RichText con múltiples artistas.
// ---------------------------------------------------------------------------

class _ArtistHoverLink extends StatefulWidget {
  final String name;
  final double fontSize;
  final Color baseColor;

  const _ArtistHoverLink({
    required this.name,
    required this.fontSize,
    required this.baseColor,
  });

  @override
  State<_ArtistHoverLink> createState() => _ArtistHoverLinkState();
}

class _ArtistHoverLinkState extends State<_ArtistHoverLink> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final color = _hovering ? context.accent : widget.baseColor;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: () => _navigateToArtist(context, widget.name),
        child: Text(
          widget.name,
          style: TextStyle(
            color: color,
            fontSize: widget.fontSize,
            decoration: TextDecoration.underline,
            decorationColor: _hovering ? color : color.withValues(alpha: 0.3),
            decorationStyle: _hovering
                ? TextDecorationStyle.solid
                : TextDecorationStyle.dotted,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Navegación al artista (compartida).
// ---------------------------------------------------------------------------

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
