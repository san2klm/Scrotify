import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../widgets/persistent_player_bar.dart';

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
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF353588),
        foregroundColor: Colors.white,
        title: const Text('Álbum'),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: PersistentPlayerBar(compact: compact),
      ),
      body: FutureBuilder<List<Track>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: Colors.white));
          }
          final tracks = snapshot.data ?? <Track>[];
          if (tracks.isEmpty) {
            return const Center(
              child: Text('Álbum sin canciones',
                  style: TextStyle(color: Colors.white54)),
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
                        color: Colors.grey.shade800,
                        borderRadius: BorderRadius.circular(8),
                        image: widget.album.coverArtUrl != null
                            ? DecorationImage(
                                image: NetworkImage(widget.album.coverArtUrl!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: widget.album.coverArtUrl == null
                          ? const Icon(Icons.album,
                              color: Colors.white54, size: 44)
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
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(widget.album.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 14)),
                          const SizedBox(height: 4),
                          Text('${tracks.length} canciones',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12),
              Expanded(
                child: ListView.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    final starred = nav.isStarred(track.id);
                    return ListTile(
                      leading: Text(
                        '${index + 1}',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 14),
                      ),
                      title: Text(track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14)),
                      subtitle: Text(track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                      trailing: IconButton(
                        icon: Icon(
                          starred ? Icons.favorite : Icons.favorite_border,
                          color:
                              starred ? Colors.greenAccent : Colors.white54,
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
    );
  }
}