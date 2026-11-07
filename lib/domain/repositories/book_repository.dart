import '../entities/book.dart';
import '../entities/enums.dart';

/// Library records (DATABASE_SCHEMA.md §8.3). Only touches the database:
/// moving or deleting publication files is the job of the storage workflows.
abstract interface class BookRepository {
  /// All books, most recently added first.
  Stream<List<Book>> watchBooks();

  Future<Book?> getBook(String bookId);

  /// Throws [DatabaseError] with `constraintViolation` if the ID or file path
  /// is already in use.
  Future<void> addBook(Book book);

  /// Replaces the descriptive metadata of an existing book. File, checksum,
  /// status and timestamps other than `updatedAt` are left unchanged.
  Future<void> updateBookMetadata(Book book);

  Future<void> updateReadingStatus(String bookId, ReadingStatus status);

  /// Deletes the record; progress, bookmarks, highlights and collection links
  /// are removed by cascade.
  Future<void> removeBook(String bookId);
}
