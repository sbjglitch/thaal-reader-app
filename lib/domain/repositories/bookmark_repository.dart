import '../entities/reading_data.dart';

abstract interface class BookmarkRepository {
  /// Bookmarks of [bookId], oldest first.
  Stream<List<Bookmark>> watchBookmarks(String bookId);

  Future<void> addBookmark(Bookmark bookmark);

  /// Updates the label of an existing bookmark.
  Future<void> updateBookmark(Bookmark bookmark);

  Future<void> deleteBookmark(String bookmarkId);
}
