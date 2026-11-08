import 'package:flutter/material.dart';

import 'app_color_tokens.dart';

/// Type scale from docs/UI_UX_SPECIFICATION.md §4, mapped onto Material's
/// [TextTheme] slots. The platform system font is used (no custom fonts).
///
/// | Spec style  | TextTheme slot  |
/// |-------------|-----------------|
/// | Display     | displaySmall    |
/// | Heading 1   | headlineSmall   |
/// | Heading 2   | titleLarge      |
/// | Heading 3   | titleMedium     |
/// | Body        | bodyLarge (16), bodyMedium (14) |
/// | Body small  | bodySmall       |
/// | Label       | labelMedium     |
/// | Caption     | labelSmall      |
///
/// `labelLarge` (14, medium) is used by Material buttons; the spec has no
/// button style, so it follows the label weight at body size.
abstract final class AppTextTokens {
  static const _semibold = FontWeight.w600;
  static const _medium = FontWeight.w500;
  static const _regular = FontWeight.w400;

  static TextTheme textTheme(AppColorTokens colors) {
    TextStyle style(double size, FontWeight weight, Color color) =>
        TextStyle(fontSize: size, fontWeight: weight, color: color);

    return TextTheme(
      displaySmall: style(28, _semibold, colors.textPrimary),
      headlineSmall: style(24, _semibold, colors.textPrimary),
      titleLarge: style(20, _semibold, colors.textPrimary),
      titleMedium: style(16, _semibold, colors.textPrimary),
      bodyLarge: style(16, _regular, colors.textPrimary),
      bodyMedium: style(14, _regular, colors.textPrimary),
      bodySmall: style(13, _regular, colors.textSecondary),
      labelLarge: style(14, _medium, colors.textPrimary),
      labelMedium: style(12, _medium, colors.textSecondary),
      labelSmall: style(11, _regular, colors.textSecondary),
    );
  }
}
