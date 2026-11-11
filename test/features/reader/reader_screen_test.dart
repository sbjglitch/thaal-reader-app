import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaal/app/providers.dart';
import 'package:thaal/app/theme/app_theme.dart';
import 'package:thaal/core/errors/app_errors.dart';
import 'package:thaal/domain/entities/enums.dart';
import 'package:thaal/domain/entities/locator_envelope.dart';
import 'package:thaal/domain/entities/reader_preferences.dart';
import 'package:thaal/domain/entities/reading_data.dart';
import 'package:thaal/features/bookmarks/application/bookmarks.dart';
import 'package:thaal/features/highlights/application/highlights.dart';
import 'package:thaal/features/reader/application/reader_controller.dart';
import 'package:thaal/features/reader/presentation/reader_screen.dart';
import 'package:thaal/features/reader/presentation/reader_scrubber.dart';
import 'package:thaal/features/reader/presentation/reader_search_sheet.dart';
import 'package:thaal/features/reader/presentation/swipe_page_turner.dart';
import 'package:thaal/services/reader/publication_reader.dart';

import '../../support/fixtures.dart';
import '../../support/large_text.dart';
import '../bookmarks/fake_bookmarks.dart';
import '../highlights/fake_highlights.dart';
import '../highlights/highlight_widgets_test.dart' show sampleHighlight;
import 'fake_publication_reader.dart';
import 'fake_screen_brightness.dart';
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

  @override
  Future<void> search(String query) async => calls.add('search:$query');

  /// Results in chapter "missing" cannot be opened.
  @override
  Future<bool> goToSearchResult(ReaderSearchResult result) async {
    final href = result.locator.locator['href'];
    calls.add('result:$href');
    return href != 'missing';
  }

  /// Jumps past the middle of the book fail, to exercise the error path.
  @override
  Future<bool> goToProgression(double progression) async {
    calls.add('progression:${progression.toStringAsFixed(2)}');
    return progression <= 0.5;
  }
}

void main() {
  late FakePublicationReader reader;
  late MemoryBookmarkRepository bookmarks;
  late MemoryHighlightRepository highlights;
  late FakeScreenBrightness screen;
  _StaticController? controller;

  setUp(() {
    bookmarks = MemoryBookmarkRepository();
    highlights = MemoryHighlightRepository();
  });

  Future<void> pump(
    WidgetTester tester,
    ReaderState state, {
    Map<String, Object> preferences = const {},
  }) async {
    SharedPreferences.setMockInitialValues(preferences);
    final prefs = await SharedPreferences.getInstance();
    reader = FakePublicationReader();
    screen = FakeScreenBrightness();
    final book = state is ReaderOpen ? state.book : sampleBook();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
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
          screenBrightnessProvider.overrideWithValue(screen),
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

  testWidgets('PDF with a known length shows the page count', (tester) async {
    await pump(
      tester,
      ReaderOpen(
        book: sampleBook(format: PublicationFormat.pdf),
        toc: const [],
        pageCount: 120,
        position: position('p', progression: 0.1, page: 4),
      ),
    );
    expect(find.text('Page 4 of 120'), findsOneWidget);
  });

  group('scrubber', () {
    ReaderOpen open({bool ready = true, bool jump = true}) => ReaderOpen(
      book: sampleBook(),
      toc: const [],
      ready: ready,
      supportsProgressionJump: jump,
      position: position('c1', progression: 0.25),
    );

    testWidgets('is shown when the book can jump', (tester) async {
      await pump(tester, open());
      expect(find.byType(ReaderScrubber), findsOneWidget);
    });

    testWidgets('is hidden when the book cannot jump', (tester) async {
      await pump(tester, open(jump: false));
      expect(find.byType(ReaderScrubber), findsNothing);
    });

    testWidgets('is hidden until the engine is ready', (tester) async {
      await pump(tester, open(ready: false));
      expect(find.byType(ReaderScrubber), findsNothing);
    });

    testWidgets('a release jumps, and a failed jump is explained', (
      tester,
    ) async {
      await pump(tester, open());
      final slider = find.byType(Slider);
      final box = tester.getRect(slider);

      await tester.tapAt(Offset(box.left + box.width * 0.4, box.center.dy));
      await tester.pump();
      expect(controller!.calls.last, startsWith('progression:0.'));
      expect(find.text('That position could not be opened.'), findsNothing);

      await tester.drag(slider, Offset(box.width, 0));
      await tester.pump();
      expect(controller!.calls.last, 'progression:1.00');
      expect(find.text('That position could not be opened.'), findsOneWidget);
    });
  });

  testWidgets('the reading brightness applies only while reading', (
    tester,
  ) async {
    await pump(
      tester,
      ReaderOpen(book: sampleBook(), toc: const [], ready: true),
      preferences: const {
        'reader.brightness.followsSystem': false,
        'reader.brightness.level': 0.25,
      },
    );
    expect(screen.applied, [0.25]);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(screen.applied, [0.25, null]);
  });

  group('search', () {
    ReaderSearchResult result(String href, {String? chapter}) =>
        ReaderSearchResult(
          locator: position(href).locator,
          before: 'the start of ',
          match: 'word',
          after: ' and the rest',
          chapterTitle: chapter,
        );

    ReaderOpen open({
      PublicationFormat format = PublicationFormat.epub,
      ReaderSearch search = const ReaderSearchIdle(),
    }) => ReaderOpen(
      book: sampleBook(format: format),
      toc: const [],
      ready: true,
      supportsSearch: format == PublicationFormat.epub,
      search: search,
      position: position('c1', progression: 0.2),
    );

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Search in book'));
      await tester.pumpAndSettle();
    }

    testWidgets('EPUB offers search', (tester) async {
      await pump(tester, open());
      expect(find.byTooltip('Search in book'), findsOneWidget);
    });

    testWidgets('PDF does not offer search', (tester) async {
      await pump(tester, open(format: PublicationFormat.pdf));
      expect(find.byTooltip('Search in book'), findsNothing);
    });

    testWidgets('a submitted query is searched', (tester) async {
      await pump(tester, open());
      await openSheet(tester);
      expect(find.text('Search in book'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'word');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(controller!.calls, contains('search:word'));

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(controller!.calls.last, 'search:');
    });

    testWidgets('results show their context and open on a tap', (tester) async {
      await pump(
        tester,
        open(
          search: ReaderSearchDone('word', [
            result('c2', chapter: 'Chapter 2'),
            result('c5'),
          ]),
        ),
      );
      await openSheet(tester);
      expect(find.text('2 matches'), findsOneWidget);
      // The previous query is back in the field.
      expect(find.widgetWithText(TextField, 'word'), findsOneWidget);
      expect(find.text('Chapter 2'), findsOneWidget);
      expect(
        find.textContaining(
          '…the start of word and the rest…',
          findRichText: true,
        ),
        findsNWidgets(2),
      );

      await tester.tap(find.byType(SearchResultTile).first);
      await tester.pumpAndSettle();
      expect(controller!.calls.last, 'result:c2');
      expect(find.byType(SearchResultTile), findsNothing);
      expect(find.text('That match could not be opened.'), findsNothing);
    });

    testWidgets('a result that cannot be opened is explained', (tester) async {
      await pump(
        tester,
        open(search: ReaderSearchDone('word', [result('missing')])),
      );
      await openSheet(tester);
      expect(find.text('1 match'), findsOneWidget);
      await tester.tap(find.byType(SearchResultTile));
      await tester.pumpAndSettle();
      expect(find.text('That match could not be opened.'), findsOneWidget);
    });

    testWidgets('no matches says so', (tester) async {
      await pump(tester, open(search: const ReaderSearchDone('word', [])));
      await openSheet(tester);
      expect(find.text('No matches'), findsOneWidget);
      expect(find.text('Nothing in this book matches “word”.'), findsOneWidget);
    });

    testWidgets('a running search shows progress', (tester) async {
      await pump(tester, open(search: const ReaderSearchRunning('word')));
      await tester.tap(find.byTooltip('Search in book'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(SearchResultTile), findsNothing);
    });

    testWidgets('a failed search can be retried', (tester) async {
      await pump(tester, open(search: const ReaderSearchFailed('word')));
      await openSheet(tester);
      expect(find.text('Search did not work'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(controller!.calls.last, 'search:word');
    });

    test('long leading context is cut at a word', () {
      expect(leadingContext('short'), 'short');
      // The cut lands at the start of "three", so it is kept.
      expect(
        leadingContext('one two three four five six seven eight nine ten'),
        'three four five six seven eight nine ten',
      );
      // The cut lands inside "three", so the partial word goes.
      expect(
        leadingContext('one two three four five six seven eight nine ten!'),
        'four five six seven eight nine ten!',
      );
      expect(leadingContext('x' * 50), 'x' * 40);
    });
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

  group('small phone, large text', () {
    testWidgets('an open book fits', (tester) async {
      useSmallPhoneWithLargeText(tester);
      await pump(
        tester,
        ReaderOpen(
          book: sampleBook(title: longTitle),
          toc: const [TocEntry(index: 0, title: longTitle, depth: 0)],
          ready: true,
          supportsProgressionJump: true,
          supportsSearch: true,
          position: position('c1', progression: 0.5),
        ),
      );
      expect(find.byType(ReaderScrubber), findsOneWidget);
      expect(find.byTooltip('Search in book'), findsOneWidget);
      await tester.tap(find.byTooltip('Contents'));
      await tester.pumpAndSettle();
    });

    testWidgets('search results fit', (tester) async {
      useSmallPhoneWithLargeText(tester);
      await pump(
        tester,
        ReaderOpen(
          book: sampleBook(title: longTitle),
          toc: const [],
          ready: true,
          supportsSearch: true,
          position: position('c1', progression: 0.5),
          search: ReaderSearchDone('word', [
            for (var i = 0; i < 20; i++)
              ReaderSearchResult(
                locator: position('c$i').locator,
                before: 'a long stretch of text before the match ' * 3,
                match: 'word',
                after: ' and a long stretch of text after it' * 3,
                chapterTitle: longTitle,
              ),
          ]),
        ),
      );
      await tester.tap(find.byTooltip('Search in book'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchResultTile), findsWidgets);
    });

    testWidgets('search states fit', (tester) async {
      useSmallPhoneWithLargeText(tester);
      await pump(
        tester,
        ReaderOpen(
          book: sampleBook(),
          toc: const [],
          ready: true,
          supportsSearch: true,
          search: const ReaderSearchFailed('word'),
          position: position('c1', progression: 0.5),
        ),
      );
      await tester.tap(find.byTooltip('Search in book'));
      await tester.pumpAndSettle();
      expect(find.text('Search did not work'), findsOneWidget);
    });

    testWidgets('problems fit', (tester) async {
      useSmallPhoneWithLargeText(tester);
      for (final problem in ReaderProblem.values) {
        await pump(tester, ReaderUnavailable(problem));
      }
    });
  });

  group('swipe page turning', () {
    bool locked(WidgetTester tester) =>
        tester.widget<SwipePageTurner>(find.byType(SwipePageTurner)).enabled;

    testWidgets('is on for paginated PDFs', (tester) async {
      await pump(
        tester,
        ReaderOpen(
          book: sampleBook(format: PublicationFormat.pdf),
          toc: const [],
        ),
      );
      expect(locked(tester), isTrue);
    });

    testWidgets('a swipe on a PDF page turns it', (tester) async {
      await pump(
        tester,
        ReaderOpen(
          book: sampleBook(format: PublicationFormat.pdf),
          toc: const [],
          ready: true,
        ),
      );
      await tester.drag(
        find.byKey(const Key('engine-view')),
        const Offset(-200, 0),
      );
      await tester.pump();
      expect(controller!.calls, ['forward']);
    });

    testWidgets('is off for scrolling PDFs', (tester) async {
      await pump(
        tester,
        ReaderOpen(
          book: sampleBook(format: PublicationFormat.pdf),
          toc: const [],
        ),
        preferences: {'reader.pdf.layout': PageLayout.scroll.name},
      );
      expect(locked(tester), isFalse);
    });

    testWidgets('is off for EPUB', (tester) async {
      await pump(tester, ReaderOpen(book: sampleBook(), toc: const []));
      expect(locked(tester), isFalse);
    });
  });
}
