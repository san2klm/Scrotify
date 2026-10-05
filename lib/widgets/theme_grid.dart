import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/app_theme.dart';
import '../services/theme_controller.dart';
import '../utils/app_colors.dart';
import 'material_surface.dart';

/// Selector Material de temas para Ajustes → Interfaz.
///
/// Muestra los `.zip` de la carpeta de temas como tarjetas con vista previa
/// bicolor, nombre, versión y distintivo CVD-safe. Permite cambiar la carpeta,
/// reescanear, importar un `.zip` y borrar temas.
class ThemesSection extends StatefulWidget {
  const ThemesSection({super.key});

  @override
  State<ThemesSection> createState() => _ThemesSectionState();
}

class _ThemesSectionState extends State<ThemesSection> {
  static const _themeFolderChannel =
      MethodChannel('navidrome_client/theme_folder');
  final _scroll = ScrollController();

  /// Id ya centrado con scroll (para no re-saltar en cada rebuild).
  String? _scrolledFor;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Lleva el scroll hasta el tema activo la primera vez que aparece.
  void _centerOnSelected(ThemeController themes) {
    if (_scrolledFor == themes.activeId) return;
    if (themes.themes.isEmpty) return;
    final i = themes.themes.indexWhere((t) => t.id == themes.activeId);
    if (i < 0) return;
    _scrolledFor = themes.activeId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      const cardW = 152.0;
      const gap = 12.0;
      final x = i * (cardW + gap) - 60.0;
      final max = _scroll.position.maxScrollExtent;
      if (max <= 0) return;
      _scroll.jumpTo(x.clamp(0.0, max));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeController>(
      builder: (context, themes, _) {
        _centerOnSelected(themes);
        final scaler = MediaQuery.textScalerOf(context);
        final extraHeight =
            (scaler.scale(13) - 13).clamp(0.0, double.infinity) * 5;
        return MaterialSurface(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.accentDim,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.palette_outlined, color: context.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tus temas',
                        style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('Personaliza los colores de Scrotify',
                        style: TextStyle(
                            color: context.textSecondary, fontSize: 13)),
                  ],
                )),
                if (themes.loading)
                  SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: context.accent)),
              ]),
              const SizedBox(height: 16),
              if (themes.migrationNotice != null) ...[
                _NoticeBanner(
                    text: themes.migrationNotice!,
                    onClose: themes.clearMigrationNotice),
                const SizedBox(height: 16),
              ],
              Text('Tema activo: ${themes.active.name}',
                  style: TextStyle(color: context.textSecondary, fontSize: 13)),
              const SizedBox(height: 12),
              SizedBox(
                height: 244 + extraHeight,
                child: Scrollbar(
                  controller: _scroll,
                  thumbVisibility: true,
                  scrollbarOrientation: ScrollbarOrientation.bottom,
                  child: ListView.separated(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: themes.themes.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, i) {
                      final t = themes.themes[i];
                      return _ThemeCard(
                        theme: t,
                        selected: t.id == themes.activeId,
                        onTap: () => themes.selectTheme(t.id),
                        onDelete: t.sourceZipPath.isEmpty
                            ? null
                            : () => _confirmDelete(context, themes, t),
                      );
                    },
                  ),
                ),
              ),
              if (themes.skippedInvalid > 0) ...[
                const SizedBox(height: 12),
                Text('${themes.skippedInvalid} archivo(s) inválidos ignorados.',
                    style:
                        TextStyle(color: context.textSecondary, fontSize: 13)),
              ],
              if (themes.error != null) ...[
                const SizedBox(height: 12),
                Text(themes.error!,
                    style: TextStyle(color: context.warning, fontSize: 13)),
              ],
              const SizedBox(height: 16),
              Divider(color: context.borderSubtle, height: 1),
              const SizedBox(height: 16),
              Row(children: [
                Icon(Icons.folder_outlined,
                    color: context.textSecondary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                    child: Tooltip(
                  message: themes.themesDir,
                  child: Text(themes.themesDir,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: context.textSecondary, fontSize: 13)),
                )),
              ]),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _FolderButton(
                    icon: Icons.folder_open_rounded,
                    label: Platform.isAndroid
                        ? 'Importar carpeta'
                        : 'Cambiar carpeta',
                    onTap: () => _pickDirectory(context, themes)),
                _FolderButton(
                    icon: Icons.refresh_rounded,
                    label: 'Reescanear',
                    onTap: themes.loading ? null : themes.rescan),
                _FolderButton(
                    icon: Icons.add_rounded,
                    label: 'Añadir .zip',
                    primary: true,
                    onTap: () => _pickZip(context, themes)),
              ]),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickDirectory(
      BuildContext context, ThemeController themes) async {
    if (Platform.isAndroid) {
      await _importAndroidFolder(context, themes);
      return;
    }

    final path = await getDirectoryPath(
      initialDirectory: themes.themesDir,
      confirmButtonText: 'Usar esta carpeta',
    );
    if (path == null || !context.mounted) return;
    await themes.setDirectory(path);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Carpeta de temas: $path',
            style: TextStyle(color: context.textPrimary)),
        backgroundColor: context.bgCard,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Importa todos los .zip de una carpeta Android por SAF. No usamos la
  /// ruta devuelta por el selector: Android no permite listar con dart:io una
  /// carpeta compartida sólo porque el usuario la haya elegido.
  Future<void> _importAndroidFolder(
    BuildContext context,
    ThemeController themes,
  ) async {
    List<dynamic>? entries;
    try {
      entries = await _themeFolderChannel.invokeMethod<List<dynamic>>(
        'pickThemeFolder',
      );
    } on PlatformException catch (e) {
      if (!context.mounted) return;
      _showFolderImportMessage(
        context,
        'No se pudo leer la carpeta: ${e.message ?? e.code}',
      );
      return;
    }

    if (!context.mounted || entries == null) return;
    if (entries.isEmpty) {
      _showFolderImportMessage(context, 'No hay archivos .zip en esa carpeta.');
      return;
    }

    var imported = 0;
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry is! Map) continue;
      final name = entry['name'] as String?;
      final rawBytes = entry['bytes'];
      if (name == null || rawBytes is! Uint8List) continue;

      // La carpeta puede contener archivos iguales en subcarpetas distintas.
      // El prefijo evita que una importación pise a la otra en el directorio
      // privado; el nombre que ve el usuario sale del manifest del tema.
      final safeName = name.replaceAll('/', '_').replaceAll('\\', '_');
      final id = await themes.importZipBytes('$i-$safeName', rawBytes);
      if (id != null) imported++;
    }

    if (!context.mounted) return;
    if (imported > 0) {
      _showFolderImportMessage(
        context,
        imported == 1 ? '1 tema importado.' : '$imported temas importados.',
      );
    } else {
      _showFolderImportMessage(
        context,
        themes.error ?? 'No se pudo importar ningún tema de la carpeta.',
      );
    }
  }

  void _showFolderImportMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: context.textPrimary)),
        backgroundColor: context.bgCard,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pickZip(BuildContext context, ThemeController themes) async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Temas PC', extensions: ['zip']),
      ],
      initialDirectory: themes.themesDir,
      confirmButtonText: 'Importar',
    );
    if (file == null) return;
    // En Android el picker entrega el archivo por SAF: se leen los bytes
    // del XFile (la copia a Download da Permission denied).
    final bytes = await file.readAsBytes();
    final id = await themes.importZipBytes(file.name, bytes);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          id == null
              ? (themes.error ?? 'No se pudo importar.')
              : 'Tema importado',
          style: TextStyle(color: context.textPrimary),
        ),
        backgroundColor: context.bgCard,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ThemeController themes,
    AppTheme theme,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bgCard,
        title:
            Text('¿Borrar tema?', style: TextStyle(color: context.textPrimary)),
        content: Text(
          'Se borrará "${theme.name}" (${theme.sourceZipPath}).',
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
            child: Text('Borrar', style: TextStyle(color: context.danger)),
          ),
        ],
      ),
    );
    if (ok == true) await themes.deleteTheme(theme.id);
  }
}

class _NoticeBanner extends StatelessWidget {
  final String text;
  final VoidCallback onClose;

  const _NoticeBanner({required this.text, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: context.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(color: context.textSecondary, fontSize: 12)),
          ),
          IconButton(
            tooltip: 'Cerrar aviso',
            onPressed: onClose,
            icon: Icon(Icons.close_rounded,
                size: 20, color: context.textSecondary),
          ),
        ],
      ),
    );
  }
}

// Tarjeta individual (lista horizontal)
// -----------------------------------------------------------------------------

class _ThemeCard extends StatelessWidget {
  final AppTheme theme;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _ThemeCard({
    required this.theme,
    required this.selected,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 152,
      child: Semantics(
        selected: selected,
        child: AppContentCard(
          selected: selected,
          onTap: onTap,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 96,
                width: double.infinity,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(fit: StackFit.expand, children: [
                    _preview(),
                    if (selected)
                      Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                                color: context.accent, shape: BoxShape.circle),
                            child: Icon(Icons.check_rounded,
                                size: 16, color: context.onAccent),
                          )),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                  child: Tooltip(
                message: theme.name,
                child: Text(theme.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              )),
              Row(children: [
                Expanded(
                    child: Text(
                  theme.isCvdSafe
                      ? 'CVD-safe'
                      : theme.version.isNotEmpty
                          ? 'v${theme.version}'
                          : '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.textSecondary, fontSize: 12),
                )),
                if (onDelete != null)
                  IconButton(
                    tooltip: 'Borrar ${theme.name}',
                    onPressed: onDelete,
                    icon: Icon(Icons.delete_outline_rounded,
                        size: 20, color: context.textSecondary),
                  ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview() {
    // Si hay thumbnail, mostrarlo; si no, vista bicolor.
    if (theme.thumbnailPath != null) {
      final f = File(theme.thumbnailPath!);
      return Image.file(
        f,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _fallbackPreview(),
      );
    }
    return _fallbackPreview();
  }

  Widget _fallbackPreview() {
    // Sin thumbnail: muestra el rango del tema (fondo + acentos).
    return Column(
      children: [
        Expanded(flex: 5, child: Container(color: theme.previewTop)),
        Container(height: 8, color: theme.accent),
        Container(height: 8, color: theme.accent2),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Botón pequeño de la fila de carpeta
// -----------------------------------------------------------------------------

class _FolderButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  const _FolderButton(
      {required this.icon,
      required this.label,
      this.onTap,
      this.primary = false});

  @override
  Widget build(BuildContext context) {
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    if (primary) {
      return FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: FilledButton.styleFrom(
            backgroundColor: context.accent,
            foregroundColor: context.onAccent,
            minimumSize: const Size(64, 48),
            shape: shape),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: OutlinedButton.styleFrom(
          foregroundColor: context.textSecondary,
          side: BorderSide(color: context.themeBorder),
          minimumSize: const Size(64, 48),
          shape: shape),
    );
  }
}
