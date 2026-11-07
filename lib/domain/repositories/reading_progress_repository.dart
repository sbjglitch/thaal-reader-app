import '../entities/reading_data.dart';

abstract interface class ReadingProgressRepository {
  Future<ReadingProgress?> getProgress(String bookId);

  /// Inserts or replaces the single progress row of the book. On failure the
  /// previously saved row is left untouched.
  Future<void> saveProgress(ReadingProgress progress);

  Future<void> clearProgress(String bookId);

  /// Approximate progression (0.0–1.0) of every book that has one, keyed by
  /// book ID. For library display and sorting only, never for restoring.
  Stream<Map<String, double>> watchProgressions();
}
