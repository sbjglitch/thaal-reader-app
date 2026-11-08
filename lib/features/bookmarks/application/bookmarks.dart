import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/uuid.dart';
import '../../../domain/entities/book.dart';
import '../../../domain/entities/locator_envelope.dart';
import '../../../domain/entities/reading_data.dart';
import '../../../domain/repositories/bookmark_repository.dart';
import '../../../services/reader/publication_reader.dart';
import '../../library/application/library_items.dart';

/// A bookmark ready to show: its book and the details read from its
/// locator. [location] is null when the stored locator cannot be decoded;
/// the bookmark is still listed and kept (READER_ENGINE_SPECIFICATION.md
/// §10.2).
final class BookmarkEntry {
  const BookmarkEntry({
    required this.bookmark,
    required this.book,
    this.location,
    this.fileAvailable = true,
  });

  final Bookmark bookmark;
  final Book book;
  final ReaderPosition? location;

  /// Whether the book's publication file is present; when it is not the
  /// bookmark is listed but cannot be opened in the reader.
  final bool fileAvailable;

  LocatorEnvelope? get locator => location?.locator;
}

BookmarkEntry _entry(
  Bookmark bookmark,
  Book book,
  LocatorInterpreter reader, {
  bool fileAvailable = true,
}) {
  final envelope = bookmark.locator.decode(book.format);
  return BookmarkEntry(
    bookmark: bookmark,
    book: book,
    location: envelope == null ? null : reader.describe(envelope),
    fileAvailable: fileAvailable,
  );
}

/// Bookmarks of one book, oldest first (reading order of creation).
final bookBookmarksProvider = StreamProvider.autoDispose
    .family<List<BookmarkEntry>, String>((ref, bookId) async* {
      final interpreter = ref.watch(locatorInterpreterProvider);
      final book = await ref.watch(bookRepositoryProvider).getBook(bookId);
      if (book == null) {
        yield const [];
        return;
      }
      yield* ref
          .watch(bookmarkRepositoryProvider)
          .watchBookmarks(bookId)
          .map((list) => [for (final b in list) _entry(b, book, interpreter)]);
    });

/// All bookmarks, newest first, for the Bookmarks tab.
final allBookmarksProvider = StreamProvider.autoDispose<List<BookmarkEntry>>((
  ref,
) async* {
  final interpreter = ref.watch(locatorInterpreterProvider);
  final items = {
    for (final item in await ref.watch(libraryItemsProvider.future))
      item.book.id: item,
  };
  yield* ref
      .watch(bookmarkRepositoryProvider)
      .watchAllBookmarks()
      .map(
        (list) => [
          for (final bookmark in list)
            if (items[bookmark.bookId] case final item?)
              _entry(
                bookmark,
                item.book,
                interpreter,
                fileAvailable: item.fileAvailable,
              ),
        ],
      );
});

/// Creates, renames, deletes and restores bookmarks. Errors propagate as
/// `AppError` so callers can report them; nothing is shown as saved until
/// the write succeeds (spec §10.1).
class BookmarkActions {
  BookmarkActions(
    this._bookmarks, {
    this._clock = DateTime.now,
    this._newId = generateUuidV4,
  });

  final BookmarkRepository _bookmarks;
  final Clock _clock;
  final String Function() _newId;

  /// Longest label kept; longer input is cut.
  static const int maxLabelLength = 100;

  Future<Bookmark> add(String bookId, LocatorEnvelope locator) async {
    final now = _clock();
    final bookmark = Bookmark(
      id: _newId(),
      bookId: bookId,
      locator: SerializedLocator.fromEnvelope(locator),
      createdAt: now,
      updatedAt: now,
    );
    await _bookmarks.addBookmark(bookmark);
    return bookmark;
  }

  /// Sets the label; blank input clears it.
  Future<void> rename(Bookmark bookmark, String label) {
    var trimmed = label.trim();
    if (trimmed.length > maxLabelLength) {
      trimmed = trimmed.substring(0, maxLabelLength);
    }
    return _bookmarks.updateBookmark(
      Bookmark(
        id: bookmark.id,
        bookId: bookmark.bookId,
        locator: bookmark.locator,
        label: trimmed.isEmpty ? null : trimmed,
        createdAt: bookmark.createdAt,
        updatedAt: _clock(),
      ),
    );
  }

  Future<void> delete(Bookmark bookmark) =>
      _bookmarks.deleteBookmark(bookmark.id);

  /// Puts back a just-deleted bookmark (undo).
  Future<void> restore(Bookmark bookmark) => _bookmarks.addBookmark(bookmark);
}

final bookmarkActionsProvider = Provider<BookmarkActions>(
  (ref) => BookmarkActions(ref.watch(bookmarkRepositoryProvider)),
);
