import 'dart:async';

import 'package:thaal/core/errors/app_errors.dart';
import 'package:thaal/domain/entities/enums.dart';
import 'package:thaal/domain/entities/reading_data.dart';
import 'package:thaal/domain/repositories/highlight_repository.dart';
import 'package:thaal/features/highlights/application/highlights.dart';
import 'package:thaal/services/reader/publication_reader.dart';

/// In-memory [HighlightRepository] that re-emits after every change.
class MemoryHighlightRepository implements HighlightRepository {
  final List<Highlight> items = [];
  final _changes = StreamController<void>.broadcast();

  /// When set, writes throw this.
  AppError? failWrites;

  @override
  Stream<List<Highlight>> watchHighlights(String bookId) async* {
    List<Highlight> select() => [
      for (final h in items)
        if (h.bookId == bookId) h,
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    yield select();
    yield* _changes.stream.map((_) => select());
  }

  void _write(void Function() change) {
    if (failWrites case final error?) throw error;
    change();
    _changes.add(null);
  }

  @override
  Future<void> addHighlight(Highlight highlight) async =>
      _write(() => items.add(highlight));

  @override
  Future<void> updateHighlight(Highlight highlight) async => _write(() {
    final index = items.indexWhere((h) => h.id == highlight.id);
    items[index] = highlight;
  });

  @override
  Future<void> deleteHighlight(String highlightId) async =>
      _write(() => items.removeWhere((h) => h.id == highlightId));
}

/// Entries as the real provider builds them, using [interpreter].
Stream<List<HighlightEntry>> highlightEntriesOf(
  Stream<List<Highlight>> highlights,
  LocatorInterpreter interpreter,
) => highlights.map(
  (list) => [
    for (final highlight in list)
      HighlightEntry(
        highlight: highlight,
        location: switch (highlight.locator.decode(PublicationFormat.epub)) {
          final envelope? => interpreter.describe(envelope),
          null => null,
        },
      ),
  ],
);
