import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../services/player_controller.dart';
import '../services/navidrome_service.dart';

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

  void _showContextMenu(PlayerController player, String id) {
    final nav = context.read<NavidromeService>();
    final starred = nav.isStarred(id);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1F1F1F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add, color: Colors.white),
                title: const Text('Añadir a una playlist',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(context).pop();
                  _showAddToPlaylistSheet(nav);
                },
              ),
              ListTile(
                leading: Icon(
                  starred ? Icons.favorite : Icons.favorite_border,
                  color: starred ? Colors.greenAccent : Colors.white,
                ),
                title: Text(
                  starred ? 'Quitar de favoritos' : 'Añadir a favoritos',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  final track = player.currentTrack;
                  if (track != null) nav.toggleStar(track);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddToPlaylistSheet(NavidromeService nav) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1F1F1F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return FutureBuilder<List<Playlist>>(
          future: nav.getPlaylists(),
          builder: (context, snapshot) {
            final playlists = snapshot.data ?? <Playlist>[];
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const ListTile(
                    leading: Icon(Icons.library_music, color: Colors.white),
                    title: Text('Selecciona una playlist',
                        style: TextStyle(color: Colors.white)),
                  ),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  else if (playlists.isEmpty)
                    const ListTile(
                      title: Text('No tienes playlists',
                          style: TextStyle(color: Colors.white54)),
                    )
                  else
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final p in playlists)
                            ListTile(
                              leading: const Icon(Icons.playlist_play,
                                  color: Colors.white70),
                              title: Text(p.name,
                                  style: const TextStyle(color: Colors.white)),
                              subtitle: Text('${p.songCount} canciones',
                                  style:
                                      const TextStyle(color: Colors.white54)),
                              onTap: () async {
                                Navigator.of(context).pop();
                                final player =
                                    context.read<PlayerController>();
                                final track = player.currentTrack;
                                if (track != null) {
                                  await nav.updatePlaylist(
                                    playlistId: p.id,
                                    songIdsToAdd: [track.id],
                                  );
                                }
                              },
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerController>(
      builder: (context, player, _) {
        final track = player.currentTrack;
        if (track == null) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: Text('Nada en reproducción',
                  style: TextStyle(color: Colors.white70)),
            ),
          );
        }

        final playing = player.playing;
        final repeatMode = player.repeatMode;
        final shuffleEnabled = player.shuffleEnabled;

        return Scaffold(
          backgroundColor: const Color(0xFF121212),
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
                            icon: const Icon(Icons.keyboard_arrow_down,
                                color: Colors.white, size: 32),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          IconButton(
                            icon: const Icon(Icons.more_horiz,
                                color: Colors.white),
                            onPressed: () => _showContextMenu(player, track.id),
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
                                      color: Colors.grey.shade800,
                                      child: const Icon(Icons.music_note,
                                          size: 60, color: Colors.grey),
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
                        style: const TextStyle(
                          color: Colors.white,
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
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
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
                      const SizedBox(height: 16),
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
                color: Colors.white.withAlpha(70),
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
              data: const SliderThemeData(
                trackHeight: 3,
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayColor: Colors.white10,
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
                        const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Text(
                    _format(duration),
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12),
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
            color: shuffleEnabled ? Colors.greenAccent : Colors.white,
          ),
          onPressed: player.toggleShuffle,
        ),
        IconButton(
          icon: const Icon(Icons.skip_previous, color: Colors.white, size: 34),
          onPressed: player.skipPrevious,
        ),
        IconButton(
          iconSize: 60,
          icon: Icon(
            playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
            color: Colors.white,
          ),
          onPressed: player.togglePlay,
        ),
        IconButton(
          icon: const Icon(Icons.skip_next, color: Colors.white, size: 34),
          onPressed: player.skipNext,
        ),
        IconButton(
          icon: Icon(
            repeatMode == LoopMode.one ? Icons.repeat_one : Icons.repeat,
            size: 22,
            color: repeatMode != LoopMode.off ? Colors.greenAccent : Colors.white,
          ),
          onPressed: player.toggleRepeat,
        ),
      ],
    );
  }
}