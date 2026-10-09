part of 'mobile_home_screen.dart';

/// Pestaña Inicio: filtros, géneros, accesos rápidos y carruseles.
mixin _MobileHomeTab on _MobileHomeBase {
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

  @override
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
        // Los géneros solo se muestran al buscar o explorar, no en Inicio.
        final filteredTracks = tracks;
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const OfflineConnectionBanner(),
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
                      child: Stack(fit: StackFit.expand, children: [
                        ClipRRect(
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
                        Positioned(
                            right: 0,
                            bottom: 0,
                            child: Material(
                              color: context.bgCard,
                              borderRadius: BorderRadius.circular(20),
                              child: LocalDownloadButton(
                                  tracks: [track], compact: true),
                            )),
                      ]),
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
}
