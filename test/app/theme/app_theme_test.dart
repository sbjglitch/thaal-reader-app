import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thaal/app/theme/app_color_tokens.dart';
import 'package:thaal/app/theme/app_theme.dart';

void main() {
  test('light tokens match the UI/UX specification', () {
    const c = AppColorTokens.light;
    expect(c.background, const Color(0xFFFFFFFF));
    expect(c.textPrimary, const Color(0xFF17191C));
    expect(c.border, const Color(0xFFE7E9EB));
    expect(c.accent, const Color(0xFF303943));
    expect(c.danger, const Color(0xFFB33B3B));
  });

  test('dark tokens match the UI/UX specification', () {
    const c = AppColorTokens.dark;
    expect(c.background, const Color(0xFF121416));
    expect(c.textPrimary, const Color(0xFFF3F4F4));
    expect(c.border, const Color(0xFF30353A));
    expect(c.accent, const Color(0xFFD9E0E5));
    expect(c.danger, const Color(0xFFF08B8B));
  });

  for (final (name, theme, tokens) in [
    ('light', AppTheme.light, AppColorTokens.light),
    ('dark', AppTheme.dark, AppColorTokens.dark),
  ]) {
    test('$name theme maps tokens onto ThemeData', () {
      expect(theme.extension<AppColorTokens>(), same(tokens));
      expect(theme.colorScheme.primary, tokens.accent);
      expect(theme.colorScheme.surface, tokens.background);
      expect(theme.colorScheme.onSurface, tokens.textPrimary);
      expect(theme.colorScheme.error, tokens.danger);
      expect(theme.scaffoldBackgroundColor, tokens.background);
      expect(theme.dividerTheme.color, tokens.border);
    });

    test('$name theme uses the specified type scale', () {
      final text = theme.textTheme;
      expect(text.displaySmall?.fontSize, 28);
      expect(text.headlineSmall?.fontSize, 24);
      expect(text.titleLarge?.fontSize, 20);
      expect(text.titleMedium?.fontSize, 16);
      expect(text.bodyMedium?.fontSize, 14);
      expect(text.bodySmall?.fontSize, 13);
      expect(text.labelMedium?.fontSize, 12);
      expect(text.titleMedium?.fontWeight, FontWeight.w600);
    });
  }
}
