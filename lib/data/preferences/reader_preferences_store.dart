import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/reader_preferences.dart';

/// Persists [ReaderPreferences] as small global settings in
/// SharedPreferences (CLAUDE.md §5). Unknown or invalid stored values, for
/// example from a later app version, fall back to the defaults field by
/// field.
class ReaderPreferencesStore {
  ReaderPreferencesStore(this._prefs);

  final SharedPreferences _prefs;

  static const themeKey = 'reader.theme';
  static const fontScaleKey = 'reader.epub.fontScale';
  static const epubLayoutKey = 'reader.epub.layout';
  static const pdfLayoutKey = 'reader.pdf.layout';
  static const pdfFitKey = 'reader.pdf.fit';

  ReaderPreferences load() {
    const defaults = ReaderPreferences();
    final scale = _prefs.getDouble(fontScaleKey);
    return ReaderPreferences(
      theme: _enum(ReadingTheme.values, themeKey) ?? defaults.theme,
      fontScale: scale == null || scale.isNaN ? defaults.fontScale : scale,
      epubLayout:
          _enum(PageLayout.values, epubLayoutKey) ?? defaults.epubLayout,
      pdfLayout: _enum(PageLayout.values, pdfLayoutKey) ?? defaults.pdfLayout,
      pdfFit: _enum(PdfPageFit.values, pdfFitKey) ?? defaults.pdfFit,
    );
  }

  Future<void> save(ReaderPreferences preferences) async {
    await Future.wait([
      _prefs.setString(themeKey, preferences.theme.name),
      _prefs.setDouble(fontScaleKey, preferences.fontScale),
      _prefs.setString(epubLayoutKey, preferences.epubLayout.name),
      _prefs.setString(pdfLayoutKey, preferences.pdfLayout.name),
      _prefs.setString(pdfFitKey, preferences.pdfFit.name),
    ]);
  }

  T? _enum<T extends Enum>(List<T> values, String key) =>
      values.asNameMap()[_prefs.getString(key)];
}
