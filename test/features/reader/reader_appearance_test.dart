import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/app/theme/reading_page_colors.dart';
import 'package:thaal/domain/entities/reader_preferences.dart';
import 'package:thaal/features/reader/application/reader_preferences_controller.dart';

void main() {
  (Color, Color) colors(ReadingTheme theme, Brightness brightness) {
    final appearance = resolveAppearance(
      ReaderPreferences(theme: theme),
      brightness,
    );
    return (appearance.background, appearance.foreground);
  }

  // Light, dark and system are covered by reader_preferences_store_test.
  test('sepia and twilight keep their colours in both app themes', () {
    for (final brightness in Brightness.values) {
      expect(colors(ReadingTheme.sepia, brightness), (
        ReadingPageColors.sepiaBackground,
        ReadingPageColors.sepiaText,
      ));
      expect(colors(ReadingTheme.twilight, brightness), (
        ReadingPageColors.twilightBackground,
        ReadingPageColors.twilightText,
      ));
    }
  });

  test('every theme keeps text contrast of at least 7:1', () {
    double contrast(Color a, Color b) {
      final (light, dark) = a.computeLuminance() > b.computeLuminance()
          ? (a, b)
          : (b, a);
      return (light.computeLuminance() + 0.05) /
          (dark.computeLuminance() + 0.05);
    }

    for (final theme in ReadingTheme.values) {
      for (final brightness in Brightness.values) {
        final (background, text) = colors(theme, brightness);
        expect(
          contrast(background, text),
          greaterThanOrEqualTo(7),
          reason: '$theme in $brightness',
        );
      }
    }
  });
}
