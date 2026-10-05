import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../services/navidrome_service.dart';
import '../services/playlist_importer.dart';
import '../services/theme_controller.dart';
import '../utils/app_colors.dart';

/// Abre el selector de archivos y guía la importación hasta mostrar su
/// resultado. Devuelve la playlist actualizada cuando la importación tuvo
/// canciones encontradas; devuelve null si se cancela o falla.
Future<Playlist?> showImportPlaylistDialog(BuildContext context) async {
  try {
    const xType = XTypeGroup(
      label: 'Playlists',
      extensions: ['csv', 'm3u', 'm3u8', 'pls', 'txt'],
    );
    final xFile = await openFile(acceptedTypeGroups: [xType]);
    if (xFile == null || !context.mounted) return null;

    final bytes = await xFile.readAsBytes();
    if (!context.mounted) return null;
    var content = utf8.decode(bytes, allowMalformed: true);
    if (content.startsWith('\uFEFF')) content = content.substring(1);

    final parsed = PlaylistImporter.parseFile(xFile.name, content);
    if (parsed.tracks.isEmpty) {
      await _showImportError(
          context, 'El archivo no contiene canciones reconocibles.');
      return null;
    }

    final defaultName = parsed.suggestedName ??
        xFile.name.split('.').first.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
    final nav = context.read<NavidromeService>();
    var existing = <Playlist>[];
    try {
      existing = await nav.getPlaylists();
    } catch (_) {}
    if (!context.mounted) return null;

    final target = await showDialog<_ImportTarget>(
      context: context,
      builder: (_) => _ImportTargetDialog(
        trackCount: parsed.tracks.length,
        defaultName: defaultName,
        existing: existing,
      ),
    );
    if (target == null || !context.mounted) return null;

    final outcome = await showDialog<_ImportOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ImportProgressDialog(
        tracks: parsed.tracks,
        nav: nav,
        target: target,
      ),
    );
    if (!context.mounted || outcome == null || outcome.cancelled) return null;
    if (outcome.error != null) {
      await _showImportError(context, outcome.error!);
      return null;
    }

    final result = outcome.result!;
    await showDialog<void>(
      context: context,
      builder: (_) => _ImportResultDialog(result: result),
    );
    if (!context.mounted || result.playlistId.isEmpty) return null;

    final playlist = await nav.getPlaylist(result.playlistId);
    if (!context.mounted) return playlist;
    if (playlist == null) {
      await _showImportError(context,
          'La importación terminó, pero no se pudo volver a cargar la playlist.');
    }
    return playlist;
  } catch (error) {
    if (context.mounted) {
      await _showImportError(
          context,
          error
              .toString()
              .replaceFirst(RegExp(r'^(Exception|StateError): '), ''));
    }
    return null;
  }
}

Future<void> _showImportError(BuildContext context, String message) async {
  if (!context.mounted) return;
  final theme = context.read<ThemeController>().active;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: theme.bgCard,
      title:
          Text('Error al importar', style: TextStyle(color: theme.textPrimary)),
      content: Text(message, style: TextStyle(color: theme.textSecondary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text('OK', style: TextStyle(color: theme.danger)),
        ),
      ],
    ),
  );
}

/// Destino elegido para la importación: playlist nueva o ya existente.
class _ImportTarget {
  final String? newName;
  final Playlist? existing;

  const _ImportTarget.create(String this.newName) : existing = null;
  const _ImportTarget.existing(Playlist this.existing) : newName = null;
}

class _ImportOutcome {
  final PlaylistImportResult? result;
  final String? error;
  final bool cancelled;

  const _ImportOutcome.done(PlaylistImportResult this.result)
      : error = null,
        cancelled = false;
  const _ImportOutcome.failed(String this.error)
      : result = null,
        cancelled = false;
  const _ImportOutcome.cancelled()
      : result = null,
        error = null,
        cancelled = true;
}

class _ImportTargetDialog extends StatefulWidget {
  final int trackCount;
  final String defaultName;
  final List<Playlist> existing;

  const _ImportTargetDialog({
    required this.trackCount,
    required this.defaultName,
    required this.existing,
  });

  @override
  State<_ImportTargetDialog> createState() => _ImportTargetDialogState();
}

class _ImportTargetDialogState extends State<_ImportTargetDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.defaultName);
  bool _useExisting = false;
  Playlist? _selected;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _useExisting ? _selected != null : _name.text.trim().isNotEmpty;

  void _submit() {
    if (!_canSubmit) return;
    Navigator.of(context).pop(_useExisting
        ? _ImportTarget.existing(_selected!)
        : _ImportTarget.create(_name.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.bgCard,
      title: Text('Importar playlist',
          style: TextStyle(color: context.textPrimary)),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.trackCount} canciones detectadas',
              style: TextStyle(color: context.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: [
                const ButtonSegment(value: false, label: Text('Nueva')),
                ButtonSegment(
                  value: true,
                  label: const Text('Existente'),
                  enabled: widget.existing.isNotEmpty,
                ),
              ],
              selected: {_useExisting},
              onSelectionChanged: (v) => setState(() => _useExisting = v.first),
            ),
            const SizedBox(height: 12),
            if (!_useExisting)
              TextField(
                controller: _name,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
                style: TextStyle(color: context.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Nombre de la playlist',
                  labelStyle: TextStyle(color: context.textSecondary),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: context.textMuted)),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: context.accent)),
                ),
              )
            else
              DropdownButtonFormField<Playlist>(
                initialValue: _selected,
                isExpanded: true,
                dropdownColor: context.bgCard,
                hint: Text('Elegí una playlist',
                    style: TextStyle(color: context.textSecondary)),
                style: TextStyle(color: context.textPrimary),
                items: [
                  for (final p in widget.existing)
                    DropdownMenuItem(
                      value: p,
                      child: Text('${p.name} (${p.songCount})',
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (p) => setState(() => _selected = p),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child:
              Text('Cancelar', style: TextStyle(color: context.textSecondary)),
        ),
        TextButton(
          onPressed: _canSubmit ? _submit : null,
          child: Text('Importar',
              style: TextStyle(
                  color: _canSubmit ? context.accent : context.textMuted)),
        ),
      ],
    );
  }
}

/// Ejecuta la importación y muestra el porcentaje de avance. Se cierra solo
/// al terminar, devolviendo un [_ImportOutcome].
class _ImportProgressDialog extends StatefulWidget {
  final List<ImportTrack> tracks;
  final NavidromeService nav;
  final _ImportTarget target;

  const _ImportProgressDialog({
    required this.tracks,
    required this.nav,
    required this.target,
  });

  @override
  State<_ImportProgressDialog> createState() => _ImportProgressDialogState();
}

class _ImportProgressDialogState extends State<_ImportProgressDialog> {
  late final ValueNotifier<PlaylistImportProgress> _progress = ValueNotifier(
    PlaylistImportProgress(
        done: 0, total: widget.tracks.length, matched: 0, notFound: 0),
  );
  bool _cancelRequested = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _cancelRequested = true;
    _progress.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    _ImportOutcome outcome;
    try {
      final result = await PlaylistImporter.import(
        tracks: widget.tracks,
        nav: widget.nav,
        name: widget.target.newName,
        existingPlaylistId: widget.target.existing?.id,
        existingPlaylistName: widget.target.existing?.name,
        isCancelled: () => _cancelRequested,
        onProgress: (p) {
          if (mounted) _progress.value = p;
        },
      );
      outcome = _ImportOutcome.done(result);
    } on PlaylistImportCancelled {
      outcome = const _ImportOutcome.cancelled();
    } catch (e) {
      outcome = _ImportOutcome.failed(
          e.toString().replaceFirst(RegExp(r'^(Exception|StateError): '), ''));
    }
    if (mounted) Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: context.bgCard,
        title:
            Text('Importando…', style: TextStyle(color: context.textPrimary)),
        content: SizedBox(
          width: 320,
          child: ValueListenableBuilder<PlaylistImportProgress>(
            valueListenable: _progress,
            builder: (context, p, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text(
                    '${p.percent}%',
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: p.fraction,
                  color: context.accent,
                  backgroundColor: context.textMuted.withValues(alpha: 0.25),
                  minHeight: 6,
                ),
                const SizedBox(height: 12),
                Text(
                  '${p.done} de ${p.total} canciones revisadas',
                  style: TextStyle(color: context.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  '${p.matched} encontradas · ${p.notFound} no encontradas',
                  style: TextStyle(color: context.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => setState(() => _cancelRequested = true),
            child: Text(_cancelRequested ? 'Cancelando…' : 'Cancelar',
                style: TextStyle(color: context.textSecondary)),
          ),
        ],
      ),
    );
  }
}

/// Pantalla de finalización de la importación. Muestra cuántas canciones se
/// importaron y cuántas no (los totales), la lista de las que faltan y un botón
/// para exportar un CSV con ellas.
class _ImportResultDialog extends StatefulWidget {
  final PlaylistImportResult result;

  const _ImportResultDialog({required this.result});

  @override
  State<_ImportResultDialog> createState() => _ImportResultDialogState();
}

class _ImportResultDialogState extends State<_ImportResultDialog> {
  bool _savingCsv = false;

  Future<void> _exportCsv() async {
    final result = widget.result;
    final safeName = result.name
            .replaceAll(RegExp(r'[^\w\s\-áéíóúüñÁÉÍÓÚÜÑ]'), '')
            .trim()
            .isEmpty
        ? 'playlist'
        : result.name
            .replaceAll(RegExp(r'[^\w\s\-áéíóúüñÁÉÍÓÚÜÑ]'), '')
            .trim()
            .replaceAll(' ', '_');

    setState(() => _savingCsv = true);
    try {
      final csv = PlaylistImporter.tracksToCsv(result.unmatched);
      final fileName = '${safeName}_faltantes.csv';

      File? file;
      var copiedToClipboard = false;
      final isDesktop =
          Platform.isLinux || Platform.isWindows || Platform.isMacOS;
      if (isDesktop) {
        final location = await getSaveLocation(
          acceptedTypeGroups: const [
            XTypeGroup(label: 'CSV', extensions: ['csv']),
          ],
          suggestedName: fileName,
        );
        if (location == null) return; // usuario canceló el guardado
        file = File(location.path);
        if (!file.path.toLowerCase().endsWith('.csv')) {
          file = File('${file.path}.csv');
        }
      } else {
        // Android/iOS no tienen diálogo "Guardar como": se guarda en la
        // carpeta de la app y además se copia al portapapeles para poder
        // pegarlo/enviarlo directamente.
        final dir = Platform.isAndroid
            ? (await getExternalStorageDirectory() ??
                await getApplicationDocumentsDirectory())
            : await getApplicationDocumentsDirectory();
        file = File('${dir.path}/$fileName');
        await Clipboard.setData(ClipboardData(text: csv));
        copiedToClipboard = true;
      }
      // BOM para que Excel abra bien los acentos.
      await file.writeAsString('\uFEFF$csv');

      if (!mounted) return;
      _snack(copiedToClipboard
          ? 'CSV guardado en ${file.path} y copiado al portapapeles'
          : 'CSV guardado en ${file.path}');
    } catch (e) {
      if (!mounted) return;
      _snack('No se pudo guardar el CSV: $e');
    } finally {
      if (mounted) setState(() => _savingCsv = false);
    }
  }

  void _snack(String message) {
    final theme = context.read<ThemeController>().active;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: theme.textPrimary)),
        backgroundColor: theme.bgCard,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final total = result.matched + result.unmatched.length;

    return AlertDialog(
      backgroundColor: context.bgCard,
      title: Text(
        !result.playlistTouched
            ? 'No se importó nada'
            : result.toExisting
                ? 'Agregadas a "${result.name}"'
                : 'Playlist "${result.name}" creada',
        style: TextStyle(color: context.textPrimary),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$total canciones en total:',
              style: TextStyle(color: context.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.check_circle, color: context.accent, size: 18),
                const SizedBox(width: 8),
                Text(
                  result.alreadyInPlaylist > 0
                      ? '${result.added} agregadas (${result.alreadyInPlaylist} ya estaban en la playlist)'
                      : '${result.matched} importadas',
                  style: TextStyle(color: context.accent, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  result.hasUnmatched
                      ? Icons.error_outline
                      : Icons.check_circle,
                  color: result.hasUnmatched ? context.warning : context.accent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  result.hasUnmatched
                      ? '${result.unmatched.length} no encontradas'
                      : 'Todas las canciones fueron importadas',
                  style: TextStyle(
                    color:
                        result.hasUnmatched ? context.warning : context.accent,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            if (result.hasUnmatched) ...[
              const SizedBox(height: 14),
              Text(
                'Canciones que faltan (${result.unmatched.length}):',
                style: TextStyle(color: context.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: result.unmatched.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (_, i) {
                    final t = result.unmatched[i];
                    return Text(
                      t.display,
                      style:
                          TextStyle(color: context.textSecondary, fontSize: 12),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _savingCsv ? null : _exportCsv,
                icon: _savingCsv
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.warning,
                        ),
                      )
                    : const Icon(Icons.file_download_outlined, size: 18),
                label: Text(
                  _savingCsv ? 'Guardando…' : 'Exportar CSV de las que faltan',
                  style: const TextStyle(fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.warning,
                  side: BorderSide(color: context.warning),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('OK', style: TextStyle(color: context.accent)),
        ),
      ],
    );
  }
}
