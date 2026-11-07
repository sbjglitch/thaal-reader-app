import 'dart:io';
import 'dart:ui' show Brightness;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaal/app/providers.dart';
import 'package:thaal/core/logging/app_logger.dart';
import 'package:thaal/data/database/app_database.dart';
import 'package:thaal/data/repositories/drift_book_repository.dart';
import 'package:thaal/data/repositories/drift_reading_progress_repository.dart';
import 'package:thaal/domain/entities/enums.dart';
import 'package:thaal/domain/entities/locator_envelope.dart';
import 'package:thaal/domain/entities/reader_preferences.dart';
import 'package:thaal/domain/entities/reading_data.dart';
import 'package:thaal/features/reader/application/reader_controller.dart';
import 'package:thaal/features/reader/application/reader_preferences_controller.dart';
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

  Future<void> addBook({bool withFile = true}) async {
    final book = sampleBook();
    await DriftBookRepository(db).addBook(book);
    if (withFile) {
      final file = storage.file(book.filePath);
      await file.parent.create(recursive: true);
      await file.writeAsString('epub bytes');
    }
  }

  Future<ReaderState> start() async {
    subscription = container.listen(
      readerControllerProvider('book-1'),
      (_, _) {},
    );
    // Let the microtask-started open run to completion.
    for (var i = 0; i < 200; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      if (subscription.read() is! ReaderOpening) break;
    }
    return subscription.read();
  }

  ReaderController controller() =>
      container.read(readerControllerProvider('book-1').notifier);

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

    test('the system theme follows the device brightness', () async {
      await addBook();
      await start();
      await controller().setPlatformBrightness(Brightness.dark);
      await controller().setPlatformBrightness(Brightness.light);
      final backgrounds = [for (final a in reader.applied) a.background];
      expect(backgrounds, hasLength(2));
      expect(backgrounds.first, isNot(backgrounds.last));
    });
  });
}
