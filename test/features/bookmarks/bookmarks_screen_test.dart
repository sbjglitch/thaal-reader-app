import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:thaal/app/providers.dart';
import 'package:thaal/app/theme/app_theme.dart';
import 'package:thaal/domain/entities/enums.dart';
import 'package:thaal/domain/entities/locator_envelope.dart';
import 'package:thaal/domain/entities/reading_data.dart';
import 'package:thaal/features/bookmarks/application/bookmarks.dart';
import 'package:thaal/features/bookmarks/presentation/bookmarks_screen.dart';

import '../../support/fixtures.dart';
import 'fake_bookmarks.dart';

Bookmark _bookmark(
  String id, {
  String bookId = 'book-1',
  String href = 'c1',
  String? title,
  String? label,
  PublicationFormat format = PublicationFormat.epub,
  int minute = 0,
}) {
  final at = fixedTime.add(Duration(minutes: minute));
  return Bookmark(
    id: id,
    bookId: bookId,
    label: label,
    locator: SerializedLocator.fromEnvelope(
      LocatorEnvelope(
        format: format,
        locator: {'href': href, 'progression': 0.42, 'title': ?title},
      ),
    ),
    createdAt: at,
    updatedAt: at,
  );
}

void main() {
  late MemoryBookmarkRepository repository;

  Future<void> pump(
    WidgetTester tester, {
    Set<String> missingFiles = const {},
  }) async {
    final books = {
      'book-1': sampleBook(title: 'Middlemarch'),
      'book-2': sampleBook(id: 'book-2', title: 'Persuasion'),
    };
    final router = GoRouter(
      initialLocation: '/bookmarks',
      routes: [
        GoRoute(path: '/bookmarks', builder: (_, _) => const BookmarksScreen()),
        GoRoute(
          path: '/reader/:bookId',
          builder: (_, state) => Text('reader ${state.uri}'),
        ),
        GoRoute(
          path: '/library/books/:bookId',
          builder: (_, state) => Text('details ${state.uri}'),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookmarkRepositoryProvider.overrideWithValue(repository),
          allBookmarksProvider.overrideWith(
            (ref) => entriesOf(
              repository.watchAllBookmarks(),
              books,
              missingFiles: missingFiles,
            ),
          ),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() => repository = MemoryBookmarkRepository());

  testWidgets('explains how to add a bookmark when there are none', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('No bookmarks yet'), findsOneWidget);
  });

  testWidgets('lists every book\'s bookmarks newest first', (tester) async {
    repository.items.addAll([
      _bookmark('old', title: 'Prelude', minute: 1),
      _bookmark('new', bookId: 'book-2', label: 'Proposal', minute: 9),
    ]);
    await pump(tester);

    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title! as Text).data)
        .toList();
    expect(titles, ['Proposal', 'Prelude · 42%']);
    expect(find.textContaining('Persuasion · 42%'), findsOneWidget);
    expect(find.textContaining('Middlemarch'), findsOneWidget);
  });

  testWidgets('opening a bookmark opens the reader at it', (tester) async {
    repository.items.add(_bookmark('bm-1'));
    await pump(tester);
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    expect(find.text('reader /reader/book-1?bookmark=bm-1'), findsOneWidget);
  });

  testWidgets('a bookmark of a missing book file opens its details', (
    tester,
  ) async {
    repository.items.add(_bookmark('bm-1'));
    await pump(tester, missingFiles: {'book-1'});
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    expect(find.text('details /library/books/book-1'), findsOneWidget);
  });

  testWidgets('delete offers undo', (tester) async {
    repository.items.add(_bookmark('bm-1', label: 'Keep me'));
    await pump(tester);

    await tester.tap(find.byTooltip('More actions for this bookmark'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(repository.items, isEmpty);
    expect(find.text('Bookmark deleted.'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(repository.items.single.label, 'Keep me');
    expect(find.text('Keep me'), findsOneWidget);
  });

  testWidgets('rename saves the new label', (tester) async {
    repository.items.add(_bookmark('bm-1'));
    await pump(tester);

    await tester.tap(find.byTooltip('More actions for this bookmark'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Chapter one');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repository.items.single.label, 'Chapter one');
    expect(find.text('Chapter one'), findsOneWidget);
  });

  testWidgets('a bookmark whose locator cannot be read is still listed', (
    tester,
  ) async {
    repository.items.add(
      Bookmark(
        id: 'future',
        bookId: 'book-1',
        locator: const SerializedLocator.stored('{"schemaVersion":99}'),
        createdAt: fixedTime,
        updatedAt: fixedTime,
      ),
    );
    await pump(tester);
    expect(find.text('Location unavailable'), findsOneWidget);
  });
}
