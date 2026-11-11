import 'dart:ui' show Brightness;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_color_tokens.dart';
import '../../../app/theme/reading_page_colors.dart';
import '../../../domain/entities/reader_preferences.dart';
import '../../../services/reader/publication_reader.dart';

/// The saved reading preferences. Changes go through
/// `ReaderController.updatePreferences`, which applies them to the engine
/// first and only then calls [save], so a rejected setting is never stored.
class ReaderPreferencesController extends Notifier<ReaderPreferences> {
  @override
  ReaderPreferences build() => ref.watch(readerPreferencesStoreProvider).load();

  Future<void> save(ReaderPreferences preferences) async {
    state = preferences;
    try {
      await ref.read(readerPreferencesStoreProvider).save(preferences);
    } on Object catch (error) {
      // Kept in memory for this run; the next launch uses the last saved set.
      ref
          .read(appLoggerProvider)
          .warning('reader.preferences_save_failed', error: error);
    }
  }
}

final readerPreferencesProvider =
    NotifierProvider<ReaderPreferencesController, ReaderPreferences>(
      ReaderPreferencesController.new,
    );

/// Window brightness while a book is open (UI/UX §7.6). The reader screen
/// calls [activate] when it opens and [release] when it closes, so outside
/// the reader the system always decides.
class ReaderBrightnessController extends Notifier<ReaderBrightness> {
  bool _active = false;

  @override
  ReaderBrightness build() =>
      ref.watch(readerPreferencesStoreProvider).loadBrightness();

  /// Whether brightness can be set here; the controls are hidden if not.
  bool get isSupported => ref.read(screenBrightnessProvider).isSupported;

  Future<void> activate() async {
    _active = true;
    await _apply(state.followsSystem ? null : state.level);
  }

  Future<void> release() async {
    _active = false;
    await _apply(null);
  }

  /// Shows [level] while the slider is dragged, without saving it.
  Future<void> preview(double level) async {
    if (_active) await _apply(level);
  }

  Future<void> save(ReaderBrightness brightness) async {
    state = brightness;
    if (_active) {
      await _apply(brightness.followsSystem ? null : brightness.level);
    }
    try {
      await ref.read(readerPreferencesStoreProvider).saveBrightness(brightness);
    } on Object catch (error) {
      // Kept for this run; the next launch uses the last saved value.
      ref
          .read(appLoggerProvider)
          .warning('reader.brightness_save_failed', error: error);
    }
  }

  Future<void> _apply(double? level) async {
    final screen = ref.read(screenBrightnessProvider);
    if (!screen.isSupported) return;
    if (!await screen.apply(level)) {
      ref.read(appLoggerProvider).warning('reader.brightness_apply_failed');
    }
  }
}

final readerBrightnessProvider =
    NotifierProvider<ReaderBrightnessController, ReaderBrightness>(
      ReaderBrightnessController.new,
    );

/// Resolves the reading theme to page colours (UI/UX §3.4). Light and dark
/// use the app's colour tokens; `system` follows the app's [appBrightness],
/// which itself follows the device unless the app theme is set (UI/UX §3.3).
/// Sepia and twilight have fixed colours.
ReaderAppearance resolveAppearance(
  ReaderPreferences preferences,
  Brightness appBrightness,
) {
  const light = AppColorTokens.light;
  const dark = AppColorTokens.dark;
  final (background, foreground) = switch (preferences.theme) {
    ReadingTheme.light => (light.background, light.textPrimary),
    ReadingTheme.dark => (dark.background, dark.textPrimary),
    ReadingTheme.system =>
      appBrightness == Brightness.dark
          ? (dark.background, dark.textPrimary)
          : (light.background, light.textPrimary),
    ReadingTheme.sepia => (
      ReadingPageColors.sepiaBackground,
      ReadingPageColors.sepiaText,
    ),
    ReadingTheme.twilight => (
      ReadingPageColors.twilightBackground,
      ReadingPageColors.twilightText,
    ),
  };
  return ReaderAppearance(
    preferences: preferences,
    background: background,
    foreground: foreground,
  );
}
