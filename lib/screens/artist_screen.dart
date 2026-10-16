import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import "../widgets/server_activity_panel.dart";
import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../services/theme_controller.dart';
import '../widgets/cover_art.dart';
import '../widgets/persistent_player_bar.dart';
import '../widgets/global_top_bar.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/local_download_button.dart';
import 'album_detail_screen.dart';
import '../widgets/interactive_artist_text.dart';
import '../utils/app_colors.dart';
import '../widgets/material_surface.dart';
import '../widgets/tv_initial_focus.dart';

/// Pantalla de un artista estilo Spotify:
/// - Header con portada, nombre, botón play
/// - Sección "Canciones populares" expansible (inicial 5, "Mostrar más")
/// - Sección "Álbumes" completa
class ArtistScreen extends StatefulWidget {
  final Artist artist;

  const ArtistScreen({super.key, required this.artist});

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  late Future<List<Track>> _futureTopTracks;
  late Future<List<Album>> _futureAlbums;

  bool _showAllTracks = false;
  static const int _initialTrackCount = 5;

  String? _bannerImageUrl;

  @override
  void initState() {
    // Iniciar con la portada de Navidrome para que no haya pantalla negra mientas busca
    _bannerImageUrl = widget.artist.coverArtUrl;
    super.initState();
    final nav = context.read<NavidromeService>();
    nav.cacheArtist(widget.artist);
    _futureTopTracks = nav.getArtistTracks(widget.artist.id);
    _futureAlbums = nav.getArtistAlbums(widget.artist.id);

    _fetchBetterArtistImage();
  }

  Future<void> _fetchBetterArtistImage() async {
    final artistName = widget.artist.name;
    try {
      // 1. Intentar TheAudioDB (prioridad para Fanart apaisado real)
      final uri = Uri.parse(
          'https://www.theaudiodb.com/api/v1/json/2/search.php?s=${Uri.encodeQueryComponent(artistName)}');
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final artists = data['artists'];
        if (artists != null && artists.isNotEmpty) {
          final fanart = artists[0]['strArtistFanart'];
          if (fanart != null && fanart.toString().trim().isNotEmpty) {
            if (mounted) setState(() => _bannerImageUrl = fanart);
            return;
          }
        }
      }
    } catch (err) {
      debugPrint('artist_screen:71 ignorado: $err');
    }

    try {
      // 2. Fallback a Deezer (picture_xl es una foto real del artista, no portada cuadrada de disco)
      final uri = Uri.parse(
          'https://api.deezer.com/search/artist?q=${Uri.encodeQueryComponent(artistName)}');
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final items = data['data'];
        if (items != null && items.isNotEmpty) {
          final img = items[0]['picture_xl'] ?? items[0]['picture_big'];
          if (img != null && img.toString().trim().isNotEmpty) {
            if (mounted) setState(() => _bannerImageUrl = img);
            return;
          }
        }
      }
    } catch (err) {
      debugPrint('artist_screen:89 ignorado: $err');
    }

    // 3. Fallback original Navidrome
    if (mounted && widget.artist.coverArtUrl != null) {
      setState(() => _bannerImageUrl = widget.artist.coverArtUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      backgroundColor: context.bgApp,
      body: Column(
        children: [
          const GlobalTopBar(title: 'Artista', showBackButton: true),
          Expanded(
            child: TvInitialFocus(
                child: CustomScrollView(
              slivers: [
                _buildSliverAppBar(),
                SliverToBoxAdapter(child: _buildContent()),
              ],
            )),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: PersistentPlayerBar(compact: compact),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    final compact = MediaQuery.sizeOf(context).width < 700;
    return SliverAppBar(
      expandedHeight: compact ? 384 : 480,
      pinned: true,
      automaticallyImplyLeading: false, // Quita el botón de atrás automático
      backgroundColor: context.bgApp,
      foregroundColor: context.textPrimary,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Fondo con imagen del artista + gradiente
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              child: _bannerImageUrl != null
                  ? Image.network(
                      _bannerImageUrl!,
                      key: ValueKey(_bannerImageUrl),
                      cacheWidth: 1280,
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, -0.6),
                      width: double.infinity,
                      height: double.infinity,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(color: context.accent2);
                      },
                      errorBuilder: (_, __, ___) =>
                          Container(color: context.accent2),
                    )
                  : Container(
                      key: const ValueKey('empty_banner'),
                      color: context.accent2,
                    ),
            ),
            // Gradiente oscuro abajo para legibilidad
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, context.bgApp],
                  stops: const [0.6, 1.0],
                ),
              ),
            ),
            // Contenido: nombre + botón play
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.artist.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Actions row: Play | Follow | Menu
                    Consumer<NavidromeService>(
                      builder: (context, nav, _) {
                        final following =
                            nav.isFollowingArtist(widget.artist.id);
                        return LayoutBuilder(
                          builder: (context, constraints) {
                            final compact = constraints.maxWidth < 360;
                            return Row(
                              children: [
                                _buildPlayButton(compact: compact),
                                const Spacer(),
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: compact ? 12 : 16,
                                      vertical: compact ? 8 : 10,
                                    ),
                                    foregroundColor: following
                                        ? context.accent
                                        : context.textPrimary,
                                    side: BorderSide(
                                        color: following
                                            ? context.accent
                                            : context.textSecondary),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                  onPressed: () {
                                    nav.toggleFollowArtist(widget.artist.id);
                                    final messenger =
                                        ScaffoldMessenger.of(context);
                                    final theme =
                                        context.read<ThemeController>().active;
                                    messenger.showSnackBar(SnackBar(
                                      content: Text(following
                                          ? 'Dejaste de seguir a ${widget.artist.name}'
                                          : 'Siguiendo a ${widget.artist.name}'),
                                      backgroundColor: theme.bgElevated,
                                    ));
                                  },
                                  child:
                                      Text(following ? 'Siguiendo' : 'Seguir'),
                                ),
                                SizedBox(width: compact ? 4 : 8),
                                _buildArtistMenu(nav),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArtistMenu(NavidromeService nav) {
    final theme = context.read<ThemeController>().active;
    final following = nav.isFollowingArtist(widget.artist.id);
    final excluded = nav.isArtistExcluded(widget.artist.id);

    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: theme.textSecondary),
      color: theme.bgApp,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.bgElevated),
      ),
      onSelected: (value) async {
        final messenger = ScaffoldMessenger.of(context);
        if (value == 'follow') {
          nav.toggleFollowArtist(widget.artist.id);
          messenger.showSnackBar(SnackBar(
            content: Text(following
                ? 'Dejaste de seguir a ${widget.artist.name}'
                : 'Siguiendo a ${widget.artist.name}'),
            backgroundColor: theme.bgElevated,
          ));
        } else if (value == 'exclude') {
          nav.toggleExcludeArtist(widget.artist.id);
          messenger.showSnackBar(SnackBar(
            content: Text(excluded
                ? 'Se reproducirá a ${widget.artist.name} nuevamente'
                : 'No se reproducirá a ${widget.artist.name} en modo aleatorio'),
            backgroundColor: theme.bgElevated,
          ));
        } else if (value == 'community') {
          final msg = '🎤 [ARTIST:${widget.artist.id}] ${widget.artist.name}';
          await nav.addChatMessage(msg);
          if (mounted) {
            messenger.showSnackBar(SnackBar(
              content: Text('${widget.artist.name} compartido en la comunidad'),
              backgroundColor: theme.bgElevated,
            ));
            unawaited(ServerActivityPanel.show(context));
          }
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'follow',
          child: Text(
            following ? 'Dejar de seguir' : 'Seguir artista',
            style: TextStyle(color: theme.textPrimary),
          ),
        ),
        PopupMenuItem(
          value: 'exclude',
          child: Text(
            excluded
                ? 'Volver a reproducir este artista'
                : 'No reproducir este artista',
            style:
                TextStyle(color: excluded ? theme.accent : theme.textPrimary),
          ),
        ),
        PopupMenuItem(
          value: 'community',
          child: Text('Compartir con la comunidad',
              style: TextStyle(color: theme.textPrimary)),
        ),
      ],
    );
  }

  Widget _buildPlayButton({bool compact = false}) {
    return Consumer<PlayerController>(
      builder: (context, player, _) {
        return InkWell(
          onTap: () => _playArtistTopTracks(),
          borderRadius: BorderRadius.circular(30),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 16 : 32,
              vertical: compact ? 9 : 12,
            ),
            decoration: BoxDecoration(
              color: context.accent,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  player.playing &&
                          player.currentTrack?.artist == widget.artist.name
                      ? Icons.pause
                      : Icons.play_arrow,
                  color: context.onAccent,
                  size: compact ? 20 : 24,
                ),
                SizedBox(width: compact ? 6 : 8),
                Text(
                  'Reproducir',
                  style: TextStyle(
                    color: context.onAccent,
                    fontSize: compact ? 14 : 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _playArtistTopTracks() async {
    final tracks = await _futureTopTracks;
    if (mounted && tracks.isNotEmpty) {
      unawaited(
          context.read<PlayerController>().playQueue(tracks, startIndex: 0));
    }
  }

  Widget _buildContent() {
    return FutureBuilder<List<Track>>(
      future: _futureTopTracks,
      builder: (context, snapshot) {
        final tracks = snapshot.data ?? <Track>[];
        final loading = snapshot.connectionState == ConnectionState.waiting;

        return FutureBuilder<List<Album>>(
          future: _futureAlbums,
          builder: (context, albumSnapshot) {
            final albums = albumSnapshot.data ?? <Album>[];

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Canciones populares ──────────────────────────────
                  _sectionHeader('Canciones populares', tracks.isNotEmpty),
                  const SizedBox(height: 8),
                  if (loading && tracks.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: CircularProgressIndicator(
                            color: context.textPrimary),
                      ),
                    )
                  else if (tracks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('Sin canciones',
                          style: TextStyle(color: context.textMuted)),
                    )
                  else
                    _buildTracksList(tracks),

                  const SizedBox(height: 24),

                  // ── Álbumes ─────────────────────────────────────────
                  _sectionHeader('Álbumes', albums.isNotEmpty),
                  const SizedBox(height: 8),
                  if (albumSnapshot.connectionState ==
                          ConnectionState.waiting &&
                      albums.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: CircularProgressIndicator(
                            color: context.textPrimary),
                      ),
                    )
                  else if (albums.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('Sin álbumes',
                          style: TextStyle(color: context.textMuted)),
                    )
                  else
                    _buildAlbumsGrid(albums),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _sectionHeader(String title, bool hasContent) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            color: context.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (hasContent)
          TextButton(
            onPressed: () {},
            child: Text(
              'Ver todo',
              style: TextStyle(color: context.textSecondary, fontSize: 14),
            ),
          ),
      ],
    );
  }

  Widget _buildTracksList(List<Track> tracks) {
    final displayTracks =
        _showAllTracks ? tracks : tracks.take(_initialTrackCount).toList();

    return Column(
      children: [
        for (int i = 0; i < displayTracks.length; i++)
          _buildTrackRow(displayTracks[i], i + 1, tracks),
        if (tracks.length > _initialTrackCount) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _showAllTracks = !_showAllTracks),
              child: Text(
                _showAllTracks ? 'Mostrar menos' : 'Mostrar más',
                style: TextStyle(
                  color: context.accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTrackRow(Track track, int number, List<Track> allTracks) {
    final nav = context.read<NavidromeService>();
    final starred = nav.isStarred(track.id);
    final indexInAll = allTracks.indexOf(track);

    return InkWell(
      onTap: () => context
          .read<PlayerController>()
          .playQueue(allTracks, startIndex: indexInAll),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            // Número / Play
            SizedBox(
              width: 48,
              child: Center(
                child: Consumer<PlayerController>(
                  builder: (context, player, _) {
                    final isPlayingThis =
                        player.playing && player.currentTrack?.id == track.id;
                    return Icon(
                      isPlayingThis ? Icons.pause : Icons.play_arrow,
                      color: isPlayingThis ? context.accent : context.textMuted,
                      size: 22,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Portada
            CoverArt(
              url: track.albumArtUrl,
              artist: track.artist,
              album: track.album,
              title: track.title,
              width: 48,
              height: 48,
              borderRadius: 4,
              fallbackIcon: Icons.music_note,
              fallbackIconSize: 22,
              fallbackColor: context.bgElevated,
            ),
            const SizedBox(width: 12),
            // Info
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
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  InteractiveArtistText(
                    artistString: track.artist,
                    fontSize: 12,
                    color: context.textMuted,
                  ),
                ],
              ),
            ),
            // Favorito + menú
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Me gusta',
                  icon: Icon(
                    starred ? Icons.favorite : Icons.favorite_border,
                    color: starred ? context.accent : context.textMuted,
                    size: 20,
                  ),
                  onPressed: () async {
                    await nav.toggleStar(track);
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
                LocalDownloadButton(tracks: [track], compact: true),
                IconButton(
                  tooltip: 'Más opciones',
                  icon: Icon(Icons.more_vert, color: context.textMuted),
                  onPressed: () => TrackContextMenu.show(context, track),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumsGrid(List<Album> albums) {
    final extraHeight = (MediaQuery.textScalerOf(context).scale(14) - 14)
            .clamp(0.0, double.infinity) *
        3;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisExtent: 220 + extraHeight,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        return AppContentCard(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AlbumDetailScreen(album: album)),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: context.bgElevated,
                    borderRadius: BorderRadius.circular(8),
                    image: album.coverArtUrl != null
                        ? DecorationImage(
                            image: ResizeImage(
                              NetworkImage(album.coverArtUrl!),
                              width: 400,
                            ),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: album.coverArtUrl == null
                      ? Center(
                          child: Icon(Icons.album,
                              color: context.textSecondary, size: 36),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${album.trackCount} canciones',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.textSecondary, fontSize: 13),
              ),
            ],
          ),
        );
      },
    );
  }
}
