import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../utils/app_colors.dart';

/// Diálogo compacto para crear una playlist desde la biblioteca.
Future<Playlist?> showCreatePlaylistDialog(BuildContext context) async {
  final nameController = TextEditingController();
  Uint8List? coverBytes;
  String? coverName;
  String? error;
  var saving = false;

  try {
    return await showDialog<Playlist>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: context.bgCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: context.borderSubtle),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: context.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.playlist_add_rounded,
                    color: context.accent, size: 21),
              ),
              const SizedBox(width: 10),
              Text('Crear playlist',
                  style: TextStyle(color: context.textPrimary, fontSize: 18)),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 390),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {},
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
                  onTap: saving
                      ? null
                      : () async {
                          final file = await openFile(
                            acceptedTypeGroups: const [
                              XTypeGroup(
                                label: 'Imágenes',
                                extensions: ['png', 'jpg', 'jpeg', 'webp'],
                              ),
                            ],
                          );
                          if (file == null) return;
                          final bytes = await file.readAsBytes();
                          if (bytes.length > 10 * 1024 * 1024) {
                            setDialogState(() => error =
                                'La portada debe pesar como máximo 10 MB.');
                            return;
                          }
                          setDialogState(() {
                            coverBytes = bytes;
                            coverName = file.name;
                            error = null;
                          });
                        },
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
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  saving ? null : () => Navigator.of(dialogContext).pop(),
              child: Text('Cancelar',
                  style: TextStyle(color: context.textSecondary)),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      if (name.isEmpty) {
                        setDialogState(() =>
                            error = 'Escribe un nombre para la playlist.');
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        final playlist = await context
                            .read<NavidromeService>()
                            .createPlaylist(
                              name,
                              coverBytes: coverBytes,
                              coverFileName: coverName,
                            );
                        if (!context.mounted) return;
                        if (playlist == null) {
                          throw Exception(
                              'El servidor no devolvió la playlist.');
                        }
                        context.read<NavidromeService>().bumpPlaylists();
                        Navigator.of(dialogContext).pop(playlist);
                      } catch (e) {
                        setDialogState(() {
                          saving = false;
                          error = e.toString().replaceFirst('Exception: ', '');
                        });
                      }
                    },
              icon: saving
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_rounded, size: 18),
              label: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  } finally {
    nameController.dispose();
  }
}
