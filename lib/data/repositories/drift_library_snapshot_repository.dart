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
}
