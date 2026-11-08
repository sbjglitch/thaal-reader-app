import 'package:flutter/material.dart';

import 'app_color_tokens.dart';
import 'app_radius_tokens.dart';

/// Component themes styled from tokens. The spec prefers surface contrast and
/// subtle borders over elevation, so shadows and tints are disabled.
abstract final class AppComponentThemes {
  static AppBarThemeData appBar(AppColorTokens colors, TextTheme text) {
    return AppBarThemeData(
      backgroundColor: colors.background,
      foregroundColor: colors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: text.headlineSmall,
    );
  }

  static NavigationBarThemeData navigationBar(
    AppColorTokens colors,
    TextTheme text,
  ) {
    return NavigationBarThemeData(
      backgroundColor: colors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: colors.surface,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => text.labelMedium?.copyWith(
          color: states.contains(WidgetState.selected)
              ? colors.textPrimary
              : colors.textSecondary,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? colors.textPrimary
              : colors.textSecondary,
        ),
      ),
    );
  }

  static FilledButtonThemeData filledButton(AppColorTokens colors) {
    return FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        minimumSize: const Size(64, 48),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mediumAll),
      ),
    );
  }

  static TextButtonThemeData textButton(AppColorTokens colors) {
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.textPrimary,
        minimumSize: const Size(48, 48),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mediumAll),
      ),
    );
  }

  static DividerThemeData divider(AppColorTokens colors) {
    return DividerThemeData(color: colors.border, thickness: 1, space: 1);
  }

  static ProgressIndicatorThemeData progressIndicator(AppColorTokens colors) {
    return ProgressIndicatorThemeData(
      color: colors.accent,
      linearTrackColor: colors.border,
    );
  }

  static SnackBarThemeData snackBar(AppColorTokens colors, TextTheme text) {
    return SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colors.textPrimary,
      contentTextStyle: text.bodyMedium?.copyWith(color: colors.background),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.mediumAll),
    );
  }

  static DialogThemeData dialog(AppColorTokens colors, TextTheme text) {
    return DialogThemeData(
      backgroundColor: colors.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.largeAll),
      titleTextStyle: text.titleMedium,
      contentTextStyle: text.bodyMedium,
    );
  }

  static BottomSheetThemeData bottomSheet(AppColorTokens colors) {
    return BottomSheetThemeData(
      backgroundColor: colors.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.large),
        ),
      ),
    );
  }
}
