import 'dart:ui' show Brightness;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaal/app/theme/app_color_tokens.dart';
import 'package:thaal/data/preferences/reader_preferences_store.dart';
import 'package:thaal/domain/entities/reader_preferences.dart';
import 'package:thaal/features/reader/application/reader_preferences_controller.dart';

void main() {
  Future<ReaderPreferencesStore> store(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return ReaderPreferencesStore(await SharedPreferences.getInstance());
  }

  test('defaults when nothing is stored', () async {
    expect((await store({})).load(), const ReaderPreferences());
  });

  test('round-trips every field', () async {
    final s = await store({});
    const preferences = ReaderPreferences(
      theme: ReadingTheme.dark,
      fontScale: 1.6,
      epubLayout: PageLayout.scroll,
      pdfLayout: PageLayout.scroll,
      pdfFit: PdfPageFit.page,
    );
    await s.save(preferences);
    expect(s.load(), preferences);
  });

  test('invalid values fall back field by field', () async {
    final s = await store({
      ReaderPreferencesStore.themeKey: 'neon',
      ReaderPreferencesStore.fontScaleKey: 9.0,
      ReaderPreferencesStore.pdfFitKey: 'page',
    });
    final loaded = s.load();
    expect(loaded.theme, ReadingTheme.system);
    expect(loaded.fontScale, ReaderPreferences.maxFontScale);
    expect(loaded.pdfFit, PdfPageFit.page);
  });

  test('font scale is clamped', () {
    expect(const ReaderPreferences(fontScale: 0.1).fontScale, 0.8);
  });

  test('reading themes resolve to token colours', () {
    final light = resolveAppearance(
      const ReaderPreferences(theme: ReadingTheme.light),
      Brightness.dark,
    );
    expect(light.background, AppColorTokens.light.background);
    expect(light.foreground, AppColorTokens.light.textPrimary);

    final system = resolveAppearance(
      const ReaderPreferences(),
      Brightness.dark,
    );
    expect(system.background, AppColorTokens.dark.background);
  });
}
