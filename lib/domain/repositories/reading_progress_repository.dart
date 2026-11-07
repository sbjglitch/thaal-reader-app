import '../entities/reading_data.dart';

abstract interface class ReadingProgressRepository {
  Future<ReadingProgress?> getProgress(String bookId);

  /// Inserts or replaces the single progress row of the book. On failure the
  /// previously saved row is left untouched.
  Future<void> saveProgress(ReadingProgress progress);

  Future<void> clearProgress(String bookId);
}
