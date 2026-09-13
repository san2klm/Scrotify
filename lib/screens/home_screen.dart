import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/navidrome_service.dart';
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _LibraryFilter { playlists, podcasts, albums, artists }

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Track>> _futureTracks;
  _LibraryFilter _filter = _LibraryFilter.playlists;
  bool _libraryCollapsed = false;

  @override
  void initState() {
    super.initState();
    _futureTracks = context.read<NavidromeService>().getTracks();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Row(
        children: [
          if (!_libraryCollapsed) _buildLibraryPanel(),
          Expanded(child: _buildMainPanel()),
        ],
      ),
      bottomNavigationBar: _buildPlayerBar(),
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
          _libraryFilters(),
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

  Widget _libraryFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _chip('Playlists', _LibraryFilter.playlists),
          _chip('Podcasts', _LibraryFilter.podcasts),
          _chip('Álbumes', _LibraryFilter.albums),
          _chip('Artistas', _LibraryFilter.artists),
        ],
      ),
    );
  }

  Widget _chip(String label, _LibraryFilter value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        backgroundColor: const Color(0xFF1F1F1F),
        selectedColor: const Color(0xFF323232),
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.white70,
          fontSize: 12,
        ),
        onSelected: (_) => setState(() => _filter = value),
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
            child: Text('Sin contenido', style: TextStyle(color: Colors.white54)),
          );
        }

        final tracks = snapshot.data!.take(40).toList();
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: tracks.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _libraryTile(
                icon: Icons.favorite,
                title: 'Liked Songs',
                subtitle: 'Playlist · ${tracks.length} canciones',
                background: const Color(0xFF353588),
              );
            }
            final track = tracks[index - 1];
            return _libraryTile(
              icon: Icons.album,
              title: track.album,
              subtitle: 'Álbum · ${track.artist}',
              background: Colors.grey.shade800,
              albumArtUrl: track.albumArtUrl,
            );
          },
        );
      },
    );
  }

  Widget _libraryTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color background,
    String? albumArtUrl,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: background,
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
              final tracks = snapshot.data!;
              return _mainContent(tracks);
            },
          ),
        ),
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
              child: const Row(
                children: [
                  Icon(Icons.search, color: Colors.white54, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      style: TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'What do you want to play?',
                        hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  Icon(Icons.mic_none, color: Colors.white54, size: 20),
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
          _sectionHeader('Recommended Stations'),
          const SizedBox(height: 12),
          _stationsRow(tracks),
          const SizedBox(height: 24),
          _sectionHeader('Recents'),
          const SizedBox(height: 12),
          _recentsList(tracks),
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(tracks: tracks, initialIndex: index),
      ),
    );
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

  Widget _stationsRow(List<Track> tracks) {
    final uniqueArtists = <String>{};
    final artists = tracks
        .where((t) => uniqueArtists.add(t.artist))
        .take(6)
        .toList();

    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: artists.length,
        itemBuilder: (context, index) {
          final artist = artists[index];
          return Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Column(
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.deepPurple.shade300,
                    image: artist.albumArtUrl != null
                        ? DecorationImage(
                            image: NetworkImage(artist.albumArtUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: artist.albumArtUrl == null
                      ? const Center(
                          child: Icon(Icons.person, color: Colors.white, size: 40),
                        )
                      : null,
                ),
                const SizedBox(height: 8),
                Text(
                  artist.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Text(
                  'Estación',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _recentsList(List<Track> tracks) {
    final items = tracks.take(5).toList();
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
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.play_circle_outline,
                      color: Colors.white, size: 28),
                  onPressed: () => _openPlayer(tracks, tracks.indexOf(track)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Barra Inferior: Reproductor
  // ---------------------------------------------------------------------------
  Widget _buildPlayerBar() {
    return Container(
      height: 72,
      color: const Color(0xFF181818),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.music_note, color: Colors.deepPurple, size: 28),
          const SizedBox(width: 12),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nada en reproducción',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Selecciona algo para escuchar',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.favorite_border, color: Colors.white70),
            onPressed: () {},
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.shuffle, color: Colors.white70, size: 20),
                  onPressed: () {},
                ),
                const Icon(Icons.skip_previous, color: Colors.white, size: 28),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(Icons.play_circle_filled,
                      color: Colors.white, size: 38),
                ),
                const Icon(Icons.skip_next, color: Colors.white, size: 28),
                IconButton(
                  icon: const Icon(Icons.repeat, color: Colors.white70, size: 20),
                  onPressed: () {},
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.format_quote, color: Colors.white70, size: 20),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.queue_music, color: Colors.white70, size: 20),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.volume_up, color: Colors.white70, size: 20),
            onPressed: () {},
          ),
          const SizedBox(width: 8),
          Container(
            width: 90,
            height: 4,
            color: Colors.white24,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: 0.6,
              child: Container(color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.fullscreen, color: Colors.white70, size: 18),
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}