import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaal/data/preferences/app_preferences_store.dart';
import 'package:thaal/domain/entities/app_preferences.dart';

void main() {
  Future<AppPreferencesStore> store(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return AppPreferencesStore(await SharedPreferences.getInstance());
  }

  test('defaults to following the system', () async {
    expect((await store({})).loadTheme(), AppThemePreference.system);
  });

  test('an unknown stored value reads as the default', () async {
    final s = await store({'flutter.app.theme': 'sepia'});
    expect(s.loadTheme(), AppThemePreference.system);
  });

  test('saves and loads the theme', () async {
    final s = await store({});
    expect(await s.saveTheme(AppThemePreference.dark), isTrue);
    expect(s.loadTheme(), AppThemePreference.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AppPreferencesStore.themeKey), 'dark');
  });
}
