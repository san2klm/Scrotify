import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/app_theme.dart';
import '../services/custom_theme_code.dart';
import '../services/theme_controller.dart';
import '../utils/app_colors.dart';
import 'material_surface.dart';
import 'theme_color_preview.dart';

/// Selector Material de temas para Ajustes → Interfaz.
///
/// Muestra los `.zip` de la carpeta de temas como tarjetas con vista previa
/// bicolor y nombre. Personalizado aparece al final con su editor. Permite cambiar la carpeta,
/// reescanear, importar un `.zip` y borrar temas.
class ThemesSection extends StatefulWidget {
  const ThemesSection({super.key});

  @override
  State<ThemesSection> createState() => _ThemesSectionState();
}

class _ThemesSectionState extends State<ThemesSection> {
  static const _themeFolderChannel = MethodChannel('crotowave/theme_folder');
  final _scroll = ScrollController();

  /// Id ya centrado con scroll (para no re-saltar en cada rebuild).
  String? _scrolledFor;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _editCustomTheme(ThemeController themes) async {
    final colors = await showDialog<_CustomThemeResult>(
      context: context,
      builder: (_) => _CustomThemeDialog(
        theme: themes.customTheme,
        transparency: themes.customTransparency,
      ),
    );
    if (colors == null || !mounted) return;
    await themes.saveCustomTheme(
        background: colors.colors[0],
        accent: colors.colors[1],
        accent2: colors.colors[2],
        transparency: colors.transparency);
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
            (scaler.scale(13) - 13).clamp(0.0, double.infinity) * 2;
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
                    Text('Personaliza los colores de CrotoWave',
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
                height: 180 + extraHeight,
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
                        onEdit: t.id == ThemeController.customThemeId
                            ? () => _editCustomTheme(themes)
                            : null,
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
                _FolderButton(
                    icon: Icons.auto_awesome_rounded,
                    label: 'Temas incluidos',
                    onTap: () async {
                      final count =
                          await themes.restoreBundledThemes(overwrite: true);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              count > 0
                                  ? '$count temas incluidos listos'
                                  : 'Todos los temas incluidos ya están listos',
                              style:
                                  TextStyle(color: themes.active.textPrimary),
                            ),
                            backgroundColor:
                                themes.surfaceColor(themes.active.bgCard),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    }),
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
  final VoidCallback? onEdit;

  const _ThemeCard({
    required this.theme,
    required this.selected,
    required this.onTap,
    this.onDelete,
    this.onEdit,
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
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  children: [
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
                      ),
                    ),
                    if (onDelete != null || onEdit != null)
                      IconButton(
                        tooltip: onEdit != null
                            ? 'Editar colores'
                            : 'Borrar ${theme.name}',
                        onPressed: onEdit ?? onDelete,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                            width: 32, height: 36),
                        icon: Icon(
                            onEdit != null
                                ? Icons.palette_outlined
                                : Icons.delete_outline_rounded,
                            size: 18,
                            color: context.textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview() {
    // Mostrar los colores del tema, incluso si hay miniaturas instaladas.
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

class _CustomThemeResult {
  final List<Color> colors;
  final double transparency;
  const _CustomThemeResult(this.colors, this.transparency);
}

class _CustomThemeDialog extends StatefulWidget {
  final AppTheme theme;
  final double transparency;
  const _CustomThemeDialog({required this.theme, required this.transparency});

  @override
  State<_CustomThemeDialog> createState() => _CustomThemeDialogState();
}

class _CustomThemeDialogState extends State<_CustomThemeDialog> {
  late final List<HSLColor> _colors;
  int _selected = 0;
  late double _transparency;
  final _codeInput = TextEditingController();
  String? _codeError;
  String? _codeStatus;

  CustomThemeCode get _themeCode => CustomThemeCode(
      background: _colors[0].toColor(),
      accent: _colors[1].toColor(),
      accent2: _colors[2].toColor(),
      transparency: _transparency);

  @override
  void dispose() {
    _codeInput.dispose();
    super.dispose();
  }

  void _loadThemeCode() {
    try {
      final imported = CustomThemeCode.decode(_codeInput.text);
      setState(() {
        _colors[0] = HSLColor.fromColor(imported.background);
        _colors[1] = HSLColor.fromColor(imported.accent);
        _colors[2] = HSLColor.fromColor(imported.accent2);
        _transparency = imported.transparency;
        _selected = 0;
        _codeError = null;
        _codeStatus = 'Tema cargado en la vista previa';
      });
    } on FormatException catch (error) {
      setState(() {
        _codeError = error.message;
        _codeStatus = null;
      });
    }
  }

  Future<void> _copyThemeCode() async {
    try {
      await Clipboard.setData(ClipboardData(text: _themeCode.encode()));
      if (mounted) setState(() => _codeStatus = 'Código copiado');
    } on PlatformException {
      if (mounted) setState(() => _codeStatus = 'No se pudo copiar el código');
    }
  }

  Future<void> _pasteThemeCode() async {
    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      if (clipboard?.text == null || clipboard!.text!.trim().isEmpty) {
        setState(() => _codeError = 'El portapapeles no contiene un código');
        return;
      }
      setState(() {
        _codeInput.text = clipboard.text!;
        _codeError = null;
        _codeStatus = null;
      });
    } on PlatformException {
      if (mounted) {
        setState(() => _codeError = 'No se pudo leer el portapapeles');
      }
    }
  }

  static const _labels = ['Fondo', 'Acento principal', 'Acento secundario'];

  @override
  void initState() {
    super.initState();
    _transparency = widget.transparency;
    _colors = [widget.theme.bgApp, widget.theme.accent, widget.theme.accent2]
        .map(HSLColor.fromColor)
        .toList();
  }

  Widget _slider(String label, double value, double max,
          ValueChanged<double> onChanged,
          {Color? color, String? unit}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(label)),
            Text('${value.round()}${unit ?? ''}'),
          ]),
          Slider(
            semanticFormatterCallback: (v) =>
                '$label ${v.round()}${unit ?? ''}',
            value: value.clamp(0, max),
            max: max,
            activeColor: color,
            onChanged: onChanged,
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final current = _colors[_selected];
    return AlertDialog(
      title: const Text('Personalizado'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ThemeColorPreview(
                background: _colors[0].toColor(),
                accent: _colors[1].toColor(),
                accent2: _colors[2].toColor(),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(
                    3,
                    (i) => Expanded(
                          child: Semantics(
                            selected: _selected == i,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => setState(() => _selected = i),
                              child: Column(children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('${i + 1}.'),
                                    Checkbox(
                                      value: _selected == i,
                                      onChanged: (_) =>
                                          setState(() => _selected = i),
                                    ),
                                  ],
                                ),
                                Text(_labels[i],
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 12)),
                              ]),
                            ),
                          ),
                        )),
              ),
              const SizedBox(height: 20),
              _slider(
                  'Color',
                  current.hue,
                  360,
                  (v) =>
                      setState(() => _colors[_selected] = current.withHue(v)),
                  color: HSLColor.fromAHSL(1, current.hue, 1, 0.5).toColor(),
                  unit: '°'),
              _slider(
                  'Tonalidad',
                  current.saturation * 100,
                  100,
                  (v) => setState(() =>
                      _colors[_selected] = current.withSaturation(v / 100)),
                  unit: '%'),
              _slider(
                  'Luz',
                  current.lightness * 100,
                  100,
                  (v) => setState(() =>
                      _colors[_selected] = current.withLightness(v / 100)),
                  unit: '%'),
              _slider('Transparencia', _transparency * 100, 100,
                  (v) => setState(() => _transparency = v / 100),
                  unit: '%'),
              const SizedBox(height: 8),
              ExpansionTile(
                title: const Text('Código del tema'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                children: [
                  SelectableText(_themeCode.encode(),
                      key: const ValueKey('custom-theme-code'),
                      style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _copyThemeCode,
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copiar código'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('custom-theme-code-input'),
                    controller: _codeInput,
                    minLines: 1,
                    maxLines: 3,
                    maxLength: 128,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Pegar código de tema',
                      errorText: _codeError,
                      errorMaxLines: 3,
                      suffixIcon: IconButton(
                        tooltip: 'Pegar del portapapeles',
                        onPressed: _pasteThemeCode,
                        icon: const Icon(Icons.content_paste_rounded),
                      ),
                    ),
                    onChanged: (_) => setState(() {
                      _codeError = null;
                      _codeStatus = null;
                    }),
                    onSubmitted: (_) => _loadThemeCode(),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _loadThemeCode,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Cargar código'),
                  ),
                  if (_codeStatus != null) ...[
                    const SizedBox(height: 8),
                    Text(_codeStatus!, textAlign: TextAlign.center),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_CustomThemeResult(
              _colors.map((c) => c.toColor()).toList(), _transparency)),
          child: const Text('Guardar y aplicar'),
        ),
      ],
    );
  }
}
