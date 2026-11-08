import 'package:drift/drift.dart';

import '../../domain/entities/locator_envelope.dart';
import '../../domain/entities/reading_data.dart';
import '../../domain/repositories/bookmark_repository.dart';
import '../database/app_database.dart';
import 'database_support.dart';

class DriftBookmarkRepository implements BookmarkRepository {
  DriftBookmarkRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Bookmark>> watchBookmarks(String bookId) {
    final query = _db.select(_db.bookmarks)
      ..where((t) => t.bookId.equals(bookId))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.watch().map((rows) => rows.map(_fromRow).toList());
  }

  @override
  Stream<List<Bookmark>> watchAllBookmarks() {
    final query = _db.select(_db.bookmarks)
      ..orderBy([
        (t) => OrderingTerm.desc(t.createdAt),
        (t) => OrderingTerm.asc(t.id),
      ]);
    return query.watch().map((rows) => rows.map(_fromRow).toList());
  }

  @override
  Future<void> addBookmark(Bookmark bookmark) =>
      guardDatabase('addBookmark', () {
        return _db
            .into(_db.bookmarks)
            .insert(
              BookmarksCompanion.insert(
                id: bookmark.id,
                bookId: bookmark.bookId,
                locatorJson: bookmark.locator.json,
                label: Value(bookmark.label),
                createdAt: toEpochMillis(bookmark.createdAt),
                updatedAt: toEpochMillis(bookmark.updatedAt),
              ),
            );
      });

  @override
  Future<void> updateBookmark(Bookmark bookmark) =>
      guardDatabase('updateBookmark', () async {
        final count =
            await (_db.update(
              _db.bookmarks,
            )..where((t) => t.id.equals(bookmark.id))).write(
              BookmarksCompanion(
                label: Value(bookmark.label),
                updatedAt: Value(toEpochMillis(bookmark.updatedAt)),
              ),
            );
        requireUpdated(count, 'updateBookmark');
      });

  @override
  Future<void> deleteBookmark(String bookmarkId) =>
      guardDatabase('deleteBookmark', () {
        return (_db.delete(
          _db.bookmarks,
        )..where((t) => t.id.equals(bookmarkId))).go();
      });

  static Bookmark _fromRow(BookmarkRow row) => Bookmark(
    id: row.id,
    bookId: row.bookId,
    locator: SerializedLocator.stored(row.locatorJson),
    label: row.label,
    createdAt: fromEpochMillis(row.createdAt),
    updatedAt: fromEpochMillis(row.updatedAt),
  );
}
