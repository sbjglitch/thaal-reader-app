import 'package:flutter/material.dart';

/// Semantic colour tokens from docs/UI_UX_SPECIFICATION.md §3.3.
///
/// Most tokens are also mapped onto [ColorScheme] in `app_theme.dart`; this
/// extension exists for tokens Flutter's scheme has no slot for (tertiary
/// text, success, warning) and so widgets can read tokens by their spec name.
@immutable
class AppColorTokens extends ThemeExtension<AppColorTokens> {
  const AppColorTokens({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.border,
    required this.accent,
    required this.onAccent,
    required this.success,
    required this.warning,
    required this.danger,
  });

  static const light = AppColorTokens(
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF7F7F5),
    surfaceElevated: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF17191C),
    textSecondary: Color(0xFF666C72),
    textTertiary: Color(0xFF858B91),
    border: Color(0xFFE7E9EB),
    accent: Color(0xFF303943),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF287A52),
    warning: Color(0xFF98651A),
    danger: Color(0xFFB33B3B),
  );

  static const dark = AppColorTokens(
    background: Color(0xFF121416),
    surface: Color(0xFF1B1E21),
    surfaceElevated: Color(0xFF24282C),
    textPrimary: Color(0xFFF3F4F4),
    textSecondary: Color(0xFFA4A9AE),
    textTertiary: Color(0xFF7F878E),
    border: Color(0xFF30353A),
    accent: Color(0xFFD9E0E5),
    onAccent: Color(0xFF17191C),
    success: Color(0xFF75C69A),
    warning: Color(0xFFE8B967),
    danger: Color(0xFFF08B8B),
  );

  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color border;
  final Color accent;
  final Color onAccent;
  final Color success;
  final Color warning;
  final Color danger;

  @override
  AppColorTokens copyWith({
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? border,
    Color? accent,
    Color? onAccent,
    Color? success,
    Color? warning,
    Color? danger,
  }) {
    return AppColorTokens(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      border: border ?? this.border,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
    );
  }

  @override
  AppColorTokens lerp(AppColorTokens? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColorTokens(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surfaceElevated: mix(surfaceElevated, other.surfaceElevated),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textTertiary: mix(textTertiary, other.textTertiary),
      border: mix(border, other.border),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      danger: mix(danger, other.danger),
    );
  }
}

extension AppColorTokensContext on BuildContext {
  /// The colour tokens of the nearest [Theme]. Both app themes register them.
  AppColorTokens get colorTokens => Theme.of(this).extension<AppColorTokens>()!;
}
