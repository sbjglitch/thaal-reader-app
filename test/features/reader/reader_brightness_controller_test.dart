import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaal/app/providers.dart';
import 'package:thaal/core/logging/app_logger.dart';
import 'package:thaal/data/preferences/reader_preferences_store.dart';
import 'package:thaal/domain/entities/reader_preferences.dart';
import 'package:thaal/features/reader/application/reader_preferences_controller.dart';

import 'fake_screen_brightness.dart';

void main() {
  late FakeScreenBrightness screen;
  late SharedPreferences prefs;
  late List<String> logged;

  Future<ProviderContainer> container({
    Map<String, Object> stored = const {},
    bool supported = true,
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    prefs = await SharedPreferences.getInstance();
    screen = FakeScreenBrightness(isSupported: supported);
    logged = [];
    final container = ProviderContainer.test(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        screenBrightnessProvider.overrideWithValue(screen),
        appLoggerProvider.overrideWithValue(
          AppLogger(sink: (entry) => logged.add(entry.event)),
        ),
      ],
    );
    return container;
  }

  ReaderBrightnessController controller(ProviderContainer c) =>
      c.read(readerBrightnessProvider.notifier);

  const dim = {
    ReaderPreferencesStore.brightnessFollowsSystemKey: false,
    ReaderPreferencesStore.brightnessLevelKey: 0.2,
  };

  test('opening the reader applies the saved level', () async {
    final c = await container(stored: dim);
    await controller(c).activate();
    expect(screen.applied, [0.2]);
  });

  test('following the system applies no level', () async {
    final c = await container();
    await controller(c).activate();
    expect(screen.applied, [null]);
  });

  test('leaving the reader hands brightness back to the system', () async {
    final c = await container(stored: dim);
    await controller(c).activate();
    await controller(c).release();
    expect(screen.applied, [0.2, null]);
  });

  test('a drag is shown live but only saved at the end', () async {
    final c = await container();
    await controller(c).activate();
    await controller(c).preview(0.7);
    expect(screen.applied.last, 0.7);
    expect(
      prefs.getBool(ReaderPreferencesStore.brightnessFollowsSystemKey),
      isNull,
    );

    await controller(c)
        .save(const ReaderBrightness(followsSystem: false, level: 0.7));
    expect(c.read(readerBrightnessProvider).level, 0.7);
    expect(
      ReaderPreferencesStore(prefs).loadBrightness(),
      const ReaderBrightness(followsSystem: false, level: 0.7),
    );
  });

  test('nothing is applied outside the reader', () async {
    final c = await container();
    await controller(c).preview(0.7);
    await controller(c)
        .save(const ReaderBrightness(followsSystem: false, level: 0.7));
    expect(screen.applied, isEmpty);
  });

  test('turning "match system" back on keeps the chosen level', () async {
    final c = await container(stored: dim);
    await controller(c).activate();
    await controller(c).save(const ReaderBrightness(level: 0.2));
    expect(screen.applied.last, isNull);
    expect(c.read(readerBrightnessProvider).level, 0.2);
  });

  test('unsupported platforms are never asked', () async {
    final c = await container(stored: dim, supported: false);
    expect(controller(c).isSupported, isFalse);
    await controller(c).activate();
    await controller(c).release();
    expect(screen.applied, isEmpty);
    expect(logged, isEmpty);
  });

  test('a refused change is logged', () async {
    final c = await container(stored: dim);
    screen.accept = false;
    await controller(c).activate();
    expect(logged, ['reader.brightness_apply_failed']);
  });
}
