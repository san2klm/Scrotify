import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/navidrome_service.dart';
import 'player_screen.dart';

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

  bool _miniFavorite = false;
  bool _miniPlaying = false;

  @override
  void initState() {
    super.initState();
    _futureTracks = context.read<NavidromeService>().getTracks();
  }

  void _openPlayer(List<Track> tracks, int index) {
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
            _buildMiniPlayer(),
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
                _recentsList(tracks),
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
            onPressed: () {},
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

  Widget _recentsList(List<Track> tracks) {
    final items = tracks.take(6).toList();
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
              icon: const Icon(Icons.more_vert, color: Colors.white54),
              onPressed: () => _openPlayer(tracks, tracks.indexOf(track)),
            ),
            onTap: () => _openPlayer(tracks, tracks.indexOf(track)),
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
              child: const Row(
                children: [
                  Icon(Icons.search, color: Colors.black54, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      style: TextStyle(color: Colors.black, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: '¿Qué quieres escuchar?',
                        hintStyle:
                            TextStyle(color: Colors.black38, fontSize: 14),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  Icon(Icons.mic_none, color: Colors.black54, size: 20),
                ],
              ),
            ),
          ),
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
          Expanded(child: _categoryGrid()),
        ],
      ),
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
    return FutureBuilder<List<Track>>(
      future: _futureTracks,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        final tracks = snapshot.data ?? <Track>[];
        return SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Tu biblioteca',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Playlists · Álbumes · Artistas',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
              Expanded(
                child: tracks.isEmpty
                    ? const Center(
                        child: Text(
                          'Sin contenido',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.9,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: tracks.take(20).length,
                        itemBuilder: (context, index) {
                          final track = tracks[index];
                          return InkWell(
                            onTap: () => _openPlayer(tracks, index),
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
                                              image: NetworkImage(
                                                  track.albumArtUrl!),
                                              fit: BoxFit.cover,
                                            )
                                          : null,
                                    ),
                                    child: track.albumArtUrl == null
                                        ? const Icon(Icons.album,
                                            color: Colors.white54)
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  track.album,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
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
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Barra inferior: Mini-reproductor flotante + navegación
  // ---------------------------------------------------------------------------
  Widget _buildMiniPlayer() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFF1F1F1F),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            margin: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.deepPurple,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.music_note, color: Colors.white, size: 22),
          ),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nada en reproducción',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Selecciona algo para escuchar',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              _miniFavorite ? Icons.favorite : Icons.favorite_border,
              color: _miniFavorite ? Colors.greenAccent : Colors.white,
              size: 20,
            ),
            onPressed: () => setState(() => _miniFavorite = !_miniFavorite),
          ),
          IconButton(
            icon: Icon(
              _miniPlaying
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_filled,
              color: Colors.white,
              size: 34,
            ),
            onPressed: () => setState(() => _miniPlaying = !_miniPlaying),
          ),
        ],
      ),
    );
  }

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
                onTap: () => Navigator.of(context).pop(),
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
}