import 'dart:ui' show Brightness;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_color_tokens.dart';
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

/// Resolves the reading theme to page colours from the app's colour tokens
/// (UI/UX §3.4). `system` follows [platformBrightness].
ReaderAppearance resolveAppearance(
  ReaderPreferences preferences,
  Brightness platformBrightness,
) {
  final dark = switch (preferences.theme) {
    ReadingTheme.light => false,
    ReadingTheme.dark => true,
    ReadingTheme.system => platformBrightness == Brightness.dark,
  };
  final tokens = dark ? AppColorTokens.dark : AppColorTokens.light;
  return ReaderAppearance(
    preferences: preferences,
    background: tokens.background,
    foreground: tokens.textPrimary,
  );
}
