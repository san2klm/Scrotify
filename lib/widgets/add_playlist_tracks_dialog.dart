import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import 'cover_art.dart';
import 'interactive_artist_text.dart';
import '../utils/app_colors.dart';

/// Devuelve los temas guardados para que la vista que abrió el diálogo pueda
/// incorporarlos inmediatamente, sin esperar una segunda petición al servidor.
Future<List<Track>?> showAddPlaylistTracksDialog(
    BuildContext context, Playlist? playlist) {
  final nav = context.read<NavidromeService>();
  return showDialog<List<Track>>(
    context: context,
    builder: (_) => _AddPlaylistTracksDialog(nav: nav, playlist: playlist),
  );
}

class _AddPlaylistTracksDialog extends StatefulWidget {
  const _AddPlaylistTracksDialog({required this.nav, required this.playlist});

  final NavidromeService nav;
  final Playlist? playlist;

  @override
  State<_AddPlaylistTracksDialog> createState() =>
      _AddPlaylistTracksDialogState();
}

class _AddPlaylistTracksDialogState extends State<_AddPlaylistTracksDialog> {
  final _controller = TextEditingController();
  final _selected = <String, Track>{};
  List<Track> _results = [];
  Timer? _debounce;
  int _searchVersion = 0;
  bool _searching = false;
  bool _saving = false;
  String? _error;

  /// IDs de las canciones que ya están en la playlist (cargados al init).
  Set<String> _existingIds = {};

  @override
  void initState() {
    super.initState();
    _loadExistingTracks();
  }

  Future<void> _loadExistingTracks() async {
    try {
      final playlist = widget.playlist;
      final tracks = playlist == null
          ? await widget.nav.getStarred()
          : await widget.nav.getPlaylistTracks(playlist.id);
      if (mounted) {
        setState(() => _existingIds = tracks.map((t) => t.id).toSet());
      }
    } catch (_) {
      // Si falla la carga no bloqueamos el diálogo; simplemente no deshabilitamos nada.
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _search(String value) {
    _debounce?.cancel();
    final version = ++_searchVersion;
    final query = value.trim();
    setState(() {
      _searching = query.isNotEmpty;
      _results = [];
      _error = null;
    });
    if (query.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final result = await widget.nav.search(query);
        if (!mounted || version != _searchVersion) return;
        setState(() => _results = result.songs);
      } catch (e) {
        if (!mounted || version != _searchVersion) return;
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      } finally {
        if (mounted && version == _searchVersion) {
          setState(() => _searching = false);
        }
      }
    });
  }

  Future<void> _save() async {
    // Solo enviamos las que no estén ya en la playlist (doble seguridad).
    final toAdd =
        _selected.keys.where((id) => !_existingIds.contains(id)).toList();
    if (toAdd.isEmpty) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final playlist = widget.playlist;
      if (playlist == null) {
        for (final id in toAdd) {
          final track = _selected[id]!;
          if (!widget.nav.isStarred(id)) await widget.nav.toggleStar(track);
          if (!widget.nav.isStarred(id)) {
            throw Exception('No se pudo añadir "${track.title}" a Likes.');
          }
        }
      } else {
        await widget.nav.updatePlaylist(
          playlistId: playlist.id,
          songIdsToAdd: toAdd,
        );
      }
      if (mounted) {
        // Devolvemos solo las que realmente se añadieron.
        final added = toAdd.map((id) => _selected[id]!).toList(growable: false);
        Navigator.of(context).pop(added);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        backgroundColor: context.bgCard,
        title: const Text('Añadir canciones'),
        content: SizedBox(
          width: 500,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                enabled: !_saving,
                onChanged: _search,
                decoration: const InputDecoration(
                  hintText: 'Buscar canciones',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Text(_error!, style: TextStyle(color: context.danger)),
              Expanded(
                child: _searching
                    ? const Center(child: CircularProgressIndicator())
                    : _results.isEmpty
                        ? Center(
                            child: Text(_controller.text.trim().isEmpty
                                ? 'Busca canciones para añadir a la lista.'
                                : 'No se encontraron canciones.'),
                          )
                        : ListView.builder(
                            itemCount: _results.length,
                            itemBuilder: (context, index) {
                              final track = _results[index];
                              final alreadyIn = _existingIds.contains(track.id);
                              return CheckboxListTile(
                                controlAffinity:
                                    ListTileControlAffinity.trailing,
                                secondary: CoverArt(
                                  url: track.albumArtUrl,
                                  artist: track.artist,
                                  album: track.album,
                                  title: track.title,
                                  width: 44,
                                  height: 44,
                                  borderRadius: 6,
                                  fallbackIcon: Icons.music_note,
                                  fallbackIconSize: 22,
                                  fallbackColor: context.bgCard,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                value: alreadyIn
                                    ? true
                                    : _selected.containsKey(track.id),
                                tristate: false,
                                // Deshabilitado si ya está o si se está guardando.
                                enabled: !_saving && !alreadyIn,
                                title: Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: alreadyIn ? context.textMuted : null,
                                  ),
                                ),
                                subtitle: alreadyIn
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: InteractiveArtistText(
                                                artistString: track.artist),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '· Ya en esta playlist',
                                            style: TextStyle(
                                              color: context.accent,
                                              fontSize: 11,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ],
                                      )
                                    : InteractiveArtistText(
                                        artistString: track.artist),
                                checkColor: alreadyIn ? context.accent : null,
                                activeColor: alreadyIn
                                    ? context.accent.withValues(alpha: 0.45)
                                    : null,
                                onChanged: (_saving || alreadyIn)
                                    ? null
                                    : (selected) => setState(() {
                                          if (selected == true) {
                                            _selected[track.id] = track;
                                          } else {
                                            _selected.remove(track.id);
                                          }
                                        }),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: _saving || _selected.isEmpty ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.playlist_add),
            label: Text('Añadir (${_selected.length})'),
          ),
        ],
      ),
    );
  }
}
