part of 'home_screen.dart';

/// Panel izquierdo de Inicio: la biblioteca (playlists y artistas seguidos),
/// en su versión ancha y en la colapsada.
mixin _HomeLibraryPanel on _HomeStateBase {
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
            if (snapshot.hasError)
              Tooltip(
                message: 'No se pudieron cargar las playlists',
                child: Icon(Icons.cloud_off_rounded, color: context.textMuted),
              )
            else if (snapshot.connectionState == ConnectionState.waiting)
              const LinearProgressIndicator(minHeight: 2),
            Tooltip(
              message: 'Tus me gusta',
              child: IconButton(
                tooltip: 'Me gusta',
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
            if (snapshot.hasError)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text('No se pudieron cargar tus playlists.',
                    style: TextStyle(color: context.textMuted, fontSize: 12)),
              )
            else if (snapshot.connectionState == ConnectionState.waiting)
              const LinearProgressIndicator(minHeight: 2),
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
            _libraryTile(
              icon: Icons.radio,
              title: 'Radios y podcasts',
              subtitle: 'Del servidor',
              background: context.accent,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RadioPodcastsScreen()),
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
      unawaited(context.read<PlayerController>().playQueue(
            tracks,
            startIndex: 0,
            sourcePlaylist: playlist,
          ));
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
}
