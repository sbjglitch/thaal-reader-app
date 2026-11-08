import 'package:shared_preferences/shared_preferences.dart';

/// Settings a backup may carry (BACKUP_FORMAT.md §6.7). Only these keys are
/// read; nothing else in SharedPreferences is exported. The values are
/// written under their storage keys and validated again on restore.
abstract final class BackupPreferences {
  /// Key → expected stored type. Kept in step with the stores' key constants
  /// by test/data/preferences/backup_preferences_test.dart.
  static const Map<String, Type> allowlist = {
    'app.theme': String,
    'reader.theme': String,
    'reader.epub.fontScale': double,
    'reader.epub.layout': String,
    'reader.pdf.layout': String,
    'reader.pdf.fit': String,
    'library.layout': String,
    'library.sort': String,
  };

  /// Accepted string values per key, for keys that hold an enum name. Kept
  /// in step with the enums by the same test.
  static const Map<String, Set<String>> allowedValues = {
    'app.theme': {'system', 'light', 'dark'},
    'reader.theme': {'system', 'light', 'dark'},
    'reader.epub.layout': {'paginated', 'scroll'},
    'reader.pdf.layout': {'paginated', 'scroll'},
    'reader.pdf.fit': {'width', 'page'},
    'library.layout': {'list', 'grid'},
    'library.sort': {'recentlyAdded', 'recentlyOpened', 'title', 'progress'},
  };

  static const double _minFontScale = 0.8;
  static const double _maxFontScale = 2.0;

  /// The allowlisted settings that are set and have the expected type.
  static Map<String, Object> read(SharedPreferences prefs) {
    final values = <String, Object>{};
    for (final MapEntry(:key, value: type) in allowlist.entries) {
      final value = prefs.get(key);
      if (value != null && value.runtimeType == type) values[key] = value;
    }
    return values;
  }

  /// [value] as it should be stored under [key], or null when the key is not
  /// allowlisted or the value is invalid. Whole numbers are accepted for the
  /// font scale because JSON does not distinguish 1 from 1.0.
  static Object? validValue(String key, Object? value) {
    final type = allowlist[key];
    if (type == String) {
      return value is String && (allowedValues[key]?.contains(value) ?? false)
          ? value
          : null;
    }
    if (type == double && value is num) {
      final number = value.toDouble();
      return number.isFinite &&
              number >= _minFontScale &&
              number <= _maxFontScale
          ? number
          : null;
    }
    return null;
  }
}

/// Applies settings from a backup. Unknown keys and invalid values are
/// ignored one by one rather than rejecting the backup.
extension BackupPreferencesRestore on SharedPreferences {
  /// Writes the valid settings in [records] and returns how many were
  /// applied. Throws if a write fails.
  Future<int> applyBackupPreferences(Map<String, Object?> records) async {
    var applied = 0;
    for (final MapEntry(:key, :value) in records.entries) {
      final valid = BackupPreferences.validValue(key, value);
      if (valid == null) continue;
      final saved = switch (valid) {
        final String text => await setString(key, text),
        final double number => await setDouble(key, number),
        _ => false,
      };
      if (!saved) throw StateError('preference write failed');
      applied++;
    }
    return applied;
  }
}
