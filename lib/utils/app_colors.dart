import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_theme.dart';
import '../services/theme_controller.dart';

/// Acceso corto a los colores del tema activo (elegido en Ajustes → Interfaz).
///
/// Uso dentro de cualquier `build`:
/// ```dart
/// Container(color: context.bgCard, child: Icon(Icons.play, color: context.accent))
/// ```
/// Al usar `watch`, el widget se reconstruye solo al cambiar de tema.
extension AppColors on BuildContext {
  AppTheme get appTheme => watch<ThemeController>().active;

  Color get accent => appTheme.accent;
  Color get accent2 => appTheme.accent2;
  Color get accentDim => appTheme.accentDim;
  Color get accentGlow => appTheme.accentGlow;
  Color get highlight => appTheme.highlight;
  Color get bgApp => appTheme.bgApp;
  Color get bgCard => appTheme.bgCard;
  Color get bgElevated => appTheme.bgElevated;
  Color get bgSidebar => appTheme.bgSidebar;
  Color get bgHover => appTheme.bgHover;
  Color get bgPlayer => appTheme.bgPlayer;
  Color get bgDeep => appTheme.bgDeep;
  Color get menuBg => appTheme.menuBg;
  Color get modalBg => appTheme.modalBg;
  Color get inputBg => appTheme.inputBg;
  Color get inputBorder => appTheme.inputBorder;
  Color get inputFocusBorder => appTheme.inputFocusBorder;
  Color get themeBorder => appTheme.border;
  Color get borderSubtle => appTheme.borderSubtle;
  Color get cardHoverBorder => appTheme.cardHoverBorder;
  Color get textPrimary => appTheme.textPrimary;
  Color get textSecondary => appTheme.textSecondary;
  Color get textMuted => appTheme.textMuted;
  Color get textOnAccent => appTheme.textOnAccent;
  Color get danger => appTheme.danger;
  Color get positive => appTheme.positive;
  Color get warning => appTheme.warning;
  Color get rowPlayingBg => appTheme.rowPlayingBg;
  Color get rowPlayingText => appTheme.rowPlayingText;
  Color get rowDivider => appTheme.rowDivider;
  Color get sidebarActiveBg => appTheme.sidebarActiveBg;
  Color get sidebarActiveText => appTheme.sidebarActiveText;
  Color get sliderTrack => appTheme.sliderTrack;
  Color get sliderThumb => appTheme.sliderThumb;
  Color get scrollbarThumb => appTheme.scrollbarThumb;
  Color get volumeAccent => appTheme.volumeAccent;
  Color get waveformPlayed => appTheme.waveformPlayed;
  Color get waveformUnplayed => appTheme.waveformUnplayed;
  Color get playerTitle => appTheme.playerTitle;
  Color get playerArtist => appTheme.playerArtist;
  Color get logoStart => appTheme.logoStart;
  Color get logoEnd => appTheme.logoEnd;

  /// Texto legible sobre el color de acento (para botones e indicadores).
  Color get onAccent => AppTheme.onColor(accent);

  /// Texto legible sobre el acento secundario (cabeceras de color).
  Color get onAccent2 => AppTheme.onColor(accent2);
}
