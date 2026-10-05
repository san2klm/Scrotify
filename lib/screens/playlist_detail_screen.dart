import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../services/player_controller.dart';
import '../widgets/cover_art.dart';
import '../widgets/interactive_artist_text.dart';
import '../widgets/playlist_actions_panel.dart';
import '../widgets/persistent_player_bar.dart';
import '../widgets/global_top_bar.dart';
import '../widgets/track_context_menu.dart';
import '../utils/app_colors.dart';
import '../widgets/material_surface.dart';

/// Pantalla que muestra las canciones de una playlist específica.
/// Se abre desde la barra lateral (Tu Biblioteca) del escritorio.
class PlaylistDetailScreen extends StatefulWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  late Future<List<Track>> _future;
  late Playlist _playlist;
  bool _reordering = false;
  int _playlistVersion = -1;

  @override
  void initState() {
    super.initState();
    _playlist = widget.playlist;
    _future = context.read<NavidromeService>().getPlaylistTracks(_playlist.id);
  }

  Future<void> _reloadPlaylist() async {
    if (!mounted) return;
    final nav = context.read<NavidromeService>();
    setState(() {
      _future = nav.getPlaylistTracks(_playlist.id);
    });
    try {
      final updated = await nav.getPlaylist(_playlist.id);
      if (mounted && updated != null) setState(() => _playlist = updated);
    } catch (_) {
      // Conservar la cabecera actual si no se pudieron recargar metadatos.
    }
  }

  Future<void> _showActionsPanel(List<Track> tracks) =>
      PlaylistActionsPanel.show(
        context,
        playlist: _playlist,
        tracks: tracks,
        onChanged: _reloadPlaylist,
      );

  /// Reproduce la playlist con el modo aleatorio activo (igual que la opción
  /// "Reproducir al azar" del menú contextual de la biblioteca).
  Future<void> _playShuffled(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    final player = context.read<PlayerController>();
    await player.playShuffledQueue(tracks, sourcePlaylist: _playlist);
  }

  Future<void> _reorderTracks(
      List<Track> tracks, int oldIndex, int newIndex) async {
    // Seguridad para evitar índices fuera de rango y ajustar el índice al mover
    if (_reordering || oldIndex < 0 || oldIndex >= tracks.length) return;

    // Si arrastramos hacia abajo, el índice nuevo debe ajustarse porque
    // removeAt cambia el índice de los siguientes elementos.
    final int finalNewIndex = (newIndex > oldIndex) ? newIndex - 1 : newIndex;

    if (finalNewIndex < 0 ||
        finalNewIndex >= tracks.length ||
        oldIndex == finalNewIndex) {
      return;
    }

    final reordered = List<Track>.of(tracks);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(finalNewIndex, moved);
    final nav = context.read<NavidromeService>();

    // La lista responde al soltar el tema, sin esperar la petición de red.
    setState(() {
      _reordering = true;
      _future = Future.value(reordered);
    });
    try {
      await nav.reorderPlaylistTracks(
        playlistId: _playlist.id,
        orderedSongIds: reordered.map((track) => track.id).toList(),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _future = Future.value(tracks);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo guardar el nuevo orden: '
            '${error.toString().replaceFirst('Exception: ', '')}',
            style: TextStyle(color: context.danger),
          ),
          backgroundColor: context.bgCard,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _reordering = false);
    }
  }

  /// Confirma y borra la playlist en Navidrome. Al terminar vuelve a la
  /// pantalla anterior, ya que la playlist ya no existe.
  Future<void> _confirmDelete() async {
    final nav = context.read<NavidromeService>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bgCard,
        title: Text('¿Eliminar playlist?',
            style: TextStyle(color: context.textPrimary)),
        content: Text(
          'Se borrará "${_playlist.name}" permanentemente.',
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
    if (confirmed != true || !mounted) return;

    try {
      if (nav.isPinnedPlaylist(_playlist.id)) {
        nav.togglePinPlaylist(_playlist.id);
      }
      await nav.deletePlaylist(_playlist.id);
      nav.bumpPlaylists();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Playlist eliminada',
              style: TextStyle(color: context.textPrimary)),
          backgroundColor: context.bgCard,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e', style: TextStyle(color: context.danger)),
          backgroundColor: context.bgCard,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavidromeService>();
    // Refresco reactivo: si bumpPlaylists() fue llamado (añadir/eliminar),
    // relanzamos el future para reflejar los cambios sin salir de la pantalla.
    final currentVersion = nav.playlistVersion;
    if (_playlistVersion >= 0 && currentVersion != _playlistVersion) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _future = nav.getPlaylistTracks(_playlist.id);
        });
      });
    }
    _playlistVersion = currentVersion;

    // Misma lógica que HomeShell: < 700px es móvil (barra compacta).
    final compact = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      backgroundColor: context.bgApp,
      bottomNavigationBar: SafeArea(
        top: false,
        child: PersistentPlayerBar(compact: compact),
      ),
      body: Column(
        children: [
          const GlobalTopBar(title: 'Playlist', showBackButton: true),
          Expanded(
            child: FutureBuilder<List<Track>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                      child: CircularProgressIndicator(
                          color: context.textPrimary));
                }
                if (snapshot.hasError) {
                  return Center(
                      child: Text('No se pudo cargar la playlist.',
                          style: TextStyle(color: context.danger)));
                }
                final tracks = snapshot.data ?? <Track>[];
                final pinned = nav.isPinnedPlaylist(_playlist.id);
                return Column(
                  children: [
                    CollectionHeader(
                      artwork: Container(
                        width: compact ? 80 : 120,
                        height: compact ? 80 : 120,
                        decoration: BoxDecoration(
                          color: context.accent2,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: _playlist.coverArtUrl != null
                            ? Image.network(
                                _playlist.coverArtUrl!,
                                fit: BoxFit.cover,
                              )
                            : Icon(Icons.queue_music,
                                color: context.textPrimary, size: 48),
                      ),
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _playlist.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: context.textPrimary,
                                fontSize: 22,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text('${tracks.length} canciones',
                              style: TextStyle(
                                  color: context.textSecondary, fontSize: 14)),
                          const SizedBox(height: 8),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              TextButton.icon(
                                onPressed: () =>
                                    nav.togglePinPlaylist(_playlist.id),
                                style: TextButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  foregroundColor: pinned
                                      ? context.accent
                                      : context.textSecondary,
                                ),
                                icon: Icon(
                                    pinned
                                        ? Icons.push_pin
                                        : Icons.push_pin_outlined,
                                    size: 18),
                                label: Text(pinned ? 'Fijada' : 'Fijar',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Acciones de playlist',
                                icon: Icon(Icons.more_vert_rounded,
                                    color: context.textMuted, size: 20),
                                onPressed: () => _showActionsPanel(tracks),
                              ),
                            ],
                          ),
                        ],
                      ),
                      actions: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.shuffle,
                                color: context.accent, size: 24),
                            tooltip: 'Reproducir al azar',
                            onPressed: () => _playShuffled(tracks),
                          ),
                          IconButton(
                            icon: Icon(Icons.play_circle_filled,
                                color: context.accent, size: 48),
                            onPressed: () =>
                                context.read<PlayerController>().playQueue(
                                      tracks,
                                      startIndex: 0,
                                      sourcePlaylist: _playlist,
                                    ),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline,
                                color: context.danger, size: 24),
                            tooltip: 'Eliminar playlist',
                            onPressed: _confirmDelete,
                          ),
                        ],
                      ),
                    ),
                    Divider(color: context.themeBorder, height: 1),
                    if (tracks.isEmpty)
                      Expanded(
                        child: Center(
                          child: Text('Playlist vacía',
                              style: TextStyle(color: context.textMuted)),
                        ),
                      )
                    else
                      Expanded(
                        child: ReorderableListView.builder(
                          physics: const BouncingScrollPhysics(),
                          buildDefaultDragHandles: false,
                          itemCount: tracks.length,
                          onReorderItem: (oldIndex, newIndex) =>
                              _reorderTracks(tracks, oldIndex, newIndex),
                          itemBuilder: (context, index) {
                            final track = tracks[index];
                            return InkWell(
                              key: ValueKey('playlist-${track.id}'),
                              onTap: () =>
                                  context.read<PlayerController>().playQueue(
                                        tracks,
                                        startIndex: index,
                                        sourcePlaylist: _playlist,
                                      ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // Portada
                                    CoverArt(
                                      url: track.albumArtUrl,
                                      artist: track.artist,
                                      album: track.album,
                                      title: track.title,
                                      width: 40,
                                      height: 40,
                                      borderRadius: 4,
                                      fallbackIcon: Icons.music_note,
                                      fallbackIconSize: 20,
                                      fallbackColor: context.bgElevated,
                                    ),
                                    const SizedBox(width: 10),
                                    // Título + artista
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            track.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                color: context.textPrimary,
                                                fontSize: 14),
                                          ),
                                          InteractiveArtistText(
                                              artistString: track.artist),
                                        ],
                                      ),
                                    ),
                                    // Drag handle centrado horizontalmente (en la mitad)
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 8),
                                        child: Icon(
                                          Icons.drag_handle_rounded,
                                          color: context.textMuted,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                    // Botón de me gusta
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: Icon(
                                        nav.isStarred(track.id)
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        color: nav.isStarred(track.id)
                                            ? context.accent
                                            : context.textMuted,
                                        size: 20,
                                      ),
                                      onPressed: () async {
                                        await nav.toggleStar(track);
                                        setState(() {});
                                      },
                                    ),
                                    // Tres puntitos → menú contextual
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      tooltip: 'Acciones de la canción',
                                      icon: Icon(Icons.more_vert_rounded,
                                          color: context.textMuted, size: 20),
                                      onPressed: () => TrackContextMenu.show(
                                          context, track,
                                          playlistId: _playlist.id),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
