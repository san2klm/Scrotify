import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../screens/player_screen.dart';
import 'cover_art.dart';

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
    return Consumer<PlayerController>(
      builder: (context, player, _) {
        final track = player.currentTrack;
        final playing = player.playing;

        if (compact) {
          return _buildMobileBar(context, player, track, playing);
        }
        return _buildDesktopBar(context, player, track, playing);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Desktop layout — Spotify desktop style
  // ---------------------------------------------------------------------------

  Widget _buildDesktopBar(BuildContext context, PlayerController player,
      Track? track, bool playing) {
    return Container(
      height: 90,
      color: const Color(0xFF181818),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // ── Left: artwork + track info + favorite ──
            _artwork(track),
            const SizedBox(width: 12),
            _trackInfo(track),
            const SizedBox(width: 12),
            _favoriteButton(context, track),
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
                              ? Colors.greenAccent
                              : Colors.white70,
                        ),
                        onPressed: player.toggleShuffle,
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.skip_previous,
                            color: Colors.white, size: 26),
                        onPressed: player.skipPrevious,
                      ),
                      _playButton(player, playing),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.skip_next,
                            color: Colors.white, size: 26),
                        onPressed: player.skipNext,
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          player.repeatMode == LoopMode.one
                              ? Icons.repeat_one
                              : Icons.repeat,
                          size: 20,
                          color: player.repeatMode != LoopMode.off
                              ? Colors.greenAccent
                              : Colors.white70,
                        ),
                        onPressed: player.toggleRepeat,
                      ),
                    ],
                  ),
                  // Progress bar with time labels
                  SizedBox(
                    width: 500,
                    child: _DesktopProgressBar(player),
                  ),
                ],
              ),
            ),

            // ── Right: volume + fullscreen ──
            _VolumeBar(player),
            const SizedBox(width: 8),
            _openFullButton(context),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Mobile layout — Spotify mobile style
  // ---------------------------------------------------------------------------

  Widget _buildMobileBar(BuildContext context, PlayerController player,
      Track? track, bool playing) {
    return Container(
      height: 84,
      color: const Color(0xFF181818),
      child: Column(
        children: [
          // Thin progress bar at the very top (Spotify mobile style)
          _MobileProgressBar(player),
          // Content row
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _artwork(track),
                  const SizedBox(width: 10),
                  Expanded(child: _trackInfo(track)),
                  _favoriteButton(context, track, compact: true),
                  const SizedBox(width: 4),
                  ..._mobileControls(context, player, playing),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _mobileControls(
      BuildContext context, PlayerController player, bool playing) {
    return [
      _compactControlIcon(
        Icons.skip_previous,
        player.skipPrevious,
        size: 24,
      ),
      _playButton(player, playing, compact: true),
      _compactControlIcon(
        Icons.skip_next,
        player.skipNext,
        size: 24,
      ),
      _openFullButton(context, up: true),
    ];
  }

  // ---------------------------------------------------------------------------
  // Shared widgets
  // ---------------------------------------------------------------------------

  Widget _artwork(Track? track) {
    return CoverArt(
      url: track?.albumArtUrl,
      width: compact ? 44 : 56,
      height: compact ? 44 : 56,
      borderRadius: compact ? 8 : 6,
      fallbackIcon: Icons.music_note,
      fallbackIconSize: 22,
      fallbackColor: Colors.deepPurple,
    );
  }

  Widget _trackInfo(Track? track) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          track?.title ?? 'Nada en reproducción',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          track?.artist ?? 'Selecciona algo para escuchar',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }

  Widget _favoriteButton(
      BuildContext context, Track? track, {bool compact = false}) {
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
        color: starred ? Colors.greenAccent : Colors.white70,
        size: compact ? 22 : 20,
      ),
      onPressed: () => nav.toggleStar(track),
    );
  }

  Widget _compactControlIcon(IconData icon, VoidCallback onPressed,
      {Color color = Colors.white, double size = 24}) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      icon: Icon(icon, color: color, size: size),
      onPressed: onPressed,
    );
  }

  Widget _playButton(PlayerController player, bool playing,
      {bool compact = false}) {
    return IconButton(
      visualDensity: compact ? VisualDensity.compact : null,
      padding: compact ? EdgeInsets.zero : null,
      constraints:
          compact ? const BoxConstraints(minWidth: 40, minHeight: 40) : null,
      iconSize: compact ? 38 : 36,
      icon: Icon(
        playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
        color: Colors.white,
      ),
      onPressed: player.togglePlay,
    );
  }

  Widget _openFullButton(BuildContext context, {bool up = false}) {
    return IconButton(
      visualDensity: up ? VisualDensity.compact : null,
      padding: up ? EdgeInsets.zero : null,
      constraints:
          up ? const BoxConstraints(minWidth: 36, minHeight: 36) : null,
      icon: Icon(
        up ? Icons.keyboard_arrow_up : Icons.fullscreen,
        color: Colors.white70,
        size: up ? 28 : 18,
      ),
      onPressed: () {
        final player = context.read<PlayerController>();
        if (player.currentTrack == null) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PlayerScreen()),
        );
      },
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
  const _DesktopProgressBar(this.player);

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
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
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
                            activeTrackColor: _hovering ? Colors.greenAccent : Colors.white,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: Colors.white,
                            thumbShape: RoundSliderThumbShape(
                              enabledThumbRadius: _hovering ? 6 : 0,
                            ),
                            overlayColor: Colors.white10,
                            overlayShape:
                                const RoundSliderOverlayShape(overlayRadius: 14),
                          ),
                          child: Slider(
                            min: 0,
                            max: maxMs,
                            value: currentMs,
                            onChanged: (v) => setState(() => _dragValue = v),
                            onChangeEnd: (v) async {
                              await widget.player
                                  .seek(Duration(milliseconds: v.round()));
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
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
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
  const _MobileProgressBar(this.player);

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
            data: const SliderThemeData(
              trackHeight: 3,
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
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
                await widget.player.seek(Duration(milliseconds: v.round()));
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
              color: Colors.white70,
              size: 20,
            ),
            SizedBox(
              width: 110,
              child: SliderTheme(
                data: const SliderThemeData(
                  trackHeight: 3,
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayColor: Colors.white10,
                  overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
                ),
                child: Slider(
                  min: 0,
                  max: 1,
                  value: volume,
                  onChanged: (v) => setState(() => _dragValue = v),
                  onChangeEnd: (v) async {
                    await widget.player.setVolume(v);
                    if (mounted) setState(() => _dragValue = null);
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
