import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/navidrome_service.dart';
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _MainTab { home, search, library, create }

enum _ContentFilter { all, music, podcasts }

enum _LibraryFilter { playlists, podcasts, albums, artists }

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Track>> _futureTracks;

  _MainTab _tab = _MainTab.home;
  _ContentFilter _filter = _ContentFilter.all;
  _LibraryFilter _libraryFilter = _LibraryFilter.playlists;

  Track? _currentTrack;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _futureTracks = context.read<NavidromeService>().getTracks();
  }

  bool get _isTablet => MediaQuery.of(context).size.width >= 600;

  void _openPlayer(List<Track> tracks, int index) {
    setState(() {
      _currentTrack = tracks[index];
      _isPlaying = true;
    });
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(tracks: tracks, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _tab.index,
          children: [
            _buildHomeTab(),
            _buildSearchTab(),
            _buildLibraryTab(),
            _buildCreateTab(),
          ],
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildMiniPlayer(),
          _buildBottomNav(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Pestañas
  // ---------------------------------------------------------------------------
  Widget _buildHomeTab() {
    return Column(
      children: [
        _buildTopHeader(),
        _buildFilterPills(),
        Expanded(
          child: FutureBuilder<List<Track>>(
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
              return _buildFeed(snapshot.data!);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchTab() {
    return Column(
      children: [
        _buildSearchHeader(),
        Expanded(child: _buildSearchBody()),
      ],
    );
  }

  Widget _buildLibraryTab() {
    return Column(
      children: [
        _buildLibraryHeader(),
        _buildLibraryFilters(),
        Expanded(
          child: FutureBuilder<List<Track>>(
            future: _futureTracks,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return const Center(
                  child: Text('Sin contenido',
                      style: TextStyle(color: Colors.white54)),
                );
              }
              return _buildLibraryGrid(snapshot.data!);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCreateTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Crear',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          _createCard(
            icon: Icons.queue_music,
            title: 'Playlist',
            subtitle: 'Crea una lista con tus canciones favoritas',
            gradient: const [Color(0xFF353588), Color(0xFF1DB954)],
          ),
          const SizedBox(height: 12),
          _createCard(
            icon: Icons.blur_on,
            title: 'Mezcla',
            subtitle: 'Mezcla automática basada en tus gustos',
            gradient: const [Color(0xFF5E35B1), Color(0xFF8E24AA)],
          ),
          const SizedBox(height: 12),
          _createCard(
            icon: Icons.album,
            title: 'Álbum',
            subtitle: 'Organiza un álbum con varias canciones',
            gradient: const [Color(0xFF283593), Color(0xFF1E88E5)],
          ),
        ],
      ),
    );
  }

  Widget _createCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> gradient,
  }) {
    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Barra superior (Header de perfil + filtros)
  // ---------------------------------------------------------------------------
  Widget _buildTopHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: Colors.deepPurple,
            child: Text('T', style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                const Text(
                  'Buenas tardes',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down,
                      color: Colors.white70, size: 20),
                  onPressed: () {},
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined,
                color: Colors.white, size: 22),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.history, color: Colors.white, size: 22),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined,
                color: Colors.white, size: 22),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPills() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _pill('Todo', _ContentFilter.all),
          _pill('Música', _ContentFilter.music),
          _pill('Podcasts', _ContentFilter.podcasts),
        ],
      ),
    );
  }

  Widget _pill(String label, _ContentFilter value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1DB954) : const Color(0xFF1F1F1F),
            borderRadius: BorderRadius.circular(18),
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

  // ---------------------------------------------------------------------------
  // Feed central adaptativo
  // ---------------------------------------------------------------------------
  Widget _buildFeed(List<Track> tracks) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('Tus accesos rápidos', padH: 16),
          const SizedBox(height: 12),
          _buildQuickAccessGrid(tracks),
          const SizedBox(height: 24),
          _buildCarouselSection(
            title: 'Preguardá los próximos lanzamientos',
            tracks: tracks,
            cardWidth: _isTablet ? 160 : 140,
          ),
          const SizedBox(height: 24),
          _buildCarouselSection(
            title: 'Tu DJ personal',
            tracks: tracks.skip(5).toList(),
            cardWidth: _isTablet ? 160 : 140,
          ),
          const SizedBox(height: 24),
          _sectionHeader('Recientes', padH: 16),
          const SizedBox(height: 12),
          _buildRecents(tracks),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildQuickAccessGrid(List<Track> tracks) {
    final items = tracks.take(_isTablet ? 8 : 6).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = _isTablet ? 4 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
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
                onTap: () {},
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

  Widget _buildCarouselSection({
    required String title,
    required List<Track> tracks,
    required double cardWidth,
  }) {
    final items = tracks.take(8).toList();
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: cardWidth + 52,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final track = items[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: SizedBox(
                  width: cardWidth,
                  child: _albumCard(track, tracks),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _albumCard(Track track, List<Track> allTracks) {
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

  Widget _buildRecents(List<Track> tracks) {
    final items = tracks.take(_isTablet ? 8 : 4).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = _isTablet ? 4 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
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

  Widget _sectionHeader(String title, {required double padH}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padH),
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
  Widget _buildSearchHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Buscar',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined,
                color: Colors.white, size: 24),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF242424),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.search, color: Colors.white54, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    style: TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '¿Qué quieres escuchar?',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Explorar todo',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildGenreGrid(),
        ],
      ),
    );
  }

  Widget _buildGenreGrid() {
    const genres = <(String, Color, IconData)>[
      ('Pop', Color(0xFF8D67AB), Icons.star),
      ('Rock', Color(0xFFE13300), Icons.local_fire_department),
      ('Hip-Hop', Color(0xFFBA5D07), Icons.mic_external_on),
      ('Electrónica', Color(0xFF503750), Icons.graphic_eq),
      ('Jazz', Color(0xFF1E3264), Icons.music_note),
      ('Clásica', Color(0xFF777777), Icons.piano),
      ('Latina', Color(0xFFA56752), Icons.airport_shuttle),
      ('Podcasts', Color(0xFF0D73EC), Icons.podcasts),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = _isTablet ? 4 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: 1.6,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: genres.length,
          itemBuilder: (context, index) {
            final (label, color, icon) = genres[index];
            return _genreCard(label, color, icon);
          },
        );
      },
    );
  }

  Widget _genreCard(String label, Color color, IconData icon) {
    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Pestaña Tu Biblioteca
  // ---------------------------------------------------------------------------
  Widget _buildLibraryHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          const Text(
            'Tu biblioteca',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white, size: 24),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white, size: 24),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryFilters() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _libraryChip('Playlists', _LibraryFilter.playlists),
          _libraryChip('Podcasts', _LibraryFilter.podcasts),
          _libraryChip('Álbumes', _LibraryFilter.albums),
          _libraryChip('Artistas', _LibraryFilter.artists),
        ],
      ),
    );
  }

  Widget _libraryChip(String label, _LibraryFilter value) {
    final selected = _libraryFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _libraryFilter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1DB954) : const Color(0xFF1F1F1F),
            borderRadius: BorderRadius.circular(18),
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

  Widget _buildLibraryGrid(List<Track> tracks) {
    final items = tracks.take(40).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = _isTablet ? 3 : 2;
        return GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: 0.72,
            crossAxisSpacing: 12,
            mainAxisSpacing: 16,
          ),
          itemCount: items.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _likedSongsCard(tracks.length);
            }
            final track = items[index - 1];
            return _recommendedCard(track, tracks);
          },
        );
      },
    );
  }

  Widget _likedSongsCard(int total) {
    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF353588), Color(0xFF1DB954)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.favorite, color: Colors.white, size: 40),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Liked Songs',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'Playlist · $total canciones',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Barra de navegación inferior
  // ---------------------------------------------------------------------------
  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0A),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _navItem(Icons.home, Icons.home_outlined, 'Inicio', _MainTab.home),
            _navItem(Icons.search, Icons.search, 'Buscar', _MainTab.search),
            _navItem(Icons.library_music, Icons.library_music_outlined,
                'Tu biblioteca', _MainTab.library),
            _navItem(Icons.add_circle, Icons.add_circle_outline, 'Crear',
                _MainTab.create),
          ],
        ),
      ),
    );
  }

  Widget _navItem(
      IconData selectedIcon, IconData icon, String label, _MainTab tab) {
    final selected = _tab == tab;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = tab),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? selectedIcon : icon,
                color: selected ? Colors.white : Colors.white54,
                size: 26,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white54,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Mini-reproductor flotante
  // ---------------------------------------------------------------------------
  Widget _buildMiniPlayer() {
    final track = _currentTrack;
    return GestureDetector(
      onTap: () {
        if (track != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PlayerScreen(
                tracks: [track],
                initialIndex: 0,
              ),
            ),
          );
        }
      },
      child: Container(
        height: 60,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF282828),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: BorderRadius.circular(6),
                image: track?.albumArtUrl != null
                    ? DecorationImage(
                        image: NetworkImage(track!.albumArtUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: track?.albumArtUrl == null
                  ? const Icon(Icons.music_note, color: Colors.deepPurple)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track?.title ?? 'Nada en reproducción',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    track?.artist ?? 'Selecciona algo para escuchar',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.favorite_border,
                  color: Colors.white70, size: 20),
              onPressed: () {},
            ),
            IconButton(
              iconSize: 36,
              icon: Icon(
                _isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled,
                color: Colors.white,
              ),
              onPressed: () {
                if (track != null) {
                  setState(() => _isPlaying = !_isPlaying);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}