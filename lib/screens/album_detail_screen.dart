import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../widgets/interactive_artist_text.dart';
import '../widgets/persistent_player_bar.dart';
import '../widgets/global_top_bar.dart';
import '../utils/app_colors.dart';

/// Pantalla que muestra las canciones de un álbum.
/// Se abre al tocar un álbum en el inicio o en un artista.
class AlbumDetailScreen extends StatefulWidget {
  final Album album;

  const AlbumDetailScreen({super.key, required this.album});

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  late Future<List<Track>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<NavidromeService>().getAlbumTracks(widget.album.id);
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
          const GlobalTopBar(title: 'Álbum'),
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
                    child: Text('Álbum sin canciones',
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
                              color: context.bgElevated,
                              borderRadius: BorderRadius.circular(8),
                              image: widget.album.coverArtUrl != null
                                  ? DecorationImage(
                                      image: NetworkImage(
                                          widget.album.coverArtUrl!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: widget.album.coverArtUrl == null
                                ? Icon(Icons.album,
                                    color: context.textMuted, size: 44)
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.album.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: context.textPrimary,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                Text(widget.album.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: context.textMuted,
                                        fontSize: 14)),
                                const SizedBox(height: 4),
                                Text('${tracks.length} canciones',
                                    style: TextStyle(
                                        color: context.textMuted,
                                        fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(color: context.themeBorder),
                    Expanded(
                      child: ListView.builder(
                        itemCount: tracks.length,
                        itemBuilder: (context, index) {
                          final track = tracks[index];
                          final starred = nav.isStarred(track.id);
                          return ListTile(
                            leading: Text(
                              '${index + 1}',
                              style: TextStyle(
                                  color: context.textMuted, fontSize: 14),
                            ),
                            title: Text(track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: context.textPrimary, fontSize: 14)),
                            subtitle: InteractiveArtistText(artistString: track.artist),
                            trailing: IconButton(
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
                                setState(() {});
                              },
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
