import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../widgets/persistent_player_bar.dart';
import '../widgets/cover_art.dart';
import '../widgets/home_content_card.dart';
import '../widgets/create_playlist_dialog.dart';
import '../widgets/global_top_bar.dart';
import '../widgets/explore_tracks_view.dart';
import '../services/home_navigation_controller.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/local_download_button.dart';
import 'liked_songs_screen.dart';
import 'playlist_detail_screen.dart';
import 'album_detail_screen.dart';
import 'artist_screen.dart';
import '../utils/app_colors.dart';
import '../utils/responsive.dart';
import '../widgets/now_playing_panel.dart';
import '../widgets/interactive_artist_text.dart';
import '../widgets/genre_selector.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Por debajo de este ancho la biblioteca se colapsa sola.
  static const double _autoCollapseWidth = 900;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late Future<List<Track>> _futureTracks;
  late Future<List<Playlist>> _futurePlaylists;
  bool _libraryCollapsed = false;
  int _coverArtVersion = -1;
  int _playlistVersion = -1;
  String? _currentSessionKey;
  int _activeNavIndex = 0; // 0 = Inicio, 1 = Explorar

  final TextEditingController _searchController = TextEditingController();
  SearchResults? _searchResults;
  bool _searching = false;
  int _searchVersion = 0;
  HomeNavigationController? _homeNavigation;
  Timer? _serverPlayCountTimer;
  Timer? _hourlyRefreshTimer;
  bool _refreshingPlayCounts = false;
  final ScrollController _artistsScrollController = ScrollController();
  int _explorePageSize = 25;
  int _explorePage = 0;
  String? _selectedGenre;
  late Future<List<String>> _futureGenres;
  late Future<List<Track>> _futureRecentlyAdded;

  @override
  void initState() {
    super.initState();
    _currentSessionKey = context.read<NavidromeService>().currentSessionKey;
    _homeNavigation = context.read<HomeNavigationController?>();
    _homeNavigation?.addListener(_openHomeDestination);
    _futureTracks = _loadTracks();
    _futurePlaylists = context.read<NavidromeService>().getPlaylists();
    _futureGenres = context.read<NavidromeService>().getGenres();
    _futureRecentlyAdded =
        context.read<NavidromeService>().getRecentlyAddedTracks();
    _serverPlayCountTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshServerPlayCounts(),
    );
    _hourlyRefreshTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) {
        if (mounted) {
          setState(() {
            _futureRecentlyAdded =
                context.read<NavidromeService>().getRecentlyAddedTracks();
          });
        }
      },
    );
  }

  Future<List<Track>> _loadTracks() async {
    final tracks = await context.read<NavidromeService>().getTracks();
    if (mounted) {
      context.read<PlayerController>().syncServerPlayCounts(tracks);
    }
    return tracks;
  }

  Future<void> _refreshServerPlayCounts() async {
    if (_refreshingPlayCounts || !mounted) return;
    _refreshingPlayCounts = true;
    try {
      final tracks = await context.read<NavidromeService>().getTracks();
      if (mounted) {
        context.read<PlayerController>().syncServerPlayCounts(tracks);
      }
    } catch (_) {
      // La siguiente actualización periódica reintentará si no hay conexión.
    } finally {
      _refreshingPlayCounts = false;
    }
  }

  void _openHomeDestination() {
    final request = _homeNavigation!.value!;
    _searchController.text = request.query;
    setState(() => _activeNavIndex = request.explore ? 1 : 0);
    _runSearch(request.query);
  }

  Future<void> _runSearch(String query) async {
    final version = ++_searchVersion;
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
      if (mounted && version == _searchVersion) {
        setState(() {
          _searchResults = results;
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted && version == _searchVersion) {
        setState(() {
          _searchResults = null;
          _searching = false;
        });
      }
    }
  }

  Future<void> _runGenreSearch(String genre) async {
    final version = ++_searchVersion;
    setState(() {
      _searching = true;
      _searchController.text = genre;
    });
    try {
      final nav = context.read<NavidromeService>();
      unawaited(nav.saveLastSelectedGenre(genre));
      final tracks = await nav.searchByGenre(genre);
      if (mounted && version == _searchVersion) {
        setState(() {
          _searchResults = SearchResults(
            songs: tracks,
            albums: [],
            artists: [],
          );
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted && version == _searchVersion) {
        setState(() {
          _searchResults = SearchResults(songs: [], albums: [], artists: []);
          _searching = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _homeNavigation?.removeListener(_openHomeDestination);
    _serverPlayCountTimer?.cancel();
    _hourlyRefreshTimer?.cancel();
    _searchController.dispose();
    _artistsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavidromeService>();
    final sessionKey = nav.currentSessionKey;
    if (sessionKey != _currentSessionKey) {
      _currentSessionKey = sessionKey;
      _coverArtVersion = nav.coverArtVersion;
      _playlistVersion = nav.playlistVersion;
      _futureTracks = _loadTracks();
      _futurePlaylists = nav.getPlaylists();
      _futureGenres = nav.getGenres();
      _futureRecentlyAdded = nav.getRecentlyAddedTracks();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _searchController.clear();
        setState(() {
          _selectedGenre = null;
          _searchResults = null;
          _searching = false;
        });
      });
    }

    final version = nav.coverArtVersion;
    if (version != _coverArtVersion && _coverArtVersion >= 0) {
      _coverArtVersion = version;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          final svc = context.read<NavidromeService>();
          _futureTracks = _loadTracks();
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

    // Layout adaptativo: en ventanas estrechas la biblioteca se colapsa a una
    // barra de iconos (y se abre como cajón); en anchas aparece el panel
    // lateral "Escuchando ahora".
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < _autoCollapseWidth;
    final showSidePanel = width >= Responsive.sidePanelBreakpoint;
    final libraryWidth = (width * 0.22).clamp(230.0, 320.0).toDouble();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: context.bgApp, // Pure AMOLED Black
      drawer: narrow
          ? Drawer(
              width: 300,
              backgroundColor: context.bgSidebar,
              child: SafeArea(child: _buildLibraryPanel(width: 300)),
            )
          : null,
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
                (_libraryCollapsed || narrow)
                    ? _buildCollapsedLibraryPanel(openAsDrawer: narrow)
                    : _buildLibraryPanel(width: libraryWidth),
                Expanded(child: ConstrainedContent(child: _buildMainPanel())),
                if (showSidePanel) const NowPlayingSidePanel(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: PersistentPlayerBar(showQueue: !showSidePanel),
    );
  }

  // ===========================================================================
  // BARRA SUPERIOR PERSISTENTE (GLOBAL HEADER)
  // ===========================================================================
  Widget _buildPersistentGlobalTopBar(NavidromeService nav) {
    return GlobalTopBar(
      searchController: _searchController,
      searching: _searching,
      activeNavIndex: _activeNavIndex,
      showBackButton: false,
      onSearch: _runSearch,
      onGenreSelected: _runGenreSearch,
      onSearchCleared: () {
        if (!mounted) return;
        setState(() {
          _searchResults = null;
          _searching = false;
        });
      },
      onLogoTap: () {
        _searchVersion++;
        setState(() {
          _searchResults = null;
          _searchController.clear();
          _searching = false;
          _activeNavIndex = 0;
        });
      },
      onNavIndexChanged: (index) {
        _searchVersion++;
        setState(() {
          _searchResults = null;
          _searchController.clear();
          _searching = false;
          _activeNavIndex = index;
        });
      },
    );
  }

  // ===========================================================================
  // Panel Izquierdo: Tu Biblioteca
  // ===========================================================================
  Widget _buildCollapsedLibraryPanel({bool openAsDrawer = false}) {
    return Container(
      width: 68,
      color: context.bgSidebar,
      child: Column(
        children: [
          SizedBox(
            height: 54,
            child: IconButton(
              icon: Icon(Icons.library_music_rounded,
                  color: context.accent, size: 21),
              tooltip: 'Expandir biblioteca',
              onPressed: () {
                if (openAsDrawer) {
                  _scaffoldKey.currentState?.openDrawer();
                } else {
                  setState(() => _libraryCollapsed = false);
                }
              },
            ),
          ),
          Divider(height: 1, color: context.bgCard),
          Expanded(child: _collapsedLibraryList()),
        ],
      ),
    );
  }

  Widget _collapsedLibraryList() {
    final nav = context.watch<NavidromeService>();
    return FutureBuilder<List<Playlist>>(
      future: _futurePlaylists,
      builder: (context, snapshot) {
        final playlists = snapshot.data ?? [];
        // Fijadas primero.
        final sorted = [
          ...playlists.where((p) => nav.isPinnedPlaylist(p.id)),
          ...playlists.where((p) => !nav.isPinnedPlaylist(p.id)),
        ];
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 10),
          children: [
            Tooltip(
              message: 'Tus me gusta',
              child: IconButton(
                icon: Icon(Icons.favorite_rounded, color: context.accent2),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LikedSongsScreen()),
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final playlist in sorted)
              _collapsedPlaylistTile(
                playlist,
                nav.isPinnedPlaylist(playlist.id),
              ),
          ],
        );
      },
    );
  }

  Widget _collapsedPlaylistTile(Playlist playlist, bool pinned) {
    return Tooltip(
      message: playlist.name,
      child: Semantics(
        button: true,
        label: playlist.name,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PlaylistDetailScreen(playlist: playlist),
            ),
          ),
          onLongPress: () => _showPlaylistActions(playlist),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CoverArt(
                  url: playlist.coverArtUrl,
                  width: 40,
                  height: 40,
                  borderRadius: 6,
                  fallbackIcon: Icons.queue_music,
                  fallbackIconSize: 18,
                  fallbackColor: context.bgElevated,
                ),
                if (pinned)
                  Positioned(
                    top: -4,
                    right: -4,
                    child:
                        Icon(Icons.push_pin, color: context.accent, size: 12),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLibraryPanel({double width = 270}) {
    return Container(
      width: width,
      color: context.bgSidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _libraryHeader(),
          Divider(height: 1, color: context.bgCard),
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
          Icon(Icons.library_music_rounded, color: context.accent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Tu Biblioteca',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.add_rounded, color: context.accent, size: 21),
            tooltip: 'Crear playlist',
            onPressed: _createPlaylist,
          ),
          IconButton(
            icon: Icon(Icons.menu_open, color: context.textMuted, size: 18),
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
          color: context.bgApp,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.inputBorder),
        ),
        child: Row(
          children: [
            Icon(Icons.search, color: context.textMuted, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                style: TextStyle(color: context.textPrimary, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Buscar en playlists...',
                  hintStyle: TextStyle(color: context.textMuted, fontSize: 12),
                  isDense: true,
                  filled: false,
                  fillColor: Colors.transparent,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
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
        // Fijadas primero, luego el resto en el orden original.
        final sorted = [
          ...playlists.where((p) => nav.isPinnedPlaylist(p.id)),
          ...playlists.where((p) => !nav.isPinnedPlaylist(p.id)),
        ];
        final followedIds = nav.followedArtistIds;
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          children: [
            _libraryTile(
              icon: Icons.favorite_rounded,
              title: 'Tus me gusta',
              subtitle: 'Canciones favoritas',
              background: context.accent2,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LikedSongsScreen()),
              ),
            ),
            // Artistas seguidos (entre Me gusta y playlists)
            for (final artistId in followedIds)
              _followedArtistTile(artistId, nav),
            const SizedBox(height: 4),
            for (final playlist in sorted) ...[
              _playlistTile(playlist, nav.isPinnedPlaylist(playlist.id)),
            ],
          ],
        );
      },
    );
  }

  Widget _followedArtistTile(String artistId, NavidromeService nav) {
    final cached = nav.getCachedArtist(artistId);
    if (cached != null) {
      return _buildFollowedArtistItem(cached, nav);
    }

    return FutureBuilder<Artist?>(
      future: nav.getArtist(artistId),
      builder: (context, snap) {
        final artist = snap.data;
        if (artist != null) {
          return _buildFollowedArtistItem(artist, nav);
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
          child: Row(
            children: [
              CoverArt(
                url: null,
                width: 40,
                height: 40,
                borderRadius: 20,
                circle: true,
                fallbackIcon: Icons.person,
                fallbackIconSize: 18,
                fallbackColor: context.bgElevated,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      snap.connectionState == ConnectionState.waiting
                          ? 'Cargando artista...'
                          : 'Artista',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      'Artista · Siguiendo',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: context.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Icon(Icons.person_rounded, color: context.accent, size: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFollowedArtistItem(Artist artist, NavidromeService nav) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ArtistScreen(artist: artist),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        child: Row(
          children: [
            CoverArt(
              url: artist.coverArtUrl,
              width: 40,
              height: 40,
              borderRadius: 20,
              circle: true,
              fallbackIcon: Icons.person,
              fallbackIconSize: 18,
              fallbackColor: context.bgElevated,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    'Artista · Siguiendo',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            Icon(Icons.person_rounded, color: context.accent, size: 16),
          ],
        ),
      ),
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
              fallbackColor: context.bgElevated,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (pinned) ...[
                        Icon(Icons.push_pin, color: context.accent, size: 12),
                        const SizedBox(width: 3),
                      ],
                      Expanded(
                        child: Text(
                          playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.textPrimary,
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
                    style: TextStyle(color: context.textMuted, fontSize: 11),
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
      backgroundColor: context.bgApp,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.play_arrow, color: context.textPrimary),
              title: Text('Reproducir',
                  style: TextStyle(color: context.textPrimary)),
              onTap: () {
                Navigator.of(context).pop();
                _playPlaylist(playlist);
              },
            ),
            ListTile(
              leading: Icon(Icons.shuffle, color: context.accent),
              title: Text('Reproducir al azar',
                  style: TextStyle(color: context.textPrimary)),
              onTap: () {
                Navigator.of(context).pop();
                _playPlaylistShuffled(playlist);
              },
            ),
            ListTile(
              leading: Icon(
                pinned ? Icons.push_pin_outlined : Icons.push_pin,
                color: context.textPrimary,
              ),
              title: Text(
                pinned ? 'Quitar de arriba' : 'Fijar arriba',
                style: TextStyle(color: context.textPrimary),
              ),
              onTap: () {
                Navigator.of(context).pop();
                nav.togglePinPlaylist(playlist.id);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: context.danger),
              title: Text('Eliminar playlist',
                  style: TextStyle(color: context.danger)),
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

  Future<void> _playPlaylist(Playlist playlist) async {
    final tracks =
        await context.read<NavidromeService>().getPlaylistTracks(playlist.id);
    if (mounted && tracks.isNotEmpty) {
      context.read<PlayerController>().playQueue(
            tracks,
            startIndex: 0,
            sourcePlaylist: playlist,
          );
    }
  }

  Future<void> _playPlaylistShuffled(Playlist playlist) async {
    final tracks =
        await context.read<NavidromeService>().getPlaylistTracks(playlist.id);
    if (mounted && tracks.isNotEmpty) {
      final player = context.read<PlayerController>();
      await player.playShuffledQueue(tracks, sourcePlaylist: playlist);
    }
  }

  Future<void> _createPlaylist() async {
    final playlist = await showCreatePlaylistDialog(context);
    if (playlist == null || !mounted) return;
    setState(() {
      _futurePlaylists = context.read<NavidromeService>().getPlaylists();
    });
  }

  Future<void> _confirmDeletePlaylist(Playlist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bgCard,
        title: Text('¿Eliminar playlist?',
            style: TextStyle(color: context.textPrimary)),
        content: Text(
          'Se borrará "${playlist.name}" permanentemente.',
          style: TextStyle(color: context.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancelar',
                style: TextStyle(color: context.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Eliminar', style: TextStyle(color: context.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    final nav = context.read<NavidromeService>();
    try {
      await nav.deletePlaylist(playlist.id);
      nav.bumpPlaylists();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Playlist eliminada',
              style: TextStyle(color: context.textPrimary)),
          backgroundColor: context.bgElevated,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e', style: TextStyle(color: context.danger)),
          backgroundColor: context.bgElevated,
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
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.textMuted, fontSize: 11),
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
    // Los chips de género solo aparecen al buscar o explorar.
    final showGenres = _searchResults != null || _activeNavIndex == 1;
    final body = _searchResults != null
        ? _buildSearchResultsPanel()
        : FutureBuilder<List<Track>>(
            future: _futureTracks,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                  child: CircularProgressIndicator(
                    color: context.accent,
                    strokeWidth: 2,
                  ),
                );
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return Center(
                  child: Text('Error al cargar contenido',
                      style: TextStyle(color: context.textMuted)),
                );
              }
              final tracks = snapshot.data!;
              return _activeNavIndex == 1
                  ? _buildExploreContent(tracks)
                  : _mainContent(tracks);
            },
          );
    return Container(
      color: context.bgApp, // AMOLED
      child: showGenres
          ? Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: _genreSelector(),
                ),
                Expanded(child: body),
              ],
            )
          : body,
    );
  }

  Widget _buildSearchResultsPanel() {
    final results = _searchResults!;
    if (_searching && results.isEmpty) {
      return Center(
        child: CircularProgressIndicator(
          color: context.accent,
          strokeWidth: 2,
        ),
      );
    }
    if (results.isEmpty) {
      return Center(
        child: Text('Sin resultados para tu búsqueda',
            style: TextStyle(color: context.textMuted)),
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
                artist: track.artist,
                album: track.album,
                title: track.title,
                width: 40,
                height: 40,
                borderRadius: 4,
                fallbackIcon: Icons.music_note,
                fallbackIconSize: 20,
                fallbackColor: context.bgCard,
              ),
              title: Text(track.title,
                  style: TextStyle(color: context.textPrimary, fontSize: 13.5)),
              subtitle: Text('${track.artist} · ${track.album}',
                  style: TextStyle(color: context.textMuted, fontSize: 11.5)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LocalDownloadButton(tracks: [track], compact: true),
                  IconButton(
                    icon: Icon(Icons.more_horiz, color: context.textMuted),
                    onPressed: () => TrackContextMenu.show(context, track),
                  ),
                  Text(
                    _formatDuration(track.duration),
                    style: TextStyle(color: context.textMuted, fontSize: 11.5),
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
                fallbackColor: context.bgCard,
              ),
              title: Text(album.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.textPrimary, fontSize: 13.5)),
              subtitle: InteractiveArtistText(
                  artistString: album.artist,
                  fontSize: 11.5,
                  color: context.textMuted),
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
                fallbackColor: context.bgCard,
              ),
              title: Text(artist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.textPrimary, fontSize: 13.5)),
              subtitle: Text('Artista',
                  style: TextStyle(color: context.textMuted, fontSize: 11.5)),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ArtistScreen(artist: artist)),
              ),
            ),
        ],
      ],
    );
  }

  double _metadataExtraHeight() {
    final scaler = MediaQuery.textScalerOf(context);
    return (scaler.scale(14) - 14).clamp(0.0, double.infinity) * 3;
  }

  Widget _mainContent(List<Track> tracks) {
    // Los géneros solo se muestran al buscar o explorar, no en Inicio.
    final filteredTracks = tracks;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _quickAccessGrid(),
          const SizedBox(height: 32),
          _sectionHeader(
            'Recientemente añadidos',
            onReload: () => setState(() {
              _futureRecentlyAdded =
                  context.read<NavidromeService>().getRecentlyAddedTracks();
            }),
          ),
          const SizedBox(height: 12),
          _recentlyAddedSection(),
          const SizedBox(height: 32),
          _sectionHeader('Recomendados para ti'),
          const SizedBox(height: 12),
          _recommendedGrid(filteredTracks, context.watch<PlayerController>()),
          const SizedBox(height: 32),
          _sectionHeader('Álbumes destacados'),
          const SizedBox(height: 12),
          _albumsCarousel(),
          const SizedBox(height: 32),
          _sectionHeader('Artistas en tu biblioteca'),
          const SizedBox(height: 12),
          _artistsCarousel(),
          const SizedBox(height: 32),
          _sectionHeader('Escuchados recientemente'),
          const SizedBox(height: 12),
          _recentsList(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildExploreContent(List<Track> allTracks) {
    final tracks = _selectedGenre == null
        ? allTracks
        : context
            .read<NavidromeService>()
            .filterByGenre(allTracks, _selectedGenre!);
    return ExploreTracksView(
      tracks: tracks,
      pageSize: _explorePageSize,
      page: _explorePage,
      onPageSizeChanged: (size) => setState(() {
        _explorePageSize = size;
        _explorePage = 0;
      }),
      onPageChanged: (page) => setState(() => _explorePage = page),
      onPlay: (index) => _openPlayer(tracks, index),
    );
  }

  void _openPlayer(List<Track> tracks, int index) {
    context.read<PlayerController>().playQueue(tracks, startIndex: index);
  }

  // Tarjetas de Acceso Rápido AMOLED
  Widget _quickAccessGrid() {
    // Orden fijo: favoritos, la playlist más reproducida y cuatro canciones.
    final mostPlayed = context.watch<PlayerController>().mostPlayed;
    MostPlayedItem? topPlaylist;
    final topTracks = <MostPlayedItem>[];
    for (final item in mostPlayed) {
      if (item.type == MostPlayedItemType.playlist && topPlaylist == null) {
        topPlaylist = item;
      } else if (item.type == MostPlayedItemType.track &&
          topTracks.length < 4) {
        topTracks.add(item);
      }
    }
    final items = <MostPlayedItem>[
      if (topPlaylist != null) topPlaylist,
      ...topTracks,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = (constraints.maxWidth / 220).floor().clamp(2, 3);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            // Conserva el bloque compacto y reserva espacio para dos líneas.
            mainAxisExtent: 52 + _metadataExtraHeight(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 8,
          ),
          itemCount: items.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _quickAccessCard(
                label: 'Tus Me Gusta',
                color: context.accent2,
                icon: Icons.favorite_rounded,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LikedSongsScreen()),
                ),
              );
            }
            final item = items[index - 1];
            if (item.type == MostPlayedItemType.playlist) {
              final playlist = item.playlist!;
              return _quickAccessCard(
                label: playlist.name,
                color: context.accent2,
                albumArtUrl: playlist.coverArtUrl,
                icon: Icons.queue_music,
                onTap: () => _playPlaylist(playlist),
              );
            }

            final track = item.track!;
            return _quickAccessCard(
              label: track.title,
              color: context.bgCard,
              albumArtUrl: track.albumArtUrl,
              artist: track.artist,
              album: track.album,
              title: track.title,
              icon: Icons.music_note,
              onTap: () => context
                  .read<PlayerController>()
                  .playQueue([track], startIndex: 0),
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
    String? artist,
    String? album,
    String? title,
    required VoidCallback onTap,
  }) {
    return HomeContentCard(
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: double.infinity,
            child: CoverArt(
              url: albumArtUrl,
              artist: artist,
              album: album,
              title: title,
              width: 52,
              borderRadius: 9,
              fallbackIcon: icon,
              fallbackIconSize: 22,
              fallbackColor: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _genreSelector() {
    return FutureBuilder<List<String>>(
      future: _futureGenres,
      builder: (context, snapshot) {
        final genres = snapshot.data ?? const <String>[];
        if (genres.isEmpty) return const SizedBox.shrink();
        return GenreSelector(
          genres: genres,
          selectedGenre: _selectedGenre,
          onGenreChanged: (genre) {
            setState(() {
              _selectedGenre = genre;
              _explorePage = 0;
            });
            if (genre != null) {
              unawaited(context
                  .read<NavidromeService>()
                  .saveLastSelectedGenre(genre));
              // En una búsqueda activa, el género lanza la búsqueda por género.
              if (_searchResults != null) unawaited(_runGenreSearch(genre));
            }
          },
        );
      },
    );
  }

  Widget _recentlyAddedSection() {
    return FutureBuilder<List<Track>>(
      future: _futureRecentlyAdded,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: 180 + _metadataExtraHeight(),
            child: Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: context.accent),
            ),
          );
        }
        final tracks = snapshot.data ?? const <Track>[];
        if (tracks.isEmpty) {
          final isOffline = !context.read<NavidromeService>().connected;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  isOffline
                      ? Icons.cloud_off_rounded
                      : Icons.info_outline_rounded,
                  color: context.textSecondary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isOffline
                        ? 'Sin conexión para sincronizar novedades del servidor.'
                        : 'No hay contenido añadido recientemente.',
                    style:
                        TextStyle(color: context.textSecondary, fontSize: 13),
                  ),
                ),
              ],
            ),
          );
        }
        return _recommendedGrid(tracks, context.watch<PlayerController>());
      },
    );
  }

  Widget _sectionHeader(String title, {VoidCallback? onReload}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: context.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (onReload != null)
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: 'Recargar $title',
            onPressed: onReload,
            color: context.textSecondary,
          ),
      ],
    );
  }

  Widget _recommendedGrid(List<Track> tracks, PlayerController player) {
    // Calcular peso de artistas basado en reproducciones
    final artistScores = <String, int>{};
    for (final item in player.mostPlayed) {
      if (item.type == MostPlayedItemType.track && item.track != null) {
        final artist = item.track!.artist;
        artistScores[artist] = (artistScores[artist] ?? 0) + item.playCount;
      }
    }

    // Ordenar tracks basado en el artista más escuchado
    final sortedTracks = List<Track>.from(tracks);
    sortedTracks.sort((a, b) {
      final scoreA = artistScores[a.artist] ?? 0;
      final scoreB = artistScores[b.artist] ?? 0;
      return scoreB.compareTo(scoreA);
    });

    final items = sortedTracks.take(10).toList();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // Conserva las tarjetas compactas y amplía solo el espacio de texto.
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 130,
        mainAxisExtent: 180 + _metadataExtraHeight(),
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final track = items[index];
        return _recommendedCard(track, tracks);
      },
    );
  }

  Widget _recommendedCard(Track track, List<Track> allTracks) {
    return HomeContentCard(
      onTap: () => _openPlayer(allTracks, allTracks.indexOf(track)),
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CoverArt(
                  url: track.albumArtUrl,
                  artist: track.artist,
                  album: track.album,
                  title: track.title,
                  borderRadius: 0,
                  fallbackIcon: Icons.music_note,
                  fallbackColor: context.bgCard,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            InteractiveArtistText(
              artistString: track.artist,
              fontSize: 12,
              color: context.textSecondary,
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
          return SizedBox(
            height: 170,
            child: Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: context.accent),
            ),
          );
        }
        if (albums.isEmpty) {
          return Text('Sin álbumes disponibles',
              style: TextStyle(color: context.textSecondary));
        }
        return SizedBox(
          height: 180 + _metadataExtraHeight(),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: albums.length,
            itemBuilder: (context, index) {
              final album = albums[index];
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: HomeContentCard(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => AlbumDetailScreen(album: album)),
                  ),
                  child: Container(
                    width: 130,
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              width: double.infinity,
                              color: context.bgCard,
                              child: album.coverArtUrl != null
                                  ? Image.network(
                                      album.coverArtUrl!,
                                      fit: BoxFit.cover,
                                      cacheWidth: 400,
                                      errorBuilder: (_, __, ___) => Center(
                                        child: Icon(Icons.album,
                                            color: context.textSecondary,
                                            size: 28),
                                      ),
                                    )
                                  : Center(
                                      child: Icon(Icons.album,
                                          color: context.textSecondary,
                                          size: 28),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          album.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        InteractiveArtistText(
                          artistString: album.artist,
                          fontSize: 12,
                          color: context.textSecondary,
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
          return SizedBox(
            height: 160,
            child: Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: context.accent),
            ),
          );
        }
        if (artists.isEmpty) {
          return Text('Sin artistas',
              style: TextStyle(color: context.textSecondary));
        }
        final showScrollbar = artists.length > 10;
        return SizedBox(
          height: (showScrollbar ? 180 : 160) + _metadataExtraHeight(),
          child: Scrollbar(
            controller: _artistsScrollController,
            thumbVisibility: showScrollbar,
            interactive: showScrollbar,
            scrollbarOrientation: ScrollbarOrientation.bottom,
            child: ListView.builder(
              controller: _artistsScrollController,
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.only(bottom: showScrollbar ? 20 : 0),
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
                                color: context.bgElevated,
                                border: Border.all(
                                  color: context.accent.withValues(alpha: 0.35),
                                  width: 1.2,
                                ),
                                image: artist.coverArtUrl != null
                                    ? DecorationImage(
                                        image: ResizeImage(
                                          NetworkImage(artist.coverArtUrl!),
                                          width: 400,
                                        ),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: artist.coverArtUrl == null
                                  ? Center(
                                      child: Icon(Icons.person,
                                          color: context.textSecondary,
                                          size: 36),
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            artist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: context.textPrimary,
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
          ),
        );
      },
    );
  }

  Widget _recentsList() {
    final player = context.watch<PlayerController>();
    final items = player.recentlyPlayed.take(6).toList();
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Todavía no has reproducido ninguna canción',
          style: TextStyle(color: context.textSecondary, fontSize: 12.5),
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
                CoverArt(
                  url: track.albumArtUrl,
                  artist: track.artist,
                  album: track.album,
                  title: track.title,
                  width: 40,
                  height: 40,
                  borderRadius: 6,
                  fallbackIcon: Icons.music_note,
                  fallbackIconSize: 20,
                  fallbackColor: context.bgCard,
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
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      InteractiveArtistText(
                        artistString: track.artist,
                        fontSize: 11.5,
                        color: context.textSecondary,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.play_circle_fill_rounded,
                      color: context.accent, size: 28),
                  onPressed: () {
                    context
                        .read<PlayerController>()
                        .playQueue([track], startIndex: 0);
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
        style: TextStyle(
          color: context.accent,
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
