import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../services/playlist_export_service.dart';
import '../services/theme_controller.dart';
import '../utils/app_colors.dart';
import 'material_surface.dart';
import 'add_playlist_tracks_dialog.dart';
import 'edit_playlist_details_dialog.dart';
import 'duplicate_tracks_dialog.dart';
import '../services/duplicate_detector.dart';

/// Panel de acciones compartido por las playlists y la colección de Likes.
class PlaylistActionsPanel extends StatefulWidget {
  final Playlist? playlist;
  final List<Track> tracks;
  final VoidCallback onChanged;

  const PlaylistActionsPanel({
    super.key,
    this.playlist,
    required this.tracks,
    required this.onChanged,
  });

  static Future<void> show(
    BuildContext context, {
    Playlist? playlist,
    required List<Track> tracks,
    required VoidCallback onChanged,
  }) {
    final theme = context.read<ThemeController>().active;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.bgApp,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: theme.border),
      ),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.85,
        child: PlaylistActionsPanel(
          playlist: playlist,
          tracks: List.of(tracks),
          onChanged: onChanged,
        ),
      ),
    );
  }

  @override
  State<PlaylistActionsPanel> createState() => _PlaylistActionsPanelState();
}

class _PlaylistActionsPanelState extends State<PlaylistActionsPanel> {
  late Playlist? _playlist = widget.playlist;
  bool _busy = false;
  bool _cancelled = false;
  String? _error;
  String? _message;
  String? _progress;
  int _done = 0;
  int _total = 0;

  String get _name => _playlist?.name ?? 'Likes';

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
      _cancelled = false;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<List<Track>> _currentTracks() {
    final nav = context.read<NavidromeService>();
    return _playlist == null
        ? nav.getStarred()
        : nav.getPlaylistTracks(_playlist!.id);
  }

  Future<void> _addSongs() async {
    try {
      final added = await showAddPlaylistTracksDialog(context, _playlist);
      if (added != null && added.isNotEmpty && mounted) {
        setState(() => _message = '${added.length} canciones añadidas.');
      }
    } finally {
      // También refrescar si una operación guardó algunas canciones y luego falló.
      widget.onChanged();
    }
  }

  Future<void> _importPlaylist() async {
    final nav = context.read<NavidromeService>();
    final source = await _choosePlaylist(importing: true);
    if (source == null || !mounted) return;
    final incoming = await nav.getPlaylistTracks(source.id);
    final existing = (await _currentTracks()).map((t) => t.id).toSet();
    final added = incoming.where((t) => existing.add(t.id)).toList();
    try {
      if (_playlist == null) {
        for (final track in added) {
          if (!nav.isStarred(track.id)) await nav.toggleStar(track);
          if (!nav.isStarred(track.id)) {
            throw Exception('No se pudo añadir "${track.title}" a Likes.');
          }
        }
      } else {
        await _append(nav, _playlist!.id, added);
      }
      if (mounted) {
        setState(
            () => _message = '${added.length} canciones añadidas a $_name.');
      }
    } finally {
      widget.onChanged();
    }
  }

  Future<void> _copyToPlaylist() async {
    final nav = context.read<NavidromeService>();
    final destination = await _choosePlaylist(importing: false);
    if (destination == null || !mounted) return;
    final incoming = await _currentTracks();
    final existing =
        (await nav.getPlaylistTracks(destination.id)).map((t) => t.id).toSet();
    final added = incoming.where((t) => existing.add(t.id)).toList();
    try {
      await _append(nav, destination.id, added);
      if (mounted) {
        setState(() => _message =
            '${added.length} canciones añadidas a ${destination.name}.');
      }
    } finally {
      widget.onChanged();
    }
  }

  Future<void> _append(
      NavidromeService nav, String id, List<Track> tracks) async {
    // Acotar cada petición evita URLs demasiado largas en listas grandes.
    for (var start = 0; start < tracks.length; start += 100) {
      final end = (start + 100).clamp(0, tracks.length);
      await nav.updatePlaylist(
        playlistId: id,
        songIdsToAdd: tracks.sublist(start, end).map((t) => t.id).toList(),
      );
    }
  }

  Future<Playlist?> _choosePlaylist({required bool importing}) async {
    final playlists = await context.read<NavidromeService>().getPlaylists();
    if (!mounted) return null;
    final candidates = playlists.where((p) => p.id != _playlist?.id).toList();
    return showDialog<Playlist>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bgCard,
        title: Text(importing
            ? 'Importar desde otra playlist'
            : 'Agregar a otra playlist'),
        content: SizedBox(
          width: 420,
          height: 320,
          child: candidates.isEmpty
              ? const Center(child: Text('No hay otras playlists disponibles.'))
              : ListView.builder(
                  itemCount: candidates.length,
                  itemBuilder: (_, index) {
                    final playlist = candidates[index];
                    return ListTile(
                      leading: const Icon(Icons.queue_music_rounded),
                      title: Text(playlist.name),
                      subtitle: Text('${playlist.songCount} canciones'),
                      onTap: () => Navigator.of(ctx).pop(playlist),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'))
        ],
      ),
    );
  }

  Future<void> _exportCsv() async {
    final path =
        await PlaylistExportService.exportCsv(await _currentTracks(), _name);
    if (path != null && mounted) {
      setState(() => _message = 'CSV guardado en $path');
    }
  }

  Future<void> _download() async {
    final nav = context.read<NavidromeService>();
    final tracks = await _currentTracks();
    if (!mounted) return;
    final count = await PlaylistExportService.downloadLocally(
      nav,
      tracks,
      _name,
      onProgress: (done, total, title) {
        if (mounted) {
          setState(() {
            _done = done;
            _total = total;
            _progress = title;
          });
        }
      },
      isCancelled: () => _cancelled || !mounted,
    );
    if (count != null && mounted) {
      setState(() => _message = _cancelled
          ? 'Descarga cancelada. $count canciones guardadas.'
          : '$count canciones guardadas localmente.');
    }
  }

  Future<void> _editDetails() async {
    final playlist = _playlist;
    if (playlist == null) return;
    final nav = context.read<NavidromeService>();
    try {
      final updated = await showEditPlaylistDetailsDialog(context, playlist);
      if (updated != null && mounted) {
        setState(() {
          _playlist = updated;
          _message = 'Nombre y portada actualizados.';
        });
      }
    } finally {
      widget.onChanged();
      // El nombre puede haberse guardado aunque luego fallara la portada.
      try {
        final refreshed = await nav.getPlaylist(playlist.id);
        if (mounted && refreshed != null) setState(() => _playlist = refreshed);
      } catch (_) {
        // Conservar los datos visibles si la conexión se interrumpe.
      }
    }
  }

  Future<void> _detectDuplicates() async {
    final nav = context.read<NavidromeService>();
    final tracks = await _currentTracks();
    if (!mounted || _playlist == null) return;
    final duplicates = DuplicateDetector.findDuplicates(tracks);
    if (duplicates.isEmpty) {
      if (mounted) {
        setState(() => _message = '¡No hay canciones duplicadas en $_name!');
      }
      return;
    }

    if (!mounted) return;
    await DuplicateTracksDialog.show(
      context,
      playlistName: _name,
      allTracks: tracks,
      onRemoveDuplicates: (indicesToRemove) async {
        await nav.updatePlaylist(
          playlistId: _playlist!.id,
          songIndexesToRemove: indicesToRemove,
        );
        widget.onChanged();
      },
    );
  }

  Widget _action(IconData icon, String title, String subtitle,
          Future<void> Function() action) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: MaterialSurface(
            child: ListTile(
          enabled: !_busy,
          leading: Icon(icon, color: context.accent),
          title: Text(title, style: TextStyle(color: context.textPrimary)),
          subtitle:
              Text(subtitle, style: TextStyle(color: context.textSecondary)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: _busy ? null : () => _run(action),
        )),
      );

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                    child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                            color: context.themeBorder,
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 12),
                Row(children: [
                  Icon(Icons.playlist_play_rounded, color: context.accent),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(_name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: context.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.bold))),
                  IconButton(
                      tooltip: 'Cerrar acciones',
                      icon: const Icon(Icons.close_rounded),
                      onPressed:
                          _busy ? null : () => Navigator.of(context).pop()),
                ]),
                const SizedBox(height: 12),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_error!,
                          style: TextStyle(color: context.danger))),
                if (_message != null)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_message!,
                          style: TextStyle(color: context.accent))),
                if (_busy) ...[
                  LinearProgressIndicator(
                      value: _progress != null && _total > 0
                          ? _done / _total
                          : null),
                  if (_progress != null)
                    Row(children: [
                      Expanded(
                          child: Text('$_done/$_total · $_progress',
                              maxLines: 1, overflow: TextOverflow.ellipsis)),
                      TextButton(
                          onPressed: () => setState(() => _cancelled = true),
                          child: const Text('Cancelar')),
                    ]),
                  const SizedBox(height: 8),
                ],
                Expanded(
                    child: ListView(children: [
                  _action(Icons.add_rounded, 'Añadir canciones',
                      'Buscar y seleccionar canciones', _addSongs),
                  _action(
                      Icons.playlist_add_rounded,
                      'Agregar a esta playlist',
                      'Importar canciones desde otra playlist',
                      _importPlaylist),
                  _action(
                      Icons.playlist_add_check_rounded,
                      'Agregar a otra playlist',
                      'Copiar las canciones de esta lista',
                      _copyToPlaylist),
                  _action(Icons.table_view_rounded, 'Descargar CSV',
                      'Exportar la lista de canciones', _exportCsv),
                  _action(
                      Icons.download_rounded,
                      'Descargar localmente',
                      'Guardar los archivos de audio en una carpeta',
                      _download),
                  if (_playlist != null) ...[
                    _action(
                        Icons.edit_rounded,
                        'Nombre y datos',
                        'Cambiar el nombre y la foto de la playlist',
                        _editDetails),
                    _action(
                        Icons.copy_all_rounded,
                        'Detectar duplicados',
                        'Buscar y limpiar canciones repetidas en la playlist',
                        _detectDuplicates),
                  ],
                ])),
              ],
            ),
          ),
        ),
      );
}
