import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../widgets/cover_art.dart';
import '../widgets/interactive_artist_text.dart';
import '../widgets/persistent_player_bar.dart';
import '../widgets/global_top_bar.dart';
import '../widgets/playlist_actions_panel.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/local_download_button.dart';
import '../utils/app_colors.dart';
import '../widgets/material_surface.dart';

/// Pantalla que muestra las canciones marcadas como favoritas (me gusta).
class LikedSongsScreen extends StatefulWidget {
  const LikedSongsScreen({super.key});

  @override
  State<LikedSongsScreen> createState() => _LikedSongsScreenState();
}

class _LikedSongsScreenState extends State<LikedSongsScreen> {
  late Future<List<Track>> _future;
  String? _lastSessionKey;

  @override
  void initState() {
    super.initState();
    _lastSessionKey = context.read<NavidromeService>().currentSessionKey;
    _future = context.read<NavidromeService>().getStarred();
  }

  void _reorderTracks(List<Track> tracks, int oldIndex, int newIndex) {
    // Ajustar índice para reordenamiento correcto
    final int finalNewIndex = (newIndex > oldIndex) ? newIndex - 1 : newIndex;

    if (oldIndex < 0 ||
        oldIndex >= tracks.length ||
        finalNewIndex < 0 ||
        finalNewIndex >= tracks.length ||
        oldIndex == finalNewIndex) {
      return;
    }

    final reordered = List<Track>.of(tracks);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(finalNewIndex, moved);
    context.read<NavidromeService>().reorderStarredTracks(reordered);
    setState(() {
      _future = Future.value(reordered);
    });
  }

  Future<void> _showActionsPanel(List<Track> tracks) =>
      PlaylistActionsPanel.show(
        context,
        playlist: null,
        tracks: tracks,
        onChanged: () {
          if (!mounted) return;
          setState(() {
            _future = context.read<NavidromeService>().getStarred();
          });
        },
      );

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavidromeService>();
    final sessionKey = nav.currentSessionKey;
    if (sessionKey != _lastSessionKey) {
      _lastSessionKey = sessionKey;
      _future = nav.getStarred();
    }
    // Misma lógica que HomeShell: < 700px es móvil (barra compacta).
    final compact = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      backgroundColor: context.bgApp,
      bottomNavigationBar: SafeArea(
        top: false,
        child: PersistentPlayerBar(compact: compact),
      ),
      body: Column(
        children: [
          const GlobalTopBar(title: 'Liked Songs'),
          Expanded(
            child: FutureBuilder<List<Track>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                      child: CircularProgressIndicator(
                          color: context.textPrimary));
                }
                final tracks = snapshot.data ?? <Track>[];
                final pinned = nav.isPinnedPlaylist('__likes__');
                return Column(
                  children: [
                    CollectionHeader(
                      artwork: Container(
                        width: compact ? 80 : 120,
                        height: compact ? 80 : 120,
                        decoration: BoxDecoration(
                          color: context.accent2,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(Icons.favorite,
                            color: context.textPrimary, size: 48),
                      ),
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Liked Songs',
                              style: TextStyle(
                                  color: context.textPrimary,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text('${tracks.length} canciones',
                              style: TextStyle(
                                  color: context.textSecondary, fontSize: 14)),
                          const SizedBox(height: 8),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              TextButton.icon(
                                onPressed: () =>
                                    nav.togglePinPlaylist('__likes__'),
                                style: TextButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  foregroundColor: pinned
                                      ? context.accent
                                      : context.textSecondary,
                                ),
                                icon: Icon(
                                    pinned
                                        ? Icons.push_pin
                                        : Icons.push_pin_outlined,
                                    size: 18),
                                label: Text(pinned ? 'Fijada' : 'Fijar',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              LocalDownloadButton(tracks: tracks, collection: 'likes'),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Acciones de favoritos',
                                icon: Icon(Icons.more_vert_rounded,
                                    color: context.textMuted, size: 20),
                                onPressed: () => _showActionsPanel(tracks),
                              ),
                            ],
                          ),
                        ],
                      ),
                      actions: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          icon: Icon(Icons.shuffle,
                              color: context.accent, size: 28),
                          tooltip: 'Reproducir al azar',
                          onPressed: () => context
                              .read<PlayerController>()
                              .playShuffledQueue(tracks),
                        ),
                        IconButton(
                          icon: Icon(Icons.play_circle_filled,
                              color: context.accent, size: 48),
                          onPressed: () => context
                              .read<PlayerController>()
                              .playQueue(tracks, startIndex: 0),
                        )
                      ]),
                    ),
                    Divider(color: context.themeBorder),
                    if (tracks.isEmpty)
                      Expanded(
                        child: Center(
                          child: Text('No tienes canciones favoritas',
                              style: TextStyle(color: context.textMuted)),
                        ),
                      )
                    else
                      Expanded(
                        child: ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          itemCount: tracks.length,
                          onReorderItem: (oldIndex, newIndex) =>
                              _reorderTracks(tracks, oldIndex, newIndex),
                          itemBuilder: (context, index) {
                            final track = tracks[index];
                            final starred = nav.isStarred(track.id);
                            return InkWell(
                              key: ValueKey('liked-${track.id}'),
                              onTap: () => context
                                  .read<PlayerController>()
                                  .playQueue(tracks, startIndex: index),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // Portada
                                    CoverArt(
                                      url: track.albumArtUrl,
                                      artist: track.artist,
                                      album: track.album,
                                      title: track.title,
                                      width: 40,
                                      height: 40,
                                      borderRadius: 4,
                                      fallbackIcon: Icons.music_note,
                                      fallbackIconSize: 20,
                                      fallbackColor: context.bgElevated,
                                    ),
                                    const SizedBox(width: 10),
                                    // Título + artista
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            track.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                color: context.textPrimary,
                                                fontSize: 14),
                                          ),
                                          InteractiveArtistText(
                                              artistString: track.artist),
                                        ],
                                      ),
                                    ),
                                    // Drag handle centrado horizontalmente (en la mitad)
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 8),
                                        child: Icon(
                                          Icons.drag_handle_rounded,
                                          color: context.textMuted,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                    // Botón de me gusta
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: Icon(
                                        starred
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        color: starred
                                            ? context.accent
                                            : context.textMuted,
                                        size: 20,
                                      ),
                                      onPressed: () async {
                                        await nav.toggleStar(track);
                                        if (mounted) {
                                          setState(() {
                                            _future = nav.getStarred();
                                          });
                                        }
                                      },
                                    ),
                                    // Menú contextual ⋮
                                    LocalDownloadButton(tracks: [track], compact: true),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      tooltip: 'Acciones de la canción',
                                      icon: Icon(Icons.more_vert_rounded,
                                          color: context.textMuted, size: 20),
                                      onPressed: () =>
                                          TrackContextMenu.show(context, track),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
