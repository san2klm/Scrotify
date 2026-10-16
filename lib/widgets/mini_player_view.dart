import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../utils/app_colors.dart';
import 'cover_art.dart';

/// Mini reproductor: carátula a la izquierda, información a la derecha y
/// reproducción centrada respecto al ancho de la ventana. Vive por encima del Navigator, por eso no utiliza tooltips.
class MiniPlayerView extends StatelessWidget {
  const MiniPlayerView({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.bgApp,
      child: Consumer2<PlayerController, NavidromeService>(
        builder: (context, player, nav, _) {
          final track = player.currentTrack;
          final liked = track != null && nav.isStarred(track.id);
          final details = track == null
              ? 'Elegí una canción en Scrotify'
              : [track.artist, track.album]
                  .where((text) => text.trim().isNotEmpty)
                  .join(' / ');

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Row(
                  children: [
                    CoverArt(
                      url: track?.albumArtUrl,
                      artist: track?.artist,
                      album: track?.album,
                      title: track?.title,
                      width: 80,
                      height: 80,
                      borderRadius: 8,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Canción: ${track?.title ?? 'Nada en reproducción'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Artista: $details',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 52),
                        ],
                      ),
                    ),
                  ],
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 16,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(width: 44),
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: IconButton(
                          tooltip: 'Anterior',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.skip_previous_rounded),
                          color: context.textPrimary,
                          onPressed: track == null ? null : player.skipPrevious,
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: IconButton.filled(
                          visualDensity: VisualDensity.compact,
                          style: IconButton.styleFrom(
                            backgroundColor: context.accent,
                          ),
                          icon: Icon(player.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded),
                          onPressed: track == null ? null : player.togglePlay,
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: IconButton(
                          tooltip: 'Siguiente',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.skip_next_rounded),
                          color: context.textPrimary,
                          onPressed: track == null ? null : player.skipNext,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Semantics(
                        button: true,
                        label: liked
                            ? 'Quitar de favoritos'
                            : 'Añadir a favoritos',
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: IconButton(
                            tooltip: 'Me gusta',
                            visualDensity: VisualDensity.compact,
                            icon: Icon(liked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded),
                            color:
                                liked ? context.accent : context.textSecondary,
                            onPressed: track == null
                                ? null
                                : () => nav.toggleStar(track),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
