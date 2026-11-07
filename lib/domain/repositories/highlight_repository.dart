import '../entities/reading_data.dart';

abstract interface class HighlightRepository {
  /// Highlights of [bookId], oldest first.
  Stream<List<Highlight>> watchHighlights(String bookId);

  Future<void> addHighlight(Highlight highlight);

  /// Updates the colour and note of an existing highlight.
  Future<void> updateHighlight(Highlight highlight);

  Future<void> deleteHighlight(String highlightId);
}
