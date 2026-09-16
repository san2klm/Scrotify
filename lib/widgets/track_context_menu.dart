import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/jam_controller.dart';
import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import 'cover_art.dart';
import '../utils/app_colors.dart';

/// Menú contextual unificado para pistas/canciones en toda la aplicación.
class TrackContextMenu extends StatelessWidget {
  final Track track;

  const TrackContextMenu({super.key, required this.track});

  static void show(BuildContext context, Track track) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.bgApp,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: context.bgElevated, width: 1.2),
      ),
      builder: (ctx) => TrackContextMenu(track: track),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavidromeService>();
    final player = context.read<PlayerController>();
    final jam = context.watch<JamController>();
    final isStarred = nav.isStarred(track.id);

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.themeBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Cabecera de la pista
              Row(
                children: [
                  CoverArt(
                    url: track.albumArtUrl,
                    width: 48,
                    height: 48,
                    borderRadius: 8,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${track.artist} · ${track.album}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: context.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      isStarred ? Icons.favorite : Icons.favorite_border,
                      color: isStarred ? context.accent : context.textSecondary,
                    ),
                    onPressed: () => nav.toggleStar(track),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: context.bgElevated, height: 1),
              const SizedBox(height: 8),

              // Acciones Jam (si hay Jam activo)
              if (jam.inJam) ...[
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: context.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.speaker_group_rounded,
                        color: context.accent, size: 20),
                  ),
                  title: Text(
                    'Añadir a la cola Jam',
                    style: TextStyle(
                      color: context.accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Text(
                    'Compartir con los ${jam.participants.length} oyentes de la sesión',
                    style: TextStyle(color: context.textMuted, fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    jam.addTrackToJam(track);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('"${track.title}" añadida a la cola Jam'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: context.bgElevated,
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(Icons.playlist_play_rounded,
                      color: context.textSecondary),
                  title: Text(
                    'Reproducir siguiente en Jam',
                    style: TextStyle(color: context.textPrimary, fontSize: 14),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    jam.addTrackToJam(track, playNext: true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            Text('"${track.title}" sonará a continuación en el Jam'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: context.bgElevated,
                      ),
                    );
                  },
                ),
              ] else ...[
                ListTile(
                  leading: Icon(Icons.play_arrow_rounded,
                      color: context.accent, size: 24),
                  title: Text(
                    'Reproducir ahora',
                    style: TextStyle(
                        color: context.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    player.playQueue([track], startIndex: 0);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.queue_music_rounded,
                      color: context.textSecondary),
                  title: Text(
                    'Añadir a la cola',
                    style: TextStyle(color: context.textPrimary, fontSize: 14),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    player.addToQueue(track);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('"${track.title}" añadida a la cola'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: context.bgElevated,
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(Icons.playlist_play_rounded,
                      color: context.textSecondary),
                  title: Text(
                    'Reproducir siguiente',
                    style: TextStyle(color: context.textPrimary, fontSize: 14),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    player.addNextInQueue(track);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('"${track.title}" sonará a continuación'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: context.bgElevated,
                      ),
                    );
                  },
                ),
              ],

              // Añadir a Playlist
              ListTile(
                leading: Icon(Icons.playlist_add_rounded,
                    color: context.textSecondary),
                title: Text(
                  'Añadir a una playlist',
                  style: TextStyle(color: context.textPrimary, fontSize: 14),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _showAddToPlaylistSheet(context, nav, track);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddToPlaylistSheet(
      BuildContext context, NavidromeService nav, Track track) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.bgApp,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: context.bgElevated, width: 1.2),
      ),
      builder: (ctx) {
        return FutureBuilder<List<Playlist>>(
          future: nav.getPlaylists(),
          builder: (context, snapshot) {
            final playlists = snapshot.data ?? <Playlist>[];
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.themeBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Añadir a Playlist',
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (playlists.isEmpty)
                      Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'No tienes playlists creadas',
                          style: TextStyle(color: context.textMuted),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: playlists.length,
                          itemBuilder: (ctx, i) {
                            final p = playlists[i];
                            return ListTile(
                              leading: Icon(Icons.playlist_play,
                                  color: context.accent),
                              title: Text(p.name,
                                  style: TextStyle(color: context.textPrimary)),
                              subtitle: Text('${p.songCount} canciones',
                                  style: TextStyle(
                                      color: context.textMuted, fontSize: 11)),
                              onTap: () async {
                                Navigator.of(context).pop();
                                await nav.updatePlaylist(
                                  playlistId: p.id,
                                  songIdsToAdd: [track.id],
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Añadida a "${p.name}"'),
                                      backgroundColor: context.bgElevated,
                                    ),
                                  );
                                }
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
