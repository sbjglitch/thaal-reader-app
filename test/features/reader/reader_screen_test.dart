import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/app/providers.dart';
import 'package:thaal/app/theme/app_theme.dart';
import 'package:thaal/core/errors/app_errors.dart';
import 'package:thaal/domain/entities/enums.dart';
import 'package:thaal/domain/entities/locator_envelope.dart';
import 'package:thaal/domain/entities/reading_data.dart';
import 'package:thaal/features/bookmarks/application/bookmarks.dart';
import 'package:thaal/features/highlights/application/highlights.dart';
import 'package:thaal/features/reader/application/reader_controller.dart';
import 'package:thaal/features/reader/presentation/reader_screen.dart';
import 'package:thaal/services/reader/publication_reader.dart';

import '../../support/fixtures.dart';
import '../bookmarks/fake_bookmarks.dart';
import '../highlights/fake_highlights.dart';
import '../highlights/highlight_widgets_test.dart' show sampleHighlight;
import 'fake_publication_reader.dart';
import 'progress_saver_test.dart' show position;

/// Controller double that exposes a fixed state.
class _StaticController extends ReaderController {
  _StaticController(super.request, this._state);

  final ReaderState _state;
  // Lives as long as the test; nothing listens after it ends.
  // ignore: close_sinks
  final noticeController = StreamController<ReaderNotice>.broadcast();

  @override
  Stream<ReaderNotice> get notices => noticeController.stream;
  final calls = <String>[];

  @override
  ReaderState build() => _state;

  @override
  Future<void> goForward() async => calls.add('forward');

  @override
  Future<bool> goToLocator(LocatorEnvelope locator) async {
    calls.add('locator:${locator.locator['href']}');
    return locator.locator['href'] != 'unresolvable';
  }

  @override
  Future<bool> goToTocEntry(TocEntry entry) async {
    calls.add('toc:${entry.title}');
    return false;
  }
}

void main() {
  late FakePublicationReader reader;
  late MemoryBookmarkRepository bookmarks;
  late MemoryHighlightRepository highlights;
  _StaticController? controller;

  setUp(() {
    bookmarks = MemoryBookmarkRepository();
    highlights = MemoryHighlightRepository();
  });

  Future<void> pump(WidgetTester tester, ReaderState state) async {
    reader = FakePublicationReader();
    final book = state is ReaderOpen ? state.book : sampleBook();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          publicationReaderProvider.overrideWithValue(reader),
          bookmarkRepositoryProvider.overrideWithValue(bookmarks),
          locatorInterpreterProvider.overrideWithValue(
            const HrefLocatorInterpreter(),
          ),
          highlightRepositoryProvider.overrideWithValue(highlights),
          bookHighlightsProvider.overrideWith(
            (ref, bookId) => highlightEntriesOf(
              highlights.watchHighlights(bookId),
              const HrefLocatorInterpreter(),
            ),
          ),
          bookBookmarksProvider.overrideWith(
            (ref, bookId) =>
                entriesOf(bookmarks.watchBookmarks(bookId), {book.id: book}),
          ),
          readerControllerProvider.overrideWith2(
            (request) => controller = _StaticController(request, state),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const ReaderScreen(request: ReaderRequest('book-1')),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows a loading state while opening', (tester) async {
    await pump(tester, const ReaderOpening());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('explains a missing file', (tester) async {
    await pump(tester, const ReaderUnavailable(ReaderProblem.missingFile));
    expect(find.text('The book file is missing'), findsOneWidget);
    expect(find.text('Back to library'), findsOneWidget);
  });

  testWidgets('a damaged file is explained without engine details', (
    tester,
  ) async {
    await pump(tester, const ReaderUnavailable(ReaderProblem.unreadable));
    expect(find.text('This book could not be opened'), findsOneWidget);
  });

  testWidgets('renders the engine view with title, contents and progress', (
    tester,
  ) async {
    await pump(
      tester,
      ReaderOpen(
        book: sampleBook(title: 'Middlemarch'),
        toc: const [TocEntry(index: 0, title: 'Prelude', depth: 0)],
        ready: true,
        position: position('c1', progression: 0.345),
      ),
    );

    expect(find.byKey(const Key('engine-view')), findsOneWidget);
    expect(find.text('Middlemarch'), findsOneWidget);
    expect(find.text('35%'), findsOneWidget);

    await tester.tap(find.byTooltip('Next page'));
    expect(controller!.calls, ['forward']);

    await tester.tap(find.byTooltip('Contents'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prelude'));
    await tester.pumpAndSettle();
    expect(controller!.calls.last, 'toc:Prelude');
    expect(find.text('That section could not be opened.'), findsOneWidget);
  });

  testWidgets('hides contents when the publication has none', (tester) async {
    await pump(tester, ReaderOpen(book: sampleBook(), toc: const []));
    expect(find.byTooltip('Contents'), findsNothing);
  });

  testWidgets('PDF shows the page number', (tester) async {
    await pump(
      tester,
      ReaderOpen(
        book: sampleBook(format: PublicationFormat.pdf),
        toc: const [],
        position: position('p', progression: 0.1, page: 4),
      ),
    );
    expect(find.text('Page 4'), findsOneWidget);
  });

  group('bookmarks', () {
    ReaderOpen openAt(String href) => ReaderOpen(
      book: sampleBook(),
      toc: const [],
      ready: true,
      position: position(href, progression: 0.5),
    );

    Bookmark stored(String id, String href, {String? label}) => Bookmark(
      id: id,
      bookId: 'book-1',
      label: label,
      locator: SerializedLocator.fromEnvelope(position(href).locator),
      createdAt: fixedTime,
      updatedAt: fixedTime,
    );

    testWidgets('adds a bookmark at the current position', (tester) async {
      await pump(tester, openAt('c2'));
      await tester.tap(find.byTooltip('Add bookmark'));
      await tester.pumpAndSettle();

      expect(bookmarks.items.single.bookId, 'book-1');
      expect(
        bookmarks.items.single.locator
            .decode(PublicationFormat.epub)
            ?.locator['href'],
        'c2',
      );
      expect(find.text('Bookmark added.'), findsOneWidget);
      expect(find.byTooltip('Remove bookmark'), findsOneWidget);
    });

    testWidgets('a failed save says so and adds nothing', (tester) async {
      bookmarks.failWrites = const DatabaseError(
        DatabaseErrorKind.failure,
        'test',
      );
      await pump(tester, openAt('c2'));
      await tester.tap(find.byTooltip('Add bookmark'));
      await tester.pumpAndSettle();

      expect(bookmarks.items, isEmpty);
      expect(find.text('The bookmark could not be saved.'), findsOneWidget);
      expect(find.byTooltip('Add bookmark'), findsOneWidget);
    });

    testWidgets('removing the bookmark here offers undo', (tester) async {
      bookmarks.items.add(stored('bm-1', 'c2'));
      await pump(tester, openAt('c2'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove bookmark'));
      await tester.pumpAndSettle();
      expect(bookmarks.items, isEmpty);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(bookmarks.items.single.id, 'bm-1');
    });

    testWidgets('cannot bookmark before the reader reports a position', (
      tester,
    ) async {
      await pump(tester, ReaderOpen(book: sampleBook(), toc: const []));
      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.bookmark_add_outlined),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('the list goes to a bookmark', (tester) async {
      bookmarks.items.addAll([
        stored('bm-1', 'c5', label: 'Ball scene'),
        stored('bm-2', 'unresolvable', label: 'Lost'),
      ]);
      await pump(tester, openAt('c1'));

      await tester.tap(find.byTooltip('Bookmarks'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ball scene'));
      await tester.pumpAndSettle();
      expect(controller!.calls.last, 'locator:c5');

      await tester.tap(find.byTooltip('Bookmarks'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lost'));
      await tester.pumpAndSettle();
      expect(controller!.calls.last, 'locator:unresolvable');
      expect(
        find.textContaining('location could not be found'),
        findsOneWidget,
      );
      expect(bookmarks.items, hasLength(2));
    });

    testWidgets('the list explains when the book has no bookmarks', (
      tester,
    ) async {
      await pump(tester, openAt('c1'));
      await tester.tap(find.byTooltip('Bookmarks'));
      await tester.pumpAndSettle();
      expect(find.text('No bookmarks in this book'), findsOneWidget);
    });
  });

  group('highlights', () {
    ReaderOpen epub({bool supports = true}) => ReaderOpen(
      book: sampleBook(),
      toc: const [TocEntry(index: 0, title: 'One', depth: 0)],
      ready: true,
      position: position('c1', progression: 0.1),
      supportsHighlights: supports,
    );

    testWidgets('EPUB offers a highlights list', (tester) async {
      await pump(tester, epub());
      expect(find.byTooltip('Highlights'), findsOneWidget);
    });

    testWidgets('no highlights button where they are unsupported', (
      tester,
    ) async {
      await pump(tester, epub(supports: false));
      expect(find.byTooltip('Highlights'), findsNothing);
    });

    testWidgets('all reader buttons fit a phone-width top bar', (tester) async {
      tester.view.physicalSize = const Size(1080, 2392);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await pump(tester, epub());
      expect(tester.takeException(), isNull);
      for (final tooltip in [
        'Add bookmark',
        'Bookmarks',
        'Highlights',
        'Contents',
      ]) {
        expect(find.byTooltip(tooltip), findsOneWidget);
      }
    });

    testWidgets('an edit notice opens the highlight editor', (tester) async {
      highlights.items.add(sampleHighlight('hl-1', text: 'Tapped words'));
      await pump(tester, epub());
      controller!.noticeController.add(const EditHighlightNotice('hl-1'));
      await tester.pumpAndSettle();
      expect(find.text('Tapped words'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('a failed save notice is shown', (tester) async {
      await pump(tester, epub());
      controller!.noticeController.add(const HighlightSaveFailedNotice());
      await tester.pumpAndSettle();
      expect(find.text('The highlight could not be saved.'), findsOneWidget);
    });

    testWidgets('the list goes to a highlight', (tester) async {
      highlights.items.add(
        sampleHighlight('hl-1', text: 'Go here', href: 'c8'),
      );
      await pump(tester, epub());
      await tester.tap(find.byTooltip('Highlights'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go here'));
      await tester.pumpAndSettle();
      expect(controller!.calls.last, 'locator:c8');
    });
  });

  testWidgets('undo works from inside the bookmarks list', (tester) async {
    bookmarks.items.add(
      Bookmark(
        id: 'bm-1',
        bookId: 'book-1',
        label: 'Keep',
        locator: SerializedLocator.fromEnvelope(position('c4').locator),
        createdAt: fixedTime,
        updatedAt: fixedTime,
      ),
    );
    await pump(
      tester,
      ReaderOpen(
        book: sampleBook(),
        toc: const [],
        ready: true,
        position: position('c1'),
      ),
    );
    await tester.tap(find.byTooltip('Bookmarks'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More actions for this bookmark'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(bookmarks.items, isEmpty);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(bookmarks.items.single.label, 'Keep');
    expect(find.text('Keep'), findsOneWidget); // Still in the open list.
  });
}
