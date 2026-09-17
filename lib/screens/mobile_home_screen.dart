import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/jam_controller.dart';
import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../services/secure_storage.dart';
import '../widgets/persistent_player_bar.dart';
import '../widgets/cover_art.dart';
import '../widgets/create_playlist_dialog.dart';
import '../widgets/pairing_panel.dart';
import '../widgets/jam_dialog.dart';
import '../widgets/server_activity_panel.dart';
import '../widgets/track_context_menu.dart';
import 'liked_songs_screen.dart';
import 'playlist_detail_screen.dart';
import 'album_detail_screen.dart';
import 'artist_screen.dart';
import 'settings_screen.dart';
import '../utils/app_colors.dart';

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
  int _coverArtVersion = -1;
  int _playlistVersion = -1;

  final TextEditingController _searchController = TextEditingController();
  SearchResults? _searchResults;
  bool _searching = false;
  Timer? _serverPlayCountTimer;
  bool _refreshingPlayCounts = false;
  final ScrollController _artistsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _futureTracks = _loadTracks();
    _futurePlaylists = context.read<NavidromeService>().getPlaylists();
    _serverPlayCountTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshServerPlayCounts(),
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

  void _openPairingModal() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.bgApp,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
    _serverPlayCountTimer?.cancel();
    _searchController.dispose();
    _artistsScrollController.dispose();
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
    final username = nav.username ?? 'U';
    final initial = username.isNotEmpty ? username[0].toUpperCase() : 'U';

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
              // Avatar
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.accent2,
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: context.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
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

              // Botón rápido Jam (Social / Colaborativo)
              Consumer<JamController>(
                builder: (context, jam, _) {
                  if (jam.inJam) {
                    return IconButton(
                      tooltip: 'Sesión Jam Activa',
                      icon: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: context.accent.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.speaker_group_rounded,
                            color: context.accent, size: 18),
                      ),
                      onPressed: () => JamDialog.showAsBottomSheet(context),
                    );
                  }
                  return IconButton(
                    tooltip: 'Jam (Escucha grupal)',
                    icon: Icon(Icons.speaker_group_outlined,
                        color: context.accent, size: 21),
                    onPressed: () => JamDialog.showAsBottomSheet(context),
                  );
                },
              ),

              // Botón rápido Vincular PC
              IconButton(
                tooltip: 'Vincular con PC',
                icon: Icon(Icons.qr_code_2_rounded,
                    color: context.accent, size: 22),
                onPressed: _openPairingModal,
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
      height: 34,
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
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _filter = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? context.accent2 : context.bgApp,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? context.accent : context.bgElevated,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? context.textPrimary : context.textSecondary,
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // Pestaña Inicio (Mobile)
  // ===========================================================================
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
              style: TextStyle(color: context.textMuted),
            ),
          );
        }
        final tracks = snapshot.data!;
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _quickAccessGrid(),
              const SizedBox(height: 24),
              _sectionHeader('Recomendados para ti'),
              const SizedBox(height: 12),
              _carousel(tracks),
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
      childAspectRatio: 2.8,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: context.bgApp,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.inputBorder),
        ),
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
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 12,
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
      style: TextStyle(
        color: context.textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _carousel(List<Track> tracks) {
    final items = tracks.take(8).toList();
    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        itemBuilder: (context, index) {
          final track = items[index];
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              onTap: () => _openPlayer(tracks, tracks.indexOf(track)),
              onLongPress: () => TrackContextMenu.show(context, track),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 145,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: context.bgApp,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.bgCard),
                ),
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
                    const SizedBox(height: 6),
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: context.textMuted, fontSize: 10.5),
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
              style: TextStyle(color: context.textMuted));
        }
        return SizedBox(
          height: 175,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: albums.length,
            itemBuilder: (context, index) {
              final album = albums[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => AlbumDetailScreen(album: album)),
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 120,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: context.bgApp,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.bgCard),
                    ),
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
                                  : Icon(Icons.album, color: context.textMuted),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          album.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          album.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(color: context.textMuted, fontSize: 10),
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
              style: TextStyle(color: context.textMuted));
        }
        final showScrollbar = artists.length > 10;
        return SizedBox(
          height: showScrollbar ? 165 : 145,
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
                                          color: context.textMuted, size: 32),
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
                            style: TextStyle(
                              color: context.textPrimary,
                              fontSize: 11.5,
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
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Todavía no has escuchado nada',
          style: TextStyle(color: context.textMuted, fontSize: 12),
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
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(color: context.textMuted, fontSize: 11),
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
          child: Container(
            // Misma omnibox que escritorio y pantallas de detalle.
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: context.inputBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.inputBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.search, color: context.textMuted, size: 19),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(color: context.textPrimary, fontSize: 13),
                    textInputAction: TextInputAction.search,
                    onChanged: _runSearch,
                    decoration: InputDecoration(
                      hintText: 'Canciones, álbumes o artistas',
                      hintStyle:
                          TextStyle(color: context.textMuted, fontSize: 13),
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
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        size: 16, color: context.textMuted),
                    onPressed: () {
                      _searchController.clear();
                      _runSearch('');
                    },
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _searchResults != null
              ? _buildSearchResults()
              : Center(
                  child: Text(
                    'Busca tus canciones o artistas favoritos',
                    style: TextStyle(color: context.textMuted, fontSize: 12.5),
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
                  style: TextStyle(color: context.textPrimary, fontSize: 13)),
              subtitle: Text(album.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.textMuted, fontSize: 11)),
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
            Divider(color: context.bgCard),
            for (final playlist in playlists) ...[
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
