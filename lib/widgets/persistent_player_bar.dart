import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../services/connect/connect_protocol.dart';
import '../services/connect/connect_service.dart';
import '../services/jam_controller.dart';
import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../screens/player_screen.dart';
import 'cover_art.dart';
import 'player_position_builder.dart';
import 'waveform_progress_bar.dart';
import 'jam_dialog.dart';
import 'connect_panel.dart';
import 'track_context_menu.dart';
import 'interactive_artist_text.dart';
import '../utils/app_colors.dart';
import '../utils/playback_time.dart';

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

  const PersistentPlayerBar({
    super.key,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer3<PlayerController, JamController, ConnectService>(
      builder: (context, player, jam, connect, _) {
        // En modo Party Speaker el invitado no reproduce audio local, pero la
        // barra debe reflejar fielmente lo que está sonando en el anfitrión.
        final remoteState = jam.isGuest ? jam.session : null;
        // Con Connect, la barra muestra y controla el dispositivo remoto.
        final remote =
            connect.controlled != null ? connect.controlledState : null;
        final track = connect.controlled != null
            ? _remoteTrack(remote)
            : remoteState?.currentTrack ?? player.currentTrack;
        final playing = connect.controlled != null
            ? (remote?.playing ?? false)
            : remoteState?.isPlaying ?? player.playing;

        if (compact) {
          return _buildMobileBar(context, player, jam, track, playing);
        }
        return _buildDesktopBar(context, player, jam, track, playing);
      },
    );
  }

  static Track? _remoteTrack(ConnectRemoteState? state) {
    final json = state?.track?.json;
    if (json == null) return null;
    return Track.fromJson(json, albumArtUrl: json['albumArtUrl'] as String?);
  }

  // ---------------------------------------------------------------------------
  // Desktop layout — Spotify desktop style
  // ---------------------------------------------------------------------------

  Widget _buildDesktopBar(BuildContext context, PlayerController player,
      JamController jam, Track? track, bool playing) {
    // Tramos adaptativos: a medida que la ventana se estrecha se ocultan
    // primero el volumen, luego Jam y pantalla completa, y se acorta el
    // bloque de título. Así la barra nunca desborda.
    final w = MediaQuery.sizeOf(context).width;
    final showVolume = w >= 1050;
    final showJam = w >= 880;
    final showFull = w >= 800;
    final infoWidth = w < 900 ? 130.0 : (w < 1100 ? 180.0 : 240.0);
    final connect = context.watch<ConnectService>();
    final remoteControlled = connect.controlled != null;
    final remoteState = connect.controlledState;

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
            SizedBox(width: infoWidth, child: _trackInfo(context, track)),
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
                        onPressed: jam.isGuest || remoteControlled
                            ? null
                            : player.toggleShuffle,
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.skip_previous,
                            color: context.textPrimary, size: 26),
                        onPressed: _playbackHandler(
                            context, jam, player, 'skip_previous'),
                      ),
                      _playButton(context, player, jam, playing),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.skip_next,
                            color: context.textPrimary, size: 26),
                        onPressed:
                            _playbackHandler(context, jam, player, 'skip_next'),
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
                        onPressed: jam.isGuest || remoteControlled
                            ? null
                            : player.toggleRepeat,
                      ),
                    ],
                  ),
                  // Progress bar with time labels
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: _DesktopProgressBar(
                      player,
                      remote: remoteControlled ? remoteState : null,
                      remoteActive: remoteControlled,
                      onSeek: (target) => _seek(context, jam, player, target),
                    ),
                  ),
                ],
              ),
            ),

            // ── Right: Jam + Queue + volume + fullscreen + three dots ──
            if (showJam) ...[
              _jamButton(context),
              const SizedBox(width: 6),
            ],
            _connectButton(context),
            if (showVolume) ...[
              const SizedBox(width: 8),
              _VolumeBar(player, connect: remoteControlled ? connect : null),
            ],
            if (showFull) ...[
              const SizedBox(width: 8),
              _openFullButton(context),
            ],
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
            remote: context.watch<ConnectService>().controlled != null
                ? context.watch<ConnectService>().controlledState
                : null,
            remoteActive: context.watch<ConnectService>().controlled != null,
            onSeek: (target) => _seek(context, jam, player, target),
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

  List<Widget> _mobileControls(BuildContext context, PlayerController player,
      JamController jam, bool playing, Track? track) {
    return [
      _compactControlIcon(
        context,
        Icons.skip_previous,
        _playbackHandler(context, jam, player, 'skip_previous'),
        size: 24,
      ),
      _playButton(context, player, jam, playing, compact: true),
      _compactControlIcon(
        context,
        Icons.skip_next,
        _playbackHandler(context, jam, player, 'skip_next'),
        size: 24,
      ),
      _connectButton(context, compact: true),
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

  /// Selector de dispositivos de Connect. Se resalta mientras se controla otro.
  Widget _connectButton(BuildContext context, {bool compact = false}) {
    final connect = context.watch<ConnectService>();
    final remote = connect.controlled;
    final color = remote != null ? context.accent : context.textSecondary;
    return IconButton(
      tooltip: remote != null
          ? 'Reproduciendo en ${remote.name}'
          : 'Conectarse a un dispositivo',
      visualDensity: VisualDensity.compact,
      padding: compact ? EdgeInsets.zero : const EdgeInsets.all(8),
      constraints:
          compact ? const BoxConstraints(minWidth: 32, minHeight: 32) : null,
      icon: Icon(Icons.devices_rounded, color: color, size: compact ? 20 : 21),
      onPressed: () => ConnectPanel.show(context),
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
              child: InteractiveArtistText(
                artistString: track?.artist ?? 'Selecciona algo para escuchar',
                fontSize: 12,
                color: context.playerArtist, // Usar el color del tema anterior
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
      icon:
          Icon(Icons.more_vert_rounded, color: context.textSecondary, size: 20),
      onPressed: () {
        final player = context.read<PlayerController>();
        TrackContextMenu.show(context, track,
            playlistId: player.sourcePlaylist?.id);
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

  Widget _playButton(BuildContext context, PlayerController player,
      JamController jam, bool playing,
      {bool compact = false}) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: compact ? EdgeInsets.zero : const EdgeInsets.all(2),
      constraints:
          compact ? const BoxConstraints(minWidth: 40, minHeight: 40) : null,
      iconSize: compact ? 38 : 36,
      icon: Icon(
        playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
        color: context.textPrimary,
      ),
      onPressed: _playbackHandler(context, jam, player, 'toggle'),
    );
  }

  VoidCallback? _playbackHandler(
    BuildContext context,
    JamController jam,
    PlayerController player,
    String action,
  ) {
    final connect = context.read<ConnectService>();
    if (connect.controlled != null) {
      final command = switch (action) {
        'toggle' => ConnectCommand.toggle,
        'skip_next' => ConnectCommand.next,
        'skip_previous' => ConnectCommand.previous,
        _ => null,
      };
      return command == null ? null : () => connect.command(command);
    }
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

  void _seek(BuildContext context, JamController jam, PlayerController player,
      Duration target) {
    final connect = context.read<ConnectService>();
    if (connect.controlled != null) {
      connect.command(ConnectCommand.seek, target.inMilliseconds);
      return;
    }
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
      tooltip: 'Ventana completa',
      visualDensity: VisualDensity.compact,
      // Flecha hacia arriba: expande el reproductor (portada, letra…) a toda
      // la ventana.
      icon: Icon(
        Icons.keyboard_arrow_up_rounded,
        color: context.textSecondary,
        size: 24,
      ),
      onPressed: () => _openPlayerScreen(context),
    );
  }

  void _openPlayerScreen(BuildContext context) {
    final player = context.read<PlayerController>();
    final jam = context.read<JamController>();
    final track =
        (jam.isGuest ? jam.session?.currentTrack : null) ?? player.currentTrack;
    if (track == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }
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

  /// Estado del dispositivo remoto cuando Connect controla otro equipo.
  final ConnectRemoteState? remote;
  final bool remoteActive;

  const _DesktopProgressBar(this.player,
      {this.onSeek, this.remote, this.remoteActive = false});

  @override
  State<_DesktopProgressBar> createState() => _DesktopProgressBarState();
}

class _DesktopProgressBarState extends State<_DesktopProgressBar> {
  double? _dragValue;
  bool _hovering = false;
  bool _showRemainingTime = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: widget.remoteActive
          ? _remotePositions(widget.remote)
          : widget.player.positionStream,
      builder: (context, snapshot) {
        final duration = widget.remoteActive
            ? Duration(milliseconds: widget.remote?.durationMs ?? 0)
            : widget.player.duration ?? Duration.zero;
        final position = snapshot.data ?? Duration.zero;

        final maxMs = duration.inMilliseconds == 0
            ? 1.0
            : duration.inMilliseconds.toDouble();
        final currentMs = (_dragValue ?? position.inMilliseconds.toDouble())
            .clamp(0.0, maxMs);
        final currentPosition = Duration(milliseconds: currentMs.round());

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
                        formatPlaybackTime(currentPosition),
                        style: TextStyle(
                            color: context.textSecondary, fontSize: 11),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    // Slider
                    Expanded(
                      // Con espectro real disponible se muestra la onda; si no
                      // (cargando / offline sin análisis) queda el slider fino.
                      child: ListenableBuilder(
                        listenable: widget.player,
                        builder: (context, _) {
                          final waveform = widget.player.waveformData;
                          if (waveform != null && duration > Duration.zero) {
                            return WaveformProgressBar(
                              waveform: waveform,
                              height: 28,
                              playing: widget.player.playing,
                              position: currentPosition,
                              duration: duration,
                              onSeek: (target) async {
                                if (widget.onSeek != null) {
                                  widget.onSeek!(target);
                                } else {
                                  await widget.player.seek(target);
                                }
                              },
                            );
                          }
                          return SizedBox(
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
                                onChanged: (v) =>
                                    setState(() => _dragValue = v),
                                onChangeEnd: (v) async {
                                  final target =
                                      Duration(milliseconds: v.round());
                                  if (widget.onSeek != null) {
                                    widget.onSeek!(target);
                                  } else {
                                    await widget.player.seek(target);
                                  }
                                  if (mounted) {
                                    setState(() => _dragValue = null);
                                  }
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // Total or remaining time
                    Tooltip(
                      message: _showRemainingTime
                          ? 'Mostrar duración total'
                          : 'Mostrar tiempo restante',
                      child: Semantics(
                        button: true,
                        label: _showRemainingTime
                            ? 'Tiempo restante: ${formatRemainingPlaybackTime(currentPosition, duration)}'
                            : 'Duración total: ${formatPlaybackTime(duration)}',
                        hint: 'Alternar entre duración total y tiempo restante',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () {
                            setState(() {
                              _showRemainingTime = !_showRemainingTime;
                            });
                          },
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                            child: Container(
                              alignment: Alignment.centerLeft,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 2),
                              child: Text(
                                _showRemainingTime
                                    ? formatRemainingPlaybackTime(
                                        currentPosition, duration)
                                    : formatPlaybackTime(duration),
                                style: TextStyle(
                                    color: context.textSecondary, fontSize: 11),
                              ),
                            ),
                          ),
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
  final ConnectRemoteState? remote;
  final bool remoteActive;

  const _MobileProgressBar(this.player,
      {this.onSeek, this.remote, this.remoteActive = false});

  @override
  State<_MobileProgressBar> createState() => _MobileProgressBarState();
}

class _MobileProgressBarState extends State<_MobileProgressBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final duration = widget.remoteActive
        ? Duration(milliseconds: widget.remote?.durationMs ?? 0)
        : widget.player.duration ?? Duration.zero;
    if (widget.remoteActive) {
      return StreamBuilder<Duration>(
        stream: _remotePositions(widget.remote),
        builder: (context, snapshot) =>
            _line(context, snapshot.data ?? Duration.zero, duration),
      );
    }
    // Posición interpolada a 250 ms: en Android el backend emite ~1 Hz y
    // la línea delgada se vería congelada con solo el StreamBuilder.
    return PlayerPositionBuilder(
      player: widget.player,
      duration: duration,
      builder: (context, position) => _line(context, position, duration),
    );
  }

  Widget _line(BuildContext context, Duration position, Duration duration) {
    final maxMs =
        duration.inMilliseconds == 0 ? 1.0 : duration.inMilliseconds.toDouble();
    final currentMs =
        (_dragValue ?? position.inMilliseconds.toDouble()).clamp(0.0, maxMs);

    return SizedBox(
      height: 6,
      child: SliderTheme(
        data: SliderThemeData(
          trackHeight: 3,
          activeTrackColor: context.waveformPlayed,
          inactiveTrackColor: context.waveformUnplayed,
          thumbColor: context.waveformPlayed,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 0),
          overlayColor: Colors.transparent,
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
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
  }
}

/// Posición estimada del dispositivo remoto, refrescada cada 500 ms.
Stream<Duration> _remotePositions(ConnectRemoteState? state) async* {
  while (true) {
    yield state?.estimatedPosition(DateTime.now()) ?? Duration.zero;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}

// =============================================================================
// Volume bar (shared by desktop controls)
// =============================================================================

class _VolumeBar extends StatefulWidget {
  final PlayerController player;

  /// Si se controla otro dispositivo, el volumen es el de ese dispositivo.
  final ConnectService? connect;
  const _VolumeBar(this.player, {this.connect});

  @override
  State<_VolumeBar> createState() => _VolumeBarState();
}

class _VolumeBarState extends State<_VolumeBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final remote = widget.connect;
    void apply(double v) => remote != null
        ? remote.command(ConnectCommand.volume, v)
        : widget.player.setVolume(v);
    return StreamBuilder<double>(
      stream: remote != null
          ? Stream.value(remote.controlledState?.volume ?? 1)
          : widget.player.volumeStream,
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
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayColor: context.accentDim,
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 12),
                ),
                child: Slider(
                  min: 0,
                  max: 1,
                  value: volume,
                  // Aplicar en vivo mientras se arrastra: el audio sube/baja al
                  // mismo tiempo que el pulgar, sin esperar a soltar.
                  onChanged: (v) {
                    setState(() => _dragValue = v);
                    apply(v);
                  },
                  onChangeEnd: (v) {
                    apply(v);
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
