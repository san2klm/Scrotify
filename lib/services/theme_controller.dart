import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter/services.dart' show rootBundle, ByteData;
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

  bool _coverAccentEnabled = false;
  Color? _coverAccent;
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

  /// El color de énfasis sigue a la carátula de la pista que suena.
  bool get coverAccentEnabled => _coverAccentEnabled;

  Future<void> setCoverAccentEnabled(bool value) async {
    if (_coverAccentEnabled == value) return;
    _coverAccentEnabled = value;
    if (!value) _coverAccent = null;
    notifyListeners();
    await _saveConfig();
  }

  /// Color extraído de la carátula actual (`null` = el del tema).
  void setCoverAccent(Color? color) {
    if (!_coverAccentEnabled || _coverAccent == color) return;
    _coverAccent = color;
    notifyListeners();
  }

  AppTheme get active {
    final base = _baseTheme;
    final accent = _coverAccentEnabled ? _coverAccent : null;
    return accent == null ? base : base.withAccent(accent);
  }

  AppTheme get _baseTheme {
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

  /// Sin carpeta elegida, se muestra y usa la carpeta real de importados o la carpeta de descargas.
  Future<void> _resolveDefaultDir() async {
    if (_themesDir.isNotEmpty && await Directory(_themesDir).exists()) return;

    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null) {
        final candidates = [
          '$userProfile\\Downloads\\temas-Scrotify-20261006T210310Z-1-001',
          '$userProfile\\Downloads\\temas-Scrotify',
          '$userProfile\\Downloads\\fondos',
        ];
        for (final candidate in candidates) {
          if (await Directory(candidate).exists()) {
            _themesDir = candidate;
            return;
          }
        }
      }
    }
    _themesDir = (await _importsDir()).path;
  }

  void _applyConfig(Map<String, dynamic> data) {
    final dir = data['themesDir'] as String?;
    _themesDir = dir == null || dir == _legacyThemesDir ? '' : dir;
    _selectedId = data['selectedId'] as String?;
    _coverAccentEnabled = data['coverAccent'] as bool? ?? false;
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
  Future<Directory> importsDirectory() => _importsDir();

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

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
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
    if (_disposed) return;
    try {
      await _ensureBundledThemes();
    } catch (_) {}
    notifyListeners();
    await rescan();
  }

  /// Extrae automáticamente los temas incluidos en el bundle de la app en la
  /// primera ejecución si la carpeta de importados no los tiene instalados.
  Future<void> _ensureBundledThemes() async {
    try {
      final imports = await _importsDir();
      final marker = File('${imports.path}/.bundled_installed_v2');
      if (await marker.exists()) return;

      final count = await restoreBundledThemes(overwrite: true);
      if (count >= 0) {
        await marker.writeAsString('v2');
      }
    } catch (err) {
      debugPrint('theme_controller: _ensureBundledThemes ignorado: $err');
    }
  }

  /// Extrae o restablece los temas empaquetados en la app (assets/themes/bundled_themes.zip).
  /// Retorna la cantidad de temas extraídos/actualizados.
  Future<int> restoreBundledThemes({bool overwrite = false}) async {
    try {
      final imports = await _importsDir();
      final ByteData data;
      try {
        data = await rootBundle.load('assets/themes/bundled_themes.zip');
      } catch (_) {
        return 0;
      }
      final bytes = data.buffer.asUint8List();
      final archive = ZipDecoder().decodeBytes(bytes);
      int count = 0;
      for (final file in archive) {
        if (!file.isFile) continue;
        final name = file.name.split('/').last.split('\\').last;
        if (!name.toLowerCase().endsWith('.zip')) continue;
        final target = File('${imports.path}/$name');
        if (overwrite || !await target.exists()) {
          await target.writeAsBytes(file.content as List<int>, flush: true);
          count++;
        }
      }
      final marker = File('${imports.path}/.bundled_installed_v2');
      await marker.writeAsString('v2');
      await rescan();
      return count;
    } catch (e) {
      debugPrint('theme_controller: restoreBundledThemes error: $e');
      return 0;
    }
  }

  Future<void> _saveConfig() async {
    try {
      final file = await _configFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({
        'version': _configVersion,
        'themesDir': _themesDir,
        'selectedId': _selectedId,
        'coverAccent': _coverAccentEnabled,
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
      final seenThemeIds = <String>{};
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
            if (seenThemeIds.add(theme.id)) {
              loaded.add(theme);
            }
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
