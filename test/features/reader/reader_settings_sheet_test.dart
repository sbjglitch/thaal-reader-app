import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaal/app/providers.dart';
import 'package:thaal/app/theme/app_theme.dart';
import 'package:thaal/domain/entities/enums.dart';
import 'package:thaal/domain/entities/reader_preferences.dart';
import 'package:thaal/features/reader/application/reader_controller.dart';
import 'package:thaal/features/reader/application/reader_preferences_controller.dart';
import 'package:thaal/features/reader/presentation/reader_settings_sheet.dart';

import '../../support/large_text.dart';
import 'fake_publication_reader.dart';
import 'fake_screen_brightness.dart';

/// Whether the next controller created accepts changes. The controller is
/// created lazily on the first change, so tests set this beforehand.
var _accept = true;

class _RecordingController extends ReaderController {
  _RecordingController(super.request);

  final updates = <ReaderPreferences>[];
  final bool accept = _accept;

  @override
  ReaderState build() => const ReaderOpening();

  @override
  Future<bool> updatePreferences(ReaderPreferences preferences) async {
    updates.add(preferences);
    return accept;
  }
}

void main() {
  late _RecordingController controller;

  setUp(() => _accept = true);

  Future<void> pump(
    WidgetTester tester,
    PublicationFormat format, {
    bool pageFit = true,
    Map<String, Object> stored = const {},
    FakeScreenBrightness? brightness,
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          publicationReaderProvider.overrideWithValue(
            FakePublicationReader()..supportsPdfPageFit = pageFit,
          ),
          screenBrightnessProvider.overrideWithValue(
            brightness ?? FakeScreenBrightness(isSupported: false),
          ),
          readerControllerProvider.overrideWith2(
            (request) => controller = _RecordingController(request),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ReaderSettingsSheet(
              request: const ReaderRequest('book-1'),
              format: format,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('EPUB shows theme, text size and page turning', (tester) async {
    await pump(tester, PublicationFormat.epub);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Text size'), findsOneWidget);
    expect(find.text('Page fit'), findsNothing);

    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect(controller.updates.single.theme, ReadingTheme.dark);
  });

  testWidgets('every reading theme is offered, sepia and twilight too', (
    tester,
  ) async {
    await pump(tester, PublicationFormat.epub);
    for (final label in ['System', 'Light', 'Dark', 'Sepia', 'Twilight']) {
      expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
    }

    // The recording controller is created per change, so check each tap.
    await tester.tap(find.text('Sepia'));
    await tester.pump();
    expect(controller.updates.single.theme, ReadingTheme.sepia);
    await tester.tap(find.text('Twilight'));
    await tester.pump();
    expect(controller.updates.single.theme, ReadingTheme.twilight);
  });

  testWidgets('theme chips fit a small phone with large text', (tester) async {
    useSmallPhoneWithLargeText(tester);
    await pump(tester, PublicationFormat.epub);
    expect(tester.takeException(), isNull);
    expect(find.text('Twilight'), findsOneWidget);
  });

  testWidgets('PDF shows only layout and fit', (tester) async {
    await pump(tester, PublicationFormat.pdf);
    expect(find.text('Theme'), findsNothing);
    expect(find.text('Text size'), findsNothing);
    expect(find.text('Page fit'), findsOneWidget);

    await tester.tap(find.text('Whole page'));
    await tester.pump();
    expect(controller.updates.single.pdfFit, PdfPageFit.page);
  });

  testWidgets('PDF hides page fit when the engine ignores it', (tester) async {
    await pump(tester, PublicationFormat.pdf, pageFit: false);
    expect(find.text('Page turning'), findsOneWidget);
    expect(find.text('Page fit'), findsNothing);
    expect(find.text('Whole page'), findsNothing);
  });

  testWidgets('reset restores the defaults for this format', (tester) async {
    await pump(
      tester,
      PublicationFormat.epub,
      stored: {
        'flutter.reader.theme': 'sepia',
        'flutter.reader.epub.pageMargins': 2.0,
        'flutter.reader.epub.textAlignment': 'justify',
        'flutter.reader.epub.fontFace': 'serif',
      },
    );
    await tester.ensureVisible(find.text('Reset to defaults'));
    await tester.tap(find.text('Reset to defaults'));
    await tester.pump();
    expect(controller.updates.single, const ReaderPreferences());
  });

  testWidgets('EPUB offers margins and text alignment', (tester) async {
    await pump(tester, PublicationFormat.epub);
    expect(find.text('Margins'), findsOneWidget);

    await tester.ensureVisible(find.text('Justified'));
    await tester.tap(find.text('Justified'));
    await tester.pump();
    expect(controller.updates.single.textAlignment, TextAlignment.justify);
  });

  testWidgets('dragging the margins slider applies once, on release', (
    tester,
  ) async {
    await pump(tester, PublicationFormat.epub);
    final slider = find.byType(Slider).at(1);
    await tester.ensureVisible(slider);
    await tester.drag(slider, const Offset(400, 0));
    await tester.pump();
    expect(controller.updates.single.pageMargins, 2.0);
  });

  testWidgets('EPUB offers a font choice', (tester) async {
    await pump(tester, PublicationFormat.epub);
    expect(find.text('Font'), findsOneWidget);
    await tester.tap(find.text('Sans-serif'));
    await tester.pump();
    expect(controller.updates.single.fontFace, FontFace.sansSerif);
  });

  testWidgets('PDF shows no font, margins or alignment', (tester) async {
    await pump(tester, PublicationFormat.pdf);
    expect(find.text('Font'), findsNothing);
    expect(find.text('Margins'), findsNothing);
    expect(find.text('Text alignment'), findsNothing);
  });

  testWidgets('all EPUB settings fit a small phone with large text', (
    tester,
  ) async {
    useSmallPhoneWithLargeText(tester);
    await pump(tester, PublicationFormat.epub);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Reset to defaults'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a rejected setting is reported', (tester) async {
    _accept = false;
    await pump(tester, PublicationFormat.pdf);
    await tester.tap(find.text('Scroll'));
    await tester.pumpAndSettle();
    expect(find.text('That setting could not be applied.'), findsOneWidget);
  });

  group('brightness', () {
    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(Scaffold)));

    testWidgets('is hidden where it cannot be set', (tester) async {
      await pump(tester, PublicationFormat.epub);
      expect(find.text('Brightness'), findsNothing);
    });

    for (final format in PublicationFormat.values) {
      testWidgets('is offered for ${format.name}', (tester) async {
        await pump(tester, format, brightness: FakeScreenBrightness());
        expect(find.text('Brightness'), findsOneWidget);
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          isTrue,
        );
      });
    }

    testWidgets('dragging changes the screen and stops matching the system', (
      tester,
    ) async {
      final screen = FakeScreenBrightness();
      await pump(tester, PublicationFormat.pdf, brightness: screen);
      final container = containerOf(tester);
      // The reader screen activates brightness while a book is open.
      await container.read(readerBrightnessProvider.notifier).activate();
      screen.applied.clear();

      final slider = find.byType(Slider).first;
      await tester.drag(slider, const Offset(-2000, 0));
      await tester.pump();
      expect(screen.applied.last, ReaderBrightness.minLevel);
      final saved = container.read(readerBrightnessProvider);
      expect(saved.followsSystem, isFalse);
      expect(saved.level, ReaderBrightness.minLevel);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      expect(
        tester.widget<Slider>(slider).semanticFormatterCallback!(0.42),
        'Brightness 42%',
      );
    });

    testWidgets('the switch hands brightness back to the system', (
      tester,
    ) async {
      final screen = FakeScreenBrightness();
      await pump(
        tester,
        PublicationFormat.epub,
        brightness: screen,
        stored: const {
          'reader.brightness.followsSystem': false,
          'reader.brightness.level': 0.3,
        },
      );
      final container = containerOf(tester);
      await container.read(readerBrightnessProvider.notifier).activate();
      expect(screen.applied.last, 0.3);

      await tester.tap(find.text('Match system brightness'));
      await tester.pump();
      expect(screen.applied.last, isNull);
      expect(container.read(readerBrightnessProvider).followsSystem, isTrue);
      expect(container.read(readerBrightnessProvider).level, 0.3);
    });

    testWidgets('fits a small phone with large text', (tester) async {
      useSmallPhoneWithLargeText(tester);
      await pump(
        tester,
        PublicationFormat.epub,
        brightness: FakeScreenBrightness(),
      );
      expect(find.text('Match system brightness'), findsOneWidget);
    });
  });
}
