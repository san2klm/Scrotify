import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/mini_player_controller.dart';
import '../services/player_controller.dart';
import '../utils/app_colors.dart';
import '../utils/playback_time.dart';
import 'cover_art.dart';
import 'player_position_builder.dart';
import 'waveform_progress_bar.dart';

/// Contenido del modo mini reproductor: carátula, título, espectro con
/// control de posición y botones. Vive por encima del Navigator (en el marco
/// de ventana), por eso no usa tooltips (no hay `Overlay` a ese nivel).
class MiniPlayerView extends StatelessWidget {
  const MiniPlayerView({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.bgApp,
      child: Consumer<PlayerController>(
        builder: (context, player, _) {
          final track = player.currentTrack;
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    CoverArt(
                      url: track?.albumArtUrl,
                      artist: track?.artist,
                      album: track?.album,
                      title: track?.title,
                      width: 52,
                      height: 52,
                      borderRadius: 8,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track?.title ?? 'Nada sonando',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: context.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700),
                          ),
                          Text(
                            track?.artist ?? 'Elegí una canción en Scrotify',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: context.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (track != null) _Progress(player: player),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded),
                      color: context.textPrimary,
                      onPressed: track == null ? null : player.skipPrevious,
                    ),
                    IconButton.filled(
                      style:
                          IconButton.styleFrom(backgroundColor: context.accent),
                      icon: Icon(player.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded),
                      onPressed: track == null ? null : player.togglePlay,
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded),
                      color: context.textPrimary,
                      onPressed: track == null ? null : player.skipNext,
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.open_in_full_rounded, size: 20),
                      color: context.textSecondary,
                      onPressed: () =>
                          context.read<MiniPlayerController>().exit(),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  final PlayerController player;
  const _Progress({required this.player});

  @override
  Widget build(BuildContext context) {
    final duration = player.duration ?? Duration.zero;
    return PlayerPositionBuilder(
      player: player,
      duration: duration,
      builder: (context, position) => Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(formatPlaybackTime(position),
                style: TextStyle(color: context.textMuted, fontSize: 10.5)),
          ),
          Expanded(
            child: WaveformProgressBar(
              waveform: player.waveformData,
              height: 26,
              playing: player.playing,
              position: position,
              duration: duration,
              onSeek: player.seek,
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(formatPlaybackTime(duration),
                textAlign: TextAlign.right,
                style: TextStyle(color: context.textMuted, fontSize: 10.5)),
          ),
        ],
      ),
    );
  }
}
