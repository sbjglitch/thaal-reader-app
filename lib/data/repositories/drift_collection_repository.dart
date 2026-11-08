import 'package:drift/drift.dart';

import '../../domain/entities/reading_data.dart';
import '../../domain/repositories/collection_repository.dart';
import '../database/app_database.dart';
import 'database_support.dart';

class DriftCollectionRepository implements CollectionRepository {
  DriftCollectionRepository(this._db, {this._clock = DateTime.now});

  final AppDatabase _db;
  final Clock _clock;

  @override
  Stream<List<Collection>> watchCollections() {
    final query = _db.select(_db.collections)
      ..orderBy([
        (t) => OrderingTerm.asc(t.name.collate(Collate.noCase)),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);
    return query.watch().map((rows) => rows.map(collectionFromRow).toList());
  }

  @override
  Future<void> createCollection(Collection collection) =>
      guardDatabase('createCollection', () {
        return _db
            .into(_db.collections)
            .insert(
              CollectionsCompanion.insert(
                id: collection.id,
                name: collection.name,
                createdAt: toEpochMillis(collection.createdAt),
                updatedAt: toEpochMillis(collection.updatedAt),
              ),
            );
      });

  @override
  Future<void> renameCollection(String collectionId, String name) =>
      guardDatabase('renameCollection', () async {
        final trimmed = name.trim();
        if (trimmed.isEmpty) {
          throw ArgumentError.value(name, 'name', 'must not be empty');
        }
        final count =
            await (_db.update(
              _db.collections,
            )..where((t) => t.id.equals(collectionId))).write(
              CollectionsCompanion(
                name: Value(trimmed),
                updatedAt: Value(toEpochMillis(_clock())),
              ),
            );
        requireUpdated(count, 'renameCollection');
      });

  @override
  Future<void> deleteCollection(String collectionId) =>
      guardDatabase('deleteCollection', () {
        return (_db.delete(
          _db.collections,
        )..where((t) => t.id.equals(collectionId))).go();
      });

  @override
  Future<void> addBookToCollection(String collectionId, String bookId) =>
      guardDatabase('addBookToCollection', () {
        // OR IGNORE skips an existing membership; SQLite still enforces the
        // foreign keys, so a missing book or collection is rejected.
        return _db
            .into(_db.collectionBooks)
            .insert(
              CollectionBooksCompanion.insert(
                collectionId: collectionId,
                bookId: bookId,
                addedAt: toEpochMillis(_clock()),
              ),
              mode: InsertMode.insertOrIgnore,
            );
      });

  @override
  Future<void> removeBookFromCollection(String collectionId, String bookId) =>
      guardDatabase('removeBookFromCollection', () {
        return (_db.delete(_db.collectionBooks)..where(
              (t) =>
                  t.collectionId.equals(collectionId) & t.bookId.equals(bookId),
            ))
            .go();
      });

  @override
  Stream<List<String>> watchBookIds(String collectionId) {
    final query = _db.select(_db.collectionBooks)
      ..where((t) => t.collectionId.equals(collectionId))
      ..orderBy([(t) => OrderingTerm.asc(t.addedAt)]);
    return query.watch().map((rows) => [for (final r in rows) r.bookId]);
  }
}

/// Maps a stored row to the domain entity. Visible for the data layer.
Collection collectionFromRow(CollectionRow row) => Collection(
  id: row.id,
  name: row.name,
  createdAt: fromEpochMillis(row.createdAt),
  updatedAt: fromEpochMillis(row.updatedAt),
);
