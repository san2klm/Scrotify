import 'theme_names.dart';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';

import 'material_presentation.dart';

/// Tema de la app importado desde un `.zip` estilo Psysonic.
///
/// Cada zip contiene (al menos):
/// - `manifest.json` → `{id, name, author, version, description, mode, tags?}`
/// - `theme.css` → variables `--accent`, `--bg-app`, `--text-primary`, ...
/// - `thumbnail.webp` (opcional) → vista previa.
class AppTheme {
  final String id;
  final String name;
  final String author;
  final String version;
  final String description;
  final String mode; // 'dark' | 'light'
  final List<String> tags;

  final Color accent;
  final Color accent2;
  final Color accentDim;
  final Color accentGlow;
  final Color highlight;
  final Color bgApp;
  final Color bgCard;
  final Color bgElevated;
  final Color bgSidebar;
  final Color bgHover;
  final Color bgPlayer;
  final Color bgDeep;
  final Color menuBg;
  final Color modalBg;
  final Color inputBg;
  final Color inputBorder;
  final Color inputFocusBorder;
  final Color border;
  final Color borderSubtle;
  final Color cardHoverBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textOnAccent;
  final Color danger;
  final Color positive;
  final Color warning;
  final Color rowPlayingBg;
  final Color rowPlayingText;
  final Color rowDivider;
  final Color sidebarActiveBg;
  final Color sidebarActiveText;
  final Color sliderTrack;
  final Color sliderThumb;
  final Color scrollbarThumb;
  final Color volumeAccent;
  final Color waveformPlayed;
  final Color waveformUnplayed;
  final Color playerTitle;
  final Color playerArtist;
  final Color logoStart;
  final Color logoEnd;

  /// Ruta al zip origen (para borrar). Vacía en built-ins.
  final String sourceZipPath;

  /// Ruta al thumbnail extraído (si hay). Null si no hay.
  final String? thumbnailPath;

  const AppTheme({
    required this.id,
    required this.name,
    required this.author,
    required this.version,
    required this.description,
    required this.mode,
    required this.tags,
    required this.accent,
    required this.accent2,
    required this.accentDim,
    required this.accentGlow,
    required this.highlight,
    required this.bgApp,
    required this.bgCard,
    required this.bgElevated,
    required this.bgSidebar,
    required this.bgHover,
    required this.bgPlayer,
    required this.bgDeep,
    required this.menuBg,
    required this.modalBg,
    required this.inputBg,
    required this.inputBorder,
    required this.inputFocusBorder,
    required this.border,
    required this.borderSubtle,
    required this.cardHoverBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textOnAccent,
    required this.danger,
    required this.positive,
    required this.warning,
    required this.rowPlayingBg,
    required this.rowPlayingText,
    required this.rowDivider,
    required this.sidebarActiveBg,
    required this.sidebarActiveText,
    required this.sliderTrack,
    required this.sliderThumb,
    required this.scrollbarThumb,
    required this.volumeAccent,
    required this.waveformPlayed,
    required this.waveformUnplayed,
    required this.playerTitle,
    required this.playerArtist,
    required this.logoStart,
    required this.logoEnd,
    this.sourceZipPath = '',
    this.thumbnailPath,
  });

  /// Copia del tema con [accent] como color de énfasis (p. ej. el de la
  /// carátula). Conserva fondos y textos; recalcula los derivados del acento.
  AppTheme withAccent(Color accent) {
    final hsl = HSLColor.fromColor(accent);
    final accent2 =
        hsl.withLightness((hsl.lightness + 0.12).clamp(0.0, 1.0)).toColor();
    final accentDim = accent.withValues(alpha: 0.6);
    final accentGlow = accent.withValues(alpha: 0.25);
    final onAccent =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
            ? const Color(0xFFFFFFFF)
            : const Color(0xFF111111);
    return AppTheme(
      id: '$id+cover',
      name: name,
      author: author,
      version: version,
      description: description,
      mode: mode,
      tags: tags,
      accent: accent,
      accent2: accent2,
      accentDim: accentDim,
      accentGlow: accentGlow,
      highlight: accent,
      bgApp: bgApp,
      bgCard: bgCard,
      bgElevated: bgElevated,
      bgSidebar: bgSidebar,
      bgHover: bgHover,
      bgPlayer: bgPlayer,
      bgDeep: bgDeep,
      menuBg: menuBg,
      modalBg: modalBg,
      inputBg: inputBg,
      inputBorder: inputBorder,
      inputFocusBorder: accent,
      border: border,
      borderSubtle: borderSubtle,
      cardHoverBorder: cardHoverBorder,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      textMuted: textMuted,
      textOnAccent: onAccent,
      danger: danger,
      positive: positive,
      warning: warning,
      rowPlayingBg: rowPlayingBg,
      rowPlayingText: accent,
      rowDivider: rowDivider,
      sidebarActiveBg: sidebarActiveBg,
      sidebarActiveText: accent,
      sliderTrack: sliderTrack,
      sliderThumb: accent,
      scrollbarThumb: scrollbarThumb,
      volumeAccent: accent,
      waveformPlayed: accent,
      waveformUnplayed: waveformUnplayed,
      playerTitle: playerTitle,
      playerArtist: playerArtist,
      logoStart: logoStart,
      logoEnd: logoEnd,
    );
  }

  bool get isDark => mode.toLowerCase() != 'light';
  bool get isCvdSafe => tags.any((t) => t.toLowerCase().contains('cvd'));

  /// Color inferior de la tarjeta de vista previa (franja de color).
  Color get previewStripe => accent;

  /// Color superior de la tarjeta de vista previa.
  Color get previewTop => bgCard;

  // ---------------------------------------------------------------------------
  // Construcción desde ZIP
  // ---------------------------------------------------------------------------

  static AppTheme? fromZipBytes(
    List<int> bytes, {
    String sourceZipPath = '',
    String? thumbnailPath,
  }) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      String? manifestRaw;
      String? cssRaw;

      for (final file in archive) {
        if (!file.isFile) continue;
        final name = file.name.toLowerCase();
        if (name.endsWith('manifest.json') && manifestRaw == null) {
          manifestRaw = utf8.decode(file.content as List<int>);
        } else if ((name.endsWith('theme.css') ||
                name.endsWith('theme.scss')) &&
            cssRaw == null) {
          cssRaw = utf8.decode(file.content as List<int>);
        }
      }

      if (manifestRaw == null || cssRaw == null) return null;

      final manifest = jsonDecode(manifestRaw) as Map<String, dynamic>;
      final vars = _parseCssVars(cssRaw);

      // Lee una variable resolviendo `var(--otra)` (p. ej. los temas `gw-*`).
      Color? parse(String key) {
        final raw = vars[key];
        if (raw == null) return null;
        return parseCssColor(_resolveVars(raw, vars));
      }

      final tags = switch (manifest['tags']) {
        final List l => l.map((e) => e.toString()).toList(),
        final String s => [s],
        _ => <String>[],
      };

      // Núcleo (los demás colores derivan de estos si faltan en el CSS).
      final accent = parse('--accent') ?? const Color(0xFFA855F7);
      final textPrimary = parse('--text-primary') ?? Colors.white;
      final textSecondary =
          parse('--text-secondary') ?? const Color(0xFFBDBDBD);
      final textMuted = parse('--text-muted') ?? const Color(0xFF7A7A7A);
      final border = parse('--border') ?? const Color(0xFF242424);
      final bgApp = parse('--bg-app') ?? const Color(0xFF000000);
      final bgCard = parse('--bg-card') ?? const Color(0xFF121212);
      final bgElevatedRaw = parse('--bg-elevated');
      final bgHover =
          parse('--bg-hover') ?? bgElevatedRaw ?? const Color(0xFF1F1F1F);
      final bgElevated = bgElevatedRaw ?? bgHover;
      final warningRaw = parse('--warning');
      final highlight =
          parse('--highlight') ?? warningRaw ?? const Color(0xFFFBBF24);
      final accent2 = parse('--accent-2') ?? parse('--accent-dim') ?? accent;

      return AppTheme(
        id: (manifest['id'] ?? manifest['name'] ?? 'tema').toString(),
        name: bundledThemeNames[manifest['id']] ??
            (manifest['name'] ?? manifest['id'] ?? 'Tema').toString(),
        author: (manifest['author'] ?? '').toString(),
        version: (manifest['version'] ?? '').toString(),
        description: (manifest['description'] ?? '').toString(),
        mode: (manifest['mode'] ?? 'dark').toString(),
        tags: tags,
        accent: accent,
        accent2: accent2,
        accentDim: parse('--accent-dim') ?? accent.withValues(alpha: 0.12),
        accentGlow: parse('--accent-glow') ?? accent.withValues(alpha: 0.35),
        highlight: highlight,
        bgApp: bgApp,
        bgCard: bgCard,
        bgElevated: bgElevated,
        bgSidebar: parse('--bg-sidebar') ?? bgApp,
        bgHover: bgHover,
        bgPlayer: parse('--bg-player') ?? bgApp,
        bgDeep: parse('--bg-deep') ?? bgApp,
        menuBg: parse('--menu-bg') ?? bgElevated,
        modalBg: parse('--modal-bg') ?? bgElevated,
        inputBg: parse('--input-bg') ?? bgApp,
        inputBorder:
            parse('--input-border') ?? parse('--border-dropdown') ?? border,
        inputFocusBorder: parse('--input-focus-border') ??
            parse('--card-hover-border') ??
            accent,
        border: border,
        borderSubtle: parse('--border-subtle') ?? border,
        cardHoverBorder: parse('--card-hover-border') ?? accent,
        textPrimary: textPrimary,
        textSecondary: textSecondary,
        textMuted: textMuted,
        textOnAccent: parse('--text-on-accent') ?? onColor(accent),
        danger: parse('--danger') ?? const Color(0xFFF87171),
        positive: parse('--positive') ?? const Color(0xFF4ADE80),
        warning: warningRaw ?? highlight,
        rowPlayingBg:
            parse('--row-playing-bg') ?? accent.withValues(alpha: 0.12),
        rowPlayingText: parse('--row-playing-text') ?? accent,
        rowDivider: parse('--row-divider') ?? border,
        sidebarActiveBg:
            parse('--sidebar-item-active-bg') ?? accent.withValues(alpha: 0.18),
        sidebarActiveText: parse('--sidebar-item-active-text') ?? accent,
        sliderTrack: parse('--slider-track') ?? textMuted,
        sliderThumb: parse('--slider-thumb') ?? accent,
        scrollbarThumb: parse('--scrollbar-thumb') ?? textMuted,
        volumeAccent: parse('--volume-accent') ?? accent,
        waveformPlayed: parse('--waveform-played') ?? accent,
        waveformUnplayed:
            parse('--waveform-unplayed') ?? textMuted.withValues(alpha: 0.25),
        playerTitle: parse('--player-title') ?? textPrimary,
        playerArtist: parse('--player-artist') ?? textSecondary,
        logoStart: parse('--logo-color-start') ?? accent,
        logoEnd: parse('--logo-color-end') ?? accent2,
        sourceZipPath: sourceZipPath,
        thumbnailPath: thumbnailPath,
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Tema por defecto (si la carpeta está vacía o no existe)
  // ---------------------------------------------------------------------------

  static const builtInCrotoWave = AppTheme(
    id: 'crotowave-default',
    name: 'CrotoWave Oscuro',
    author: 'CrotoWave',
    version: '1.0.0',
    description: 'Tema oscuro por defecto.',
    mode: 'dark',
    tags: [],
    accent: Color(0xFFA855F7),
    accent2: Color(0xFF7C3AED),
    accentDim: Color(0x1FA855F7),
    accentGlow: Color(0x59A855F7),
    highlight: Color(0xFFFBBF24),
    bgApp: Color(0xFF000000),
    bgCard: Color(0xFF121212),
    bgElevated: Color(0xFF1F1F1F),
    bgSidebar: Color(0xFF000000),
    bgHover: Color(0xFF1F1F1F),
    bgPlayer: Color(0xFF000000),
    bgDeep: Color(0xFF000000),
    menuBg: Color(0xFF1F1F1F),
    modalBg: Color(0xFF1F1F1F),
    inputBg: Color(0xFF000000),
    inputBorder: Color(0xFF242424),
    inputFocusBorder: Color(0xFFA855F7),
    border: Color(0xFF242424),
    borderSubtle: Color(0xFF1A1A1A),
    cardHoverBorder: Color(0xFFA855F7),
    textPrimary: Colors.white,
    textSecondary: Color(0xFFBDBDBD),
    textMuted: Color(0xFF7A7A7A),
    textOnAccent: Colors.white,
    danger: Color(0xFFF87171),
    positive: Color(0xFF4ADE80),
    warning: Color(0xFFFBBF24),
    rowPlayingBg: Color(0x1FA855F7),
    rowPlayingText: Color(0xFFA855F7),
    rowDivider: Color(0xFF242424),
    sidebarActiveBg: Color(0x2EA855F7),
    sidebarActiveText: Color(0xFFA855F7),
    sliderTrack: Color(0xFF7A7A7A),
    sliderThumb: Color(0xFFA855F7),
    scrollbarThumb: Color(0xFF7A7A7A),
    volumeAccent: Color(0xFFA855F7),
    waveformPlayed: Color(0xFFA855F7),
    waveformUnplayed: Color(0x407A7A7A),
    playerTitle: Colors.white,
    playerArtist: Color(0xFFBDBDBD),
    logoStart: Color(0xFFA855F7),
    logoEnd: Color(0xFF7C3AED),
  );

  /// Constructor compacto para temas fijos bundleados: deriva toda la
  /// paleta extendida desde núcleo + overrides opcionales (igual que
  /// los fallbacks de [fromZipBytes]).
  static AppTheme fixed({
    required String id,
    required String name,
    String author = 'CrotoWave',
    String version = '1.0.0',
    String description = '',
    String mode = 'dark',
    List<String> tags = const [],
    required Color accent,
    Color? accent2,
    required Color bgApp,
    required Color bgCard,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? logoStart,
    Color? logoEnd,
  }) {
    final dark = mode.toLowerCase() != 'light';
    final tp = textPrimary ?? (dark ? Colors.white : const Color(0xFF1A1B20));
    final ts = textSecondary ??
        (dark ? const Color(0xFFBDBDBD) : const Color(0xFF4C4F69));
    final tm =
        textMuted ?? (dark ? const Color(0xFF7A7A7A) : const Color(0xFF8C8FA1));
    final a2 = accent2 ?? accent;
    final elevated = bgCard;
    final border = dark ? const Color(0xFF242424) : const Color(0xFFBCC0CC);
    return AppTheme(
      id: id,
      name: name,
      author: author,
      version: version,
      description: description,
      mode: mode,
      tags: tags,
      accent: accent,
      accent2: a2,
      accentDim: accent.withValues(alpha: 0.12),
      accentGlow: accent.withValues(alpha: 0.35),
      highlight: const Color(0xFFFBBF24),
      bgApp: bgApp,
      bgCard: bgCard,
      bgElevated: elevated,
      bgSidebar: bgApp,
      bgHover: elevated,
      bgPlayer: bgApp,
      bgDeep: bgApp,
      menuBg: elevated,
      modalBg: elevated,
      inputBg: bgApp,
      inputBorder: border,
      inputFocusBorder: accent,
      border: border,
      borderSubtle: border,
      cardHoverBorder: accent,
      textPrimary: tp,
      textSecondary: ts,
      textMuted: tm,
      textOnAccent: onColor(accent),
      danger: const Color(0xFFF87171),
      positive: const Color(0xFF4ADE80),
      warning: const Color(0xFFFBBF24),
      rowPlayingBg: accent.withValues(alpha: 0.12),
      rowPlayingText: accent,
      rowDivider: border,
      sidebarActiveBg: accent.withValues(alpha: 0.18),
      sidebarActiveText: accent,
      sliderTrack: tm,
      sliderThumb: accent,
      scrollbarThumb: tm,
      volumeAccent: accent,
      waveformPlayed: accent,
      waveformUnplayed: tm.withValues(alpha: 0.25),
      playerTitle: tp,
      playerArtist: ts,
      logoStart: logoStart ?? accent,
      logoEnd: logoEnd ?? a2,
    );
  }

  /// Temas fijos bundleados (nunca desinstalables), equivalentes a los
  /// `FIXED_THEMES` de Psysonic.
  static final List<AppTheme> fixedThemes = [
    AppTheme.fixed(
      id: 'latte',
      name: 'Crema',
      author: 'Psysonic',
      mode: 'light',
      description: 'Claro cálido para el día.',
      accent: const Color(0xFF8839EF),
      accent2: const Color(0xFF1E66F5),
      bgApp: const Color(0xFFEFF1F5),
      bgCard: const Color(0xFFCCD0DA),
    ),
    AppTheme.fixed(
      id: 'kanagawa-wave',
      name: 'Ola',
      author: 'Psysonic',
      description: 'Azules tormenta japoneses.',
      accent: const Color(0xFF7E9CD8),
      accent2: const Color(0xFF9CABCA),
      bgApp: const Color(0xFF1F1F28),
      bgCard: const Color(0xFF2A2A37),
    ),
    AppTheme.fixed(
      id: 'stark-hud',
      name: 'Neón celeste',
      author: 'Psysonic',
      description: 'Neón cian estilo HUD.',
      accent: const Color(0xFF00F2FF),
      accent2: const Color(0xFF0080FF),
      bgApp: const Color(0xFF0B0F15),
      bgCard: const Color(0xFF05070A),
    ),
    AppTheme.fixed(
      id: 'vision-dark',
      name: 'Noche dorada',
      author: 'Psysonic',
      description: 'Dorado sobre negro, seguro para daltonismo.',
      tags: const ['cvd-safe'],
      accent: const Color(0xFFFFD700),
      accent2: const Color(0xFFFFA500),
      bgApp: const Color(0xFF0D0B12),
      bgCard: const Color(0xFF16131E),
    ),
    AppTheme.fixed(
      id: 'vision-navy',
      name: 'Marino dorado',
      author: 'Psysonic',
      description: 'Dorado sobre azul marino, seguro para daltonismo.',
      tags: const ['cvd-safe'],
      accent: const Color(0xFFFFD700),
      accent2: const Color(0xFF4D9FFF),
      bgApp: const Color(0xFF0A1628),
      bgCard: const Color(0xFF112038),
    ),
  ];

  // ---------------------------------------------------------------------------
  // Material ThemeData derivado
  // ---------------------------------------------------------------------------

  ThemeData toThemeData() {
    final brightness = isDark ? Brightness.dark : Brightness.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    ).copyWith(
      surface: bgApp,
      primary: accent,
      onPrimary: _onColor(accent),
      secondary: accent2,
      error: danger,
    );
    return materialPresentation(
      this,
      ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: bgApp,
        cardColor: bgCard,
        dialogTheme: DialogThemeData(backgroundColor: modalBg),
        dividerColor: rowDivider,
        progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: accent,
          selectionColor: accentDim,
          selectionHandleColor: accent,
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: accent,
          inactiveTrackColor: sliderTrack,
          thumbColor: sliderThumb,
          overlayColor: accentDim,
        ),
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStatePropertyAll(scrollbarThumb),
          thickness: const WidgetStatePropertyAll(6),
          radius: const Radius.circular(3),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: inputBg,
          hintStyle: TextStyle(color: textMuted),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: inputBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: inputFocusBorder, width: 1.5),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        useMaterial3: true,
      ),
    );
  }

  static Color _onColor(Color bg) {
    return onColor(bg);
  }

  /// Color de texto legible sobre [bg] (negro o blanco según luminancia).
  static Color onColor(Color bg) {
    final l =
        (0.299 * bg.r * 255 + 0.587 * bg.g * 255 + 0.114 * bg.b * 255) / 255;
    return l > 0.6 ? Colors.black : Colors.white;
  }

  // ---------------------------------------------------------------------------
  // Parseo CSS
  // ---------------------------------------------------------------------------

  /// Resuelve `var(--otra [, respaldo])` dentro de un valor CSS.
  /// Algunos temas (p. ej. `gw-*`) componen colores así:
  /// `rgba(var(--gw-accent-rgb), 0.11)`.
  static String _resolveVars(
    String raw,
    Map<String, String> vars, [
    int depth = 0,
  ]) {
    if (depth > 4 || !raw.contains('var(')) return raw;
    final reg = RegExp(r'var\(\s*(--[\w-]+)\s*(?:,\s*([^)]+))?\)');
    return raw.replaceAllMapped(reg, (m) {
      final name = m.group(1)!.toLowerCase();
      final fallback = m.group(2);
      final v = vars[name] ?? fallback ?? '';
      return _resolveVars(v, vars, depth + 1);
    });
  }

  /// Extrae `--var: valor;` del bloque `[data-theme=...] { ... }`.
  static Map<String, String> _parseCssVars(String css) {
    final out = <String, String>{};
    // Quita comentarios /* ... */
    final clean = css.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
    final reg = RegExp(r'(--[\w-]+)\s*:\s*([^;]+);');
    for (final m in reg.allMatches(clean)) {
      out[m.group(1)!.trim().toLowerCase()] = m.group(2)!.trim();
    }
    return out;
  }

  /// Convierte `#fff`, `#rrggbb`, `#rrggbbaa`, `rgb()`, `rgba()`.
  static Color? parseCssColor(String raw) {
    var v = raw.trim().toLowerCase();
    // Quita !important
    v = v.replaceAll('!important', '').trim();
    if (v.isEmpty || v == 'transparent') return Colors.transparent;
    if (v == 'none') return null;

    if (v.startsWith('#')) {
      var hex = v.substring(1).replaceAll(RegExp(r'[^0-9a-f]'), '');
      if (hex.length == 3) {
        hex = hex.split('').map((c) => '$c$c').join();
      }
      if (hex.length == 6) {
        // #rrggbb opaco -> 0xffrrggbb.
        final i = int.tryParse('ff$hex', radix: 16);
        if (i == null) return null;
        return Color(i);
      }
      if (hex.length == 8) {
        // CSS usa #rrggbbaa, Flutter usa 0xaarrggbb.
        final rr = hex.substring(0, 2);
        final gg = hex.substring(2, 4);
        final bb = hex.substring(4, 6);
        final aa = hex.substring(6, 8);
        final i = int.tryParse('$aa$rr$gg$bb', radix: 16);
        if (i == null) return null;
        return Color(i);
      }
      return null;
    }

    final rgb = RegExp(
      r'rgba?\s*\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)(?:\s*,\s*([\d.]+))?\s*\)',
    ).firstMatch(v);
    if (rgb != null) {
      final r = (double.tryParse(rgb.group(1)!) ?? 0).clamp(0, 255).toInt();
      final g = (double.tryParse(rgb.group(2)!) ?? 0).clamp(0, 255).toInt();
      final b = (double.tryParse(rgb.group(3)!) ?? 0).clamp(0, 255).toInt();
      double a = 1;
      if (rgb.group(4) != null) {
        a = double.tryParse(rgb.group(4)!) ?? 1;
        if (a > 1) a = a / 255;
      }
      return Color.fromRGBO(r, g, b, a.clamp(0.0, 1.0));
    }

    const named = {
      'white': 0xFFFFFFFF,
      'black': 0xFF000000,
      'red': 0xFFFF0000,
      'green': 0xFF008000,
      'blue': 0xFF0000FF,
    };
    if (named.containsKey(v)) return Color(named[v]!);
    return null;
  }
}
