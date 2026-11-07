import 'package:flutter/material.dart';

import 'app_color_tokens.dart';
import 'app_component_themes.dart';
import 'app_text_tokens.dart';

/// App chrome themes. Publication rendering colours (reader page themes) are
/// configured separately in the reader feature, per UI/UX spec §3.4 and §9.
abstract final class AppTheme {
  static final ThemeData light = _build(AppColorTokens.light, Brightness.light);
  static final ThemeData dark = _build(AppColorTokens.dark, Brightness.dark);

  static ThemeData _build(AppColorTokens colors, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: colors.accent,
      onPrimary: colors.onAccent,
      secondary: colors.accent,
      onSecondary: colors.onAccent,
      error: colors.danger,
      onError: colors.onAccent,
      surface: colors.background,
      onSurface: colors.textPrimary,
      onSurfaceVariant: colors.textSecondary,
      surfaceContainerLowest: colors.background,
      surfaceContainerLow: colors.surface,
      surfaceContainer: colors.surface,
      surfaceContainerHigh: colors.surfaceElevated,
      surfaceContainerHighest: colors.surfaceElevated,
      outline: colors.border,
      outlineVariant: colors.border,
      surfaceTint: Colors.transparent,
    );
    final text = AppTextTokens.textTheme(colors);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      textTheme: text,
      extensions: [colors],
      appBarTheme: AppComponentThemes.appBar(colors, text),
      navigationBarTheme: AppComponentThemes.navigationBar(colors, text),
      filledButtonTheme: AppComponentThemes.filledButton(colors),
      textButtonTheme: AppComponentThemes.textButton(colors),
      dividerTheme: AppComponentThemes.divider(colors),
      progressIndicatorTheme: AppComponentThemes.progressIndicator(colors),
      snackBarTheme: AppComponentThemes.snackBar(colors, text),
      dialogTheme: AppComponentThemes.dialog(colors, text),
      bottomSheetTheme: AppComponentThemes.bottomSheet(colors),
    );
  }
}
