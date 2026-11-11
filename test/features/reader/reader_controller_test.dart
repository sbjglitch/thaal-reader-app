import 'dart:async';
import 'dart:io';
import 'dart:ui' show Brightness;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaal/app/providers.dart';
import 'package:thaal/core/logging/app_logger.dart';
import 'package:thaal/data/database/app_database.dart';
import 'package:thaal/data/repositories/drift_book_repository.dart';
import 'package:thaal/data/repositories/drift_bookmark_repository.dart';
import 'package:thaal/data/repositories/drift_highlight_repository.dart';
import 'package:thaal/data/repositories/drift_reading_progress_repository.dart';
import 'package:thaal/domain/entities/app_preferences.dart';
import 'package:thaal/domain/entities/enums.dart';
import 'package:thaal/domain/entities/locator_envelope.dart';
import 'package:thaal/domain/entities/reader_preferences.dart';
import 'package:thaal/domain/entities/reading_data.dart';
import 'package:thaal/features/reader/application/reader_controller.dart';
import 'package:thaal/features/reader/application/reader_preferences_controller.dart';
import 'package:thaal/features/settings/application/app_theme_controller.dart';
import 'package:thaal/services/reader/publication_reader.dart';
import 'package:thaal/services/storage/library_storage.dart';

import '../../support/fixtures.dart';
import 'fake_publication_reader.dart';
import 'progress_saver_test.dart' show position;

void main() {
  // AppLifecycleListener needs the binding.
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late LibraryStorage storage;
  late AppDatabase db;
  late FakePublicationReader reader;
  late ProviderContainer container;
  late ProviderSubscription<ReaderState> subscription;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('thaal_reader');
    storage = await LibraryStorage.open(Directory('${temp.path}/library'));
    db = openTestDatabase();
    reader = FakePublicationReader();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer.test(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        libraryStorageProvider.overrideWithValue(storage),
        publicationReaderProvider.overrideWithValue(reader),
        appLoggerProvider.overrideWithValue(AppLogger(sink: (_) {})),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<void> addBook({
    bool withFile = true,
    PublicationFormat format = PublicationFormat.epub,
  }) async {
    final book = sampleBook(format: format);
    await DriftBookRepository(db).addBook(book);
    if (withFile) {
      final file = storage.file(book.filePath);
      await file.parent.create(recursive: true);
      await file.writeAsString('epub bytes');
    }
  }

  Future<ReaderState> start({String? bookmarkId}) async {
    subscription = container.listen(
      readerControllerProvider(ReaderRequest('book-1', bookmarkId: bookmarkId)),
      (_, _) {},
    );
    // Let the microtask-started open run to completion.
    for (var i = 0; i < 200; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      if (subscription.read() is! ReaderOpening) break;
    }
    return subscription.read();
  }

  ReaderController controller() => container.read(
    readerControllerProvider(const ReaderRequest('book-1')).notifier,
  );

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 5));

  test('an unknown book is reported without touching the engine', () async {
    final state = await start();
    expect((state as ReaderUnavailable).problem, ReaderProblem.bookNotFound);
    expect(reader.calls, isEmpty);
  });

  test('a missing file is reported without touching the engine', () async {
    await addBook(withFile: false);
    final state = await start();
    expect((state as ReaderUnavailable).problem, ReaderProblem.missingFile);
    expect(reader.calls, isEmpty);
  });

  test('engine open failures map to reader problems', () async {
    await addBook();
    reader.openFailure = const ReaderFailure(
      ReaderFailureKind.unreadable,
      code: 'readingError',
    );
    final state = await start();
    expect((state as ReaderUnavailable).problem, ReaderProblem.unreadable);
  });

  test('opens the app-private copy at the beginning when unread', () async {
    await addBook();
    final state = await start() as ReaderOpen;
    expect(state.initialLocator, isNull);
    expect(state.restoreFailed, isFalse);
    expect(reader.openedPath, storage.file(sampleBook().filePath).path);
  });

  test('restores the saved locator', () async {
    await addBook();
    await DriftReadingProgressRepository(db).saveProgress(
      ReadingProgress(
        bookId: 'book-1',
        locator: sampleLocator(href: 'chapter9.xhtml'),
        updatedAt: fixedTime,
      ),
    );
    final state = await start() as ReaderOpen;
    expect(state.initialLocator?.locator['href'], 'chapter9.xhtml');
  });

  test(
    'a bookmark request opens at the bookmark, not the saved place',
    () async {
      await addBook();
      await DriftReadingProgressRepository(db).saveProgress(
        ReadingProgress(
          bookId: 'book-1',
          locator: sampleLocator(href: 'chapter9.xhtml'),
          updatedAt: fixedTime,
        ),
      );
      await DriftBookmarkRepository(db).addBookmark(
        Bookmark(
          id: 'bm-1',
          bookId: 'book-1',
          locator: sampleLocator(href: 'chapter2.xhtml'),
          createdAt: fixedTime,
          updatedAt: fixedTime,
        ),
      );
      final state = await start(bookmarkId: 'bm-1') as ReaderOpen;
      expect(state.initialLocator?.locator['href'], 'chapter2.xhtml');
      expect(state.restoreFailed, isFalse);
    },
  );

  test('an unknown bookmark falls back to the saved place', () async {
    await addBook();
    await DriftReadingProgressRepository(db).saveProgress(
      ReadingProgress(
        bookId: 'book-1',
        locator: sampleLocator(href: 'chapter9.xhtml'),
        updatedAt: fixedTime,
      ),
    );
    final state = await start(bookmarkId: 'gone') as ReaderOpen;
    expect(state.initialLocator?.locator['href'], 'chapter9.xhtml');
  });

  test('going to a locator saves the current place first', () async {
    await addBook();
    await start();
    reader.emit(ReaderPositionChanged(position('c3', progression: 0.5)));
    await settle();
    final target = position('c7').locator;
    expect(await controller().goToLocator(target), isTrue);
    expect(reader.visited.last, target);
    final saved = await DriftReadingProgressRepository(db)
        .getProgress('book-1');
    expect(
      saved?.locator?.decode(PublicationFormat.epub)?.locator['href'],
      'c3',
    );
  });

  group('jumping by progression', () {
    test('an open book says whether it can jump, and PDF its pages', () async {
      reader.pages = 120;
      await addBook(format: PublicationFormat.pdf);
      final state = await start() as ReaderOpen;
      expect(state.supportsProgressionJump, isTrue);
      expect(state.pageCount, 120);
    });

    test('an EPUB the map cannot cover cannot jump', () async {
      reader.progressionJump = false;
      await addBook();
      final state = await start() as ReaderOpen;
      expect(state.supportsProgressionJump, isFalse);
      expect(state.pageCount, isNull);
    });

    test('a jump saves the current place first', () async {
      await addBook();
      await start();
      reader.emit(ReaderPositionChanged(position('c3', progression: 0.5)));
      await settle();
      expect(await controller().goToProgression(0.75), isTrue);
      expect(reader.jumps, [0.75]);
      final saved = await DriftReadingProgressRepository(db)
          .getProgress('book-1');
      expect(
        saved?.locator?.decode(PublicationFormat.epub)?.locator['href'],
        'c3',
      );
    });

    test('a failed jump is reported', () async {
      await addBook();
      await start();
      reader.progressionJump = false;
      expect(await controller().goToProgression(0.5), isFalse);
    });
  });

  group('search', () {
    ReaderSearchResult found(String href) =>
        ReaderSearchResult(locator: position(href).locator, match: 'word');

    ReaderSearch current() => (subscription.read() as ReaderOpen).search;

    test('results are kept with the session', () async {
      await addBook();
      final state = await start() as ReaderOpen;
      expect(state.supportsSearch, isTrue);
      reader.searchOutcome = [found('c2'), found('c5')];

      await controller().search('  word ');
      expect(reader.searches, ['word']);
      final done = current() as ReaderSearchDone;
      expect(done.query, 'word');
      expect(done.results.map((r) => r.locator.locator['href']), ['c2', 'c5']);
    });

    test('shows the search as running', () async {
      await addBook();
      await start();
      reader.searchGate = Completer<void>();
      final searching = controller().search('word');
      await settle();
      expect((current() as ReaderSearchRunning).query, 'word');
      reader.searchGate!.complete();
      await searching;
      expect(current(), isA<ReaderSearchDone>());
    });

    test('an engine failure is reported without the query', () async {
      await addBook();
      await start();
      reader.searchOutcome = const ReaderFailure(
        ReaderFailureKind.engine,
        code: 'searchError',
      );
      await controller().search('word');
      expect((current() as ReaderSearchFailed).query, 'word');
    });

    test('a blank query clears the search and the mark', () async {
      await addBook();
      await start();
      await controller().search('word');
      await controller().search('   ');
      expect(current(), isA<ReaderSearchIdle>());
      expect(reader.searches, ['word']);
      expect(reader.searchMarks, [null]);
    });

    test('a slower earlier search does not replace a newer one', () async {
      await addBook();
      await start();
      final slow = Completer<void>();
      reader.searchGate = slow;
      reader.searchOutcome = [found('old')];
      final first = controller().search('old');
      await settle();
      reader.searchGate = null;
      reader.searchOutcome = [found('new')];
      await controller().search('new');
      slow.complete();
      await first;
      final done = current() as ReaderSearchDone;
      expect(done.query, 'new');
      expect(done.results.single.locator.locator['href'], 'new');
    });

    test('PDF cannot be searched', () async {
      await addBook(format: PublicationFormat.pdf);
      final state = await start() as ReaderOpen;
      expect(state.supportsSearch, isFalse);
      await controller().search('word');
      expect(reader.searches, isEmpty);
    });

    test('opening a result jumps there and marks it', () async {
      await addBook();
      await start();
      final result = found('c7');
      expect(await controller().goToSearchResult(result), isTrue);
      expect(reader.visited.last, result.locator);
      expect(reader.searchMarks, [result.locator]);
    });
  });

  test('an unusable saved locator opens at the start and is kept', () async {
    await addBook();
    final progress = DriftReadingProgressRepository(db);
    await progress.saveProgress(
      ReadingProgress(
        bookId: 'book-1',
        locator: const SerializedLocator.stored('{"schemaVersion":99}'),
        updatedAt: fixedTime,
      ),
    );

    final state = await start() as ReaderOpen;
    expect(state.restoreFailed, isTrue);
    expect(state.initialLocator, isNull);

    // The engine's start-of-book report must not replace the saved row...
    reader.emit(ReaderPositionChanged(position('start')));
    await settle();
    container.dispose();
    await settle();
    expect(
      (await progress.getProgress('book-1'))!.locator!.json,
      '{"schemaVersion":99}',
    );
  });

  test('ready records the open and marks an unread book as reading', () async {
    await addBook();
    await start();
    reader.emit(const ReaderReady());
    await settle();

    final book = await DriftBookRepository(db).getBook('book-1');
    expect(book!.readingStatus, ReadingStatus.reading);
    expect(book.lastOpenedAt, isNotNull);
    expect((subscription.read() as ReaderOpen).ready, isTrue);
  });

  group('highlights', () {
    Future<void> eventually(bool Function() condition) async {
      for (var i = 0; i < 200 && !condition(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(condition(), isTrue);
    }

    ReaderTextActionEvent selection(ReaderTextAction action) =>
        ReaderTextActionEvent(
          action: action,
          locator: position('c2', progression: 0.4).locator,
          selectedText: 'chosen words',
        );

    Future<List<Highlight>> stored() =>
        DriftHighlightRepository(db).watchHighlights('book-1').first;

    test('saved highlights are drawn once the engine is ready', () async {
      await addBook();
      await DriftHighlightRepository(db).addHighlight(
        Highlight(
          id: 'hl-1',
          bookId: 'book-1',
          locator: sampleLocator(href: 'c5.xhtml'),
          color: HighlightColor.pink,
          createdAt: fixedTime,
          updatedAt: fixedTime,
        ),
      );
      final state = await start() as ReaderOpen;
      expect(state.supportsHighlights, isTrue);
      expect(reader.shownHighlights, isEmpty); // Not before ready.

      reader.emit(const ReaderReady());
      await eventually(() => reader.shownHighlights.isNotEmpty);
      final shown = reader.shownHighlights.last.single;
      expect(shown.id, 'hl-1');
      expect(shown.color, HighlightColor.pink);
      expect(shown.locator.locator['href'], 'c5.xhtml');
    });

    test('a highlight action saves the selection and redraws', () async {
      await addBook();
      await start();
      reader.emit(const ReaderReady());
      final notices = <ReaderNotice>[];
      controller().notices.listen(notices.add);

      reader.emit(selection(ReaderTextAction.highlight));
      await eventually(() => reader.shownHighlights.lastOrNull?.length == 1);

      final highlight = (await stored()).single;
      expect(highlight.selectedText, 'chosen words');
      expect(highlight.color, HighlightColor.yellow);
      expect(notices, isEmpty);
    });

    test('a note action saves, then asks to edit the highlight', () async {
      await addBook();
      await start();
      final notices = <ReaderNotice>[];
      controller().notices.listen(notices.add);

      reader.emit(selection(ReaderTextAction.note));
      await eventually(() => notices.isNotEmpty);
      final id = (await stored()).single.id;
      expect((notices.single as EditHighlightNotice).highlightId, id);
    });

    test('tapping a highlight asks to edit it', () async {
      await addBook();
      await start();
      final notices = <ReaderNotice>[];
      controller().notices.listen(notices.add);
      reader.emit(const ReaderHighlightTapped('hl-9'));
      await eventually(() => notices.isNotEmpty);
      expect((notices.single as EditHighlightNotice).highlightId, 'hl-9');
    });

    test('a failed save is reported and nothing is drawn', () async {
      await addBook();
      await start();
      reader.emit(const ReaderReady());
      final notices = <ReaderNotice>[];
      controller().notices.listen(notices.add);
      // The book disappears underneath the reader, so the insert fails.
      await DriftBookRepository(db).removeBook('book-1');

      reader.emit(selection(ReaderTextAction.highlight));
      await eventually(() => notices.isNotEmpty);
      expect(notices.single, isA<HighlightSaveFailedNotice>());
    });

    test('PDF offers no highlights and ignores text actions', () async {
      await addBook(format: PublicationFormat.pdf);
      final state = await start() as ReaderOpen;
      expect(state.supportsHighlights, isFalse);
      reader.emit(const ReaderReady());
      reader.emit(selection(ReaderTextAction.highlight));
      await settle();
      expect(await stored(), isEmpty);
      expect(reader.shownHighlights, isEmpty);
    });
  });

  test('reaching the end marks the book finished', () async {
    await addBook();
    await start();
    reader.emit(const ReaderReachedEnd());
    await settle();
    final book = await DriftBookRepository(db).getBook('book-1');
    expect(book!.readingStatus, ReadingStatus.finished);
  });

  test(
    'positions are saved when the session ends, then the engine closes',
    () async {
      await addBook();
      await start();
      reader.emit(ReaderPositionChanged(position('c4', progression: 0.6)));
      await settle();
      expect((subscription.read() as ReaderOpen).position?.progression, 0.6);

      container.dispose();
      await settle();

      final saved = await DriftReadingProgressRepository(db)
          .getProgress('book-1');
      expect(
        saved!.locator!.decode(PublicationFormat.epub)!.locator['href'],
        'c4',
      );
      expect(saved.progression, 0.6);
      expect(reader.calls.last, 'close');
    },
  );

  test('a fatal engine error shows a recoverable problem', () async {
    await addBook();
    await start();
    reader.emit(
      const ReaderErrorEvent(
        ReaderFailure(ReaderFailureKind.engine, code: 'x'),
        fatal: true,
      ),
    );
    await settle();
    expect(
      (subscription.read() as ReaderUnavailable).problem,
      ReaderProblem.failed,
    );
  });

  test('navigation commands reach the engine', () async {
    await addBook();
    reader.toc = const [TocEntry(index: 0, title: 'One', depth: 0)];
    await start();
    await controller().goForward();
    await controller().goBackward();
    expect(await controller().goToTocEntry(reader.toc.single), isTrue);
    expect(reader.calls, containsAllInOrder(['forward', 'backward', 'toc:0']));
  });

  group('preferences', () {
    test('the book opens with the saved preferences', () async {
      await addBook();
      await container
          .read(readerPreferencesProvider.notifier)
          .save(const ReaderPreferences(fontScale: 1.5));
      await start();
      expect(reader.openedWith?.preferences.fontScale, 1.5);
    });

    test('a change is applied, saved, and keeps the reading place', () async {
      await addBook();
      await start();
      reader.emit(ReaderPositionChanged(position('c7')));
      await settle();

      final applied = await controller().updatePreferences(
        const ReaderPreferences(fontScale: 1.4),
      );

      expect(applied, isTrue);
      expect(reader.applied.single.preferences.fontScale, 1.4);
      expect(reader.visited.single.locator['href'], 'c7');
      expect(container.read(readerPreferencesProvider).fontScale, 1.4);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('reader.epub.fontScale'), 1.4);
    });

    test('a theme change does not move the reader', () async {
      await addBook();
      await start();
      reader.emit(ReaderPositionChanged(position('c7')));
      await settle();
      await controller().updatePreferences(
        const ReaderPreferences(theme: ReadingTheme.dark),
      );
      expect(reader.applied, hasLength(1));
      expect(reader.visited, isEmpty);
    });

    test('a rejected change is not saved', () async {
      await addBook();
      await start();
      reader.acceptAppearance = false;

      final applied = await controller().updatePreferences(
        const ReaderPreferences(fontScale: 1.8),
      );

      expect(applied, isFalse);
      expect(container.read(readerPreferencesProvider).fontScale, 1.0);
    });

    test('the system reading theme opens in the app theme', () async {
      await container
          .read(appThemeProvider.notifier)
          .select(AppThemePreference.dark);
      await addBook();
      await start();
      expect(
        reader.openedWith?.background,
        resolveAppearance(
          const ReaderPreferences(),
          Brightness.dark,
        ).background,
      );
    });

    test('the system theme follows the app brightness', () async {
      await addBook();
      await start();
      await controller().setAppBrightness(Brightness.dark);
      await controller().setAppBrightness(Brightness.light);
      final backgrounds = [for (final a in reader.applied) a.background];
      expect(backgrounds, hasLength(2));
      expect(backgrounds.first, isNot(backgrounds.last));
    });
  });
}
