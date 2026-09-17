import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../widgets/cover_art.dart';
import '../widgets/persistent_player_bar.dart';
import '../widgets/global_top_bar.dart';
import '../utils/app_colors.dart';

/// Pantalla que muestra las canciones marcadas como favoritas (me gusta).
class LikedSongsScreen extends StatefulWidget {
  const LikedSongsScreen({super.key});

  @override
  State<LikedSongsScreen> createState() => _LikedSongsScreenState();
}

class _LikedSongsScreenState extends State<LikedSongsScreen> {
  late Future<List<Track>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<NavidromeService>().getStarred();
  }

  void _reorderTracks(List<Track> tracks, int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;

    final reordered = List<Track>.of(tracks);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    context.read<NavidromeService>().reorderStarredTracks(reordered);
    setState(() => _future = Future.value(reordered));
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.read<NavidromeService>();
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
                if (tracks.isEmpty) {
                  return Center(
                    child: Text('No tienes canciones favoritas',
                        style: TextStyle(color: context.textMuted)),
                  );
                }
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: context.accent2,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.favorite,
                                color: context.textPrimary, size: 48),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
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
                                        color: context.textMuted,
                                        fontSize: 14)),
                              ],
                            ),
                          ),
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
                          ),
                        ],
                      ),
                    ),
                    Divider(color: context.themeBorder),
                    Expanded(
                      child: ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        itemCount: tracks.length,
                        onReorderItem: (oldIndex, newIndex) =>
                            _reorderTracks(tracks, oldIndex, newIndex),
                        itemBuilder: (context, index) {
                          final track = tracks[index];
                          final starred = nav.isStarred(track.id);
                          return ListTile(
                            key: ValueKey('liked-${track.id}-$index'),
                            leading: CoverArt(
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
                            title: Text(track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: context.textPrimary, fontSize: 14)),
                            subtitle: Text(track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: context.textMuted, fontSize: 12)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    starred
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: starred
                                        ? context.accent
                                        : context.textMuted,
                                  ),
                                  onPressed: () async {
                                    await nav.toggleStar(track);
                                    if (mounted) {
                                      setState(
                                          () => _future = nav.getStarred());
                                    }
                                  },
                                ),
                                ReorderableDragStartListener(
                                  index: index,
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Icon(
                                      Icons.drag_handle_rounded,
                                      color: context.textMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            onTap: () => context
                                .read<PlayerController>()
                                .playQueue(tracks, startIndex: index),
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
