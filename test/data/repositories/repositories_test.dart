import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/core/errors/app_errors.dart';
import 'package:thaal/data/database/app_database.dart';
import 'package:thaal/data/repositories/drift_book_repository.dart';
import 'package:thaal/data/repositories/drift_bookmark_repository.dart';
import 'package:thaal/data/repositories/drift_collection_repository.dart';
import 'package:thaal/data/repositories/drift_highlight_repository.dart';
import 'package:thaal/data/repositories/drift_reading_progress_repository.dart';
import 'package:thaal/domain/entities/enums.dart';
import 'package:thaal/domain/entities/locator_envelope.dart';
import 'package:thaal/domain/entities/managed_path.dart';
import 'package:thaal/domain/entities/reading_data.dart';

import '../../support/fixtures.dart';

Matcher throwsDatabaseError(DatabaseErrorKind kind) =>
    throwsA(isA<DatabaseError>().having((e) => e.kind, 'kind', kind));

void main() {
  late AppDatabase db;
  late DriftBookRepository books;
  late DriftReadingProgressRepository progress;
  late DriftBookmarkRepository bookmarks;
  late DriftHighlightRepository highlights;
  late DriftCollectionRepository collections;
  final later = fixedTime.add(const Duration(hours: 1));

  setUp(() {
    db = openTestDatabase();
    books = DriftBookRepository(db, clock: () => later);
    progress = DriftReadingProgressRepository(db);
    bookmarks = DriftBookmarkRepository(db);
    highlights = DriftHighlightRepository(db);
    collections = DriftCollectionRepository(db, clock: () => later);
  });
  tearDown(() => db.close());

  Bookmark bookmark(String id, {String bookId = 'book-1', int minute = 0}) =>
      Bookmark(
        id: id,
        bookId: bookId,
        locator: sampleLocator(),
        label: 'Label $id',
        createdAt: fixedTime.add(Duration(minutes: minute)),
        updatedAt: fixedTime,
      );

  Highlight highlight(String id, {String bookId = 'book-1'}) => Highlight(
    id: id,
    bookId: bookId,
    locator: sampleLocator(),
    selectedText: 'selected',
    color: HighlightColor.yellow,
    note: 'note',
    createdAt: fixedTime,
    updatedAt: fixedTime,
  );

  Collection collection(String id, String name) => Collection(
    id: id,
    name: name,
    createdAt: fixedTime,
    updatedAt: fixedTime,
  );

  group('BookRepository', () {
    test('recordOpened sets lastOpenedAt and starts an unread book', () async {
      await books.addBook(sampleBook());
      await books.recordOpened('book-1', later);

      final opened = (await books.getBook('book-1'))!;
      expect(opened.lastOpenedAt, later);
      expect(opened.readingStatus, ReadingStatus.reading);

      await books.updateReadingStatus('book-1', ReadingStatus.finished);
      await books.recordOpened('book-1', later);
      expect(
        (await books.getBook('book-1'))!.readingStatus,
        ReadingStatus.finished,
      );
      await expectLater(
        books.recordOpened('missing', later),
        throwsA(isA<DatabaseError>()),
      );
    });

    test('adds and reads back every field', () async {
      final book = sampleBook();
      await books.addBook(book);

      final stored = (await books.getBook(book.id))!;
      expect(stored.title, book.title);
      expect(stored.authors, book.authors);
      expect(stored.format, PublicationFormat.epub);
      expect(stored.filePath, book.filePath);
      expect(stored.fileChecksum, sampleChecksum);
      expect(stored.readingStatus, ReadingStatus.unread);
      expect(stored.addedAt, fixedTime);
      expect(stored.addedAt.isUtc, isTrue);
      expect(stored.lastOpenedAt, isNull);
      expect(await books.getBook('missing'), isNull);
    });

    test('watchBooks emits newest first and reacts to changes', () async {
      await books.addBook(sampleBook(id: 'old', addedAt: fixedTime));
      final stream = books.watchBooks();
      expect((await stream.first).map((b) => b.id), ['old']);

      await books.addBook(sampleBook(id: 'new', addedAt: later));
      expect((await stream.first).map((b) => b.id), ['new', 'old']);
    });

    test('rejects a duplicate id or file path', () async {
      await books.addBook(sampleBook());
      expect(
        books.addBook(sampleBook()),
        throwsDatabaseError(DatabaseErrorKind.constraintViolation),
      );
    });

    test('allows duplicate checksums (separate copies)', () async {
      await books.addBook(sampleBook(id: 'a'));
      await books.addBook(sampleBook(id: 'b'));
      expect(await books.watchBooks().first, hasLength(2));
    });

    test('updates metadata and status, stamping updatedAt', () async {
      await books.addBook(sampleBook());
      await books.updateBookMetadata(
        sampleBook().copyWith(title: 'Renamed', authors: ['Solo']),
      );
      await books.updateReadingStatus('book-1', ReadingStatus.finished);

      final stored = (await books.getBook('book-1'))!;
      expect(stored.title, 'Renamed');
      expect(stored.authors, ['Solo']);
      expect(stored.readingStatus, ReadingStatus.finished);
      expect(stored.updatedAt, later);
    });

    test('updating a missing book reports notFound', () {
      expect(
        books.updateReadingStatus('missing', ReadingStatus.reading),
        throwsDatabaseError(DatabaseErrorKind.notFound),
      );
    });

    test('removing a book cascades to all dependent rows', () async {
      await books.addBook(sampleBook());
      await books.addBook(sampleBook(id: 'other'));
      await progress.saveProgress(
        ReadingProgress(
          bookId: 'book-1',
          progression: 0.4,
          updatedAt: fixedTime,
        ),
      );
      await bookmarks.addBookmark(bookmark('bm'));
      await highlights.addHighlight(highlight('hl'));
      await collections.createCollection(collection('c', 'Shelf'));
      await collections.addBookToCollection('c', 'book-1');
      await collections.addBookToCollection('c', 'other');

      await books.removeBook('book-1');

      expect(await progress.getProgress('book-1'), isNull);
      expect(await bookmarks.watchBookmarks('book-1').first, isEmpty);
      expect(await highlights.watchHighlights('book-1').first, isEmpty);
      expect(await collections.watchBookIds('c').first, ['other']);
      expect(await collections.watchCollections().first, hasLength(1));
      // Idempotent for retrying cleanup.
      await books.removeBook('book-1');
    });
  });

  group('ReadingProgressRepository', () {
    setUp(() => books.addBook(sampleBook()));

    test('watchProgressions lists books that have a progression', () async {
      await books.addBook(sampleBook(id: 'book-2'));
      await progress.saveProgress(
        ReadingProgress(bookId: 'book-1', progression: 0.4, updatedAt: later),
      );
      await progress.saveProgress(
        ReadingProgress(
          bookId: 'book-2',
          locator: sampleLocator(),
          updatedAt: later,
        ),
      );
      expect(await progress.watchProgressions().first, {'book-1': 0.4});
    });

    test('saves, replaces and clears the single progress row', () async {
      final first = ReadingProgress(
        bookId: 'book-1',
        locator: sampleLocator(href: 'a.xhtml'),
        progression: 0.1,
        updatedAt: fixedTime,
      );
      await progress.saveProgress(first);
      await progress.saveProgress(
        ReadingProgress(
          bookId: 'book-1',
          locator: sampleLocator(href: 'b.xhtml'),
          pageNumber: 3,
          progression: 0.2,
          updatedAt: later,
        ),
      );

      final stored = (await progress.getProgress('book-1'))!;
      expect(stored.locator, sampleLocator(href: 'b.xhtml'));
      expect(
        stored.locator!.decode(PublicationFormat.epub)!.locator['href'],
        'b.xhtml',
      );
      expect(stored.pageNumber, 3);
      expect(stored.progression, 0.2);
      expect(stored.updatedAt, later);

      await progress.clearProgress('book-1');
      expect(await progress.getProgress('book-1'), isNull);
    });

    test('a failed write keeps the last valid position', () async {
      await progress.saveProgress(
        ReadingProgress(
          bookId: 'book-1',
          locator: sampleLocator(href: 'kept.xhtml'),
          updatedAt: fixedTime,
        ),
      );

      await expectLater(
        progress.saveProgress(
          ReadingProgress(
            bookId: 'book-1',
            locator: const SerializedLocator.stored('not json'),
            updatedAt: later,
          ),
        ),
        throwsDatabaseError(DatabaseErrorKind.constraintViolation),
      );

      final stored = (await progress.getProgress('book-1'))!;
      expect(stored.locator, sampleLocator(href: 'kept.xhtml'));
    });

    test('progress for a missing book is rejected', () {
      expect(
        progress.saveProgress(
          ReadingProgress(bookId: 'missing', updatedAt: fixedTime),
        ),
        throwsDatabaseError(DatabaseErrorKind.constraintViolation),
      );
    });
  });

  group('BookmarkRepository', () {
    setUp(() => books.addBook(sampleBook()));

    test('adds, orders, updates and deletes bookmarks', () async {
      await bookmarks.addBookmark(bookmark('second', minute: 5));
      await bookmarks.addBookmark(bookmark('first', minute: 1));
      // Same location twice is allowed (no deduplication in the MVP).
      await bookmarks.addBookmark(bookmark('third', minute: 9));

      var list = await bookmarks.watchBookmarks('book-1').first;
      expect(list.map((b) => b.id), ['first', 'second', 'third']);
      expect(list.first.locator, sampleLocator());

      await bookmarks.updateBookmark(
        list.first.copyWith(label: 'Renamed', updatedAt: later),
      );
      await bookmarks.deleteBookmark('second');

      list = await bookmarks.watchBookmarks('book-1').first;
      expect(list.map((b) => b.id), ['first', 'third']);
      expect(list.first.label, 'Renamed');
      expect(list.first.updatedAt, later);
    });

    test('lists bookmarks of every book newest first', () async {
      await books.addBook(sampleBook(id: 'book-2'));
      await bookmarks.addBookmark(bookmark('old', minute: 1));
      await bookmarks.addBookmark(bookmark('new', bookId: 'book-2', minute: 9));
      await bookmarks.addBookmark(bookmark('mid', minute: 5));
      final all = await bookmarks.watchAllBookmarks().first;
      expect(all.map((b) => b.id), ['new', 'mid', 'old']);
    });

    test('a bookmark must reference an existing book', () {
      expect(
        bookmarks.addBookmark(bookmark('x', bookId: 'missing')),
        throwsDatabaseError(DatabaseErrorKind.constraintViolation),
      );
    });

    test('a stored locator this version cannot decode is preserved', () async {
      await bookmarks.addBookmark(
        Bookmark(
          id: 'future',
          bookId: 'book-1',
          locator: const SerializedLocator.stored('{"schemaVersion":2}'),
          createdAt: fixedTime,
          updatedAt: fixedTime,
        ),
      );
      final stored = (await bookmarks.watchBookmarks('book-1').first).single;
      expect(stored.locator.json, '{"schemaVersion":2}');
      expect(stored.locator.decode(PublicationFormat.epub), isNull);
    });
  });

  group('HighlightRepository', () {
    setUp(() => books.addBook(sampleBook()));

    test('adds, updates and deletes highlights', () async {
      await highlights.addHighlight(highlight('h1'));
      final original =
          (await highlights.watchHighlights('book-1').first).single;
      expect(original.selectedText, 'selected');
      expect(original.color, HighlightColor.yellow);

      await highlights.updateHighlight(
        Highlight(
          id: 'h1',
          bookId: 'book-1',
          locator: original.locator,
          selectedText: original.selectedText,
          color: HighlightColor.blue,
          note: 'changed',
          createdAt: original.createdAt,
          updatedAt: later,
        ),
      );
      final updated = (await highlights.watchHighlights('book-1').first).single;
      expect(updated.color, HighlightColor.blue);
      expect(updated.note, 'changed');

      await highlights.deleteHighlight('h1');
      expect(await highlights.watchHighlights('book-1').first, isEmpty);
    });
  });

  group('CollectionRepository', () {
    setUp(() async {
      await books.addBook(sampleBook(id: 'a'));
      await books.addBook(sampleBook(id: 'b'));
    });

    test(
      'creates, renames and sorts collections; duplicates allowed',
      () async {
        await collections.createCollection(collection('1', 'zebra'));
        await collections.createCollection(collection('2', 'Apple'));
        await collections.createCollection(collection('3', 'Apple'));
        await collections.renameCollection('1', '  Mango ');

        final list = await collections.watchCollections().first;
        expect(list.map((c) => c.name), ['Apple', 'Apple', 'Mango']);
        expect(list.last.updatedAt, later);
        expect(
          () => collections.renameCollection('1', ' '),
          throwsArgumentError,
        );
        expect(
          collections.renameCollection('missing', 'X'),
          throwsDatabaseError(DatabaseErrorKind.notFound),
        );
      },
    );

    test(
      'membership is unique, removable, and keeps books on delete',
      () async {
        await collections.createCollection(collection('c', 'Shelf'));
        await collections.addBookToCollection('c', 'a');
        await collections.addBookToCollection('c', 'a');
        await collections.addBookToCollection('c', 'b');
        expect(await collections.watchBookIds('c').first, ['a', 'b']);

        await collections.removeBookFromCollection('c', 'a');
        expect(await collections.watchBookIds('c').first, ['b']);

        await collections.deleteCollection('c');
        expect(await collections.watchBookIds('c').first, isEmpty);
        expect(await books.watchBooks().first, hasLength(2));
      },
    );

    test('membership requires an existing book and collection', () async {
      await collections.createCollection(collection('c', 'Shelf'));
      expect(
        collections.addBookToCollection('c', 'missing'),
        throwsDatabaseError(DatabaseErrorKind.constraintViolation),
      );
      expect(
        collections.addBookToCollection('missing', 'a'),
        throwsDatabaseError(DatabaseErrorKind.constraintViolation),
      );
    });
  });

  test(
    'constraint errors from the background-isolate database are typed',
    () async {
      final dir = await Directory.systemTemp.createTemp('thaal_repo');
      addTearDown(() => dir.delete(recursive: true));
      final background = AppDatabase.open(File('${dir.path}/t.sqlite'));
      addTearDown(background.close);

      await expectLater(
        DriftBookmarkRepository(background)
            .addBookmark(bookmark('x', bookId: 'missing')),
        throwsDatabaseError(DatabaseErrorKind.constraintViolation),
      );
    },
  );

  test('managed paths round-trip through storage', () async {
    final book = sampleBook();
    await books.addBook(book);
    expect(
      (await books.getBook(book.id))!.filePath,
      ManagedPath.parse('books/book-1/publication.epub'),
    );
  });
}
