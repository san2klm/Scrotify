import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'app_theme.dart';
import 'theme_validation.dart';

/// Gestiona temas fijos bundleados + temas `.zip` estilo Psysonic.
///
/// - Temas fijos ([AppTheme.fixedThemes]): nunca desinstalables.
/// - Comunidad: `.zip` con `manifest.json` + `theme.css` en una carpeta
///   configurable (por defecto la carpeta privada de importados de la app).
///   Cada zip se valida antes de aceptarse (manifest + CSS seguro).
/// - Persiste todo en `themes.json` (versión 2, con migración).
class ThemeController extends ChangeNotifier {
  /// Ruta de desarrollo que versiones anteriores guardaban como valor por
  /// defecto; hoy se trata como "sin elegir".
  static const _legacyThemesDir = '/home/pc/Proyectos/themes/pc-web';
  static const _configVersion = 2;

  static Set<String> get fixedIds =>
      AppTheme.fixedThemes.map((t) => t.id).toSet();

  String _themesDir = '';
  String? _selectedId;
  List<AppTheme> _installed = const [];
  bool _loading = false;
  String? _error;
  int _skippedInvalid = 0;
  String? _migrationNotice;

  ThemeController({Map<String, dynamic>? initial}) {
    if (initial != null && initial.isNotEmpty) {
      _applyConfig(initial);
    }
    _load();
  }

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  String get themesDir => _themesDir;

  /// Fijos primero, luego instalados.
  List<AppTheme> get themes => [...AppTheme.fixedThemes, ..._installed];
  List<AppTheme> get installedThemes => _installed;
  List<AppTheme> get fixedThemeList => AppTheme.fixedThemes;

  bool get loading => _loading;
  String? get error => _error;
  int get skippedInvalid => _skippedInvalid;
  String? get migrationNotice => _migrationNotice;

  AppTheme get active {
    final id = _selectedId ?? 'mocha';
    for (final t in themes) {
      if (t.id == id) return t;
    }
    if (_installed.isNotEmpty) return _installed.first;
    return AppTheme.fixedThemes.first;
  }

  String get activeId => active.id;

  // ---------------------------------------------------------------------------
  // Persistencia (themes.json) + preload sin flash + migración
  // ---------------------------------------------------------------------------

  Future<File> _configFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/themes.json');
  }

  /// Lee la config cruda antes de `runApp` (equiv. startupThemeAppearance:
  /// evita el primer frame con el tema equivocado).
  static Future<Map<String, dynamic>> readInitial() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/themes.json');
      if (!await file.exists()) return {};
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// Sin carpeta elegida, se muestra y usa la carpeta real de importados.
  Future<void> _resolveDefaultDir() async {
    if (_themesDir.isNotEmpty) return;
    _themesDir = (await _importsDir()).path;
  }

  void _applyConfig(Map<String, dynamic> data) {
    final dir = data['themesDir'] as String?;
    _themesDir = dir == null || dir == _legacyThemesDir ? '' : dir;
    _selectedId = data['selectedId'] as String?;
  }

  Future<Directory> _thumbDir() async {
    final dir = await getApplicationSupportDirectory();
    final thumbs = Directory('${dir.path}/theme_thumbs');
    if (!await thumbs.exists()) await thumbs.create(recursive: true);
    return thumbs;
  }

  /// Carpeta privada donde se copian los `.zip` importados con
  /// “Añadir .zip”. En Android es lo único confiable para escribir:
  /// las carpetas compartidas (Download, etc.) rechazan la copia
  /// con `Permission denied` (almacenamiento con alcance).
  Future<Directory> _importsDir() async {
    final dir = await getApplicationSupportDirectory();
    final imports = Directory('${dir.path}/theme_imports');
    if (!await imports.exists()) await imports.create(recursive: true);
    return imports;
  }

  /// Lista `.zip` sin romper si el SO niega el acceso (Android).
  Future<List<File>> _listZips(Directory root) async {
    try {
      if (!await root.exists()) return [];
      return await root
          .list(recursive: true, followLinks: false)
          .where((e) => e is File && e.path.toLowerCase().endsWith('.zip'))
          .cast<File>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  bool _knownId(String? id) {
    if (id == null) return false;
    if (fixedIds.contains(id)) return true;
    return _installed.any((t) => t.id == id);
  }

  /// Migra prefs viejas a ids válidos. Devuelve aviso one-time si hubo
  /// que resetear algo (los slots día/noche de la v2 se ignoran).
  String? _migrate(Map<String, dynamic> data) {
    if ((data['version'] as num?)?.toInt() == _configVersion) return null;
    return null;
  }

  Future<void> _load() async {
    try {
      final file = await _configFile();
      if (await file.exists()) {
        final data =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        if (data.isEmpty) {
          _applyConfig({});
        } else {
          _migrationNotice = _migrate(data);
          _applyConfig(data);
        }
      }
    } catch (_) {
      // Sin config previa: usar valores por defecto.
    }
    try {
      await _resolveDefaultDir();
    } catch (_) {}
    notifyListeners();
    await rescan();
  }

  Future<void> _saveConfig() async {
    try {
      final file = await _configFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({
        'version': _configVersion,
        'themesDir': _themesDir,
        'selectedId': _selectedId,
      }));
    } catch (err) {
      debugPrint('theme_controller:170 ignorado: $err');
    }
  }

  void clearMigrationNotice() {
    _migrationNotice = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Escaneo de la carpeta (con validación)
  // ---------------------------------------------------------------------------

  Future<void> rescan() async {
    _loading = true;
    _error = null;
    _skippedInvalid = 0;
    notifyListeners();

    try {
      // Se escanea la carpeta elegida (si el SO la deja leer) MÁS la
      // privada de importados (siempre legible). Así lo traído con
      // “Añadir .zip” aparece aunque Download no se pueda listar.
      final seen = <String>{};
      final zips = <File>[];
      for (final root in [Directory(_themesDir), await _importsDir()]) {
        for (final f in await _listZips(root)) {
          if (seen.add(f.path)) zips.add(f);
        }
      }
      zips.sort((a, b) => a.path.compareTo(b.path));

      final thumbs = await _thumbDir();
      final loaded = <AppTheme>[];
      for (final zip in zips) {
        try {
          final bytes = await zip.readAsBytes();
          final err = ThemeValidation.validateZipBytes(
            bytes,
            reservedIds: fixedIds,
          );
          if (err != null) {
            _skippedInvalid++;
            continue;
          }
          final thumbPath = await _extractThumbnail(bytes, thumbs);
          final theme = AppTheme.fromZipBytes(
            bytes,
            sourceZipPath: zip.path,
            thumbnailPath: thumbPath,
          );
          if (theme != null) {
            loaded.add(theme);
          } else {
            _skippedInvalid++;
          }
        } catch (_) {
          _skippedInvalid++;
        }
      }

      _installed = loaded;
      // Si algún slot apunta a un id inexistente, caer con aviso.
      if (_selectedId != null && !_knownId(_selectedId)) {
        _selectedId = null;
        _migrationNotice ??=
            'El tema guardado ya no existe, se usó el predeterminado.';
        await _saveConfig();
      }
    } catch (e) {
      _installed = const [];
      _error = 'No se pudo leer la carpeta:\n$e';
    }

    _loading = false;
    notifyListeners();
  }

  /// Extrae `thumbnail.webp|png|jpg` del zip a la carpeta de thumbs.
  /// Devuelve la ruta extraída o null.
  Future<String?> _extractThumbnail(
    List<int> bytes,
    Directory thumbs,
  ) async {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive) {
        if (!file.isFile) continue;
        final lower = file.name.toLowerCase();
        if (lower.endsWith('thumbnail.webp') ||
            lower.endsWith('thumbnail.png') ||
            lower.endsWith('thumbnail.jpg') ||
            lower.endsWith('thumbnail.jpeg') ||
            lower.endsWith('preview.webp') ||
            lower.endsWith('preview.png')) {
          final content = file.content as List<int>;
          // Nombre estable por hash del contenido para no duplicar.
          final hash = content.length.hashCode.abs() + file.name.hashCode.abs();
          final ext = lower.split('.').last;
          final out = File('${thumbs.path}/thumb_$hash.$ext');
          if (!await out.exists()) {
            await out.writeAsBytes(content, flush: true);
          }
          return out.path;
        }
      }
    } catch (err) {
      debugPrint('theme_controller:276 ignorado: $err');
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Acciones
  // ---------------------------------------------------------------------------

  Future<void> setDirectory(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty || trimmed == _themesDir) return;
    _themesDir = trimmed;
    _selectedId = null;
    await _saveConfig();
    await rescan();
  }

  Future<void> selectTheme(String id) async {
    _selectedId = id;
    await _saveConfig();
    notifyListeners();
  }

  /// Valida e importa un `.zip` externo a la carpeta de temas.
  /// Devuelve el id del tema importado o null si falló (ver [error]).
  Future<String?> importZip(String sourcePath) async {
    try {
      final bytes = await File(sourcePath).readAsBytes();
      final name = sourcePath.split('/').last;
      return await importZipBytes(name, bytes);
    } catch (e) {
      _error = 'No se pudo importar:\n$e';
      notifyListeners();
      return null;
    }
  }

  /// Importa desde bytes ya leídos (flujo Android/SAF) y lo guarda en
  /// la carpeta privada (en Download da `Permission denied`).
  Future<String?> importZipBytes(String fileName, List<int> bytes) async {
    try {
      var name = fileName.split('/').last.trim();
      if (name.isEmpty) name = 'tema.zip';
      if (!name.toLowerCase().endsWith('.zip')) {
        _error = 'Solo se aceptan archivos .zip.';
        notifyListeners();
        return null;
      }
      final validationError = ThemeValidation.validateZipBytes(
        bytes,
        reservedIds: fixedIds,
      );
      if (validationError != null) {
        _error = 'Tema inválido: $validationError';
        notifyListeners();
        return null;
      }
      final imports = await _importsDir();
      await File('${imports.path}/$name').writeAsBytes(bytes, flush: true);
      await rescan();
      // Intentar seleccionar el recién importado.
      final probe = AppTheme.fromZipBytes(bytes);
      if (probe != null && _installed.any((t) => t.id == probe.id)) {
        await selectTheme(probe.id);
        return probe.id;
      }
      return null;
    } catch (e) {
      _error = 'No se pudo importar:\n$e';
      notifyListeners();
      return null;
    }
  }

  /// Borra el `.zip` origen del tema (los fijos no se pueden borrar).
  Future<void> deleteTheme(String id) async {
    AppTheme? target;
    for (final t in _installed) {
      if (t.id == id) {
        target = t;
        break;
      }
    }
    if (target == null || target.sourceZipPath.isEmpty) return;
    try {
      final f = File(target.sourceZipPath);
      if (await f.exists()) await f.delete();
      if (_selectedId == id) _selectedId = null;
      await _saveConfig();
      await rescan();
    } catch (e) {
      _error = 'No se pudo borrar:\n$e';
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
