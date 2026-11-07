import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaal/app/providers.dart';
import 'package:thaal/app/theme/app_theme.dart';
import 'package:thaal/domain/entities/enums.dart';
import 'package:thaal/domain/entities/reader_preferences.dart';
import 'package:thaal/features/reader/application/reader_controller.dart';
import 'package:thaal/features/reader/presentation/reader_settings_sheet.dart';

/// Whether the next controller created accepts changes. The controller is
/// created lazily on the first change, so tests set this beforehand.
var _accept = true;

class _RecordingController extends ReaderController {
  _RecordingController(super.bookId);

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

  Future<void> pump(WidgetTester tester, PublicationFormat format) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          readerControllerProvider.overrideWith2(
            (bookId) => controller = _RecordingController(bookId),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ReaderSettingsSheet(bookId: 'book-1', format: format),
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

  testWidgets('PDF shows only layout and fit', (tester) async {
    await pump(tester, PublicationFormat.pdf);
    expect(find.text('Theme'), findsNothing);
    expect(find.text('Text size'), findsNothing);
    expect(find.text('Page fit'), findsOneWidget);

    await tester.tap(find.text('Whole page'));
    await tester.pump();
    expect(controller.updates.single.pdfFit, PdfPageFit.page);
  });

  testWidgets('reset restores the defaults for this format', (tester) async {
    await pump(tester, PublicationFormat.epub);
    await tester.tap(find.text('Reset to defaults'));
    await tester.pump();
    expect(controller.updates.single, const ReaderPreferences());
  });

  testWidgets('a rejected setting is reported', (tester) async {
    _accept = false;
    await pump(tester, PublicationFormat.pdf);
    await tester.tap(find.text('Scroll'));
    await tester.pumpAndSettle();
    expect(find.text('That setting could not be applied.'), findsOneWidget);
  });
}
