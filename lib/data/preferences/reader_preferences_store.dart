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
  static const pageMarginsKey = 'reader.epub.pageMargins';
  static const textAlignmentKey = 'reader.epub.textAlignment';
  static const fontFaceKey = 'reader.epub.fontFace';

  /// Brightness keys. Deliberately absent from the backup allowlist
  /// (BACKUP_FORMAT.md): the level suits one device's screen.
  static const brightnessFollowsSystemKey = 'reader.brightness.followsSystem';
  static const brightnessLevelKey = 'reader.brightness.level';

  ReaderPreferences load() {
    const defaults = ReaderPreferences();
    final scale = _prefs.getDouble(fontScaleKey);
    final margins = _prefs.getDouble(pageMarginsKey);
    return ReaderPreferences(
      theme: _enum(ReadingTheme.values, themeKey) ?? defaults.theme,
      fontScale: scale == null || scale.isNaN ? defaults.fontScale : scale,
      epubLayout:
          _enum(PageLayout.values, epubLayoutKey) ?? defaults.epubLayout,
      pdfLayout: _enum(PageLayout.values, pdfLayoutKey) ?? defaults.pdfLayout,
      pdfFit: _enum(PdfPageFit.values, pdfFitKey) ?? defaults.pdfFit,
      pageMargins: margins == null || margins.isNaN
          ? defaults.pageMargins
          : margins,
      textAlignment:
          _enum(TextAlignment.values, textAlignmentKey) ??
          defaults.textAlignment,
      fontFace: _enum(FontFace.values, fontFaceKey) ?? defaults.fontFace,
    );
  }

  Future<void> save(ReaderPreferences preferences) async {
    await Future.wait([
      _prefs.setString(themeKey, preferences.theme.name),
      _prefs.setDouble(fontScaleKey, preferences.fontScale),
      _prefs.setString(epubLayoutKey, preferences.epubLayout.name),
      _prefs.setString(pdfLayoutKey, preferences.pdfLayout.name),
      _prefs.setString(pdfFitKey, preferences.pdfFit.name),
      _prefs.setDouble(pageMarginsKey, preferences.pageMargins),
      _prefs.setString(textAlignmentKey, preferences.textAlignment.name),
      _prefs.setString(fontFaceKey, preferences.fontFace.name),
    ]);
  }

  ReaderBrightness loadBrightness() {
    const defaults = ReaderBrightness();
    final level = _prefs.getDouble(brightnessLevelKey);
    return ReaderBrightness(
      followsSystem:
          _prefs.getBool(brightnessFollowsSystemKey) ?? defaults.followsSystem,
      level: level == null || level.isNaN ? defaults.level : level,
    );
  }

  Future<void> saveBrightness(ReaderBrightness brightness) async {
    await Future.wait([
      _prefs.setBool(brightnessFollowsSystemKey, brightness.followsSystem),
      _prefs.setDouble(brightnessLevelKey, brightness.level),
    ]);
  }

  T? _enum<T extends Enum>(List<T> values, String key) =>
      values.asNameMap()[_prefs.getString(key)];
}
