import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../utils/app_colors.dart';

/// Permite cambiar el nombre y reemplazar la portada de una playlist.
/// Devuelve la playlist recargada al guardar los cambios.
Future<Playlist?> showEditPlaylistDetailsDialog(
    BuildContext context, Playlist playlist) async {
  final nav = context.read<NavidromeService>();
  final updated = await showDialog<Playlist>(
    context: context,
    builder: (_) => _EditPlaylistDetailsDialog(nav: nav, playlist: playlist),
  );
  if (updated != null) nav.bumpPlaylists();
  return updated;
}

class _EditPlaylistDetailsDialog extends StatefulWidget {
  const _EditPlaylistDetailsDialog({required this.nav, required this.playlist});

  final NavidromeService nav;
  final Playlist playlist;

  @override
  State<_EditPlaylistDetailsDialog> createState() =>
      _EditPlaylistDetailsDialogState();
}

class _EditPlaylistDetailsDialogState
    extends State<_EditPlaylistDetailsDialog> {
  late final TextEditingController _nameController;
  late String _savedName;
  Uint8List? _coverBytes;
  String? _coverName;
  String? _error;
  bool _saving = false;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _savedName = widget.playlist.name;
    _nameController = TextEditingController(text: _savedName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    setState(() => _picking = true);
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Imágenes',
            extensions: ['png', 'jpg', 'jpeg', 'webp'],
            mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
          ),
        ],
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.length > 10 * 1024 * 1024) {
        throw Exception('La portada debe pesar como máximo 10 MB.');
      }
      setState(() {
        _coverBytes = bytes;
        _coverName = file.name;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = _message(e));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  String _message(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Escribe un nombre para la playlist.');
      return;
    }
    if (name == _savedName && _coverBytes == null) {
      Navigator.of(context).pop(widget.playlist);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Si el nombre ya se guardó en un intento anterior cuya portada falló,
      // _savedName evita repetir la llamada de renombrado al reintentar.
      if (name != _savedName) {
        await widget.nav.updatePlaylist(
          playlistId: widget.playlist.id,
          name: name,
        );
        _savedName = name;
        widget.nav.bumpPlaylists();
      }

      if (_coverBytes != null) {
        await widget.nav.uploadPlaylistCover(
          widget.playlist.id,
          _coverBytes!,
          fileName: _coverName,
        );
      }

      final updated = await widget.nav.getPlaylist(widget.playlist.id);
      if (updated == null) {
        throw Exception('No se pudo volver a cargar la playlist actualizada.');
      }
      if (mounted) Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _message(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = !_saving && !_picking;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        backgroundColor: context.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: context.borderSubtle),
        ),
        title: Text('Editar playlist',
            style: TextStyle(color: context.textPrimary, fontSize: 18)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                enabled: canEdit,
                autofocus: true,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Nombre'),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: canEdit ? _pickCover : null,
                icon: const Icon(Icons.image_outlined),
                label: Text(_coverName == null
                    ? 'Cambiar foto de portada'
                    : 'Portada: $_coverName'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: context.danger)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: canEdit ? () => Navigator.of(context).pop() : null,
            child: Text('Cancelar',
                style: TextStyle(color: context.textSecondary)),
          ),
          FilledButton(
            onPressed: canEdit ? _save : null,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}
