import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../services/jam_controller.dart';
import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../screens/player_screen.dart';
import 'cover_art.dart';
import 'jam_dialog.dart';
import 'jam_queue_panel.dart';
import 'track_context_menu.dart';
import '../utils/app_colors.dart';

/// Panel de control persistente (barra inferior del reproductor).
/// Refleja el estado real del [PlayerController] y permite controlar la
/// reproducción sin importar en qué pantalla se esté.
///
/// **Desktop (no compact):** Barra de progreso estilo Spotify desktop — la
/// línea de tiempo va en la parte superior de la barra, controles centrados
/// abajo.
///
/// **Mobile (compact):** Barra de progreso estilo Spotify mobile — línea
/// delgada en el borde superior de la barra, controles y texto compactos.
class PersistentPlayerBar extends StatelessWidget {
  final bool compact;

  const PersistentPlayerBar({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Consumer2<PlayerController, JamController>(
      builder: (context, player, jam, _) {
        // En modo Party Speaker el invitado no reproduce audio local, pero la
        // barra debe reflejar fielmente lo que está sonando en el anfitrión.
        final remoteState = jam.isGuest ? jam.session : null;
        final track = remoteState?.currentTrack ?? player.currentTrack;
        final playing = remoteState?.isPlaying ?? player.playing;

        if (compact) {
          return _buildMobileBar(context, player, jam, track, playing);
        }
        return _buildDesktopBar(context, player, jam, track, playing);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Desktop layout — Spotify desktop style
  // ---------------------------------------------------------------------------

  Widget _buildDesktopBar(BuildContext context, PlayerController player,
      JamController jam, Track? track, bool playing) {
    return Container(
      height: 90,
      color: context.bgPlayer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // ── Left: artwork + track info (title, artist, favorite) ──
            _artwork(context, track),
            const SizedBox(width: 12),
            _trackInfo(context, track),
            const SizedBox(width: 8),

            // ── Center: playback controls on top, progress bar below ──
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Playback controls
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.shuffle,
                          size: 20,
                          color: player.shuffleEnabled
                              ? context.accent
                              : context.textSecondary,
                        ),
                        onPressed: jam.isGuest ? null : player.toggleShuffle,
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.skip_previous,
                            color: context.textPrimary, size: 26),
                        onPressed: _playbackHandler(
                            jam, player, 'skip_previous'),
                      ),
                      _playButton(context, player, jam, playing),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.skip_next,
                            color: context.textPrimary, size: 26),
                        onPressed: _playbackHandler(jam, player, 'skip_next'),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          player.repeatMode == LoopMode.one
                              ? Icons.repeat_one
                              : Icons.repeat,
                          size: 20,
                          color: player.repeatMode != LoopMode.off
                              ? context.accent
                              : context.textSecondary,
                        ),
                        onPressed: jam.isGuest ? null : player.toggleRepeat,
                      ),
                    ],
                  ),
                  // Progress bar with time labels
                  SizedBox(
                    width: 500,
                    child: _DesktopProgressBar(
                      player,
                      onSeek: (target) => _seek(jam, player, target),
                    ),
                  ),
                ],
              ),
            ),

            // ── Right: Jam + Queue + volume + fullscreen + three dots ──
            _jamButton(context),
            const SizedBox(width: 6),
            _queueButton(context),
            const SizedBox(width: 8),
            _VolumeBar(player),
            const SizedBox(width: 8),
            _openFullButton(context),
            const SizedBox(width: 4),
            _threeDotsMenu(context, track),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Mobile layout — Spotify mobile style
  // ---------------------------------------------------------------------------

  Widget _buildMobileBar(BuildContext context, PlayerController player,
      JamController jam, Track? track, bool playing) {
    return Container(
      height: 84,
      color: context.bgPlayer,
      child: Column(
        children: [
          // Thin progress bar at the very top (Spotify mobile style)
          _MobileProgressBar(
            player,
            onSeek: (target) => _seek(jam, player, target),
          ),
          // Content row
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  // La zona completa abre el
                  // reproductor en pantalla completa al tocarla.
                  Expanded(
                    child: InkWell(
                      onTap: () => _openPlayerScreen(context),
                      borderRadius: BorderRadius.circular(8),
                      child: Row(
                        children: [
                          _artwork(context, track),
                          const SizedBox(width: 10),
                          Expanded(child: _trackInfo(context, track)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  ..._mobileControls(context, player, jam, playing, track),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _mobileControls(
      BuildContext context, PlayerController player, JamController jam, bool playing, Track? track) {
    return [
      _compactControlIcon(
        context,
        Icons.skip_previous,
        _playbackHandler(jam, player, 'skip_previous'),
        size: 24,
      ),
      _playButton(context, player, jam, playing, compact: true),
      _compactControlIcon(
        context,
        Icons.skip_next,
        _playbackHandler(jam, player, 'skip_next'),
        size: 24,
      ),
      IconButton(
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        icon: Icon(Icons.queue_music_rounded,
            color: context.textSecondary, size: 20),
        onPressed: () => JamQueuePanel.show(context),
      ),
      _threeDotsMenu(context, track),
    ];
  }

  Widget _jamButton(BuildContext context) {
    final jam = context.watch<JamController>();
    if (jam.inJam) {
      return InkWell(
        onTap: () => JamDialog.show(context),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: context.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: context.accent.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.accent,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.speaker_group_rounded,
                  color: context.accent, size: 15),
              const SizedBox(width: 5),
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
      tooltip: 'Iniciar o unirse a Jam',
      visualDensity: VisualDensity.compact,
      icon: Icon(Icons.speaker_group_outlined,
          color: context.textSecondary, size: 20),
      onPressed: () => JamDialog.show(context),
    );
  }

  Widget _queueButton(BuildContext context) {
    return IconButton(
      tooltip: 'Cola de reproducción',
      visualDensity: VisualDensity.compact,
      icon: Icon(Icons.queue_music_rounded,
          color: context.textSecondary, size: 21),
      onPressed: () => JamQueuePanel.show(context),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared widgets
  // ---------------------------------------------------------------------------

  Widget _artwork(BuildContext context, Track? track) {
    return CoverArt(
      url: track?.albumArtUrl,
      artist: track?.artist,
      album: track?.album,
      title: track?.title,
      width: compact ? 44 : 56,
      height: compact ? 44 : 56,
      borderRadius: compact ? 8 : 6,
      fallbackIcon: Icons.music_note,
      fallbackIconSize: 22,
      fallbackColor: context.accent,
    );
  }

  Widget _trackInfo(BuildContext context, Track? track) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          track?.title ?? 'Nada en reproducción',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.playerTitle,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                track?.artist ?? 'Selecciona algo para escuchar',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.playerArtist, fontSize: 12),
              ),
            ),
            const SizedBox(width: 4),
            _favoriteButton(context, track, compact: true),
          ],
        ),
      ],
    );
  }

  Widget _threeDotsMenu(BuildContext context, Track? track) {
    if (track == null) return const SizedBox.shrink();
    return IconButton(
      visualDensity: compact ? VisualDensity.compact : null,
      icon: Icon(Icons.more_vert_rounded, color: context.textSecondary, size: 20),
      onPressed: () {
        final player = context.read<PlayerController>();
        TrackContextMenu.show(context, track, playlistId: player.sourcePlaylist?.id);
      },
    );
  }

  Widget _favoriteButton(BuildContext context, Track? track,
      {bool compact = false}) {
    if (track == null) {
      return const SizedBox.shrink();
    }
    final nav = context.watch<NavidromeService>();
    final starred = nav.isStarred(track.id);
    return IconButton(
      visualDensity: compact ? VisualDensity.compact : null,
      padding: compact ? EdgeInsets.zero : null,
      constraints:
          compact ? const BoxConstraints(minWidth: 36, minHeight: 36) : null,
      icon: Icon(
        starred ? Icons.favorite : Icons.favorite_border,
        color: starred ? context.accent : context.textSecondary,
        size: compact ? 22 : 20,
      ),
      onPressed: () => nav.toggleStar(track),
    );
  }

  Widget _compactControlIcon(
      BuildContext context, IconData icon, VoidCallback? onPressed,
      {Color? color, double size = 24}) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      icon: Icon(icon, color: color ?? context.textPrimary, size: size),
      onPressed: onPressed,
    );
  }

  Widget _playButton(
      BuildContext context, PlayerController player, JamController jam, bool playing,
      {bool compact = false}) {
    return IconButton(
      visualDensity: compact ? VisualDensity.compact : null,
      padding: compact ? EdgeInsets.zero : null,
      constraints:
          compact ? const BoxConstraints(minWidth: 40, minHeight: 40) : null,
      iconSize: compact ? 38 : 36,
      icon: Icon(
        playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
        color: context.textPrimary,
      ),
      onPressed: _playbackHandler(jam, player, 'toggle'),
    );
  }

  VoidCallback? _playbackHandler(
    JamController jam,
    PlayerController player,
    String action,
  ) {
    if (jam.isGuest && !(jam.localParticipant?.canControlPlayback ?? false)) {
      return null;
    }
    if (jam.inJam) {
      return () {
        jam.playbackAction(action);
      };
    }
    return switch (action) {
      'toggle' => player.togglePlay,
      'skip_next' => player.skipNext,
      'skip_previous' => player.skipPrevious,
      _ => null,
    };
  }

  void _seek(JamController jam, PlayerController player, Duration target) {
    if (jam.isGuest && !(jam.localParticipant?.canControlPlayback ?? false)) {
      return;
    }
    if (jam.inJam) {
      jam.playbackAction('seek', position: target);
    } else {
      player.seek(target);
    }
  }

  Widget _openFullButton(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      icon: Icon(
        Icons.fullscreen,
        color: context.textSecondary,
        size: 18,
      ),
      onPressed: () => _openPlayerScreen(context),
    );
  }

  void _openPlayerScreen(BuildContext context) {
    final player = context.read<PlayerController>();
    if (player.currentTrack == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }
}

String _format(Duration d) {
  final minutes = d.inMinutes;
  final secs = d.inSeconds % 60;
  return '$minutes:${secs.toString().padLeft(2, '0')}';
}

// =============================================================================
// Desktop progress bar — Spotify desktop style
//
// A thin green/white progress line at the very top of the player bar.
// Time labels (current / total) sit centered BELOW the progress line, between
// the line and the controls row. The progress bar stretches the full width with
// small horizontal padding.
// =============================================================================

class _DesktopProgressBar extends StatefulWidget {
  final PlayerController player;
  final ValueChanged<Duration>? onSeek;

  const _DesktopProgressBar(this.player, {this.onSeek});

  @override
  State<_DesktopProgressBar> createState() => _DesktopProgressBarState();
}

class _DesktopProgressBarState extends State<_DesktopProgressBar> {
  double? _dragValue;
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: widget.player.positionStream,
      builder: (context, snapshot) {
        final duration = widget.player.duration ?? Duration.zero;
        final position = snapshot.data ?? Duration.zero;

        final maxMs = duration.inMilliseconds == 0
            ? 1.0
            : duration.inMilliseconds.toDouble();
        final currentMs = (_dragValue ?? position.inMilliseconds.toDouble())
            .clamp(0.0, maxMs);

        return MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Progress slider + time labels (Spotify desktop style)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    // Current time
                    SizedBox(
                      width: 40,
                      child: Text(
                        _format(Duration(milliseconds: currentMs.round())),
                        style: TextStyle(
                            color: context.textSecondary, fontSize: 11),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    // Slider
                    Expanded(
                      child: SizedBox(
                        height: 14,
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: _hovering ? 4 : 3,
                            activeTrackColor: context.waveformPlayed,
                            inactiveTrackColor: context.waveformUnplayed,
                            thumbColor: context.sliderThumb,
                            thumbShape: RoundSliderThumbShape(
                              enabledThumbRadius: _hovering ? 6 : 0,
                            ),
                            overlayColor: context.accentDim,
                            overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14),
                          ),
                          child: Slider(
                            min: 0,
                            max: maxMs,
                            value: currentMs,
                            onChanged: (v) => setState(() => _dragValue = v),
                            onChangeEnd: (v) async {
                              final target = Duration(milliseconds: v.round());
                              if (widget.onSeek != null) {
                                widget.onSeek!(target);
                              } else {
                                await widget.player.seek(target);
                              }
                              if (mounted) setState(() => _dragValue = null);
                            },
                          ),
                        ),
                      ),
                    ),
                    // Total time
                    SizedBox(
                      width: 40,
                      child: Text(
                        _format(duration),
                        style: TextStyle(
                            color: context.textSecondary, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// Mobile progress bar — Spotify mobile style
//
// A very thin progress line at the very top of the bar, full width.
// No time labels in the bar itself (those live in the full-screen player).
// =============================================================================

class _MobileProgressBar extends StatefulWidget {
  final PlayerController player;
  final ValueChanged<Duration>? onSeek;

  const _MobileProgressBar(this.player, {this.onSeek});

  @override
  State<_MobileProgressBar> createState() => _MobileProgressBarState();
}

class _MobileProgressBarState extends State<_MobileProgressBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: widget.player.positionStream,
      builder: (context, snapshot) {
        final duration = widget.player.duration ?? Duration.zero;
        final position = snapshot.data ?? Duration.zero;

        final maxMs = duration.inMilliseconds == 0
            ? 1.0
            : duration.inMilliseconds.toDouble();
        final currentMs = (_dragValue ?? position.inMilliseconds.toDouble())
            .clamp(0.0, maxMs);

        return SizedBox(
          height: 6,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: context.waveformPlayed,
              inactiveTrackColor: context.waveformUnplayed,
              thumbColor: context.waveformPlayed,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 0),
              overlayColor: Colors.transparent,
              overlayShape: RoundSliderOverlayShape(overlayRadius: 0),
            ),
            child: Slider(
              min: 0,
              max: maxMs,
              value: currentMs,
              onChanged: (v) => setState(() => _dragValue = v),
              onChangeEnd: (v) async {
                final target = Duration(milliseconds: v.round());
                if (widget.onSeek != null) {
                  widget.onSeek!(target);
                } else {
                  await widget.player.seek(target);
                }
                if (mounted) setState(() => _dragValue = null);
              },
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// Volume bar (shared by desktop controls)
// =============================================================================

class _VolumeBar extends StatefulWidget {
  final PlayerController player;
  const _VolumeBar(this.player);

  @override
  State<_VolumeBar> createState() => _VolumeBarState();
}

class _VolumeBarState extends State<_VolumeBar> {
  double? _dragValue;

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
            Icon(
              muted
                  ? Icons.volume_off
                  : volume < 0.5
                      ? Icons.volume_down
                      : Icons.volume_up,
              color: context.textSecondary,
              size: 20,
            ),
            SizedBox(
              width: 110,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  activeTrackColor: context.volumeAccent,
                  inactiveTrackColor: context.themeBorder,
                  thumbColor: context.sliderThumb,
                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayColor: context.accentDim,
                  overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
                ),
                child: Slider(
                  min: 0,
                  max: 1,
                  value: volume,
                  // Aplicar en vivo mientras se arrastra: el audio sube/baja al
                  // mismo tiempo que el pulgar, sin esperar a soltar.
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
              width: 38,
              child: Text(
                '${(volume * 100).round()}%',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.textSecondary, fontSize: 11),
              ),
            ),
          ],
        );
      },
    );
  }
}
