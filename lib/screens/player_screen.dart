import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../services/jam_controller.dart';
import '../services/player_controller.dart';
import '../services/navidrome_service.dart';
import '../services/cover_fallback_service.dart';
import '../widgets/jam_dialog.dart';
import '../widgets/jam_queue_panel.dart';
import '../widgets/lyrics_follow_panel.dart';
import '../widgets/lyrics_overlay.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/cover_art.dart';
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
  // La letra se muestra de entrada; el usuario puede ocultarla desde el
  // mismo botón si prefiere ver sólo la portada.
  bool _showLyrics = true;
  bool _lyricsEverOpened = true;

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
                        child: _buildCenterArea(context, track),
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
                      // Barra de utilidades inferior: Favoritos + Volumen + Karaoke + Letra + Cola
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
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Barra de volumen: solo en pantalla grande.
                                // En celular se oculta para no saturar.
                                if (_isWide(context)) ...[
                                  _PlayerVolumeBar(player: player),
                                  const SizedBox(width: 4),
                                ],
                                IconButton(
                                  icon: Icon(Icons.music_note,
                                      color: _showLyrics
                                          ? context.accent
                                          : context.textSecondary,
                                      size: 24),
                                  tooltip: 'Letra',
                                  onPressed: () => setState(() {
                                    _showLyrics = !_showLyrics;
                                    if (_showLyrics) {
                                      _lyricsEverOpened = true;
                                    }
                                  }),
                                ),
                                IconButton(
                                  icon: Icon(Icons.queue_music_rounded,
                                      color: context.textSecondary, size: 24),
                                  tooltip: 'Cola de reproducción',
                                  onPressed: () => JamQueuePanel.show(context),
                                ),
                              ],
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

  /// Ancho a partir del cual se considera pantalla grande:
  /// portada a la izquierda y letra que sigue a la derecha.
  static const double _wideBreakpoint = 750;

  bool _isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= _wideBreakpoint;

  /// Zona central responsive:
  /// - Pantalla chica: portada centrada con overlay de letra + blur.
  /// - Pantalla grande + Letra activa: portada a la izquierda y
  ///   letra que sigue la canción a la derecha.
  Widget _buildCenterArea(BuildContext context, Track track) {
    if (_isWide(context) && _showLyrics) {
      return Row(
        children: [
          Expanded(
            flex: 5,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: _buildCoverImage(context, track),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 6,
            child: _lyricsEverOpened
                ? LyricsFollowPanel(
                    key: ValueKey('follow:${track.id}'),
                    track: track,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      );
    }

    // Pantalla chica (comportamiento actual): overlay sobre la portada.
    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          children: [
            _buildCoverImage(context, track),
            // Blur progresivo para modo "Letra" (karaoke).
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: _showLyrics ? 1.0 : 0.0),
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOut,
                builder: (context, t, _) {
                  if (t <= 0.01) {
                    return const SizedBox.shrink();
                  }
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter:
                          ImageFilter.blur(sigmaX: 19.5 * t, sigmaY: 19.5 * t),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.39 * t),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Letra sobre la portada con blur:
            // prioridad local de Navidrome > LRCLIB.
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: _showLyrics ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 350),
                child: IgnorePointer(
                  ignoring: !_showLyrics,
                  child: _lyricsEverOpened
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: LyricsOverlay(
                              key: ValueKey(track.id), track: track),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverImage(BuildContext context, Track track) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: CoverArt(
        url: track.albumArtUrl,
        artist: track.artist,
        album: track.album,
        title: track.title,
        width: double.infinity,
        height: double.infinity,
        borderRadius: 0,
        fallbackIconSize: 60,
        fallbackColor: context.bgElevated,
      ),
    );
  }

  Widget _buildAmbientBackground(Track track) {
    return Positioned.fill(
      child: FutureBuilder<String?>(
        future: () async {
          if (track.albumArtUrl != null && track.albumArtUrl!.isNotEmpty) {
            return track.albumArtUrl;
          }
          return CoverFallbackService.instance.findCover(
            artist: track.artist,
            album: track.album,
            title: track.title,
            size: 300,
          );
        }(),
        builder: (context, snapshot) {
          final url = snapshot.data;
          if (url == null || url.isEmpty) {
            return const SizedBox.shrink();
          }
          return ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              color: context.textPrimary.withAlpha(70),
              colorBlendMode: BlendMode.modulate,
            ),
          );
        },
      ),
    );
  }

  Widget _buildProgressBar(PlayerController player) {
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, snapshot) {
        final trackTime = Duration(
            seconds: int.tryParse(player.currentTrack?.duration ?? '') ?? 0);
        final duration = player.duration ?? trackTime;
        final position = snapshot.data ?? Duration.zero;

        final maxMs = duration.inMilliseconds == 0
            ? 1.0
            : duration.inMilliseconds.toDouble();
        final currentMs = (_dragValue ?? position.inMilliseconds.toDouble())
            .clamp(0.0, maxMs);

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
            color: repeatMode != LoopMode.off
                ? context.accent
                : context.textPrimary,
          ),
          onPressed: player.toggleRepeat,
        ),
      ],
    );
  }
}

class _PlayerVolumeBar extends StatefulWidget {
  final PlayerController player;
  const _PlayerVolumeBar({required this.player});

  @override
  State<_PlayerVolumeBar> createState() => _PlayerVolumeBarState();
}

class _PlayerVolumeBarState extends State<_PlayerVolumeBar> {
  double? _dragValue;
  double _lastNonZeroVolume = 0.7;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: widget.player.volumeStream,
      builder: (context, snapshot) {
        final volume = (_dragValue ?? snapshot.data ?? widget.player.volume)
            .clamp(0.0, 1.0)
            .toDouble();
        final muted = volume <= 0.001;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              icon: Icon(
                muted
                    ? Icons.volume_off
                    : volume < 0.5
                        ? Icons.volume_down
                        : Icons.volume_up,
                color: context.textSecondary,
                size: 18,
              ),
              onPressed: () {
                if (muted) {
                  widget.player.setVolume(
                      _lastNonZeroVolume > 0.05 ? _lastNonZeroVolume : 0.5);
                } else {
                  _lastNonZeroVolume = volume;
                  widget.player.setVolume(0.0);
                }
              },
            ),
            SizedBox(
              width: 75,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 2.5,
                  activeTrackColor: context.volumeAccent,
                  inactiveTrackColor: context.waveformUnplayed,
                  thumbColor: context.sliderThumb,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 4),
                  overlayColor: context.accentDim,
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                ),
                child: Slider(
                  min: 0,
                  max: 1,
                  value: volume,
                  onChanged: (v) {
                    setState(() => _dragValue = v);
                    widget.player.setVolume(v);
                  },
                  onChangeEnd: (v) {
                    widget.player.setVolume(v);
                    if (mounted) setState(() => _dragValue = null);
                  },
                ),
              ),
            ),
            SizedBox(
              width: 28,
              child: Text(
                '${(volume * 100).round()}%',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.textSecondary, fontSize: 10),
              ),
            ),
          ],
        );
      },
    );
  }
}
