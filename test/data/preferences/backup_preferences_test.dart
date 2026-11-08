import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/data/preferences/app_preferences_store.dart';
import 'package:thaal/data/preferences/backup_preferences.dart';
import 'package:thaal/data/preferences/reader_preferences_store.dart';
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
      LibraryViewController.layoutKey,
      LibraryViewController.sortKey,
    });
  });
}
