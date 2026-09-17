import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../utils/app_colors.dart';

/// Devuelve los temas guardados para que la vista que abrió el diálogo pueda
/// incorporarlos inmediatamente, sin esperar una segunda petición al servidor.
Future<List<Track>?> showAddPlaylistTracksDialog(
    BuildContext context, Playlist playlist) {
  final nav = context.read<NavidromeService>();
  return showDialog<List<Track>>(
    context: context,
    builder: (_) => _AddPlaylistTracksDialog(nav: nav, playlist: playlist),
  );
}

class _AddPlaylistTracksDialog extends StatefulWidget {
  const _AddPlaylistTracksDialog({required this.nav, required this.playlist});

  final NavidromeService nav;
  final Playlist playlist;

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
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.nav.updatePlaylist(
        playlistId: widget.playlist.id,
        songIdsToAdd: _selected.keys.toList(),
      );
      if (mounted) {
        Navigator.of(context).pop(_selected.values.toList(growable: false));
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
          width: 460,
          height: 360,
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
                                ? 'Busca canciones para añadir a la playlist.'
                                : 'No se encontraron canciones.'),
                          )
                        : ListView.builder(
                            itemCount: _results.length,
                            itemBuilder: (context, index) {
                              final track = _results[index];
                              return CheckboxListTile(
                                value: _selected.containsKey(track.id),
                                title: Text(track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(track.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                onChanged: _saving
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
