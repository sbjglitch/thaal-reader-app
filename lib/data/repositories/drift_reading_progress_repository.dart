import 'package:drift/drift.dart';

import '../../domain/entities/locator_envelope.dart';
import '../../domain/entities/reading_data.dart';
import '../../domain/repositories/reading_progress_repository.dart';
import '../database/app_database.dart';
import 'database_support.dart';

class DriftReadingProgressRepository implements ReadingProgressRepository {
  DriftReadingProgressRepository(this._db);

  final AppDatabase _db;

  @override
  Future<ReadingProgress?> getProgress(String bookId) =>
      guardDatabase('getProgress', () async {
        final row = await (_db.select(
          _db.readingProgressEntries,
        )..where((t) => t.bookId.equals(bookId))).getSingleOrNull();
        return row == null ? null : progressFromRow(row);
      });

  /// A single upsert statement, so a failed write leaves the previous
  /// position intact.
  @override
  Future<void> saveProgress(ReadingProgress progress) =>
      guardDatabase('saveProgress', () {
        return _db
            .into(_db.readingProgressEntries)
            .insertOnConflictUpdate(
              ReadingProgressEntriesCompanion.insert(
                bookId: progress.bookId,
                locatorJson: Value(progress.locator?.json),
                pageNumber: Value(progress.pageNumber),
                progression: Value(progress.progression),
                updatedAt: toEpochMillis(progress.updatedAt),
              ),
            );
      });

  @override
  Future<void> clearProgress(String bookId) =>
      guardDatabase('clearProgress', () {
        return (_db.delete(
          _db.readingProgressEntries,
        )..where((t) => t.bookId.equals(bookId))).go();
      });

  @override
  Stream<Map<String, double>> watchProgressions() {
    final query = _db.selectOnly(_db.readingProgressEntries)
      ..addColumns([
        _db.readingProgressEntries.bookId,
        _db.readingProgressEntries.progression,
      ])
      ..where(_db.readingProgressEntries.progression.isNotNull());
    return query.watch().map(
      (rows) => {
        for (final row in rows)
          row.read(_db.readingProgressEntries.bookId)!: row.read(
            _db.readingProgressEntries.progression,
          )!,
      },
    );
  }
}

/// Maps a stored row to the domain entity. Visible for the data layer.
ReadingProgress progressFromRow(ReadingProgressRow row) {
  final locatorJson = row.locatorJson;
  return ReadingProgress(
    bookId: row.bookId,
    locator: locatorJson == null ? null : SerializedLocator.stored(locatorJson),
    pageNumber: row.pageNumber,
    progression: row.progression,
    updatedAt: fromEpochMillis(row.updatedAt),
  );
}
