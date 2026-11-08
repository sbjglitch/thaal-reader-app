import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../domain/entities/app_preferences.dart';

/// The app theme setting. A change is shown only after it has been saved,
/// so the app never looks set to a theme it will forget on restart.
class AppThemeController extends Notifier<AppThemePreference> {
  @override
  AppThemePreference build() =>
      ref.watch(appPreferencesStoreProvider).loadTheme();

  /// Returns false when the setting could not be saved; the current theme
  /// is kept then.
  Future<bool> select(AppThemePreference theme) async {
    if (theme == state) return true;
    bool saved;
    try {
      saved = await ref.read(appPreferencesStoreProvider).saveTheme(theme);
    } on Exception catch (error) {
      ref
          .read(appLoggerProvider)
          .warning('settings.theme_save_failed', error: error);
      saved = false;
    }
    if (saved) state = theme;
    return saved;
  }
}

final appThemeProvider =
    NotifierProvider<AppThemeController, AppThemePreference>(
      AppThemeController.new,
    );

ThemeMode themeModeFor(AppThemePreference theme) => switch (theme) {
  AppThemePreference.system => ThemeMode.system,
  AppThemePreference.light => ThemeMode.light,
  AppThemePreference.dark => ThemeMode.dark,
};

/// The brightness the app is shown in, given the device's.
Brightness appBrightnessFor(AppThemePreference theme, Brightness device) =>
    switch (theme) {
      AppThemePreference.system => device,
      AppThemePreference.light => Brightness.light,
      AppThemePreference.dark => Brightness.dark,
    };
