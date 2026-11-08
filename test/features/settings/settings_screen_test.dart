import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaal/app/providers.dart';
import 'package:thaal/app/theme/app_theme.dart';
import 'package:thaal/data/preferences/app_preferences_store.dart';
import 'package:thaal/domain/entities/app_preferences.dart';
import 'package:thaal/features/settings/application/app_theme_controller.dart';
import 'package:thaal/features/settings/presentation/settings_screen.dart';

/// A store whose writes fail.
class _FailingStore extends AppPreferencesStore {
  _FailingStore(super.prefs);

  @override
  Future<bool> saveTheme(AppThemePreference theme) async => false;
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  /// The settings screen inside an app that applies the chosen theme.
  Future<void> pump(WidgetTester tester, {bool failWrites = false}) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          if (failWrites)
            appPreferencesStoreProvider.overrideWithValue(_FailingStore(prefs)),
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: themeModeFor(ref.watch(appThemeProvider)),
            home: const SettingsScreen(),
          ),
        ),
      ),
    );
  }

  Brightness shownBrightness(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(SettingsScreen))).brightness;

  testWidgets('offers System, Light and Dark with System selected', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Appearance'), findsOneWidget);
    for (final label in ['System', 'Light', 'Dark']) {
      expect(find.text(label), findsOneWidget);
    }
    final group = tester.widget<RadioGroup<AppThemePreference>>(
      find.byType(RadioGroup<AppThemePreference>),
    );
    expect(group.groupValue, AppThemePreference.system);
  });

  testWidgets('choosing Dark switches the app and is saved', (tester) async {
    await pump(tester);
    expect(shownBrightness(tester), Brightness.light);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(shownBrightness(tester), Brightness.dark);
    expect(prefs.getString(AppPreferencesStore.themeKey), 'dark');
  });

  testWidgets('a saved theme is used on the next start', (tester) async {
    await prefs.setString(AppPreferencesStore.themeKey, 'dark');
    await pump(tester);
    expect(shownBrightness(tester), Brightness.dark);
  });

  testWidgets('a failed save keeps the current theme and says so', (
    tester,
  ) async {
    await pump(tester, failWrites: true);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(shownBrightness(tester), Brightness.light);
    expect(find.text('The theme could not be changed.'), findsOneWidget);
  });

  test('app brightness follows the device only for System', () {
    expect(
      appBrightnessFor(AppThemePreference.system, Brightness.dark),
      Brightness.dark,
    );
    expect(
      appBrightnessFor(AppThemePreference.light, Brightness.dark),
      Brightness.light,
    );
    expect(
      appBrightnessFor(AppThemePreference.dark, Brightness.light),
      Brightness.dark,
    );
  });
}
