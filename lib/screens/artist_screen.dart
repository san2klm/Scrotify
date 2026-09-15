import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../widgets/persistent_player_bar.dart';
import 'album_detail_screen.dart';

/// Pantalla de un artista estilo Spotify:
/// - Header con portada, nombre, botón play
/// - Sección "Canciones populares" expansible (inicial 5, "Mostrar más")
/// - Sección "Álbumes" completa
class ArtistScreen extends StatefulWidget {
  final Artist artist;

  const ArtistScreen({super.key, required this.artist});

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  late Future<List<Track>> _futureTopTracks;
  late Future<List<Album>> _futureAlbums;

  bool _showAllTracks = false;
  static const int _initialTrackCount = 5;

  @override
  void initState() {
    super.initState();
    final nav = context.read<NavidromeService>();
    _futureTopTracks = nav.getArtistTracks(widget.artist.id);
    _futureAlbums = nav.getArtistAlbums(widget.artist.id);
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          SliverToBoxAdapter(child: _buildContent()),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: PersistentPlayerBar(compact: compact),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      backgroundColor: const Color(0xFF121212),
      foregroundColor: Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Fondo con imagen del artista + gradiente
            widget.artist.coverArtUrl != null
                ? Image.network(
                    widget.artist.coverArtUrl!,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Container(color: Colors.deepPurple.shade900);
                    },
                    errorBuilder: (_, __, ___) =>
                        Container(color: Colors.deepPurple.shade900),
                  )
                : Container(color: Colors.deepPurple.shade900),
            // Gradiente oscuro abajo para legibilidad
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xFF121212)],
                  stops: [0.6, 1.0],
                ),
              ),
            ),
            // Contenido: nombre + botón play
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.artist.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildPlayButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayButton() {
    return Consumer<PlayerController>(
      builder: (context, player, _) {
        return InkWell(
          onTap: () => _playArtistTopTracks(),
          borderRadius: BorderRadius.circular(30),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.greenAccent,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  player.playing && player.currentTrack?.artist == widget.artist.name
                      ? Icons.pause
                      : Icons.play_arrow,
                  color: Colors.black,
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Reproducir',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _playArtistTopTracks() async {
    final tracks = await _futureTopTracks;
    if (mounted && tracks.isNotEmpty) {
      context.read<PlayerController>().playQueue(tracks, startIndex: 0);
    }
  }

  Widget _buildContent() {
    return FutureBuilder<List<Track>>(
      future: _futureTopTracks,
      builder: (context, snapshot) {
        final tracks = snapshot.data ?? <Track>[];
        final loading = snapshot.connectionState == ConnectionState.waiting;

        return FutureBuilder<List<Album>>(
          future: _futureAlbums,
          builder: (context, albumSnapshot) {
            final albums = albumSnapshot.data ?? <Album>[];

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Canciones populares ──────────────────────────────
                  _sectionHeader('Canciones populares', tracks.isNotEmpty),
                  const SizedBox(height: 8),
                  if (loading && tracks.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    )
                  else if (tracks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Sin canciones',
                          style: TextStyle(color: Colors.white54)),
                    )
                  else
                    _buildTracksList(tracks),

                  const SizedBox(height: 24),

                  // ── Álbumes ─────────────────────────────────────────
                  _sectionHeader('Álbumes', albums.isNotEmpty),
                  const SizedBox(height: 8),
                  if (albumSnapshot.connectionState == ConnectionState.waiting &&
                      albums.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    )
                  else if (albums.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Sin álbumes',
                          style: TextStyle(color: Colors.white54)),
                    )
                  else
                    _buildAlbumsGrid(albums),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _sectionHeader(String title, bool hasContent) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (hasContent)
          TextButton(
            onPressed: () {},
            child: const Text(
              'Ver todo',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
      ],
    );
  }

  Widget _buildTracksList(List<Track> tracks) {
    final displayTracks = _showAllTracks
        ? tracks
        : tracks.take(_initialTrackCount).toList();

    return Column(
      children: [
        for (int i = 0; i < displayTracks.length; i++)
          _buildTrackRow(displayTracks[i], i + 1, tracks),
        if (tracks.length > _initialTrackCount) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _showAllTracks = !_showAllTracks),
              child: Text(
                _showAllTracks ? 'Mostrar menos' : 'Mostrar más',
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTrackRow(Track track, int number, List<Track> allTracks) {
    final nav = context.read<NavidromeService>();
    final starred = nav.isStarred(track.id);
    final indexInAll = allTracks.indexOf(track);

    return InkWell(
      onTap: () => context
          .read<PlayerController>()
          .playQueue(allTracks, startIndex: indexInAll),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            // Número / Play
            SizedBox(
              width: 48,
              child: Center(
                child: Consumer<PlayerController>(
                  builder: (context, player, _) {
                    final isPlayingThis = player.playing &&
                        player.currentTrack?.id == track.id;
                    return Icon(
                      isPlayingThis ? Icons.pause : Icons.play_arrow,
                      color: isPlayingThis
                          ? Colors.greenAccent
                          : Colors.white38,
                      size: 22,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Portada
            Container(
              width: 48,
              height: 48,
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
                  ? const Icon(Icons.music_note, color: Colors.white54, size: 22)
                  : null,
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // Favorito + menú
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    starred ? Icons.favorite : Icons.favorite_border,
                    color: starred ? Colors.greenAccent : Colors.white54,
                    size: 20,
                  ),
                  onPressed: () async {
                    await nav.toggleStar(track);
                    setState(() {});
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert, color: Colors.white54),
                  onPressed: () {}, // TODO: menú contextual
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumsGrid(List<Album> albums) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.8,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        return InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => AlbumDetailScreen(album: album)),
          ),
          borderRadius: BorderRadius.circular(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade800,
                    borderRadius: BorderRadius.circular(8),
                    image: album.coverArtUrl != null
                        ? DecorationImage(
                            image: NetworkImage(album.coverArtUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: album.coverArtUrl == null
                      ? const Center(
                          child: Icon(Icons.album,
                              color: Colors.white54, size: 36),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${album.trackCount} canciones',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}