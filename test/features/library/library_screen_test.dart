import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaal/app/providers.dart';
import 'package:thaal/app/theme/app_theme.dart';
import 'package:thaal/domain/entities/enums.dart';
import 'package:thaal/features/library/application/library_items.dart';
import 'package:thaal/features/library/presentation/library_screen.dart';
import 'package:thaal/services/import/document_picker.dart';
import 'package:thaal/services/import/import_service.dart';

import '../../support/fixtures.dart';
import 'import_controller_test.dart' show FakeImportService, FakePicker;

void main() {
  late FakePicker picker;
  late FakeImportService service;

  setUp(() {
    picker = FakePicker();
    service = FakeImportService();
  });

  Future<void> pump(
    WidgetTester tester,
    Stream<List<LibraryItem>> Function() items, {
    Map<String, Object> preferences = const {},
  }) async {
    SharedPreferences.setMockInitialValues(preferences);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryItemsProvider.overrideWith((ref) => items()),
          documentPickerProvider.overrideWithValue(picker),
          importServiceProvider.overrideWithValue(service),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const LibraryScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('empty library offers an import button', (tester) async {
    await pump(tester, () => Stream.value(const []));

    expect(find.text('Your library is empty'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Import books'), findsOneWidget);
    expect(find.byTooltip('Import books'), findsOneWidget);
  });

  testWidgets('shows a loading indicator until the library arrives', (
    tester,
  ) async {
    final controller = StreamController<List<LibraryItem>>();
    addTearDown(controller.close);
    await pump(tester, () => controller.stream);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('a load error offers retry', (tester) async {
    await pump(tester, () => Stream.error(StateError('db')));

    expect(find.text('Your library could not be loaded'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('lists books and marks missing files', (tester) async {
    await pump(
      tester,
      () => Stream.value([
        LibraryItem(book: sampleBook(title: 'Present'), fileAvailable: true),
        LibraryItem(
          book: sampleBook(
            id: 'book-2',
            title: 'Gone',
            format: PublicationFormat.pdf,
          ),
          fileAvailable: false,
        ),
      ]),
    );

    expect(find.text('Present'), findsOneWidget);
    expect(find.text('Gone'), findsOneWidget);
    expect(find.text('File missing'), findsOneWidget);
    expect(find.textContaining('PDF'), findsOneWidget);
  });

  testWidgets('import shows progress, then a success message', (tester) async {
    picker.next = const [ImportSource(name: 'a.epub', path: '/a')];
    service.gate = Completer<void>();

    await pump(tester, () => Stream.value(const []));
    await tester.tap(find.byTooltip('Import books'));
    await tester.pump();

    expect(find.text('Importing book…'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );

    service.gate!.complete();
    await tester.pumpAndSettle();

    expect(find.text('Importing book…'), findsNothing);
    expect(find.text('Imported 1 book.'), findsOneWidget);
    expect(picker.releases, 1);
  });

  testWidgets('failures are explained in plain language', (tester) async {
    picker.next = const [ImportSource(name: 'notes.txt', path: '/n')];
    service.respond = (source, _) =>
        ImportFailed(source, ImportFailureReason.unsupportedFormat);

    await pump(tester, () => Stream.value(const []));
    await tester.tap(find.byTooltip('Import books'));
    await tester.pumpAndSettle();

    expect(find.text('A file could not be imported'), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget);
    expect(
      find.text('Only EPUB and PDF files can be imported.'),
      findsOneWidget,
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(picker.releases, 1);
  });

  testWidgets('duplicates ask before importing a copy', (tester) async {
    picker.next = const [ImportSource(name: 'dup.epub', path: '/d')];
    service.respond = (source, allow) => allow
        ? ImportSucceeded(source, sampleBook(id: 'copy'))
        : ImportDuplicate(source, [sampleBook()]);

    await pump(tester, () => Stream.value(const []));
    await tester.tap(find.byTooltip('Import books'));
    await tester.pumpAndSettle();

    expect(find.text('Already in your library'), findsOneWidget);
    await tester.tap(find.text('Import copy'));
    await tester.pumpAndSettle();

    expect(service.calls.last, ('dup.epub', true));
    expect(find.text('Imported 1 book.'), findsOneWidget);
  });

  List<LibraryItem> sampleItems() => [
    LibraryItem(
      book: sampleBook(id: 'b1', title: 'Middlemarch'),
      fileAvailable: true,
    ),
    LibraryItem(
      book: sampleBook(
        id: 'b2',
        title: 'Annual Report',
        format: PublicationFormat.pdf,
      ),
      fileAvailable: true,
    ),
  ];

  testWidgets('search narrows the list and can be cleared', (tester) async {
    await pump(tester, () => Stream.value(sampleItems()));

    await tester.enterText(find.byType(TextField), 'middle');
    await tester.pump();
    expect(find.text('Middlemarch'), findsOneWidget);
    expect(find.text('Annual Report'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('No matching books'), findsOneWidget);
    await tester.tap(find.text('Clear search and filters'));
    await tester.pump();
    expect(find.text('Annual Report'), findsOneWidget);
    expect(find.text('Middlemarch'), findsOneWidget);
  });

  testWidgets('format filter from the sheet', (tester) async {
    await pump(tester, () => Stream.value(sampleItems()));

    await tester.tap(find.byTooltip('Sort and filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'PDF'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('Annual Report'), findsOneWidget);
    expect(find.text('Middlemarch'), findsNothing);
    expect(find.byTooltip('Sort and filter, filters on'), findsOneWidget);
  });

  testWidgets('grid layout is restored from preferences', (tester) async {
    await pump(
      tester,
      () => Stream.value(sampleItems()),
      preferences: {'library.layout': 'grid'},
    );

    expect(find.byType(GridView), findsOneWidget);
    await tester.tap(find.byTooltip('Show as list'));
    await tester.pump();
    expect(find.byType(GridView), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('library.layout'), 'list');
  });

  testWidgets('the overflow sheet offers only working actions', (tester) async {
    await pump(tester, () => Stream.value(sampleItems()));

    await tester.tap(find.byTooltip('More actions for Middlemarch'));
    await tester.pumpAndSettle();

    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Remove from library'), findsOneWidget);
    expect(find.text('Add to collection'), findsNothing);
  });
}
