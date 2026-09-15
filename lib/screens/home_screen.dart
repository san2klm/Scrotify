import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../widgets/persistent_player_bar.dart';
import '../widgets/cover_art.dart';
import 'liked_songs_screen.dart';
import 'playlist_detail_screen.dart';
import 'album_detail_screen.dart';
import 'artist_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Track>> _futureTracks;
  late Future<List<Playlist>> _futurePlaylists;
  bool _libraryCollapsed = false;
  int _coverArtVersion = -1;
  int _playlistVersion = -1;

  final TextEditingController _searchController = TextEditingController();
  SearchResults? _searchResults;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _futureTracks = context.read<NavidromeService>().getTracks();
    _futurePlaylists = context.read<NavidromeService>().getPlaylists();
  }

  Future<void> _runSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final results =
          await context.read<NavidromeService>().search(query.trim());
      if (mounted) {
        setState(() {
          _searchResults = results;
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _searchResults = null;
          _searching = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Refrescar portadas cuando cambia la resolución configurada.
    final nav = context.watch<NavidromeService>();
    final version = nav.coverArtVersion;
    if (version != _coverArtVersion && _coverArtVersion >= 0) {
      _coverArtVersion = version;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          final svc = context.read<NavidromeService>();
          _futureTracks = svc.getTracks();
          _futurePlaylists = svc.getPlaylists();
        });
      });
    }
    _coverArtVersion = version;

    // Refrescar lista de playlists tras importación/creación/borrado.
    final pVersion = nav.playlistVersion;
    if (pVersion != _playlistVersion && _playlistVersion >= 0) {
      _playlistVersion = pVersion;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          final svc = context.read<NavidromeService>();
          _futurePlaylists = svc.getPlaylists();
        });
      });
    }
    _playlistVersion = pVersion;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Row(
        children: [
          if (!_libraryCollapsed) _buildLibraryPanel(),
          Expanded(child: _buildMainPanel()),
        ],
      ),
      bottomNavigationBar: const PersistentPlayerBar(),
    );
  }

  // ---------------------------------------------------------------------------
  // Panel Izquierdo: Tu Biblioteca
  // ---------------------------------------------------------------------------
  Widget _buildLibraryPanel() {
    return Container(
      width: 280,
      color: const Color(0xFF0A0A0A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _libraryHeader(),
          const Divider(height: 1, color: Colors.white12),
          _librarySearchBar(),
          Expanded(child: _libraryList()),
        ],
      ),
    );
  }

  Widget _libraryHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
      child: Row(
        children: [
          const Icon(Icons.arrow_back_ios_new, color: Colors.white54, size: 18),
          const SizedBox(width: 16),
          const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 18),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.menu_open, color: Colors.white, size: 20),
            tooltip: 'Colapsar biblioteca',
            onPressed: () => setState(() => _libraryCollapsed = true),
          ),
        ],
      ),
    );
  }

  Widget _librarySearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF242424),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.search, color: Colors.white54, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      style: TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Buscar en tu biblioteca',
                        hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.swap_vert, color: Colors.white70, size: 20),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _libraryList() {
    // `watch` para que el icono de fijar se actualice al tocar pin/unpin.
    final nav = context.watch<NavidromeService>();
    return FutureBuilder<List<Playlist>>(
      future: _futurePlaylists,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }

        final playlists = snapshot.data ?? <Playlist>[];
        final pinned =
            playlists.where((p) => nav.isPinnedPlaylist(p.id)).toList();
        final rest =
            playlists.where((p) => !nav.isPinnedPlaylist(p.id)).toList();

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            _libraryTile(
              icon: Icons.favorite,
              title: 'Liked Songs',
              subtitle: 'Playlist · canciones',
              background: const Color(0xFF353588),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const LikedSongsScreen()),
              ),
            ),
            if (pinned.isNotEmpty) ...[
              const _SidebarSectionHeader('Fijadas'),
              for (final playlist in pinned)
                _playlistTile(playlist, pinned: true),
            ],
            if (rest.isNotEmpty) ...[
              const _SidebarSectionHeader('Playlists'),
              for (final playlist in rest) _playlistTile(playlist),
            ],
          ],
        );
      },
    );
  }

  Widget _playlistTile(Playlist playlist, {bool pinned = false}) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlaylistDetailScreen(playlist: playlist),
        ),
      ),
      onLongPress: () => _showPlaylistActions(playlist),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            CoverArt(
              url: playlist.coverArtUrl,
              width: 44,
              height: 44,
              borderRadius: 6,
              fallbackIcon: Icons.queue_music,
              fallbackIconSize: 20,
              fallbackColor: Colors.grey.shade700,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (pinned) ...[
                        const Icon(Icons.push_pin,
                            color: Colors.greenAccent, size: 13),
                        const SizedBox(width: 3),
                      ],
                      Expanded(
                        child: Text(
                          playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Playlist · ${playlist.songCount} canciones',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPlaylistActions(Playlist playlist) {
    final nav = context.read<NavidromeService>();
    final pinned = nav.isPinnedPlaylist(playlist.id);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF282828),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow, color: Colors.white),
              title: const Text('Reproducir',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(context).pop();
                _playPlaylist(playlist.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.shuffle, color: Colors.greenAccent),
              title: const Text('Reproducir al azar',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(context).pop();
                _playPlaylistShuffled(playlist.id);
              },
            ),
            ListTile(
              leading: Icon(
                pinned ? Icons.push_pin_outlined : Icons.push_pin,
                color: Colors.white,
              ),
              title: Text(
                pinned ? 'Quitar de arriba' : 'Fijar arriba',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(context).pop();
                nav.togglePinPlaylist(playlist.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('Eliminar playlist',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.of(context).pop();
                _confirmDeletePlaylist(playlist);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _playPlaylist(String playlistId) async {
    final tracks =
        await context.read<NavidromeService>().getPlaylistTracks(playlistId);
    if (mounted && tracks.isNotEmpty) {
      context.read<PlayerController>().playQueue(tracks, startIndex: 0);
    }
  }

  Future<void> _playPlaylistShuffled(String playlistId) async {
    final tracks =
        await context.read<NavidromeService>().getPlaylistTracks(playlistId);
    if (mounted && tracks.isNotEmpty) {
      final player = context.read<PlayerController>();
      player.playQueue(tracks, startIndex: 0);
      // Activar shuffle después de que la cola esté lista
      await player.toggleShuffle();
    }
  }

  Future<void> _confirmDeletePlaylist(Playlist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F1F),
        title: const Text('¿Eliminar playlist?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Se borrará "${playlist.name}" permanentemente.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child:
                const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final nav = context.read<NavidromeService>();
    try {
      await nav.deletePlaylist(playlist.id);
      nav.bumpPlaylists();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Playlist eliminada',
              style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF1F1F1F),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e',
              style: const TextStyle(color: Colors.redAccent)),
          backgroundColor: const Color(0xFF1F1F1F),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _libraryTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color background,
    String? albumArtUrl,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            CoverArt(
              url: albumArtUrl,
              width: 44,
              height: 44,
              borderRadius: 6,
              fallbackIcon: icon,
              fallbackIconSize: 20,
              fallbackColor: background,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Panel Central: Descubrimiento y Contenido
  // ---------------------------------------------------------------------------
  Widget _buildMainPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _mainTopBar(),
        Expanded(
          child: _searchResults != null
              ? _buildSearchResultsPanel()
              : FutureBuilder<List<Track>>(
                  future: _futureTracks,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    }
                    if (snapshot.hasError || !snapshot.hasData) {
                      return const Center(
                        child: Text('Error al cargar',
                            style: TextStyle(color: Colors.white54)),
                      );
                    }
                    final tracks = snapshot.data!;
                    return _mainContent(tracks);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSearchResultsPanel() {
    final results = _searchResults!;
    if (_searching && results.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (results.isEmpty) {
      return const Center(
        child: Text('Sin resultados', style: TextStyle(color: Colors.white54)),
      );
    }

    final songs = results.songs;
    final albums = results.albums;
    final artists = results.artists;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      children: [
        if (songs.isNotEmpty) ...[
          const _SectionLabel('Canciones'),
          for (final track in songs)
            ListTile(
              dense: true,
              leading: CoverArt(
                url: track.albumArtUrl,
                width: 40,
                height: 40,
                borderRadius: 4,
                fallbackIcon: Icons.music_note,
                fallbackIconSize: 20,
                fallbackColor: Colors.grey.shade800,
              ),
              title: Text(track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: Text('${track.artist} · ${track.album}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () => _openPlayer(songs, songs.indexOf(track)),
            ),
        ],
        if (albums.isNotEmpty) ...[
          const _SectionLabel('Álbumes'),
          for (final album in albums)
            ListTile(
              dense: true,
              leading: CoverArt(
                url: album.coverArtUrl,
                width: 40,
                height: 40,
                borderRadius: 4,
                fallbackIcon: Icons.album,
                fallbackIconSize: 20,
                fallbackColor: Colors.grey.shade800,
              ),
              title: Text(album.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: Text(album.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => AlbumDetailScreen(album: album)),
              ),
            ),
        ],
        if (artists.isNotEmpty) ...[
          const _SectionLabel('Artistas'),
          for (final artist in artists)
            ListTile(
              dense: true,
              leading: CoverArt(
                url: artist.coverArtUrl,
                width: 40,
                height: 40,
                circle: true,
                fallbackIcon: Icons.person,
                fallbackIconSize: 20,
                fallbackColor: Colors.deepPurple.shade300,
              ),
              title: Text(artist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: const Text('Artista',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ArtistScreen(artist: artist)),
              ),
            ),
        ],
      ],
    );
  }

  Widget _mainTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Row(
        children: [
          if (_libraryCollapsed)
            IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => setState(() => _libraryCollapsed = false),
            ),
          IconButton(
            icon: const Icon(Icons.home, color: Colors.white, size: 24),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.explore_outlined, color: Colors.white, size: 24),
            onPressed: () {},
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF242424),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Colors.white54, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      textInputAction: TextInputAction.search,
                      onChanged: _runSearch,
                      decoration: const InputDecoration(
                        hintText: 'What do you want to play?',
                        hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  _searching
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white54),
                        )
                      : const Icon(Icons.mic_none,
                          color: Colors.white54, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.white),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.history, color: Colors.white),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            tooltip: 'Ajustes',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const CircleAvatar(
            radius: 15,
            backgroundColor: Colors.deepPurple,
            child: Text('T', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _mainContent(List<Track> tracks) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _pill('AI'),
              _pill('Music', selected: true),
              _pill('Podcasts'),
            ],
          ),
          const SizedBox(height: 16),
          _quickAccessGrid(tracks),
          const SizedBox(height: 24),
          _sectionHeader('Recommended for today'),
          const SizedBox(height: 12),
          _recommendedGrid(tracks),
          const SizedBox(height: 24),
          _sectionHeader('Álbumes'),
          const SizedBox(height: 12),
          _albumsCarousel(),
          const SizedBox(height: 24),
          _sectionHeader('Artistas'),
          const SizedBox(height: 12),
          _artistsCarousel(),
          const SizedBox(height: 24),
          _sectionHeader('Recientes'),
          const SizedBox(height: 12),
          _recentsList(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _pill(String label, {bool selected = false}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : const Color(0xFF1F1F1F),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _openPlayer(List<Track> tracks, int index) {
    context.read<PlayerController>().playQueue(tracks, startIndex: index);
  }

  Widget _quickAccessGrid(List<Track> tracks) {
    final items = tracks.take(6).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = (constraints.maxWidth / 220).floor().clamp(2, 3);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: 2.6,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: items.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _quickAccessCard(
                label: 'Liked Songs',
                color: const Color(0xFF353588),
                icon: Icons.favorite,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const LikedSongsScreen()),
                ),
              );
            }
            final track = items[index - 1];
            return _quickAccessCard(
              label: track.album,
              color: Colors.grey.shade800,
              albumArtUrl: track.albumArtUrl,
              icon: Icons.album,
              onTap: () => _openPlayer(tracks, tracks.indexOf(track)),
            );
          },
        );
      },
    );
  }

  Widget _quickAccessCard({
    required String label,
    required Color color,
    IconData? icon,
    String? albumArtUrl,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF1F1F1F),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
                image: albumArtUrl != null
                    ? DecorationImage(
                        image: NetworkImage(albumArtUrl),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: albumArtUrl == null
                  ? Icon(icon, color: Colors.white, size: 20)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _recommendedGrid(List<Track> tracks) {
    final items = tracks.take(10).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = (constraints.maxWidth / 170).floor().clamp(3, 6);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: 0.72,
            crossAxisSpacing: 12,
            mainAxisSpacing: 16,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final track = items[index];
            return _recommendedCard(track, tracks);
          },
        );
      },
    );
  }

  Widget _recommendedCard(Track track, List<Track> allTracks) {
    return InkWell(
      onTap: () => _openPlayer(allTracks, allTracks.indexOf(track)),
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
                image: track.albumArtUrl != null
                    ? DecorationImage(
                        image: NetworkImage(track.albumArtUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: track.albumArtUrl == null
                  ? const Icon(Icons.music_note, color: Colors.white54)
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _albumsCarousel() {
    final nav = context.read<NavidromeService>();
    return FutureBuilder<List<Album>>(
      future: nav.getAlbums(limit: 15),
      builder: (context, snapshot) {
        final albums = snapshot.data ?? <Album>[];
        if (snapshot.connectionState == ConnectionState.waiting &&
            albums.isEmpty) {
          return const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator(color: Colors.white)),
          );
        }
        if (albums.isEmpty) {
          return const Text('Sin álbumes',
              style: TextStyle(color: Colors.white54));
        }
        return SizedBox(
          height: 170,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: albums.length,
            itemBuilder: (context, index) {
              final album = albums[index];
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => AlbumDetailScreen(album: album)),
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 130,
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
                                ? const Icon(Icons.album,
                                    color: Colors.white54, size: 32)
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
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          album.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _artistsCarousel() {
    final nav = context.read<NavidromeService>();
    return FutureBuilder<List<Artist>>(
      future: nav.getArtists().then(
            (raw) => raw
                .map((e) => Artist.fromJson(e as Map<String, dynamic>))
                .toList(),
          ),
      builder: (context, snapshot) {
        final artists = snapshot.data ?? <Artist>[];
        if (snapshot.connectionState == ConnectionState.waiting &&
            artists.isEmpty) {
          return const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator(color: Colors.white)),
          );
        }
        if (artists.isEmpty) {
          return const Text('Sin artistas',
              style: TextStyle(color: Colors.white54));
        }
        return SizedBox(
          height: 170,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: artists.length,
            itemBuilder: (context, index) {
              final artist = artists[index];
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ArtistScreen(artist: artist)),
                  ),
                  borderRadius: BorderRadius.circular(80),
                  child: SizedBox(
                    width: 120,
                    child: Column(
                      children: [
                        Expanded(
                          child: Container(
                            width: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.deepPurple.shade300,
                              image: artist.coverArtUrl != null
                                  ? DecorationImage(
                                      image:
                                          NetworkImage(artist.coverArtUrl!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: artist.coverArtUrl == null
                                ? const Center(
                                    child: Icon(Icons.person,
                                        color: Colors.white, size: 40),
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          artist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _recentsList() {
    // `watch` para que la lista se actualice al reproducir canciones.
    final player = context.watch<PlayerController>();
    final items = player.recentlyPlayed.take(6).toList();
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Todavía no escuchaste nada',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    return Column(
      children: [
        for (final track in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
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
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.play_circle_outline,
                      color: Colors.white, size: 28),
                  onPressed: () =>
                      player.playQueue(player.recentlyPlayed, startIndex: items.indexOf(track)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;

  const _SectionLabel(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _SidebarSectionHeader extends StatelessWidget {
  final String title;

  const _SidebarSectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}