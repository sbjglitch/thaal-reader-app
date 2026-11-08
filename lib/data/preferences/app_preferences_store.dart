import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/app_preferences.dart';

/// App-wide settings kept in SharedPreferences (CLAUDE.md §5). An unknown
/// stored value, for example from a later version, reads as the default.
class AppPreferencesStore {
  AppPreferencesStore(this._prefs);

  final SharedPreferences _prefs;

  static const themeKey = 'app.theme';

  AppThemePreference loadTheme() =>
      AppThemePreference.values.asNameMap()[_prefs.getString(themeKey)] ??
      AppThemePreference.system;

  /// Returns false when the value could not be written.
  Future<bool> saveTheme(AppThemePreference theme) =>
      _prefs.setString(themeKey, theme.name);
}
