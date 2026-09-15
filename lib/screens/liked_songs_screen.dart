import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../widgets/persistent_player_bar.dart';

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
        title: const Text('Liked Songs'),
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
              child: Text('No tienes canciones favoritas',
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
                        color: const Color(0xFF353588),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.favorite,
                          color: Colors.white, size: 48),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Liked Songs',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text('${tracks.length} canciones',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 14)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.play_circle_filled,
                          color: Colors.greenAccent, size: 48),
                      onPressed: () => context
                          .read<PlayerController>()
                          .playQueue(tracks, startIndex: 0),
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
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade800,
                          borderRadius: BorderRadius.circular(4),
                          image: track.albumArtUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(track.albumArtUrl!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: track.albumArtUrl == null
                            ? const Icon(Icons.music_note,
                                color: Colors.white54, size: 20)
                            : null,
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
                        ),
                        onPressed: () async {
                          await nav.toggleStar(track);
                          setState(() {
                            _future = nav.getStarred();
                          });
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