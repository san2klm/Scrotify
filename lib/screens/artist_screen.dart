import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../widgets/cover_art.dart';
import '../widgets/persistent_player_bar.dart';
import 'album_detail_screen.dart';
import '../utils/app_colors.dart';

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
      backgroundColor: context.bgApp,
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
      backgroundColor: context.bgApp,
      foregroundColor: context.textPrimary,
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
                      return Container(color: context.accent2);
                    },
                    errorBuilder: (_, __, ___) =>
                        Container(color: context.accent2),
                  )
                : Container(color: context.accent2),
            // Gradiente oscuro abajo para legibilidad
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, context.bgApp],
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
                      style: TextStyle(
                        color: context.textPrimary,
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
              color: context.accent,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  player.playing && player.currentTrack?.artist == widget.artist.name
                      ? Icons.pause
                      : Icons.play_arrow,
                  color: context.onAccent,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'Reproducir',
                  style: TextStyle(
                    color: context.onAccent,
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
                    Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(color: context.textPrimary),
                      ),
                    )
                  else if (tracks.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Sin canciones',
                          style: TextStyle(color: context.textMuted)),
                    )
                  else
                    _buildTracksList(tracks),

                  const SizedBox(height: 24),

                  // ── Álbumes ─────────────────────────────────────────
                  _sectionHeader('Álbumes', albums.isNotEmpty),
                  const SizedBox(height: 8),
                  if (albumSnapshot.connectionState == ConnectionState.waiting &&
                      albums.isEmpty)
                    Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(color: context.textPrimary),
                      ),
                    )
                  else if (albums.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Sin álbumes',
                          style: TextStyle(color: context.textMuted)),
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
          style: TextStyle(
            color: context.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (hasContent)
          TextButton(
            onPressed: () {},
            child: Text(
              'Ver todo',
              style: TextStyle(color: context.textSecondary, fontSize: 14),
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
                style: TextStyle(
                  color: context.accent,
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
                          ? context.accent
                          : context.textMuted,
                      size: 22,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Portada
            CoverArt(
              url: track.albumArtUrl,
              artist: track.artist,
              album: track.album,
              title: track.title,
              width: 48,
              height: 48,
              borderRadius: 4,
              fallbackIcon: Icons.music_note,
              fallbackIconSize: 22,
              fallbackColor: context.bgElevated,
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
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.textMuted,
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
                    color: starred ? context.accent : context.textMuted,
                    size: 20,
                  ),
                  onPressed: () async {
                    await nav.toggleStar(track);
                    setState(() {});
                  },
                ),
                IconButton(
                  icon: Icon(Icons.more_vert, color: context.textMuted),
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
                    color: context.bgElevated,
                    borderRadius: BorderRadius.circular(8),
                    image: album.coverArtUrl != null
                        ? DecorationImage(
                            image: NetworkImage(album.coverArtUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: album.coverArtUrl == null
                      ? Center(
                          child: Icon(Icons.album,
                              color: context.textMuted, size: 36),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${album.trackCount} canciones',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.textMuted, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}