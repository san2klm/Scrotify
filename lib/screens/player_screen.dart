import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../services/jam_controller.dart';
import '../services/player_controller.dart';
import '../services/navidrome_service.dart';
import '../widgets/jam_dialog.dart';
import '../widgets/jam_queue_panel.dart';
import '../widgets/track_context_menu.dart';
import '../utils/app_colors.dart';

/// Pantalla completa del reproductor. Es una vista del estado global de
/// reproducción ([PlayerController]); al cerrar esta pantalla la música sigue
/// sonando y queda reflejada en la barra persistente.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  double? _dragValue;

  String _format(Duration d) {
    final minutes = d.inMinutes;
    final secs = d.inSeconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  void _showContextMenu(PlayerController player, Track track) {
    TrackContextMenu.show(context, track);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerController>(
      builder: (context, player, _) {
        final track = player.currentTrack;
        if (track == null) {
          return Scaffold(
            backgroundColor: context.bgApp,
            body: Center(
              child: Text('Nada en reproducción',
                  style: TextStyle(color: context.textSecondary)),
            ),
          );
        }

        final playing = player.playing;
        final repeatMode = player.repeatMode;
        final shuffleEnabled = player.shuffleEnabled;

        return Scaffold(
          backgroundColor: context.bgDeep,
          body: Stack(
            children: [
              _buildAmbientBackground(track),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: Icon(Icons.keyboard_arrow_down,
                                color: context.textPrimary, size: 32),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          Consumer<JamController>(
                            builder: (context, jam, _) {
                              if (jam.inJam) {
                                return InkWell(
                                  onTap: () =>
                                      JamDialog.showAsBottomSheet(context),
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: context.accent
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: context.accent
                                            .withValues(alpha: 0.4),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: context.accent,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Jam · ${jam.participants.length}',
                                          style: TextStyle(
                                            color: context.accent,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }
                              return IconButton(
                                icon: Icon(Icons.speaker_group_outlined,
                                    color: context.textSecondary, size: 22),
                                tooltip: 'Jam',
                                onPressed: () =>
                                    JamDialog.showAsBottomSheet(context),
                              );
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.more_horiz,
                                color: context.textPrimary),
                            onPressed: () => _showContextMenu(player, track),
                          ),
                        ],
                      ),
                      Expanded(
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: track.albumArtUrl != null
                                  ? Image.network(track.albumArtUrl!,
                                      fit: BoxFit.cover)
                                  : Container(
                                      color: context.bgElevated,
                                      child: Icon(Icons.music_note,
                                          size: 60, color: context.textMuted),
                                    ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.textSecondary,
                          fontSize: 16,
                        ),
                      ),
                      Consumer<JamController>(
                        builder: (context, jam, _) {
                          if (jam.inJam && jam.currentTrackAddedBy != null) {
                            final p = jam.currentTrackAddedBy!;
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Color(p.avatarColorValue)
                                      .withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Color(p.avatarColorValue)
                                        .withValues(alpha: 0.4),
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircleAvatar(
                                      radius: 4,
                                      backgroundColor:
                                          Color(p.avatarColorValue),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Añadido al Jam por ${p.name}',
                                      style: TextStyle(
                                        color: Color(p.avatarColorValue),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildProgressBar(player),
                      const SizedBox(height: 8),
                      _buildControls(
                        player,
                        playing: playing,
                        repeatMode: repeatMode,
                        shuffleEnabled: shuffleEnabled,
                      ),
                      const SizedBox(height: 12),
                      // Barra de utilidades inferior: Favoritos + Jam + Cola
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Consumer<NavidromeService>(
                              builder: (context, nav, _) {
                                final isStarred = nav.isStarred(track.id);
                                return IconButton(
                                  icon: Icon(
                                    isStarred
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: isStarred
                                        ? context.accent
                                        : context.textSecondary,
                                    size: 22,
                                  ),
                                  onPressed: () => nav.toggleStar(track),
                                );
                              },
                            ),
                            IconButton(
                              icon: Icon(Icons.queue_music_rounded,
                                  color: context.textSecondary, size: 24),
                              tooltip: 'Cola de reproducción',
                              onPressed: () => JamQueuePanel.show(context),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAmbientBackground(dynamic track) {
    return Positioned.fill(
      child: track.albumArtUrl == null
          ? const SizedBox.shrink()
          : ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Image.network(
                track.albumArtUrl!,
                fit: BoxFit.cover,
                color: context.textPrimary.withAlpha(70),
                colorBlendMode: BlendMode.modulate,
              ),
            ),
    );
  }

  Widget _buildProgressBar(PlayerController player) {
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, snapshot) {
        final trackTime =
            Duration(seconds: int.tryParse(player.currentTrack?.duration ?? '') ?? 0);
        final duration = player.duration ?? trackTime;
        final position = snapshot.data ?? Duration.zero;

        final maxMs = duration.inMilliseconds == 0
            ? 1.0
            : duration.inMilliseconds.toDouble();
        final currentMs =
            (_dragValue ?? position.inMilliseconds.toDouble()).clamp(0.0, maxMs);

        return Column(
          children: [
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                activeTrackColor: context.waveformPlayed,
                inactiveTrackColor: context.waveformUnplayed,
                thumbColor: context.sliderThumb,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayColor: context.accentDim,
                overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: Slider(
                min: 0,
                max: maxMs,
                value: currentMs,
                onChanged: (v) => setState(() => _dragValue = v),
                onChangeEnd: (v) async {
                  await player.seek(Duration(milliseconds: v.round()));
                  if (mounted) setState(() => _dragValue = null);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _format(Duration(milliseconds: currentMs.round())),
                    style:
                        TextStyle(color: context.textSecondary, fontSize: 12),
                  ),
                  Text(
                    _format(duration),
                    style:
                        TextStyle(color: context.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildControls(
    PlayerController player, {
    required bool playing,
    required LoopMode repeatMode,
    required bool shuffleEnabled,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          icon: Icon(
            Icons.shuffle,
            size: 22,
            color: shuffleEnabled ? context.accent : context.textPrimary,
          ),
          onPressed: player.toggleShuffle,
        ),
        IconButton(
          icon: Icon(Icons.skip_previous, color: context.textPrimary, size: 34),
          onPressed: player.skipPrevious,
        ),
        IconButton(
          iconSize: 60,
          icon: Icon(
            playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
            color: context.textPrimary,
          ),
          onPressed: player.togglePlay,
        ),
        IconButton(
          icon: Icon(Icons.skip_next, color: context.textPrimary, size: 34),
          onPressed: player.skipNext,
        ),
        IconButton(
          icon: Icon(
            repeatMode == LoopMode.one ? Icons.repeat_one : Icons.repeat,
            size: 22,
            color: repeatMode != LoopMode.off ? context.accent : context.textPrimary,
          ),
          onPressed: player.toggleRepeat,
        ),
      ],
    );
  }
}

