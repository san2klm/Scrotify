part of 'mobile_home_screen.dart';

/// Pestañas Búsqueda y Biblioteca.
mixin _MobileSearchLibraryTabs on _MobileHomeBase {
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
        if (_showExplore || _searchResults != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.35),
              child: SingleChildScrollView(child: _genreSelector()),
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
                    final allTracks = snapshot.data ?? <Track>[];
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

    final nav = context.read<NavidromeService>();
    final songs =
        _trackFilter.apply(results.songs, isStarred: nav.isStarred);
    final albums = results.albums;
    final artists = results.artists;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        if (results.songs.isNotEmpty) ...[
          const _ResultHeader('Canciones'),
          TrackFilterBar(
            filter: _trackFilter,
            tracks: results.songs,
            onChanged: (f) => setState(() => _trackFilter = f),
          ),
          if (songs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Ninguna canción cumple los filtros.',
                  style: TextStyle(color: context.textMuted, fontSize: 12.5)),
            ),
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
}
