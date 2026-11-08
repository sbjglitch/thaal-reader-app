import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/uuid.dart';
import '../../../domain/entities/enums.dart';
import '../../../domain/entities/locator_envelope.dart';
import '../../../domain/entities/reading_data.dart';
import '../../../domain/repositories/highlight_repository.dart';
import '../../../services/reader/publication_reader.dart';

/// A highlight ready to show. [location] is null when its stored locator
/// cannot be decoded; the highlight and its note are still listed and kept
/// (READER_ENGINE_SPECIFICATION.md §11.5).
final class HighlightEntry {
  const HighlightEntry({required this.highlight, this.location});

  final Highlight highlight;
  final ReaderPosition? location;

  LocatorEnvelope? get locator => location?.locator;
}

/// Highlights of one EPUB, oldest first.
final bookHighlightsProvider = StreamProvider.autoDispose
    .family<List<HighlightEntry>, String>((ref, bookId) {
      final interpreter = ref.watch(locatorInterpreterProvider);
      return ref
          .watch(highlightRepositoryProvider)
          .watchHighlights(bookId)
          .map(
            (list) => [
              for (final highlight in list)
                HighlightEntry(
                  highlight: highlight,
                  location: switch (highlight.locator.decode(
                    PublicationFormat.epub,
                  )) {
                    final envelope? => interpreter.describe(envelope),
                    null => null,
                  },
                ),
            ],
          );
    });

/// Creates, edits, deletes and restores highlights. Errors propagate as
/// `AppError`; callers report them and show nothing as saved.
class HighlightActions {
  HighlightActions(
    this._highlights, {
    this._clock = DateTime.now,
    this._newId = generateUuidV4,
  });

  final HighlightRepository _highlights;
  final Clock _clock;
  final String Function() _newId;

  /// Longest note kept; longer input is cut.
  static const int maxNoteLength = 5000;

  Future<Highlight> add(
    String bookId,
    LocatorEnvelope locator, {
    String? selectedText,
    HighlightColor color = HighlightColor.yellow,
  }) async {
    final now = _clock();
    final text = selectedText?.trim();
    final highlight = Highlight(
      id: _newId(),
      bookId: bookId,
      locator: SerializedLocator.fromEnvelope(locator),
      selectedText: text == null || text.isEmpty ? null : text,
      color: color,
      createdAt: now,
      updatedAt: now,
    );
    await _highlights.addHighlight(highlight);
    return highlight;
  }

  /// Saves [color] and [note]; a blank note removes it.
  Future<Highlight> update(
    Highlight highlight, {
    required HighlightColor color,
    required String note,
  }) async {
    var trimmed = note.trim();
    if (trimmed.length > maxNoteLength) {
      trimmed = trimmed.substring(0, maxNoteLength);
    }
    final updated = Highlight(
      id: highlight.id,
      bookId: highlight.bookId,
      locator: highlight.locator,
      selectedText: highlight.selectedText,
      color: color,
      note: trimmed.isEmpty ? null : trimmed,
      createdAt: highlight.createdAt,
      updatedAt: _clock(),
    );
    await _highlights.updateHighlight(updated);
    return updated;
  }

  Future<void> delete(Highlight highlight) =>
      _highlights.deleteHighlight(highlight.id);

  /// Undo for [delete]: re-inserts the same record.
  Future<void> restore(Highlight highlight) =>
      _highlights.addHighlight(highlight);
}

final highlightActionsProvider = Provider<HighlightActions>(
  (ref) => HighlightActions(ref.watch(highlightRepositoryProvider)),
);
