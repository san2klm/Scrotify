import '../services/track_filters.dart';
import '../widgets/track_filter_bar.dart';
import '../utils/player_select.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../services/secure_storage.dart';
import '../widgets/persistent_player_bar.dart';
import '../widgets/cover_art.dart';
import '../widgets/home_content_card.dart';
import '../widgets/account_menu_button.dart';
import '../widgets/genre_selector.dart';
import '../widgets/create_playlist_dialog.dart';
import '../widgets/search_explore_field.dart';
import '../widgets/explore_tracks_view.dart';
import '../services/home_navigation_controller.dart';
import '../widgets/pairing_panel.dart';
import '../widgets/server_activity_panel.dart';
import '../widgets/interactive_artist_text.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/local_download_button.dart';
import '../widgets/offline_connection_banner.dart';
import 'liked_songs_screen.dart';
import 'playlist_detail_screen.dart';
import 'album_detail_screen.dart';
import 'artist_screen.dart';
import 'settings_screen.dart';
import '../utils/app_visibility.dart';
import '../utils/app_colors.dart';
import '../widgets/quick_actions_row.dart';

part 'mobile_home_tab.dart';
part 'mobile_search_library_tabs.dart';

/// Interfaz móvil de Scrotify (estilo Spotify AMOLED).
/// Diseñada exclusivamente para pantallas táctiles de teléfonos.
class MobileHomeScreen extends StatefulWidget {
  const MobileHomeScreen({super.key});

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

enum _HomeFilter { todo, musica, podcasts }

/// Estado de [MobileHomeScreen]. Vive en una clase base para que las pestañas (en
/// archivos aparte) puedan ser mixins sobre el mismo estado.
abstract class _MobileHomeBase extends State<MobileHomeScreen> {
  int _tabIndex = 0; // 0 = Inicio, 1 = Búsqueda, 2 = Biblioteca

  _HomeFilter _filter = _HomeFilter.todo;

  late Future<List<Track>> _futureTracks;

  late Future<List<Playlist>> _futurePlaylists;

  late Future<List<Track>> _futureRecentlyAdded;

  int _coverArtVersion = -1;

  int _playlistVersion = -1;

  String? _currentSessionKey;

  final TextEditingController _searchController = TextEditingController();

  SearchResults? _searchResults;

  /// Orden y filtros locales de las canciones encontradas.
  TrackFilter _trackFilter = const TrackFilter();

  bool _searching = false;

  int _searchVersion = 0;

  bool _showExplore = false;

  int _explorePageSize = 25;

  int _explorePage = 0;

  HomeNavigationController? _homeNavigation;

  String? _selectedGenre;

  late Future<List<String>> _futureGenres;

  Timer? _serverPlayCountTimer;

  Timer? _hourlyRefreshTimer;

  bool _refreshingPlayCounts = false;

  final ScrollController _artistsScrollController = ScrollController();

  Future<void> _createPlaylist();
  Widget _genreSelector();
  void _openExplore();
  void _openPlayer(List<Track> tracks, int index);
  Future<void> _playPlaylist(Playlist playlist);
  Future<void> _runGenreSearch(String genre);
  Future<void> _runSearch(String query);
}

class _MobileHomeScreenState extends _MobileHomeBase
    with _MobileHomeTab, _MobileSearchLibraryTabs {
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
      (_) {
        if (isAppVisible) _refreshServerPlayCounts();
      },
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

  @override
  void _openPlayer(List<Track> tracks, int index) {
    context.read<PlayerController>().playQueue(tracks, startIndex: index);
  }

  @override
  Future<void> _playPlaylist(Playlist playlist) async {
    final tracks =
        await context.read<NavidromeService>().getPlaylistTracks(playlist.id);
    if (!mounted || tracks.isEmpty) return;
    unawaited(context.read<PlayerController>().playQueue(
          tracks,
          startIndex: 0,
          sourcePlaylist: playlist,
        ));
  }

  @override
  Future<void> _createPlaylist() async {
    final playlist = await showCreatePlaylistDialog(context);
    if (playlist == null || !mounted) return;
    setState(() {
      _futurePlaylists = context.read<NavidromeService>().getPlaylists();
    });
  }

  void _openHomeDestination() {
    final request = _homeNavigation!.value!;
    _searchController.text = request.query;
    _runSearch(request.query);
    setState(() {
      _tabIndex = request.explore || request.query.isNotEmpty ? 1 : 0;
      _showExplore = request.explore;
    });
  }

  @override
  void _openExplore() {
    _searchController.clear();
    _runSearch('');
    setState(() => _showExplore = true);
  }

  @override
  Future<void> _runSearch(String query) async {
    final version = ++_searchVersion;
    _showExplore = false;
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
    _showExplore = false;
    setState(() {
      _searching = true;
      _searchController.text = genre;
      _tabIndex = 1;
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

  void _openPairingModal({bool autoOpenScanner = false}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.bgApp,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: context.bgElevated, width: 1.2),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 18,
          right: 18,
          top: 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: context.themeBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.qr_code_2_rounded,
                      color: context.accent, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Vincular con tu PC',
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Cerrar',
                    icon: Icon(Icons.close, color: context.textMuted, size: 20),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              PairingJoinPanel(
                autoOpenScanner: autoOpenScanner,
                onCredentialsReceived: (creds) async {
                  Navigator.of(ctx).pop();
                  final nav = context.read<NavidromeService>();
                  await nav.connectByUrl(
                      creds.url, creds.username, creds.password);
                  await SecureStorage.saveCredentials(
                    serverUrl: creds.url,
                    username: creds.username,
                    password: creds.password,
                  );
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
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
          _showExplore = false;
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

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: context.bgApp, // Pure AMOLED Black
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ---------------------------------------------------------------
            // 1. BARRA SUPERIOR PERSISTENTE EN MÓVIL
            // ---------------------------------------------------------------
            _buildPersistentMobileHeader(nav),

            // ---------------------------------------------------------------
            // 2. CUERPO DE LAS PESTAÑAS (HACE SCROLL DEBAJO DE LA BARRA)
            // ---------------------------------------------------------------
            Expanded(
              child: IndexedStack(
                index: _tabIndex,
                // Las pestañas ocultas no deben animar: sin TickerMode seguían
                // consumiendo fotogramas (p. ej. el pulso de la waveform).
                children: [
                  TickerMode(enabled: _tabIndex == 0, child: _buildHomeTab()),
                  TickerMode(enabled: _tabIndex == 1, child: _buildSearchTab()),
                  TickerMode(
                      enabled: _tabIndex == 2, child: _buildLibraryTab()),
                ],
              ),
            ),
          ],
        ),
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

  // ===========================================================================
  // BARRA SUPERIOR PERSISTENTE MÓVIL (HEADER FIJO)
  // ===========================================================================
  Widget _buildPersistentMobileHeader(NavidromeService nav) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      decoration: BoxDecoration(
        color: context.bgApp,
        border: Border(
          bottom: BorderSide(color: context.bgCard, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const AccountMenuButton(),
              const SizedBox(width: 10),

              // Título según pestaña
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tabIndex == 0
                          ? 'Inicio'
                          : _tabIndex == 1
                              ? 'Buscar'
                              : 'Tu Biblioteca',
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      nav.serverUrl != null
                          ? Uri.tryParse(nav.serverUrl!)?.host ?? nav.serverUrl!
                          : 'Navidrome',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.accent,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Botón Comunidad & Chat del Servidor
              IconButton(
                tooltip: 'Comunidad del Servidor',
                icon: Icon(Icons.people_alt_outlined,
                    color: context.accent, size: 21),
                onPressed: () => ServerActivityPanel.show(context),
              ),

              // Botón rápido Vincular PC
              IconButton(
                tooltip: 'Vincular con PC',
                icon: Icon(Icons.qr_code_2_rounded,
                    color: context.accent, size: 22),
                onPressed: () => _openPairingModal(autoOpenScanner: true),
              ),

              // Botón Ajustes
              IconButton(
                tooltip: 'Ajustes',
                icon: Icon(Icons.settings_outlined,
                    color: context.textSecondary, size: 20),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
            ],
          ),

          // Píldoras de filtro en el Home
          if (_tabIndex == 0) ...[
            const SizedBox(height: 8),
            _filterPills(),
          ],
        ],
      ),
    );
  }

  // ===========================================================================
  // Barra Inferior de Navegación Móvil AMOLED
  // ===========================================================================
  Widget _buildNavBar() {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: context.bgSidebar,
        border: Border(top: BorderSide(color: context.bgCard, width: 1)),
      ),
      child: Row(
        children: [
          _navItem(Icons.home_rounded, 'Inicio', 0),
          _navItem(Icons.search_rounded, 'Buscar', 1),
          _navItem(Icons.library_music_rounded, 'Biblioteca', 2),
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
              decoration: BoxDecoration(
                color: selected ? context.sidebarActiveBg : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: selected ? context.sidebarActiveText : context.textMuted,
                size: 22,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? context.sidebarActiveText : context.textMuted,
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
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
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Text(
        title,
        style: TextStyle(
          color: context.accent,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
