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
import 'liked_songs_screen.dart';
import 'playlist_detail_screen.dart';
import 'album_detail_screen.dart';
import 'artist_screen.dart';
import 'settings_screen.dart';
import '../utils/app_colors.dart';
import '../widgets/quick_actions_row.dart';

/// Interfaz móvil de Scrotify (estilo Spotify AMOLED).
/// Diseñada exclusivamente para pantallas táctiles de teléfonos.
class MobileHomeScreen extends StatefulWidget {
  const MobileHomeScreen({super.key});

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

enum _HomeFilter { todo, musica, podcasts }

class _MobileHomeScreenState extends State<MobileHomeScreen> {
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

  void _openPlayer(List<Track> tracks, int index) {
    context.read<PlayerController>().playQueue(tracks, startIndex: index);
  }

  Future<void> _playPlaylist(Playlist playlist) async {
    final tracks =
        await context.read<NavidromeService>().getPlaylistTracks(playlist.id);
    if (!mounted || tracks.isEmpty) return;
    context.read<PlayerController>().playQueue(
          tracks,
          startIndex: 0,
          sourcePlaylist: playlist,
        );
  }

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

  void _openExplore() {
    _searchController.clear();
    _runSearch('');
    setState(() => _showExplore = true);
  }

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
                children: [
                  _buildHomeTab(),
                  _buildSearchTab(),
                  _buildLibraryTab(),
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

  Widget _filterPills() {
    return SizedBox(
      height: 48 +
          (MediaQuery.textScalerOf(context).scale(13) - 13)
              .clamp(0.0, double.infinity),
      child: ListView(
        scrollDirection: Axis.horizontal,
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
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => setState(() => _filter = value),
        selectedColor: context.sidebarActiveBg,
        backgroundColor: context.bgCard,
        labelStyle: TextStyle(
          color: selected ? context.sidebarActiveText : context.textSecondary,
          fontSize: 13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
        side:
            BorderSide(color: selected ? context.accent : context.borderSubtle),
        shape: const StadiumBorder(),
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
            setState(() => _selectedGenre = genre);
            if (genre != null) {
              unawaited(context
                  .read<NavidromeService>()
                  .saveLastSelectedGenre(genre));
            }
          },
        );
      },
    );
  }

  // ===========================================================================
  // Pestaña Inicio (Mobile)
  // ===========================================================================
  double _metadataExtraHeight() {
    final scaler = MediaQuery.textScalerOf(context);
    return (scaler.scale(14) - 14).clamp(0.0, double.infinity) * 3;
  }

  Widget _buildHomeTab() {
    return FutureBuilder<List<Track>>(
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
            child: Text(
              'Sin contenido disponible',
              style: TextStyle(color: context.textSecondary),
            ),
          );
        }
        final tracks = snapshot.data!;
        final filteredTracks = _selectedGenre == null
            ? tracks
            : context
                .read<NavidromeService>()
                .filterByGenre(tracks, _selectedGenre!);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _genreSelector(),
              const SizedBox(height: 12),
              QuickActionsRow(tracks: filteredTracks),
              const SizedBox(height: 16),
              _quickAccessGrid(),
              const SizedBox(height: 24),
              _sectionHeader(
                'Recientemente añadidos',
                onReload: () => setState(() {
                  _futureRecentlyAdded =
                      context.read<NavidromeService>().getRecentlyAddedTracks();
                }),
              ),
              const SizedBox(height: 12),
              _recentlyAddedCarousel(),
              const SizedBox(height: 24),
              _sectionHeader('Recomendados para ti'),
              const SizedBox(height: 12),
              _carousel(filteredTracks),
              const SizedBox(height: 24),
              _sectionHeader('Álbumes'),
              const SizedBox(height: 12),
              _albumsCarousel(),
              const SizedBox(height: 24),
              _sectionHeader('Artistas'),
              const SizedBox(height: 12),
              _artistsCarousel(),
              const SizedBox(height: 24),
              _sectionHeader('Escuchados recientemente'),
              const SizedBox(height: 8),
              _recentsList(),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _quickAccessGrid() {
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
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisExtent: 64 + _metadataExtraHeight(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 8,
      children: [
        _quickAccessCard(
          label: 'Tus Me Gusta',
          color: context.accent2,
          icon: Icons.favorite_rounded,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LikedSongsScreen()),
          ),
        ),
        for (final item in items)
          if (item.type == MostPlayedItemType.playlist)
            _quickAccessCard(
              label: item.playlist!.name,
              color: context.accent2,
              albumArtUrl: item.playlist!.coverArtUrl,
              icon: Icons.queue_music,
              onTap: () => _playPlaylist(item.playlist!),
            )
          else
            _quickAccessCard(
              label: item.track!.title,
              color: context.bgCard,
              albumArtUrl: item.track!.albumArtUrl,
              artist: item.track!.artist,
              album: item.track!.album,
              title: item.track!.title,
              icon: Icons.music_note,
              onTap: () => context
                  .read<PlayerController>()
                  .playQueue([item.track!], startIndex: 0),
            ),
      ],
    );
  }

  Widget _quickAccessCard({
    required String label,
    required Color color,
    IconData? icon,
    String? albumArtUrl,
    String? artist,
    String? album,
    String? title,
    VoidCallback? onTap,
  }) {
    return HomeContentCard(
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: double.infinity,
            child: CoverArt(
              url: albumArtUrl,
              artist: artist,
              album: album,
              title: title,
              width: 44,
              borderRadius: 7,
              fallbackIcon: icon ?? Icons.music_note,
              fallbackIconSize: 20,
              fallbackColor: color,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, {VoidCallback? onReload}) {
    if (onReload == null) {
      return Text(
        title,
        style: TextStyle(
          color: context.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      );
    }
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
        IconButton(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: const Icon(Icons.refresh_rounded, size: 20),
          tooltip: 'Recargar $title',
          onPressed: onReload,
          color: context.textSecondary,
        ),
      ],
    );
  }

  Widget _recentlyAddedCarousel() {
    return FutureBuilder<List<Track>>(
      future: _futureRecentlyAdded,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: 196 + _metadataExtraHeight(),
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
        return _carousel(tracks);
      },
    );
  }

  Widget _carousel(List<Track> tracks) {
    final items = tracks.take(8).toList();
    return SizedBox(
      height: 196 + _metadataExtraHeight(),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        itemBuilder: (context, index) {
          final track = items[index];
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: HomeContentCard(
              onTap: () => _openPlayer(tracks, tracks.indexOf(track)),
              onLongPress: () => TrackContextMenu.show(context, track),
              child: Container(
                width: 145,
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
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
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: context.textSecondary, fontSize: 12),
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

  Widget _albumsCarousel() {
    final nav = context.read<NavidromeService>();
    return FutureBuilder<List<Album>>(
      future: nav.getAlbums(),
      builder: (context, snapshot) {
        final albums = snapshot.data ?? [];
        if (snapshot.connectionState == ConnectionState.waiting &&
            albums.isEmpty) {
          return SizedBox(
            height: 160,
            child: Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: context.accent),
            ),
          );
        }
        if (albums.isEmpty) {
          return Text('Sin álbumes',
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
                padding: const EdgeInsets.only(right: 12),
                child: HomeContentCard(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => AlbumDetailScreen(album: album)),
                  ),
                  child: Container(
                    width: 120,
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
                                    )
                                  : Icon(Icons.album,
                                      color: context.textSecondary),
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
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          album.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: context.textSecondary, fontSize: 12),
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
            height: 140,
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
          height: (showScrollbar ? 165 : 145) + _metadataExtraHeight(),
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
                  padding: const EdgeInsets.only(right: 12),
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ArtistScreen(artist: artist)),
                    ),
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 100,
                      child: Column(
                        children: [
                          Expanded(
                            child: Container(
                              width: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: context.bgElevated,
                                border: Border.all(
                                  color: context.accent.withValues(alpha: 0.35),
                                  width: 1.2,
                                ),
                                image: artist.coverArtUrl != null
                                    ? DecorationImage(
                                        image:
                                            NetworkImage(artist.coverArtUrl!),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: artist.coverArtUrl == null
                                  ? Center(
                                      child: Icon(Icons.person,
                                          color: context.textSecondary,
                                          size: 32),
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
                              fontSize: 14,
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
    final items = player.recentlyPlayed.take(5).toList();
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Todavía no has escuchado nada',
          style: TextStyle(color: context.textSecondary, fontSize: 12),
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
                  width: 38,
                  height: 38,
                  borderRadius: 6,
                  fallbackIcon: Icons.music_note,
                  fallbackIconSize: 18,
                  fallbackColor: context.bgCard,
                ),
                const SizedBox(width: 10),
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
                          fontWeight: FontWeight.w600,
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
                IconButton(
                  icon: Icon(Icons.play_circle_fill_rounded,
                      color: context.accent, size: 26),
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

  // ===========================================================================
  // Pestaña Buscar (Mobile)
  // ===========================================================================
  Widget _buildSearchTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SearchExploreField(
            controller: _searchController,
            onSearch: _runSearch,
            onExplore: _openExplore,
            genreSuggestionsBuilder: (query) {
              final genres = context.read<NavidromeService>().cachedGenres;
              if (genres.isEmpty) return const [];
              final q = query.toLowerCase();
              return genres
                  .where((g) => g.toLowerCase().startsWith(q))
                  .toList();
            },
            onGenreSelected: _runGenreSearch,
            searching: _searching,
            exploring: _showExplore,
            hintText: 'Canciones, álbumes o artistas',
          ),
        ),
        Expanded(
          child: _showExplore
              ? FutureBuilder<List<Track>>(
                  future: _futureTracks,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return const Center(
                          child: Text('Error al cargar contenido'));
                    }
                    final tracks = snapshot.data ?? <Track>[];
                    return ExploreTracksView(
                      tracks: tracks,
                      pageSize: _explorePageSize,
                      page: _explorePage,
                      onPageSizeChanged: (size) => setState(() {
                        _explorePageSize = size;
                        _explorePage = 0;
                      }),
                      onPageChanged: (page) =>
                          setState(() => _explorePage = page),
                      onPlay: (index) => _openPlayer(tracks, index),
                    );
                  },
                )
              : _searchResults != null
                  ? _buildSearchResults()
                  : Center(
                      child: Text(
                        'Busca tus canciones o artistas favoritos',
                        style:
                            TextStyle(color: context.textMuted, fontSize: 12.5),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
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
        child:
            Text('Sin resultados', style: TextStyle(color: context.textMuted)),
      );
    }

    final songs = results.songs;
    final albums = results.albums;
    final artists = results.artists;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        if (songs.isNotEmpty) ...[
          const _ResultHeader('Canciones'),
          for (final track in songs)
            ListTile(
              dense: true,
              leading: CoverArt(
                url: track.albumArtUrl,
                artist: track.artist,
                album: track.album,
                title: track.title,
                width: 38,
                height: 38,
                borderRadius: 4,
                fallbackIcon: Icons.music_note,
                fallbackIconSize: 18,
                fallbackColor: context.bgCard,
              ),
              title: Text(track.title,
                  style: TextStyle(color: context.textPrimary, fontSize: 13)),
              subtitle: Text('${track.artist} · ${track.album}',
                  style: TextStyle(color: context.textMuted, fontSize: 11)),
              onTap: () {
                context
                    .read<PlayerController>()
                    .playQueue([track], startIndex: 0);
              },
            ),
        ],
        if (albums.isNotEmpty) ...[
          const _ResultHeader('Álbumes'),
          for (final album in albums)
            ListTile(
              dense: true,
              leading: CoverArt(
                url: album.coverArtUrl,
                width: 38,
                height: 38,
                borderRadius: 4,
                fallbackIcon: Icons.album,
                fallbackIconSize: 18,
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
          const _ResultHeader('Artistas'),
          for (final artist in artists)
            ListTile(
              dense: true,
              leading: CoverArt(
                url: artist.coverArtUrl,
                width: 38,
                height: 38,
                circle: true,
                fallbackIcon: Icons.person,
                fallbackIconSize: 18,
                fallbackColor: context.bgCard,
              ),
              title: Text(artist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.textPrimary, fontSize: 13)),
              subtitle: Text('Artista',
                  style: TextStyle(color: context.textMuted, fontSize: 11)),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ArtistScreen(artist: artist)),
              ),
            ),
        ],
      ],
    );
  }

  // ===========================================================================
  // Pestaña Tu Biblioteca (Mobile)
  // ===========================================================================
  Widget _buildLibraryTab() {
    final nav = context.watch<NavidromeService>();
    return FutureBuilder<List<Playlist>>(
      future: _futurePlaylists,
      builder: (context, snapshot) {
        final playlists = snapshot.data ?? [];
        final sorted = [
          ...playlists.where((p) => nav.isPinnedPlaylist(p.id)),
          ...playlists.where((p) => !nav.isPinnedPlaylist(p.id)),
        ];
        final followedIds = nav.followedArtistIds;
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            FilledButton.icon(
              onPressed: _createPlaylist,
              icon: const Icon(Icons.add_rounded, size: 19),
              label: const Text('Crear playlist'),
              style: FilledButton.styleFrom(
                alignment: Alignment.centerLeft,
                backgroundColor: context.bgCard,
                foregroundColor: context.accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                  side: BorderSide(color: context.borderSubtle),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.accent2,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(Icons.favorite_rounded,
                    color: context.textPrimary, size: 22),
              ),
              title: Text('Tus Me Gusta',
                  style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              subtitle: Text('Canciones favoritas',
                  style: TextStyle(color: context.textMuted, fontSize: 12)),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LikedSongsScreen()),
              ),
            ),
            if (followedIds.isNotEmpty) ...[
              for (final artistId in followedIds)
                _followedArtistTile(artistId, nav),
            ],
            Divider(color: context.bgCard),
            for (final playlist in sorted) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CoverArt(
                  url: playlist.coverArtUrl,
                  width: 44,
                  height: 44,
                  borderRadius: 6,
                  fallbackIcon: Icons.queue_music,
                  fallbackIconSize: 20,
                  fallbackColor: context.bgCard,
                ),
                title: Text(playlist.name,
                    style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500)),
                subtitle: Text(
                  'Playlist · ${playlist.songCount} canciones',
                  style: TextStyle(color: context.textMuted, fontSize: 11.5),
                ),
                trailing: nav.isPinnedPlaylist(playlist.id)
                    ? Icon(Icons.push_pin, color: context.accent, size: 14)
                    : null,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlaylistDetailScreen(playlist: playlist),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _followedArtistTile(String artistId, NavidromeService nav) {
    final cached = nav.getCachedArtist(artistId);
    if (cached != null) {
      return _buildFollowedArtistItem(cached);
    }

    return FutureBuilder<Artist?>(
      future: nav.getArtist(artistId),
      builder: (context, snap) {
        final artist = snap.data;
        if (artist != null) {
          return _buildFollowedArtistItem(artist);
        }
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CoverArt(
            url: null,
            width: 44,
            height: 44,
            borderRadius: 22,
            circle: true,
            fallbackIcon: Icons.person,
            fallbackIconSize: 20,
            fallbackColor: context.bgCard,
          ),
          title: Text(
            snap.connectionState == ConnectionState.waiting
                ? 'Cargando artista...'
                : 'Artista',
            style: TextStyle(
              color: context.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Text(
            'Artista · Siguiendo',
            style: TextStyle(color: context.textMuted, fontSize: 11.5),
          ),
        );
      },
    );
  }

  Widget _buildFollowedArtistItem(Artist artist) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CoverArt(
        url: artist.coverArtUrl,
        width: 44,
        height: 44,
        borderRadius: 22,
        circle: true,
        fallbackIcon: Icons.person,
        fallbackIconSize: 20,
        fallbackColor: context.bgCard,
      ),
      title: Text(
        artist.name,
        style: TextStyle(
          color: context.textPrimary,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        'Artista · Siguiendo',
        style: TextStyle(color: context.textMuted, fontSize: 11.5),
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ArtistScreen(artist: artist),
        ),
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
