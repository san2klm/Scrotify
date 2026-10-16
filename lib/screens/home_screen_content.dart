part of 'home_screen.dart';

/// Panel central de Inicio: resultados de búsqueda, exploración y los bloques
/// de descubrimiento (accesos rápidos, recomendados, álbumes, artistas…).
mixin _HomeMainContent on _HomeStateBase, _HomeLibraryPanel {
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
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.35),
                    child: SingleChildScrollView(child: _genreSelector()),
                  ),
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

    final nav = context.read<NavidromeService>();
    final songs =
        _trackFilter.apply(results.songs, isStarred: nav.isStarred);
    final albums = results.albums;
    final artists = results.artists;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      children: [
        if (results.songs.isNotEmpty) ...[
          const _SectionLabel('Canciones'),
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
                    tooltip: 'Más opciones',
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
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OfflineConnectionBanner(),
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
          const DiscoverySection(),
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
  Widget _quickAccessGrid() => PlayerSelector.mostPlayed(
      builder: (_, player) => _quickAccessGridFor(player.mostPlayed));

  Widget _quickAccessGridFor(List<MostPlayedItem> mostPlayed) {
    // Orden fijo: favoritos, la playlist más reproducida y cuatro canciones.
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
        return PlayerSelector.mostPlayed(
            builder: (_, player) => _recommendedGrid(tracks, player));
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

  Widget _recentsList() => PlayerSelector.recents(
      builder: (_, player) => _recentsListFor(player));

  Widget _recentsListFor(PlayerController player) {
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
                  tooltip: 'Reproducir',
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
