import 'radio_podcasts_screen.dart';
import '../services/track_filters.dart';
import '../widgets/track_filter_bar.dart';
import '../utils/player_select.dart';
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
import '../widgets/offline_connection_banner.dart';
import 'liked_songs_screen.dart';
import 'playlist_detail_screen.dart';
import 'album_detail_screen.dart';
import 'artist_screen.dart';
import '../utils/app_visibility.dart';
import '../utils/app_colors.dart';
import '../utils/responsive.dart';
import '../widgets/now_playing_panel.dart';
import '../widgets/interactive_artist_text.dart';
import '../widgets/genre_selector.dart';
import '../widgets/tv_initial_focus.dart';
import '../widgets/discovery_section.dart';

part 'home_screen_library.dart';
part 'home_screen_content.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Estado compartido de la pantalla de inicio. Vive en una clase base para que
/// los paneles (en archivos aparte) puedan usarlo como mixins.
abstract class _HomeStateBase extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late Future<List<Track>> _futureTracks;
  late Future<List<Playlist>> _futurePlaylists;
  late Future<List<Album>> _futureAlbums;
  late Future<List<Artist>> _futureArtists;
  bool _libraryCollapsed = false;
  int _coverArtVersion = -1;
  int _playlistVersion = -1;
  String? _currentSessionKey;
  int _activeNavIndex = 0; // 0 = Inicio, 1 = Explorar

  final TextEditingController _searchController = TextEditingController();
  SearchResults? _searchResults;

  /// Orden y filtros locales de las canciones encontradas.
  TrackFilter _trackFilter = const TrackFilter();
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

  /// Búsqueda por género; la implementa `_HomeScreenState` y la usan los paneles.
  Future<void> _runGenreSearch(String genre);
}

class _HomeScreenState extends _HomeStateBase
    with _HomeLibraryPanel, _HomeMainContent {
  /// Por debajo de este ancho la biblioteca se colapsa sola.
  static const double _autoCollapseWidth = 900;

  Future<List<Artist>> _loadArtists(NavidromeService nav) =>
      nav.getArtists().then(
            (raw) => raw
                .map((e) => Artist.fromJson(e as Map<String, dynamic>))
                .toList(),
          );

  @override
  void initState() {
    super.initState();
    final nav = context.read<NavidromeService>();
    _currentSessionKey = nav.currentSessionKey;
    _homeNavigation = context.read<HomeNavigationController?>();
    _homeNavigation?.addListener(_openHomeDestination);
    _futureTracks = _loadTracks();
    _futurePlaylists = nav.getPlaylists();
    _futureAlbums = nav.getAlbums();
    _futureArtists = _loadArtists(nav);
    _futureGenres = nav.getGenres();
    _futureRecentlyAdded = nav.getRecentlyAddedTracks();
    _serverPlayCountTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (isAppVisible) _refreshServerPlayCounts();
      },
    );
    _hourlyRefreshTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) {
        if (!mounted) return;
        final svc = context.read<NavidromeService>();
        if (!svc.connected || svc.offlineMode) return;
        setState(() {
          _futureRecentlyAdded = svc.getRecentlyAddedTracks();
        });
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
    final nav = context.read<NavidromeService>();
    if (!nav.connected || nav.offlineMode) return;
    _refreshingPlayCounts = true;
    try {
      final tracks = await nav.getTracks();
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

  @override
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
      _futureAlbums = nav.getAlbums();
      _futureArtists = _loadArtists(nav);
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
          _futureAlbums = svc.getAlbums();
          _futureArtists = _loadArtists(svc);
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
                Expanded(
                    child: TvInitialFocus(
                        child: ConstrainedContent(child: _buildMainPanel()))),
                if (showSidePanel) const NowPlayingSidePanel(),
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
  Future<void> _shuffleAllTracks() async {
    try {
      final tracks = await _futureTracks;
      if (tracks.isNotEmpty && mounted) {
        await context.read<PlayerController>().playShuffledQueue(tracks);
      }
    } catch (_) {
      // Si ocurre un error al obtener las pistas, no interrumpir la interfaz.
    }
  }

  Widget _buildPersistentGlobalTopBar(NavidromeService nav) {
    return GlobalTopBar(
      searchController: _searchController,
      searching: _searching,
      activeNavIndex: _activeNavIndex,
      showBackButton: false,
      onSearch: _runSearch,
      onGenreSelected: _runGenreSearch,
      onShuffle: _shuffleAllTracks,
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
