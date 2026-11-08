import 'book.dart';
import 'reading_data.dart';

/// A book's membership in a collection (DATABASE_SCHEMA.md §6.2).
final class CollectionMembership {
  const CollectionMembership({
    required this.collectionId,
    required this.bookId,
    required this.addedAt,
  });

  final String collectionId;
  final String bookId;
  final DateTime addedAt;
}

/// Every library record at one moment, read in a single transaction so the
/// datasets agree with each other (BACKUP_FORMAT.md §7.1).
final class LibrarySnapshot {
  const LibrarySnapshot({
    required this.books,
    required this.progress,
    required this.bookmarks,
    required this.highlights,
    required this.collections,
    required this.memberships,
  });

  final List<Book> books;
  final List<ReadingProgress> progress;
  final List<Bookmark> bookmarks;
  final List<Highlight> highlights;
  final List<Collection> collections;
  final List<CollectionMembership> memberships;
}
