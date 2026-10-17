import 'dart:convert';

import 'package:archive/archive.dart';

/// Validación de temas `.zip` importados, equivalente a
/// `validateThemePackage.ts` + `validateThemeCss()` de Psysonic.
///
/// - Manifest: ids kebab-case, SemVer, author sin @, sin keys desconocidas,
///   sin colisionar con temas fijos.
/// - CSS: tope de tamaño, sin `@import`/`javascript:`/`expression(`/etc.,
///   `url()` solo `data:` o `assets/...` válidos, `@keyframes` con
///   prefijo `<id>-` para no colisionar entre temas.
///
/// Los sideloads inválidos se rechazan con un mensaje en español.
class ThemeValidation {
  static const cssMaxBytes = 256 * 1024;
  static const zipMaxBytes = 5 * 1024 * 1024;

  /// Versión de la app para `minAppVersion` (igual que pubspec).
  static const appVersion = '1.0.0';

  static const _manifestKeys = {
    'id',
    'name',
    'author',
    'version',
    'description',
    'mode',
    'tags',
    'minAppVersion',
    'changelog',
    'homepage',
    'license',
    'preview',
    'accentColor',
    'repository',
    'source',
    'bugs',
    'funding',
    'email',
  };

  static final _kebab = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
  static final _author = RegExp(r'^[A-Za-z0-9](-?[A-Za-z0-9]){0,38}$');
  static final _semver = RegExp(r'^\d+\.\d+\.\d+(-[\w.]+)?(\+[\w.]+)?$');
  static final _tag = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

  static const _assetExts = {
    'webp',
    'png',
    'jpg',
    'jpeg',
    'gif',
    'avif',
    'svg',
    'woff2',
    'woff',
  };

  // ---------------------------------------------------------------------------
  // Manifest
  // ---------------------------------------------------------------------------

  /// Devuelve el error o null si el manifest es válido.
  static String? validateManifest(
    Map<String, dynamic> m, {
    required Set<String> reservedIds,
  }) {
    for (final k in m.keys) {
      if (!_manifestKeys.contains(k)) {
        return 'Campo desconocido en manifest: "$k".';
      }
    }

    final id = m['id']?.toString() ?? '';
    if (!_kebab.hasMatch(id) || id.length < 2 || id.length > 48) {
      return 'id inválido: usa kebab-case, 2-48 caracteres.';
    }
    if (reservedIds.contains(id)) {
      return 'El id "$id" es un tema fijo del sistema.';
    }

    final name = m['name']?.toString() ?? '';
    if (name.isEmpty || name.length > 50) {
      return 'name debe tener 1-50 caracteres.';
    }

    final author = m['author']?.toString() ?? '';
    if (!_author.hasMatch(author)) {
      return 'author inválido: sin @, letras/números/guiones.';
    }

    final version = m['version']?.toString() ?? '';
    if (!_semver.hasMatch(version)) {
      return 'version debe ser SemVer (ej. 1.0.0).';
    }

    final description = m['description']?.toString() ?? '';
    if (description.isEmpty || description.length > 200) {
      return 'description debe tener 1-200 caracteres.';
    }

    final mode = m['mode']?.toString() ?? '';
    if (mode != 'dark' && mode != 'light') {
      return 'mode debe ser "dark" o "light".';
    }

    final tags = m['tags'];
    if (tags != null) {
      final list = tags is List
          ? tags.map((e) => e.toString()).toList()
          : [tags.toString()];
      if (list.length > 8 || list.toSet().length != list.length) {
        return 'tags: máximo 8 y sin repetidos.';
      }
      for (final t in list) {
        if (!_tag.hasMatch(t) || t.length > 24) {
          return 'tag inválido: "$t" (kebab-case, máx. 24).';
        }
      }
    }

    final minApp = m['minAppVersion']?.toString();
    if (minApp != null && minApp.isNotEmpty) {
      if (!_semver.hasMatch(minApp)) {
        return 'minAppVersion debe ser SemVer.';
      }
      if (compareVersions(appVersion, minApp) < 0) {
        return 'Requiere app v$minApp o mayor (tienes v$appVersion).';
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // CSS (security floor)
  // ---------------------------------------------------------------------------

  /// Devuelve el error o null si el CSS es seguro.
  static String? validateCss(String css, String id) {
    if (css.trim().isEmpty) return 'theme.css está vacío.';
    if (utf8.encode(css).length > cssMaxBytes) {
      return 'theme.css supera 256 KB.';
    }

    // Quitar comentarios antes de chequear (anti-smuggling).
    final clean = css.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
    final low = clean.toLowerCase();

    const forbidden = [
      '</style',
      '<script',
      '@import',
      '@property',
      'expression(',
      'javascript:',
      '-moz-binding',
    ];
    for (final f in forbidden) {
      if (low.contains(f)) return 'CSS prohibido: "$f".';
    }
    if (RegExp(r'-[a-z]+-property').hasMatch(low)) {
      return 'CSS prohibido: @property con prefijo.';
    }

    // url() solo data: o assets/... válidos.
    final urlReg = RegExp('url\\(\\s*([\'"]?)([^\'")]+)\\1\\s*\\)');
    for (final m in urlReg.allMatches(clean)) {
      final target = m.group(2)!.trim();
      if (target.startsWith('data:')) continue;
      if (!_isAllowedAssetPath(target)) {
        return 'URL no permitida en CSS: "$target".';
      }
    }

    // @keyframes con prefijo <id>- para no colisionar.
    final kfReg =
        RegExp('@(?:-[a-z]+-)?keyframes\\s+([^\\s{]+)', caseSensitive: false);
    for (final m in kfReg.allMatches(clean)) {
      final name = m.group(1)!;
      if (!name.startsWith('$id-')) {
        return 'El @keyframes "$name" debe empezar por "$id-".';
      }
    }

    return null;
  }

  static bool _isAllowedAssetPath(String p) {
    if (!p.startsWith('assets/')) return false;
    if (p.contains('\\') || p.startsWith('/') || p.contains('..')) {
      return false;
    }
    final segs = p.split('/');
    if (segs.any((s) => s.isEmpty)) return false;
    final ext = segs.last.split('.').last.toLowerCase();
    return _assetExts.contains(ext);
  }

  // ---------------------------------------------------------------------------
  // ZIP completo
  // ---------------------------------------------------------------------------

  /// Valida el `.zip` entero. Devuelve el error o null si es instalable.
  static String? validateZipBytes(
    List<int> bytes, {
    required Set<String> reservedIds,
  }) {
    if (bytes.length > zipMaxBytes) {
      return 'El .zip supera 5 MB.';
    }
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return 'No es un .zip válido.';
    }

    String? manifestRaw;
    String? cssRaw;
    for (final file in archive) {
      if (!file.isFile) continue;
      final name = file.name.toLowerCase();
      if (name.endsWith('manifest.json') && manifestRaw == null) {
        manifestRaw = utf8.decode(file.content as List<int>);
      } else if ((name.endsWith('theme.css') || name.endsWith('theme.scss')) &&
          cssRaw == null) {
        cssRaw = utf8.decode(file.content as List<int>);
      }
    }
    if (manifestRaw == null) return 'Falta manifest.json.';
    if (cssRaw == null) return 'Falta theme.css.';

    Map<String, dynamic> manifest;
    try {
      manifest = jsonDecode(manifestRaw) as Map<String, dynamic>;
    } catch (_) {
      return 'manifest.json no es JSON válido.';
    }

    final mErr = validateManifest(manifest, reservedIds: reservedIds);
    if (mErr != null) return mErr;

    final cssErr = validateCss(cssRaw, manifest['id'].toString());
    if (cssErr != null) return cssErr;

    return null;
  }

  // ---------------------------------------------------------------------------
  // SemVer
  // ---------------------------------------------------------------------------

  /// Compara `X.Y.Z` (-dev y +build se ignoran). <0 si a<b, 0 si igual, >0 si a>b.
  static int compareVersions(String a, String b) {
    List<int> parts(String v) {
      final core = v.split('-').first.split('+').first;
      return core.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    }

    final pa = parts(a);
    final pb = parts(b);
    for (var i = 0; i < 3; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}
