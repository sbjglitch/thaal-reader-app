import '../../core/errors/app_errors.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/entities/managed_path.dart';
import '../../domain/repositories/book_repository.dart';
import '../storage/library_storage.dart';

/// Removes a book from the library as a recoverable workflow
/// (DATABASE_SCHEMA.md §7.1):
///
/// 1. Move the book's files into a staging area.
/// 2. Delete the record; progress, bookmarks, highlights and collection links
///    go with it by cascade.
/// 3. Delete the staged files.
///
/// If step 2 fails, the files are moved back and the error is rethrown. If
/// step 3 fails, the record is already gone and startup staging cleanup
/// deletes the leftovers. The user's original source document is never
/// involved: only the app's private copy is removed.
class BookRemovalService {
  BookRemovalService({
    required this._storage,
    required this._books,
    required this._logger,
  });

  final LibraryStorage _storage;
  final BookRepository _books;
  final AppLogger _logger;

  /// Throws [AppError] when the book could not be removed; the library is
  /// then unchanged.
  Future<void> removeBook(String bookId) async {
    final area = await _storage.moveBookToStaging(bookId);
    try {
      await _books.removeBook(bookId);
    } on Object {
      if (area != null) {
        try {
          await _storage.restoreBookFromStaging(area, bookId);
          await _discard(area);
        } on StorageError catch (error) {
          // The record still exists but its files are stranded in staging:
          // it shows as "file missing", which the user can remove again.
          _logger.error('removal.restore_failed', error);
        }
      }
      rethrow;
    }
    if (area != null) await _discard(area);
    _logger.info('removal.finished', fields: {'hadFiles': area != null});
  }

  /// Best effort: startup staging cleanup removes anything left behind.
  Future<void> _discard(ManagedPath area) async {
    try {
      await _storage.discardStagingArea(area);
    } on StorageError catch (error) {
      _logger.warning('removal.cleanup_deferred', error: error);
    }
  }
}
