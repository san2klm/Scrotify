import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../utils/app_colors.dart';
import 'import_playlist_dialog.dart';

/// Diálogo compacto para crear una playlist desde la biblioteca.
Future<Playlist?> showCreatePlaylistDialog(BuildContext context) async {
  final nav = context.read<NavidromeService>();
  var importRequested = false;
  final playlist = await showDialog<Playlist>(
    context: context,
    builder: (dialogContext) => _CreatePlaylistDialog(
      nav: nav,
      onImport: () {
        importRequested = true;
        Navigator.of(dialogContext).pop();
      },
    ),
  );
  if (importRequested && context.mounted) {
    return showImportPlaylistDialog(context);
  }
  if (playlist != null) nav.bumpPlaylists();
  return playlist;
}

class _CreatePlaylistDialog extends StatefulWidget {
  const _CreatePlaylistDialog({required this.nav, required this.onImport});

  final NavidromeService nav;
  final VoidCallback onImport;

  @override
  State<_CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends State<_CreatePlaylistDialog> {
  final nameController = TextEditingController();
  Uint8List? coverBytes;
  String? coverName;
  String? error;
  Playlist? createdPlaylist;
  bool saving = false;
  bool picking = false;
  int selectedTab = 1;

  @override
  void dispose() {
    // La ruta puede seguir animándose después de resolver showDialog.
    nameController.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    setState(() => picking = true);
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
        coverBytes = bytes;
        coverName = file.name;
        error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> _save() async {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      setState(() => error = 'Escribe un nombre para la playlist.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final playlist = createdPlaylist == null
          ? await widget.nav.createPlaylist(
              name,
              coverBytes: coverBytes,
              coverFileName: coverName,
            )
          : await widget.nav.uploadPlaylistCover(
              createdPlaylist!.id, coverBytes!,
              fileName: coverName);
      if (!mounted) return;
      if (playlist == null) {
        throw Exception('El servidor no devolvió la playlist.');
      }
      Navigator.of(context).pop(playlist);
    } catch (e) {
      if (!mounted) return;
      if (e is PlaylistCoverUploadException) {
        createdPlaylist = e.playlist;
        // Incluso si se cierra con Atrás o tocando fuera, la playlist creada
        // debe aparecer en la biblioteca. Reintentar sólo subirá la portada.
        widget.nav.bumpPlaylists();
      }
      setState(() {
        saving = false;
        error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !saving,
      child: AlertDialog(
        scrollable: true,
        backgroundColor: context.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: context.borderSubtle),
        ),
        title: SizedBox(
          width: 390,
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            expandedInsets: EdgeInsets.zero,
            segments: const [
              ButtonSegment(value: 0, label: Text('Importar')),
              ButtonSegment(value: 1, label: Text('Crear')),
            ],
            selected: {selectedTab},
            onSelectionChanged: saving || picking || createdPlaylist != null
                ? null
                : (selection) {
                    FocusScope.of(context).unfocus();
                    setState(() => selectedTab = selection.first);
                  },
          ),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390, minHeight: 240),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (selectedTab == 0) ...[
                const SizedBox(height: 24),
                Icon(Icons.upload_file_rounded,
                    color: context.accent, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Importar desde un archivo',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.textPrimary, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  'CSV, M3U/M3U8, PLS o TXT',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Text(
                  'Podés crear una playlist nueva o añadir las canciones a una existente.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.textSecondary, fontSize: 13),
                ),
              ] else ...[
                TextField(
                  controller: nameController,
                  enabled: !saving && createdPlaylist == null,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    if (!saving && !picking) _save();
                  },
                  style: TextStyle(color: context.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Nombre de playlist *',
                    labelStyle: TextStyle(color: context.textMuted),
                    hintText: 'Mi playlist',
                    hintStyle: TextStyle(color: context.textMuted),
                    filled: true,
                    fillColor: context.inputBg,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: context.inputBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: context.accent),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Portada (opcional)',
                    style: TextStyle(
                        color: context.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 7),
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: saving || picking ? null : _pickCover,
                  child: Container(
                    height: 76,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.inputBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: context.inputBorder),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: SizedBox(
                            width: 58,
                            height: 58,
                            child: coverBytes == null
                                ? Icon(Icons.image_outlined,
                                    color: context.textMuted)
                                : Image.memory(coverBytes!, fit: BoxFit.cover),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            coverName ?? 'Elegir PNG, JPG o WebP',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: coverName == null
                                  ? context.textMuted
                                  : context.textPrimary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Icon(Icons.upload_file_rounded,
                            color: context.accent, size: 20),
                      ],
                    ),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!,
                      style: TextStyle(color: context.danger, fontSize: 12)),
                ],
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving
                ? null
                : () => Navigator.of(context).pop(createdPlaylist),
            child: Text(createdPlaylist == null ? 'Cancelar' : 'Cerrar',
                style: TextStyle(color: context.textSecondary)),
          ),
          FilledButton.icon(
            onPressed: saving || picking
                ? null
                : selectedTab == 0
                    ? widget.onImport
                    : _save,
            icon: saving
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    selectedTab == 0
                        ? Icons.upload_file_rounded
                        : Icons.add_rounded,
                    size: 18),
            label: Text(selectedTab == 0
                ? 'Seleccionar archivo'
                : createdPlaylist == null
                    ? 'Crear'
                    : 'Reintentar portada'),
          ),
        ],
      ),
    );
  }
}
