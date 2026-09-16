import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/jam_controller.dart';
import '../services/navidrome_service.dart';
import '../services/pairing_server.dart';
import '../services/player_controller.dart';
import '../widgets/persistent_player_bar.dart';
import '../widgets/cover_art.dart';
import '../widgets/pairing_panel.dart';
import '../widgets/jam_dialog.dart';
import '../widgets/server_activity_panel.dart';
import '../widgets/track_context_menu.dart';
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
  int _activeNavIndex = 0; // 0 = Inicio, 1 = Explorar

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

  void _openPairingDialog() {
    final nav = context.read<NavidromeService>();
    final server = context.read<PairingServer>();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0C0C10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF1E1E28), width: 1.2),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
        contentPadding: const EdgeInsets.all(20),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.qr_code_2_rounded,
                  color: Color(0xFFA855F7), size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'Vincular con tu Teléfono',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white54, size: 20),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: PairingSharePanel(
            compact: true,
            server: server,
            onGetCredentials: () async => nav.currentCredentials,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
      backgroundColor: const Color(0xFF000000), // Pure AMOLED Black
      body: Column(
        children: [
          // -----------------------------------------------------------------
          // 1. BARRA SUPERIOR PERSISTENTE (Global Header de extremo a extremo)
          // -----------------------------------------------------------------
          _buildPersistentGlobalTopBar(nav),

          // -----------------------------------------------------------------
          // 2. CUERPO: Panel Lateral de Biblioteca + Área Principal
          // -----------------------------------------------------------------
          Expanded(
            child: Row(
              children: [
                if (!_libraryCollapsed) _buildLibraryPanel(),
                Expanded(child: _buildMainPanel()),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const PersistentPlayerBar(),
    );
  }

  // ===========================================================================
  // BARRA SUPERIOR PERSISTENTE (GLOBAL HEADER)
  // ===========================================================================
  Widget _buildPersistentGlobalTopBar(NavidromeService nav) {
    final username = nav.username ?? 'U';
    final initial = username.isNotEmpty ? username[0].toUpperCase() : 'U';

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF07070A),
        border: Border(
          bottom: BorderSide(color: Color(0xFF181820), width: 1.2),
        ),
      ),
      child: Row(
        children: [
          // Logo de Scrotify
          InkWell(
            onTap: () {
              setState(() {
                _searchResults = null;
                _searchController.clear();
                _activeNavIndex = 0;
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF140E24),
                      border: Border.all(
                        color: const Color(0xFFA855F7).withValues(alpha: 0.5),
                        width: 1.2,
                      ),
                    ),
                    child: const Icon(
                      Icons.graphic_eq_rounded,
                      color: Color(0xFFA855F7),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'SCROTIFY',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Botones de navegación persistentes
          _navItem(
            index: 0,
            icon: Icons.home_rounded,
            label: 'Inicio',
            onTap: () {
              setState(() {
                _searchResults = null;
                _searchController.clear();
                _activeNavIndex = 0;
              });
            },
          ),
          const SizedBox(width: 6),
          _navItem(
            index: 1,
            icon: Icons.explore_outlined,
            label: 'Explorar',
            onTap: () {
              setState(() {
                _activeNavIndex = 1;
              });
            },
          ),

          const SizedBox(width: 16),

          // Barra de Búsqueda Omnibox Central
          Expanded(
            child: Center(
              child: Container(
                height: 38,
                constraints: const BoxConstraints(maxWidth: 480),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0F14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF1E1E28)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded,
                        color: Colors.white38, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        textInputAction: TextInputAction.search,
                        onChanged: _runSearch,
                        decoration: const InputDecoration(
                          hintText: '¿Qué quieres escuchar hoy?',
                          hintStyle:
                              TextStyle(color: Colors.white30, fontSize: 13),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            size: 16, color: Colors.white38),
                        onPressed: () {
                          _searchController.clear();
                          _runSearch('');
                        },
                      )
                    else if (_searching)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: Color(0xFFA855F7),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Botón Rápido: Jam (Sesión compartida / colaborativa)
          Consumer<JamController>(
            builder: (context, jam, _) {
              if (jam.inJam) {
                return FilledButton.tonalIcon(
                  onPressed: () => JamDialog.show(context),
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        const Color(0xFF10B981).withValues(alpha: 0.18),
                    foregroundColor: const Color(0xFF10B981),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(
                          color: Color(0xFF10B981), width: 0.8),
                    ),
                  ),
                  icon: const Icon(Icons.speaker_group_rounded, size: 17),
                  label: Text(
                    'Jam (${jam.participants.length})',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                );
              }
              return FilledButton.tonalIcon(
                onPressed: () => JamDialog.show(context),
                style: FilledButton.styleFrom(
                  backgroundColor:
                      const Color(0xFF10B981).withValues(alpha: 0.12),
                  foregroundColor: const Color(0xFF10B981),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.speaker_group_outlined, size: 17),
                label: const Text(
                  'Jam',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              );
            },
          ),

          const SizedBox(width: 8),

          // Botón Rápido: Comunidad / Ahora sonando en el servidor
          IconButton(
            tooltip: 'Comunidad & Chat Navidrome',
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF14141E),
              foregroundColor: const Color(0xFF10B981),
            ),
            icon: const Icon(Icons.people_alt_rounded, size: 19),
            onPressed: () => ServerActivityPanel.show(context),
          ),

          const SizedBox(width: 8),

          // Botón Rápido: Vincular Teléfono (QR/LAN)
          FilledButton.tonalIcon(
            onPressed: _openPairingDialog,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1A122E),
              foregroundColor: const Color(0xFFA855F7),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.qr_code_2_rounded, size: 17),
            label: const Text(
              'Vincular celular',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),

          const SizedBox(width: 10),

          // Botón Ajustes
          IconButton(
            icon: const Icon(Icons.settings_outlined,
                color: Colors.white70, size: 20),
            tooltip: 'Ajustes',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),

          const SizedBox(width: 6),

          // Avatar de Usuario
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF7C3AED),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem({
    required int index,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final isSelected = _activeNavIndex == index && _searchResults == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF181824) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(
                  color: const Color(0xFFA855F7).withValues(alpha: 0.35),
                  width: 1)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 17,
              color: isSelected ? const Color(0xFFA855F7) : Colors.white60,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white60,
                fontSize: 13,
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // Panel Izquierdo: Tu Biblioteca
  // ===========================================================================
  Widget _buildLibraryPanel() {
    return Container(
      width: 270,
      color: const Color(0xFF060608),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _libraryHeader(),
          const Divider(height: 1, color: Color(0xFF1A1A22)),
          _librarySearchBar(),
          Expanded(child: _libraryList()),
        ],
      ),
    );
  }

  Widget _libraryHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
      child: Row(
        children: [
          const Icon(Icons.library_music_rounded,
              color: Color(0xFFA855F7), size: 18),
          const SizedBox(width: 8),
          const Text(
            'Tu Biblioteca',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.menu_open, color: Colors.white54, size: 18),
            tooltip: 'Colapsar biblioteca',
            onPressed: () => setState(() => _libraryCollapsed = true),
          ),
        ],
      ),
    );
  }

  Widget _librarySearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F14),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF1E1E26)),
        ),
        child: const Row(
          children: [
            Icon(Icons.search, color: Colors.white38, size: 16),
            SizedBox(width: 6),
            Expanded(
              child: TextField(
                style: TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Buscar en playlists...',
                  hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _libraryList() {
    final nav = context.watch<NavidromeService>();
    return FutureBuilder<List<Playlist>>(
      future: _futurePlaylists,
      builder: (context, snapshot) {
        final playlists = snapshot.data ?? [];
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          children: [
            _libraryTile(
              icon: Icons.favorite_rounded,
              title: 'Tus me gusta',
              subtitle: 'Canciones favoritas',
              background: const Color(0xFF4C1D95),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const LikedSongsScreen()),
              ),
            ),
            const SizedBox(height: 4),
            for (final playlist in playlists) ...[
              _playlistTile(playlist, nav.isPinnedPlaylist(playlist.id)),
            ],
          ],
        );
      },
    );
  }

  Widget _playlistTile(Playlist playlist, bool pinned) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlaylistDetailScreen(playlist: playlist),
        ),
      ),
      onLongPress: () => _showPlaylistActions(playlist),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        child: Row(
          children: [
            CoverArt(
              url: playlist.coverArtUrl,
              width: 40,
              height: 40,
              borderRadius: 6,
              fallbackIcon: Icons.queue_music,
              fallbackIconSize: 18,
              fallbackColor: const Color(0xFF1A1A24),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (pinned) ...[
                        const Icon(Icons.push_pin,
                            color: Color(0xFF10B981), size: 12),
                        const SizedBox(width: 3),
                      ],
                      Expanded(
                        child: Text(
                          playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
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
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
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
      backgroundColor: const Color(0xFF0C0C10),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
              leading: const Icon(Icons.shuffle, color: Color(0xFF10B981)),
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
      await player.toggleShuffle();
    }
  }

  Future<void> _confirmDeletePlaylist(Playlist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141418),
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
        const SnackBar(
          content: Text('Playlist eliminada',
              style: TextStyle(color: Colors.white)),
          backgroundColor: Color(0xFF1C1328),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e',
              style: const TextStyle(color: Colors.redAccent)),
          backgroundColor: const Color(0xFF1C1328),
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
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        child: Row(
          children: [
            CoverArt(
              url: albumArtUrl,
              width: 40,
              height: 40,
              borderRadius: 6,
              fallbackIcon: icon,
              fallbackIconSize: 18,
              fallbackColor: background,
            ),
            const SizedBox(width: 10),
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
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // Panel Central: Descubrimiento y Contenido AMOLED
  // ===========================================================================
  Widget _buildMainPanel() {
    return Container(
      color: const Color(0xFF000000), // AMOLED
      child: _searchResults != null
          ? _buildSearchResultsPanel()
          : FutureBuilder<List<Track>>(
              future: _futureTracks,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFA855F7),
                      strokeWidth: 2,
                    ),
                  );
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return const Center(
                    child: Text('Error al cargar contenido',
                        style: TextStyle(color: Colors.white54)),
                  );
                }
                final tracks = snapshot.data!;
                return _mainContent(tracks);
              },
            ),
    );
  }

  Widget _buildSearchResultsPanel() {
    final results = _searchResults!;
    if (_searching && results.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFFA855F7),
          strokeWidth: 2,
        ),
      );
    }
    if (results.isEmpty) {
      return const Center(
        child: Text('Sin resultados para tu búsqueda',
            style: TextStyle(color: Colors.white54)),
      );
    }

    final songs = results.songs;
    final albums = results.albums;
    final artists = results.artists;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
                fallbackColor: const Color(0xFF141418),
              ),
              title: Text(track.title,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5)),
              subtitle: Text('${track.artist} · ${track.album}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.more_horiz, color: Colors.white54),
                    onPressed: () => TrackContextMenu.show(context, track),
                  ),
                  Text(
                    _formatDuration(track.duration),
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 11.5),
                  ),
                ],
              ),
              onTap: () {
                context
                    .read<PlayerController>()
                    .playQueue([track], startIndex: 0);
              },
            ),
        ],
        if (albums.isNotEmpty) ...[
          const SizedBox(height: 16),
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
                fallbackColor: const Color(0xFF141418),
              ),
              title: Text(album.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5)),
              subtitle: Text(album.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => AlbumDetailScreen(album: album)),
              ),
            ),
        ],
        if (artists.isNotEmpty) ...[
          const SizedBox(height: 16),
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
                fallbackColor: const Color(0xFF141418),
              ),
              title: Text(artist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5)),
              subtitle: const Text('Artista',
                  style: TextStyle(color: Colors.white54, fontSize: 11.5)),
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

  Widget _mainContent(List<Track> tracks) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _quickAccessGrid(tracks),
          const SizedBox(height: 28),
          _sectionHeader('Recomendados para ti'),
          const SizedBox(height: 14),
          _recommendedGrid(tracks),
          const SizedBox(height: 28),
          _sectionHeader('Álbumes destacados'),
          const SizedBox(height: 14),
          _albumsCarousel(),
          const SizedBox(height: 28),
          _sectionHeader('Artistas en tu biblioteca'),
          const SizedBox(height: 14),
          _artistsCarousel(),
          const SizedBox(height: 28),
          _sectionHeader('Escuchados recientemente'),
          const SizedBox(height: 12),
          _recentsList(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _openPlayer(List<Track> tracks, int index) {
    context.read<PlayerController>().playQueue(tracks, startIndex: index);
  }

  // Tarjetas de Acceso Rápido AMOLED
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
            childAspectRatio: 2.8,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: items.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _quickAccessCard(
                label: 'Tus Me Gusta',
                color: const Color(0xFF4C1D95),
                icon: Icons.favorite_rounded,
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
              color: const Color(0xFF14141A),
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
    required IconData icon,
    String? albumArtUrl,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0C0C10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF1E1E26), width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: double.infinity,
              decoration: BoxDecoration(
                color: color,
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(9)),
                image: albumArtUrl != null
                    ? DecorationImage(
                        image: NetworkImage(albumArtUrl),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: albumArtUrl == null
                  ? Icon(icon, color: Colors.white, size: 22)
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
        final cols = (constraints.maxWidth / 160).floor().clamp(3, 6);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            childAspectRatio: 0.74,
            crossAxisSpacing: 14,
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
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF07070A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF14141C)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: double.infinity,
                  color: const Color(0xFF14141A),
                  child: track.albumArtUrl != null
                      ? Image.network(
                          track.albumArtUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.music_note, color: Colors.white38),
                          ),
                        )
                      : const Center(
                          child: Icon(Icons.music_note, color: Colors.white38),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _albumsCarousel() {
    final nav = context.read<NavidromeService>();
    return FutureBuilder<List<Album>>(
      future: nav.getAlbums(),
      builder: (context, snapshot) {
        final albums = snapshot.data ?? [];
        if (snapshot.connectionState == ConnectionState.waiting &&
            albums.isEmpty) {
          return const SizedBox(
            height: 170,
            child: Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFFA855F7)),
            ),
          );
        }
        if (albums.isEmpty) {
          return const Text('Sin álbumes disponibles',
              style: TextStyle(color: Colors.white54));
        }
        return SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: albums.length,
            itemBuilder: (context, index) {
              final album = albums[index];
              return Padding(
                padding: const EdgeInsets.only(right: 14),
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => AlbumDetailScreen(album: album)),
                  ),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 130,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF07070A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF14141C)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              width: double.infinity,
                              color: const Color(0xFF14141A),
                              child: album.coverArtUrl != null
                                  ? Image.network(
                                      album.coverArtUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          const Center(
                                        child: Icon(Icons.album,
                                            color: Colors.white38, size: 28),
                                      ),
                                    )
                                  : const Center(
                                      child: Icon(Icons.album,
                                          color: Colors.white38, size: 28),
                                    ),
                            ),
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
            child: Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFFA855F7)),
            ),
          );
        }
        if (artists.isEmpty) {
          return const Text('Sin artistas',
              style: TextStyle(color: Colors.white54));
        }
        return SizedBox(
          height: 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: artists.length,
            itemBuilder: (context, index) {
              final artist = artists[index];
              return Padding(
                padding: const EdgeInsets.only(right: 14),
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ArtistScreen(artist: artist)),
                  ),
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 110,
                    child: Column(
                      children: [
                        Expanded(
                          child: Container(
                            width: 110,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF140E24),
                              border: Border.all(
                                color: const Color(0xFFA855F7)
                                    .withValues(alpha: 0.35),
                                width: 1.2,
                              ),
                              image: artist.coverArtUrl != null
                                  ? DecorationImage(
                                      image: NetworkImage(artist.coverArtUrl!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: artist.coverArtUrl == null
                                ? const Center(
                                    child: Icon(Icons.person,
                                        color: Colors.white38, size: 36),
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          artist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
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
    final player = context.watch<PlayerController>();
    final items = player.recentlyPlayed.take(6).toList();
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Todavía no has reproducido ninguna canción',
          style: TextStyle(color: Colors.white38, fontSize: 12.5),
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 40,
                    height: 40,
                    color: const Color(0xFF14141A),
                    child: track.albumArtUrl != null
                        ? Image.network(track.albumArtUrl!, fit: BoxFit.cover)
                        : const Icon(Icons.music_note,
                            color: Colors.white38, size: 20),
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
                            color: Colors.white54, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.play_circle_fill_rounded,
                      color: Color(0xFFA855F7), size: 28),
                  onPressed: () {
                    context.read<PlayerController>().playQueue([track], startIndex: 0);
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _formatDuration(String raw) {
    final s = int.tryParse(raw) ?? 0;
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFA855F7),
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
