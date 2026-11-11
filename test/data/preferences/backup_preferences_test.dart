import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaal/data/preferences/app_preferences_store.dart';
import 'package:thaal/data/preferences/backup_preferences.dart';
import 'package:thaal/data/preferences/reader_preferences_store.dart';
import 'package:thaal/domain/entities/app_preferences.dart';
import 'package:thaal/domain/entities/reader_preferences.dart';
import 'package:thaal/features/library/application/library_view.dart';

void main() {
  test('the allowlist names exactly the settings the stores use', () {
    expect(BackupPreferences.allowlist.keys.toSet(), {
      AppPreferencesStore.themeKey,
      ReaderPreferencesStore.themeKey,
      ReaderPreferencesStore.fontScaleKey,
      ReaderPreferencesStore.epubLayoutKey,
      ReaderPreferencesStore.pdfLayoutKey,
      ReaderPreferencesStore.pdfFitKey,
      ReaderPreferencesStore.pageMarginsKey,
      ReaderPreferencesStore.textAlignmentKey,
      ReaderPreferencesStore.fontFaceKey,
      LibraryViewController.layoutKey,
      LibraryViewController.sortKey,
    });
  });

  test('brightness is not backed up: it suits one device', () {
    expect(
      BackupPreferences.allowlist.keys,
      isNot(
        anyOf(
          contains(ReaderPreferencesStore.brightnessFollowsSystemKey),
          contains(ReaderPreferencesStore.brightnessLevelKey),
        ),
      ),
    );
  });

  test('allowed values match the enums they store', () {
    Set<String> names(List<Enum> values) => {for (final v in values) v.name};
    expect(BackupPreferences.allowedValues, {
      AppPreferencesStore.themeKey: names(AppThemePreference.values),
      ReaderPreferencesStore.themeKey: names(ReadingTheme.values),
      ReaderPreferencesStore.epubLayoutKey: names(PageLayout.values),
      ReaderPreferencesStore.pdfLayoutKey: names(PageLayout.values),
      ReaderPreferencesStore.pdfFitKey: names(PdfPageFit.values),
      ReaderPreferencesStore.textAlignmentKey: names(TextAlignment.values),
      ReaderPreferencesStore.fontFaceKey: names(FontFace.values),
      LibraryViewController.layoutKey: names(LibraryLayout.values),
      LibraryViewController.sortKey: names(LibrarySort.values),
    });
  });

  test('number ranges match the preference limits', () {
    expect(BackupPreferences.allowedRanges, {
      ReaderPreferencesStore.fontScaleKey: (
        ReaderPreferences.minFontScale,
        ReaderPreferences.maxFontScale,
      ),
      ReaderPreferencesStore.pageMarginsKey: (
        ReaderPreferences.minPageMargins,
        ReaderPreferences.maxPageMargins,
      ),
    });
    expect(
      BackupPreferences.validValue(ReaderPreferencesStore.pageMarginsKey, 2),
      2.0,
    );
    expect(
      BackupPreferences.validValue(ReaderPreferencesStore.pageMarginsKey, 0.1),
      isNull,
    );
  });

  test('applies only allowlisted, valid values', () async {
    SharedPreferences.setMockInitialValues({'app.theme': 'light'});
    final prefs = await SharedPreferences.getInstance();
    final applied = await prefs.applyBackupPreferences({
      'app.theme': 'dark',
      'reader.epub.fontScale': 2,
      'reader.pdf.fit': 'stretch',
      'library.sort': 'title',
      'other.key': 'value',
      'reader.theme': 7,
    });
    expect(applied, 3);
    expect(prefs.getString('app.theme'), 'dark');
    expect(prefs.getDouble('reader.epub.fontScale'), 2.0);
    expect(prefs.getString('reader.pdf.fit'), isNull);
    expect(prefs.getString('library.sort'), 'title');
    expect(prefs.get('other.key'), isNull);
    expect(BackupPreferences.validValue('reader.epub.fontScale', 9.0), isNull);
  });
}
