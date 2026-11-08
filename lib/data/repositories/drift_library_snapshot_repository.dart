import 'package:drift/drift.dart';

import '../../domain/entities/library_snapshot.dart';
import '../../domain/repositories/library_snapshot_repository.dart';
import '../database/app_database.dart';
import 'database_support.dart';
import 'drift_book_repository.dart';
import 'drift_bookmark_repository.dart';
import 'drift_collection_repository.dart';
import 'drift_highlight_repository.dart';
import 'drift_reading_progress_repository.dart';

class DriftLibrarySnapshotRepository implements LibrarySnapshotRepository {
  DriftLibrarySnapshotRepository(this._db);

  final AppDatabase _db;

  /// One transaction, so a concurrent write cannot leave, say, a bookmark
  /// whose book is missing from the snapshot. Rows are ordered by id to make
  /// exports deterministic.
  @override
  Future<LibrarySnapshot> readSnapshot() => guardDatabase('readSnapshot', () {
    return _db.transaction(() async {
      final books = await (_db.select(
        _db.books,
      )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
      final progress = await (_db.select(
        _db.readingProgressEntries,
      )..orderBy([(t) => OrderingTerm.asc(t.bookId)])).get();
      final bookmarks = await (_db.select(
        _db.bookmarks,
      )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
      final highlights = await (_db.select(
        _db.highlights,
      )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
      final collections = await (_db.select(
        _db.collections,
      )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
      final memberships =
          await (_db.select(_db.collectionBooks)..orderBy([
                (t) => OrderingTerm.asc(t.collectionId),
                (t) => OrderingTerm.asc(t.bookId),
              ]))
              .get();
      return LibrarySnapshot(
        books: books.map(bookFromRow).toList(),
        progress: progress.map(progressFromRow).toList(),
        bookmarks: bookmarks.map(bookmarkFromRow).toList(),
        highlights: highlights.map(highlightFromRow).toList(),
        collections: collections.map(collectionFromRow).toList(),
        memberships: [
          for (final row in memberships)
            CollectionMembership(
              collectionId: row.collectionId,
              bookId: row.bookId,
              addedAt: fromEpochMillis(row.addedAt),
            ),
        ],
      );
    });
  });

  @override
  Future<void> insertRecords(LibrarySnapshot records) =>
      guardDatabase('insertRecords', () {
        return _db.transaction(() async {
          await _db.batch((batch) {
            batch
              ..insertAll(_db.books, [
                for (final book in records.books)
                  BooksCompanion.insert(
                    id: book.id,
                    title: book.title,
                    authorsJson: Value(book.authors),
                    description: Value(book.description),
                    language: Value(book.language),
                    identifier: Value(book.identifier),
                    publisher: Value(book.publisher),
                    publishedAt: Value(book.publishedAt),
                    format: book.format,
                    filePath: book.filePath.value,
                    coverPath: Value(book.coverPath?.value),
                    fileSizeBytes: book.fileSizeBytes,
                    fileChecksum: book.fileChecksum,
                    readingStatus: Value(book.readingStatus),
                    addedAt: toEpochMillis(book.addedAt),
                    lastOpenedAt: Value(
                      book.lastOpenedAt == null
                          ? null
                          : toEpochMillis(book.lastOpenedAt!),
                    ),
                    updatedAt: toEpochMillis(book.updatedAt),
                    metadataJson: Value(book.metadataJson),
                  ),
              ])
              ..insertAll(_db.readingProgressEntries, [
                for (final progress in records.progress)
                  ReadingProgressEntriesCompanion.insert(
                    bookId: progress.bookId,
                    locatorJson: Value(progress.locator?.json),
                    pageNumber: Value(progress.pageNumber),
                    progression: Value(progress.progression),
                    updatedAt: toEpochMillis(progress.updatedAt),
                  ),
              ])
              ..insertAll(_db.bookmarks, [
                for (final bookmark in records.bookmarks)
                  BookmarksCompanion.insert(
                    id: bookmark.id,
                    bookId: bookmark.bookId,
                    locatorJson: bookmark.locator.json,
                    label: Value(bookmark.label),
                    createdAt: toEpochMillis(bookmark.createdAt),
                    updatedAt: toEpochMillis(bookmark.updatedAt),
                  ),
              ])
              ..insertAll(_db.highlights, [
                for (final highlight in records.highlights)
                  HighlightsCompanion.insert(
                    id: highlight.id,
                    bookId: highlight.bookId,
                    locatorJson: highlight.locator.json,
                    selectedText: Value(highlight.selectedText),
                    color: highlight.color,
                    note: Value(highlight.note),
                    createdAt: toEpochMillis(highlight.createdAt),
                    updatedAt: toEpochMillis(highlight.updatedAt),
                  ),
              ])
              ..insertAll(_db.collections, [
                for (final collection in records.collections)
                  CollectionsCompanion.insert(
                    id: collection.id,
                    name: collection.name,
                    createdAt: toEpochMillis(collection.createdAt),
                    updatedAt: toEpochMillis(collection.updatedAt),
                  ),
              ])
              ..insertAll(_db.collectionBooks, [
                for (final membership in records.memberships)
                  CollectionBooksCompanion.insert(
                    collectionId: membership.collectionId,
                    bookId: membership.bookId,
                    addedAt: toEpochMillis(membership.addedAt),
                  ),
              ]);
          });
        });
      });
}
