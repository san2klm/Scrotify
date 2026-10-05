import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../utils/app_colors.dart';
import 'cover_art.dart';
import 'lyrics_follow_panel.dart';

/// Panel lateral "Escuchando ahora" para escritorio (ventanas anchas).
///
/// Muestra la carátula grande, los controles básicos y dos pestañas:
/// la cola de reproducción y la letra sincronizada.
class NowPlayingSidePanel extends StatefulWidget {
  const NowPlayingSidePanel({super.key});

  /// Ancho fijo del panel.
  static const double width = 340;

  @override
  State<NowPlayingSidePanel> createState() => _NowPlayingSidePanelState();
}

class _NowPlayingSidePanelState extends State<NowPlayingSidePanel> {
  bool _showLyrics = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: NowPlayingSidePanel.width,
      color: context.bgSidebar,
      child: Consumer<PlayerController>(
        builder: (context, player, _) {
          final track = player.currentTrack;
          if (track == null) return const _EmptyState();

          final upcoming = _upcoming(player);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text(
                  'Escuchando ahora',
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: CoverArt(
                    url: track.albumArtUrl,
                    artist: track.artist,
                    album: track.album,
                    title: track.title,
                    borderRadius: 12,
                    fallbackIconSize: 56,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: context.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
              _Controls(player: player),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                      visualDensity: VisualDensity.compact),
                  segments: [
                    ButtonSegment(
                        value: false,
                        label: Text('Cola (${upcoming.length})')),
                    const ButtonSegment(value: true, label: Text('Letra')),
                  ],
                  selected: {_showLyrics},
                  onSelectionChanged: (v) =>
                      setState(() => _showLyrics = v.first),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _showLyrics
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: LyricsFollowPanel(track: track),
                      )
                    : _QueueList(player: player, upcoming: upcoming),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Pistas que vienen después de la actual, según el orden real (con shuffle).
  List<Track> _upcoming(PlayerController player) {
    final ordered = player.orderedQueue;
    final start = player.currentOrderPos + 1;
    if (start <= 0 || start >= ordered.length) return const [];
    return ordered.sublist(start);
  }
}

class _Controls extends StatelessWidget {
  final PlayerController player;
  const _Controls({required this.player});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Anterior',
            icon: Icon(Icons.skip_previous_rounded,
                color: context.textPrimary, size: 28),
            onPressed: player.skipPrevious,
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            tooltip: player.playing ? 'Pausar' : 'Reproducir',
            style: IconButton.styleFrom(backgroundColor: context.accent),
            iconSize: 30,
            icon: Icon(player.playing
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded),
            onPressed: player.togglePlay,
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Siguiente',
            icon: Icon(Icons.skip_next_rounded,
                color: context.textPrimary, size: 28),
            onPressed: player.skipNext,
          ),
        ],
      ),
    );
  }
}

class _QueueList extends StatelessWidget {
  final PlayerController player;
  final List<Track> upcoming;
  const _QueueList({required this.player, required this.upcoming});

  @override
  Widget build(BuildContext context) {
    if (upcoming.isEmpty) {
      return Center(
        child: Text('No hay más canciones en la cola',
            style: TextStyle(color: context.textMuted, fontSize: 12.5)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      itemCount: upcoming.length,
      itemBuilder: (context, i) {
        final t = upcoming[i];
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: CoverArt(
            url: t.albumArtUrl,
            artist: t.artist,
            album: t.album,
            title: t.title,
            width: 36,
            height: 36,
            borderRadius: 4,
            fallbackIconSize: 18,
          ),
          title: Text(t.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.textPrimary, fontSize: 13)),
          subtitle: Text(t.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.textMuted, fontSize: 11.5)),
          onTap: () {
            // Salta a esa pista conservando la cola completa.
            final all = player.orderedQueue;
            final index = player.currentOrderPos + 1 + i;
            player.playQueue(all, startIndex: index);
          },
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.graphic_eq_rounded, color: context.textMuted, size: 40),
            const SizedBox(height: 12),
            Text('No hay nada sonando',
                style: TextStyle(color: context.textSecondary, fontSize: 14)),
            const SizedBox(height: 4),
            Text('Elegí una canción para verla acá',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.textMuted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
