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

  /// The allowlisted settings that are set and have the expected type.
  static Map<String, Object> read(SharedPreferences prefs) {
    final values = <String, Object>{};
    for (final MapEntry(:key, value: type) in allowlist.entries) {
      final value = prefs.get(key);
      if (value != null && value.runtimeType == type) values[key] = value;
    }
    return values;
  }
}
