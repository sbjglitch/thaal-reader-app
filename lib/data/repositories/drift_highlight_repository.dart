import 'package:drift/drift.dart';

import '../../domain/entities/locator_envelope.dart';
import '../../domain/entities/reading_data.dart';
import '../../domain/repositories/highlight_repository.dart';
import '../database/app_database.dart';
import 'database_support.dart';

class DriftHighlightRepository implements HighlightRepository {
  DriftHighlightRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Highlight>> watchHighlights(String bookId) {
    final query = _db.select(_db.highlights)
      ..where((t) => t.bookId.equals(bookId))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.watch().map((rows) => rows.map(highlightFromRow).toList());
  }

  @override
  Future<void> addHighlight(Highlight highlight) =>
      guardDatabase('addHighlight', () {
        return _db
            .into(_db.highlights)
            .insert(
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
            );
      });

  @override
  Future<void> updateHighlight(Highlight highlight) =>
      guardDatabase('updateHighlight', () async {
        final count =
            await (_db.update(
              _db.highlights,
            )..where((t) => t.id.equals(highlight.id))).write(
              HighlightsCompanion(
                color: Value(highlight.color),
                note: Value(highlight.note),
                updatedAt: Value(toEpochMillis(highlight.updatedAt)),
              ),
            );
        requireUpdated(count, 'updateHighlight');
      });

  @override
  Future<void> deleteHighlight(String highlightId) =>
      guardDatabase('deleteHighlight', () {
        return (_db.delete(
          _db.highlights,
        )..where((t) => t.id.equals(highlightId))).go();
      });
}

/// Maps a stored row to the domain entity. Visible for the data layer.
Highlight highlightFromRow(HighlightRow row) => Highlight(
  id: row.id,
  bookId: row.bookId,
  locator: SerializedLocator.stored(row.locatorJson),
  selectedText: row.selectedText,
  color: row.color,
  note: row.note,
  createdAt: fromEpochMillis(row.createdAt),
  updatedAt: fromEpochMillis(row.updatedAt),
);
