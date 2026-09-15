import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../widgets/persistent_player_bar.dart';

/// Pantalla que muestra las canciones de una playlist específica.
/// Se abre desde la barra lateral (Tu Biblioteca) del escritorio.
class PlaylistDetailScreen extends StatefulWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  late Future<List<Track>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<NavidromeService>().getPlaylistTracks(widget.playlist.id);
  }

  /// Reproduce la playlist con el modo aleatorio activo (igual que la opción
  /// "Reproducir al azar" del menú contextual de la biblioteca).
  Future<void> _playShuffled(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    final player = context.read<PlayerController>();
    player.playQueue(tracks, startIndex: 0);
    await player.toggleShuffle();
  }

  /// Confirma y borra la playlist en Navidrome. Al terminar vuelve a la
  /// pantalla anterior, ya que la playlist ya no existe.
  Future<void> _confirmDelete() async {
    final nav = context.read<NavidromeService>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F1F),
        title: const Text('¿Eliminar playlist?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Se borrará "${widget.playlist.name}" permanentemente.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar',
                style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      if (nav.isPinnedPlaylist(widget.playlist.id)) {
        nav.togglePinPlaylist(widget.playlist.id);
      }
      await nav.deletePlaylist(widget.playlist.id);
      nav.bumpPlaylists();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Playlist eliminada',
              style: TextStyle(color: Colors.white)),
          backgroundColor: Color(0xFF1F1F1F),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e',
              style: TextStyle(color: Colors.redAccent)),
          backgroundColor: const Color(0xFF1F1F1F),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
        title: const Text('Playlist'),
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
              child: Text('Playlist vacía',
                  style: TextStyle(color: Colors.white54)),
            );
          }
          final pinned = nav.isPinnedPlaylist(widget.playlist.id);
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
                      child: widget.playlist.coverArtUrl != null
                          ? Image.network(
                              widget.playlist.coverArtUrl!,
                              fit: BoxFit.cover,
                            )
                          : const Icon(Icons.queue_music,
                              color: Colors.white, size: 48),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.playlist.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text('${tracks.length} canciones',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 14)),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () =>
                                nav.togglePinPlaylist(widget.playlist.id),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  pinned
                                      ? Icons.push_pin
                                      : Icons.push_pin_outlined,
                                  color: pinned
                                      ? Colors.greenAccent
                                      : Colors.white54,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  pinned ? 'Fijada' : 'Fijar',
                                  style: TextStyle(
                                    color: pinned
                                        ? Colors.greenAccent
                                        : Colors.white54,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.shuffle,
                              color: Colors.greenAccent, size: 24),
                          tooltip: 'Reproducir al azar',
                          onPressed: () => _playShuffled(tracks),
                        ),
                        IconButton(
                          icon: const Icon(Icons.play_circle_filled,
                              color: Colors.greenAccent, size: 48),
                          onPressed: () => context
                              .read<PlayerController>()
                              .playQueue(tracks, startIndex: 0),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.redAccent, size: 24),
                          tooltip: 'Eliminar playlist',
                          onPressed: _confirmDelete,
                        ),
                      ],
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