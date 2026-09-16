import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_theme.dart';
import '../services/theme_controller.dart';
import '../utils/app_colors.dart';

/// Apartado "TUS TEMAS" estilo Psysonic para Ajustes → Interfaz.
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
    final i =
        themes.themes.indexWhere((t) => t.id == themes.activeId);
    if (i < 0) return;
    _scrolledFor = themes.activeId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      const cardW = 104.0;
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
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.bgApp,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cabecera
              Row(
                children: [
                  Icon(Icons.palette_outlined,
                      color: context.textSecondary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'TUS TEMAS',
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const Spacer(),
                  if (themes.loading)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.textMuted,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Aviso de migración (one-time)
              if (themes.migrationNotice != null) ...[
                _NoticeBanner(
                  text: themes.migrationNotice!,
                  onClose: themes.clearMigrationNotice,
                ),
                const SizedBox(height: 12),
              ],

              _ListLabel(context, 'TEMAS'),
              const SizedBox(height: 8),

              // Lista horizontal: fijos primero, luego instalados.
              // (centrada + scrollbar)
              SizedBox(
                height: 180,
                child: Scrollbar(
                  controller: _scroll,
                  thumbVisibility: true,
                  thickness: 6,
                  radius: const Radius.circular(3),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Center(
                      child: ListView.separated(
                        controller: _scroll,
                        shrinkWrap: true,
                        scrollDirection: Axis.horizontal,
                        // Margen superior interno: baja las tarjetas 15px
                        // y evita que la ✕ (que sobresale por arriba)
                        // se corte con el recorte del scroll.
                        padding: const EdgeInsets.only(
                            top: 15, left: 4, right: 4),
                        itemCount: themes.themes.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 12),
                        itemBuilder: (context, i) {
                          final t = themes.themes[i];
                          return _ThemeCard(
                            theme: t,
                            selected: t.id == themes.activeId,
                            onTap: () =>
                                themes.selectTheme(t.id),
                            onDelete: t.sourceZipPath.isEmpty
                                ? null
                                : () => _confirmDelete(
                                    context, themes, t),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),

              if (themes.skippedInvalid > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '${themes.skippedInvalid} archivo(s) inválidos ignorados.',
                  style: TextStyle(
                      color: context.textMuted, fontSize: 11),
                ),
              ],

              if (themes.error != null) ...[
                const SizedBox(height: 10),
                Text(
                  themes.error!,
                  style: TextStyle(
                      color: context.warning, fontSize: 12),
                ),
              ],

              const SizedBox(height: 14),
              Divider(color: context.borderSubtle, height: 1),
              const SizedBox(height: 10),

              // Carpeta de temas
              Row(
                children: [
                  Icon(Icons.folder_outlined,
                      color: context.textMuted, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      themes.themesDir,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: context.textMuted, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FolderButton(
                    icon: Icons.folder_open,
                    label: 'Cambiar carpeta',
                    onTap: () => _pickDirectory(context, themes),
                  ),
                  _FolderButton(
                    icon: Icons.refresh,
                    label: 'Reescanear',
                    onTap: themes.loading ? null : themes.rescan,
                  ),
                  _FolderButton(
                    icon: Icons.add,
                    label: 'Añadir .zip',
                    onTap: () => _pickZip(context, themes),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickDirectory(
      BuildContext context, ThemeController themes) async {
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

  Future<void> _pickZip(
      BuildContext context, ThemeController themes) async {
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
          id == null ? (themes.error ?? 'No se pudo importar.') : 'Tema importado',
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
        title: Text('¿Borrar tema?',
            style: TextStyle(color: context.textPrimary)),
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
            child: Text('Borrar',
                style: TextStyle(color: context.danger)),
          ),
        ],
      ),
    );
    if (ok == true) await themes.deleteTheme(theme.id);
  }
}

class _ListLabel extends StatelessWidget {
  final BuildContext context;
  final String text;

  const _ListLabel(this.context, this.text);

  @override
  Widget build(BuildContext _) {
    return Text(
      text,
      style: TextStyle(
        color: context.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
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
        border: Border.all(
            color: context.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              size: 16, color: context.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: context.textSecondary, fontSize: 12)),
          ),
          GestureDetector(
            onTap: onClose,
            child: Icon(Icons.close,
                size: 16, color: context.textMuted),
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
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 104,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: 72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? context.textPrimary : context.themeBorder,
                      width: selected ? 2.5 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: _preview(),
                  ),
                ),
                if (onDelete != null)
                  Positioned(
                    top: -8,
                    right: -8,
                    child: GestureDetector(
                      onTap: onDelete,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: context.bgCard,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: context.themeBorder),
                        ),
                        child: Icon(Icons.close,
                            size: 12, color: context.textSecondary),
                      ),
                    ),
                  ),
                if (selected)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Icon(Icons.check_circle,
                        size: 16, color: context.textPrimary),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              theme.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: context.textPrimary, fontSize: 11, height: 1.2),
            ),
            const SizedBox(height: 3),
            if (theme.isCvdSafe)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: context.textPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'CVD-safe',
                  style: TextStyle(
                      color: context.textSecondary, fontSize: 9),
                ),
              )
            else if (theme.version.isNotEmpty)
              Text(
                'v${theme.version}',
                style: TextStyle(
                    color: context.textMuted, fontSize: 10),
              ),
          ],
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

  const _FolderButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        foregroundColor: context.textSecondary,
        side: BorderSide(color: context.themeBorder),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
        ),
      ),
    );
  }
}
