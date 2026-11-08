import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/app/providers.dart';
import 'package:thaal/app/theme/app_theme.dart';
import 'package:thaal/features/library/application/library_items.dart';
import 'package:thaal/features/library/presentation/book_details_screen.dart';
import 'package:thaal/services/library/book_removal_service.dart';

import '../../support/fixtures.dart';

class _FakeRemoval implements BookRemovalService {
  final removed = <String>[];
  bool fail = false;

  @override
  Future<void> removeBook(String bookId) async {
    if (fail) throw StateError('fake');
    removed.add(bookId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeRemoval removal;

  setUp(() => removal = _FakeRemoval());

  Future<void> pump(WidgetTester tester, List<LibraryItem> items) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryItemsProvider.overrideWith((ref) => Stream.value(items)),
          bookRemovalServiceProvider.overrideWithValue(removal),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const BookDetailsScreen(bookId: 'book-1'),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the book information', (tester) async {
    await pump(tester, [LibraryItem(book: sampleBook(), fileAvailable: true)]);

    expect(find.text('Sample Book'), findsOneWidget);
    expect(find.text('A. Author, B. Author'), findsOneWidget);
    expect(find.text('EPUB'), findsOneWidget);
    expect(find.text('1.0 KB'), findsOneWidget);
    expect(find.text('Not started'), findsOneWidget);
    expect(find.textContaining('file for this book is missing'), findsNothing);
  });

  testWidgets('explains a missing file', (tester) async {
    await pump(tester, [LibraryItem(book: sampleBook(), fileAvailable: false)]);
    expect(
      find.textContaining('file for this book is missing'),
      findsOneWidget,
    );
  });

  testWidgets('an unknown book shows a recoverable state', (tester) async {
    await pump(tester, const []);
    expect(find.text('Book not found'), findsOneWidget);
  });

  testWidgets('remove asks first; cancel changes nothing', (tester) async {
    await pump(tester, [LibraryItem(book: sampleBook(), fileAvailable: true)]);

    await tester.ensureVisible(find.text('Remove from library'));
    await tester.tap(find.text('Remove from library'));
    await tester.pumpAndSettle();
    expect(find.text('Remove from library?'), findsOneWidget);
    expect(find.textContaining('original file on your device'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(removal.removed, isEmpty);
  });

  testWidgets('confirming removes the book', (tester) async {
    await pump(tester, [LibraryItem(book: sampleBook(), fileAvailable: true)]);

    await tester.ensureVisible(find.text('Remove from library'));
    await tester.tap(find.text('Remove from library'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(removal.removed, ['book-1']);
  });

  testWidgets('a failed removal is reported', (tester) async {
    removal.fail = true;
    await pump(tester, [LibraryItem(book: sampleBook(), fileAvailable: true)]);

    await tester.ensureVisible(find.text('Remove from library'));
    await tester.tap(find.text('Remove from library'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(
      find.text('The book could not be removed. Nothing was changed.'),
      findsOneWidget,
    );
  });
}
