import '../entities/book.dart';
import '../entities/enums.dart';

/// Library records (DATABASE_SCHEMA.md §8.3). Only touches the database:
/// moving or deleting publication files is the job of the storage workflows.
abstract interface class BookRepository {
  /// All books, most recently added first.
  Stream<List<Book>> watchBooks();

  Future<Book?> getBook(String bookId);

  /// Books whose file has [checksum]; used to warn about duplicate imports.
  Future<List<Book>> findBooksByChecksum(String checksum);

  /// Throws [DatabaseError] with `constraintViolation` if the ID or file path
  /// is already in use.
  Future<void> addBook(Book book);

  /// Replaces the descriptive metadata of an existing book. File, checksum,
  /// status and timestamps other than `updatedAt` are left unchanged.
  Future<void> updateBookMetadata(Book book);

  Future<void> updateReadingStatus(String bookId, ReadingStatus status);

  /// Sets `lastOpenedAt` to [at] and moves an unread book to
  /// [ReadingStatus.reading]. Finished books stay finished.
  Future<void> recordOpened(String bookId, DateTime at);

  /// Deletes the record; progress, bookmarks, highlights and collection links
  /// are removed by cascade.
  Future<void> removeBook(String bookId);
}
