import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../widgets/persistent_player_bar.dart';
import 'liked_songs_screen.dart';
import 'playlist_detail_screen.dart';
import 'album_detail_screen.dart';
import 'artist_screen.dart';
import 'settings_screen.dart';

/// Interfaz móvil de Scrotify (estilo Spotify).
/// Está pensada para pantallas estrechas (teléfonos) y se adapta a tablets
/// mostrando más columnas en los carruseles y cuadrículas.
class MobileHomeScreen extends StatefulWidget {
  const MobileHomeScreen({super.key});

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

enum _HomeFilter { todo, musica, podcasts }

class _MobileHomeScreenState extends State<MobileHomeScreen> {
  int _tabIndex = 0;
  _HomeFilter _filter = _HomeFilter.todo;
  late Future<List<Track>> _futureTracks;
  late Future<List<Playlist>> _futurePlaylists;
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

  void _openPlayer(List<Track> tracks, int index) {
    context.read<PlayerController>().playQueue(tracks, startIndex: index);
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
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFF121212),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          _buildHomeTab(),
          _buildSearchTab(),
          _buildLibraryTab(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PersistentPlayerBar(compact: true),
            _buildNavBar(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Pestaña Inicio
  // ---------------------------------------------------------------------------
  Widget _buildHomeTab() {
    return FutureBuilder<List<Track>>(
      future: _futureTracks,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const Center(
            child: Text(
              'Sin contenido',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }
        final tracks = snapshot.data!;
        return SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopBar(),
                _filterPills(),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _quickAccessGrid(tracks),
                ),
                const SizedBox(height: 24),
                _sectionHeader('Preguardá los próximos lanzamientos'),
                const SizedBox(height: 12),
                _carousel(tracks),
                const SizedBox(height: 24),
                _sectionHeader('Your own personal DJ'),
                const SizedBox(height: 12),
                _carousel(tracks),
                const SizedBox(height: 24),
                _sectionHeader('Recientes'),
                const SizedBox(height: 8),
                _recentsList(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 16,
            backgroundColor: Colors.deepPurple,
            child: Text('T', style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Home',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.history, color: Colors.white, size: 22),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none,
                color: Colors.white, size: 22),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined,
                color: Colors.white, size: 22),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterPills() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _pill('Todo', _HomeFilter.todo),
          _pill('Música', _HomeFilter.musica),
          _pill('Podcasts', _HomeFilter.podcasts),
        ],
      ),
    );
  }

  Widget _pill(String label, _HomeFilter value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _filter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
      ),
    );
  }

  Widget _quickAccessGrid(List<Track> tracks) {
    final items = tracks.take(6).toList();
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 2.6,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: [
        _quickAccessCard(
          label: 'Liked Songs',
          color: const Color(0xFF353588),
          icon: Icons.favorite,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LikedSongsScreen()),
          ),
        ),
        for (final track in items)
          _quickAccessCard(
            label: track.album,
            color: Colors.grey.shade800,
            albumArtUrl: track.albumArtUrl,
            icon: Icons.album,
            onTap: () => _openPlayer(tracks, tracks.indexOf(track)),
          ),
      ],
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

  Widget _carousel(List<Track> tracks) {
    final items = tracks.take(10).toList();
    return SizedBox(
      height: 176,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final track = items[index];
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              onTap: () => _openPlayer(tracks, tracks.indexOf(track)),
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 128,
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
                            ? const Icon(Icons.music_note,
                                color: Colors.white54)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      track.artist,
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
          ListTile(
            dense: true,
            leading: Container(
              width: 42,
              height: 42,
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
            title: Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            subtitle: Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.play_circle_outline,
                  color: Colors.white, size: 28),
              onPressed: () =>
                  player.playQueue(player.recentlyPlayed, startIndex: items.indexOf(track)),
            ),
            onTap: () =>
                player.playQueue(player.recentlyPlayed, startIndex: items.indexOf(track)),
          ),
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Pestaña Buscar
  // ---------------------------------------------------------------------------
  Widget _buildSearchTab() {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Buscar',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Colors.black54, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.black, fontSize: 14),
                      textInputAction: TextInputAction.search,
                      onChanged: _runSearch,
                      decoration: const InputDecoration(
                        hintText: '¿Qué quieres escuchar?',
                        hintStyle:
                            TextStyle(color: Colors.black38, fontSize: 14),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  const Icon(Icons.mic_none, color: Colors.black54, size: 20),
                ],
              ),
            ),
          ),
          Expanded(
            child: _searchResults == null
                ? _buildExploreAll()
                : _buildSearchResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildExploreAll() {
    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Explorar todo',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _categoryGrid(),
      ],
    );
  }

  Widget _buildSearchResults() {
    final results = _searchResults!;
    if (_searching) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (results.isEmpty) {
      return const Center(
        child: Text('Sin resultados',
            style: TextStyle(color: Colors.white54)),
      );
    }

    final songs = results.songs;
    final albums = results.albums;
    final artists = results.artists;

    return ListView(
      children: [
        if (songs.isNotEmpty) ...[
          const _ResultHeader('Canciones'),
          for (final track in songs)
            ListTile(
              dense: true,
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
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: Text('${track.artist} · ${track.album}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () => _openPlayer(songs, songs.indexOf(track)),
            ),
        ],
        if (albums.isNotEmpty) ...[
          const _ResultHeader('Álbumes'),
          for (final album in albums)
            ListTile(
              dense: true,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(4),
                  image: album.coverArtUrl != null
                      ? DecorationImage(
                          image: NetworkImage(album.coverArtUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: album.coverArtUrl == null
                    ? const Icon(Icons.album, color: Colors.white54, size: 20)
                    : null,
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
          const _ResultHeader('Artistas'),
          for (final artist in artists)
            ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 20,
                backgroundColor: Colors.deepPurple.shade300,
                backgroundImage: artist.coverArtUrl != null
                    ? NetworkImage(artist.coverArtUrl!)
                    : null,
                child: artist.coverArtUrl == null
                    ? const Icon(Icons.person, color: Colors.white, size: 20)
                    : null,
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

  Widget _categoryGrid() {
    final categories = [
      ('Rock', const Color(0xFFE13300)),
      ('Pop', const Color(0xFF148A08)),
      ('Hip-Hop', const Color(0xFF503750)),
      ('Jazz', const Color(0xFF7358FF)),
      ('Electrónica', const Color(0xFF8D67AB)),
      ('Clásica', const Color(0xFF7D4B32)),
    ];
    return GridView.count(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      crossAxisCount: 2,
      childAspectRatio: 1.6,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: [
        for (final category in categories)
          Container(
            decoration: BoxDecoration(
              color: category.$2,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                category.$1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Pestaña Tu Biblioteca
  // ---------------------------------------------------------------------------
  Widget _buildLibraryTab() {
    // `watch` para que el icono de fijar se actualice al tocar pin/unpin.
    final nav = context.watch<NavidromeService>();
    return FutureBuilder<List<Playlist>>(
      future: _futurePlaylists,
      builder: (context, snapshot) {
        final playlists = snapshot.data ?? <Playlist>[];
        final loading =
            snapshot.connectionState == ConnectionState.waiting;
        final pinned =
            playlists.where((p) => nav.isPinnedPlaylist(p.id)).toList();
        final rest =
            playlists.where((p) => !nav.isPinnedPlaylist(p.id)).toList();

        if (loading && playlists.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }

        return SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Tu biblioteca',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      '${playlists.length} playlists',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: playlists.isEmpty
                    ? const Center(
                        child: Text(
                          'Sin playlists',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 16),
                        children: [
                          const SizedBox(height: 8),
                          // ── Liked Songs ──────────────────────────
                          _likedSongsCard(),
                          // ── Fijadas ─────────────────────────────
                          if (pinned.isNotEmpty) ...[
                            const _LibrarySectionLabel('Fijadas'),
                            for (final p in pinned)
                              _playlistListTile(p, pinned: true),
                          ],
                          // ── Playlists ───────────────────────────
                          if (rest.isNotEmpty) ...[
                            const _LibrarySectionLabel('Playlists'),
                            for (final p in rest) _playlistListTile(p),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _likedSongsCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LikedSongsScreen()),
        ),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF353588), Color(0xFF4040AA)],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: const Row(
            children: [
              Icon(Icons.favorite, color: Colors.white, size: 26),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Liked Songs',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }

  Widget _playlistListTile(Playlist playlist, {bool pinned = false}) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlaylistDetailScreen(playlist: playlist),
        ),
      ),
      onLongPress: () => _showMobilePlaylistActions(playlist),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: BorderRadius.circular(6),
                image: playlist.coverArtUrl != null
                    ? DecorationImage(
                        image: NetworkImage(playlist.coverArtUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: playlist.coverArtUrl == null
                  ? const Icon(Icons.queue_music,
                      color: Colors.white54, size: 22)
                  : null,
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
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
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
            const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
          ],
        ),
      ),
    );
  }

  void _showMobilePlaylistActions(Playlist playlist) {
    final nav = context.read<NavidromeService>();
    final pinned = nav.isPinnedPlaylist(playlist.id);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1F1F1F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.play_arrow, color: Colors.white),
              title: const Text('Reproducir',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(context).pop();
                _playMobilePlaylist(playlist.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.shuffle, color: Colors.greenAccent),
              title: const Text('Reproducir al azar',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(context).pop();
                _playMobilePlaylistShuffled(playlist.id);
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

  Future<void> _playMobilePlaylist(String playlistId) async {
    final tracks =
        await context.read<NavidromeService>().getPlaylistTracks(playlistId);
    if (mounted && tracks.isNotEmpty) {
      context.read<PlayerController>().playQueue(tracks, startIndex: 0);
    }
  }

  Future<void> _playMobilePlaylistShuffled(String playlistId) async {
    final tracks =
        await context.read<NavidromeService>().getPlaylistTracks(playlistId);
    if (mounted && tracks.isNotEmpty) {
      final player = context.read<PlayerController>();
      player.playQueue(tracks, startIndex: 0);
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
            child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
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
          content: Text('Playlist eliminada', style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF1F1F1F),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e', style: const TextStyle(color: Colors.redAccent)),
          backgroundColor: const Color(0xFF1F1F1F),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

    // ---------------------------------------------------------------------------
  // Barra inferior: Mini-reproductor flotante + navegación
  // ---------------------------------------------------------------------------
  Widget _buildNavBar() {
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0A),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          _navItem(Icons.home_rounded, 'Inicio', 0),
          _navItem(Icons.search_rounded, 'Buscar', 1),
          _navItem(Icons.library_music_outlined, 'Tu biblioteca', 2),
          Expanded(
            child: InkWell(
              onTap: _showCreateSheet,
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle_outline,
                      color: Colors.white54, size: 24),
                  SizedBox(height: 2),
                  Text(
                    'Crear',
                    style: TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final selected = _tabIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tabIndex = index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: selected ? Colors.white : Colors.white54, size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white54,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1F1F1F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading:
                    const Icon(Icons.playlist_add, color: Colors.white),
                title: const Text('Nueva playlist',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(context).pop();
                  _promptNewPlaylist();
                },
              ),
              ListTile(
                leading: const Icon(Icons.shuffle, color: Colors.white),
                title: const Text('Crear mezcla',
                    style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  void _promptNewPlaylist() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1F1F1F),
          title: const Text('Nueva playlist',
              style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Nombre de la playlist',
              hintStyle: TextStyle(color: Colors.white38),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar',
                  style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                Navigator.of(context).pop();
                try {
                  await context.read<NavidromeService>().createPlaylist(name);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Playlist "$name" creada')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              child: const Text('Crear', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}

class _LibrarySectionLabel extends StatelessWidget {
  final String title;

  const _LibrarySectionLabel(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
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

class _ResultHeader extends StatelessWidget {
  final String title;

  const _ResultHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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