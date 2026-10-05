import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Presentación Material común, derivada exclusivamente de los temas de la app.
ThemeData materialPresentation(AppTheme colors, ThemeData base) {
  final transparent = colors.bgCard.withValues(alpha: 0);
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
    side: BorderSide(color: colors.borderSubtle),
  );
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
  );
  final buttonHeight = base.platform == TargetPlatform.android ? 48.0 : 40.0;
  final buttonStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(64, buttonHeight)),
    shape: WidgetStatePropertyAll(buttonShape),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );
  final scheme = base.colorScheme.copyWith(
    surface: colors.bgApp,
    onPrimary: colors.textOnAccent,
    onSurface: colors.textPrimary,
    onSurfaceVariant: colors.textSecondary,
    surfaceContainerLow: colors.bgCard,
    surfaceContainer: colors.bgElevated,
    surfaceContainerHigh: colors.menuBg,
    outline: colors.border,
    outlineVariant: colors.borderSubtle,
    primaryContainer: colors.sidebarActiveBg,
    onPrimaryContainer: colors.sidebarActiveText,
    secondaryContainer: colors.accentDim,
    onSecondaryContainer: colors.textPrimary,
  );
  return base.copyWith(
    colorScheme: scheme,
    textTheme: base.textTheme.apply(
      bodyColor: colors.textPrimary,
      displayColor: colors.textPrimary,
    ),
    iconTheme: base.iconTheme.copyWith(color: colors.textSecondary),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.bgApp,
      foregroundColor: colors.textPrimary,
      surfaceTintColor: transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        color: colors.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      color: colors.bgCard,
      surfaceTintColor: transparent,
      elevation: 0,
      shape: shape,
      clipBehavior: Clip.antiAlias,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.modalBg,
      surfaceTintColor: transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.borderSubtle),
      ),
      titleTextStyle: TextStyle(
        color: colors.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: TextStyle(color: colors.textSecondary, fontSize: 14),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.modalBg,
      modalBackgroundColor: colors.modalBg,
      surfaceTintColor: transparent,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: colors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.menuBg,
      surfaceTintColor: transparent,
      shape: shape,
      textStyle: TextStyle(color: colors.textPrimary, fontSize: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
        style: buttonStyle.copyWith(
      backgroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.disabled)
              ? colors.bgElevated
              : colors.accent),
      foregroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.disabled)
              ? colors.textMuted
              : colors.textOnAccent),
    )),
    elevatedButtonTheme: ElevatedButtonThemeData(
        style: buttonStyle.copyWith(
      backgroundColor: WidgetStatePropertyAll(colors.bgElevated),
      foregroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.disabled)
              ? colors.textMuted
              : colors.accent),
      surfaceTintColor: WidgetStatePropertyAll(transparent),
      elevation: const WidgetStatePropertyAll(0),
    )),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: buttonStyle.copyWith(
      foregroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.disabled)
              ? colors.textMuted
              : colors.textSecondary),
      side: WidgetStatePropertyAll(BorderSide(color: colors.border)),
    )),
    textButtonTheme: TextButtonThemeData(
        style: buttonStyle.copyWith(
      foregroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.disabled)
              ? colors.textMuted
              : colors.accent),
    )),
    listTileTheme: ListTileThemeData(
      textColor: colors.textPrimary,
      iconColor: colors.textSecondary,
      selectedColor: colors.sidebarActiveText,
      selectedTileColor: colors.sidebarActiveBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.menuBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.borderSubtle),
      ),
      textStyle: TextStyle(color: colors.textPrimary, fontSize: 12),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.bgElevated,
      contentTextStyle: TextStyle(color: colors.textPrimary, fontSize: 14),
      actionTextColor: colors.accent,
      shape: buttonShape,
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      labelStyle: TextStyle(color: colors.textSecondary),
      errorStyle: TextStyle(color: colors.danger),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.inputBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.inputFocusBorder, width: 1.5),
      ),
    ),
  );
}
