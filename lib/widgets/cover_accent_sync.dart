import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/cover_palette.dart';
import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../services/theme_controller.dart';
import 'cover_art.dart';

/// Mantiene el color de énfasis del tema alineado con la carátula de la pista
/// que suena (si el usuario activó «Color según la carátula»).
///
/// No dibuja nada propio: devuelve [child] tal cual.
class CoverAccentSync extends StatefulWidget {
  const CoverAccentSync({super.key, required this.child});

  final Widget child;

  @override
  State<CoverAccentSync> createState() => _CoverAccentSyncState();
}

class _CoverAccentSyncState extends State<CoverAccentSync> {
  final CoverPalette _palette = CoverPalette();
  String? _lastKey;

  Future<void> _sync(ThemeController theme, Track? track, bool enabled) async {
    final url = track?.albumArtUrl;
    final key = enabled && track != null && url != null ? track.id : null;
    if (key == _lastKey) return;
    _lastKey = key;
    if (key == null) {
      theme.setCoverAccent(null);
      return;
    }
    final color = await _palette.accentFor(key, CoverArt.imageProvider(url!));
    // Si mientras tanto cambió la pista, este resultado ya no vale.
    if (!mounted || _lastKey != key) return;
    theme.setCoverAccent(color);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeController>();
    final enabled =
        context.select<ThemeController, bool>((t) => t.coverAccentEnabled);
    final track =
        context.select<PlayerController, Track?>((p) => p.currentTrack);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _sync(theme, track, enabled));
    return widget.child;
  }
}
