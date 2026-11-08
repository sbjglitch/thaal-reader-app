import '../../domain/entities/book.dart';
import '../../domain/entities/library_snapshot.dart';
import '../../domain/entities/reading_data.dart';
import 'backup_contents.dart';

/// Why an incoming book is not restored.
enum RestoreBookConflict {
  /// The library has a book with this id but a different file.
  differentFile,

  /// The library already has this file under another id.
  duplicate,

  /// Leftover files occupy the book's storage directory.
  occupied,
}

final class SkippedBook {
  const SkippedBook(this.book, this.reason);

  final Book book;
  final RestoreBookConflict reason;
}

/// What a merge restore will do (BACKUP_FORMAT.md §8.2–8.3, conservative
/// merge): add what is new, keep everything already in the library, and
/// skip and report anything that conflicts. Nothing local is changed or
/// removed.
final class RestorePlan {
  const RestorePlan({
    required this.add,
    required this.booksToAdd,
    required this.booksAlreadyPresent,
    required this.skippedBooks,
    required this.skippedCollections,
    required this.skippedAnnotations,
    required this.keptProgress,
  });

  /// Records to insert.
  final LibrarySnapshot add;

  /// The backup records of [add]'s books, with their archive entries.
  final List<BackupBookRecord> booksToAdd;

  /// Same id and same file as a library book: its new bookmarks,
  /// highlights and collection memberships are still added.
  final int booksAlreadyPresent;
  final List<SkippedBook> skippedBooks;

  /// Same id as a library collection but a different name.
  final List<Collection> skippedCollections;

  /// Bookmarks and highlights whose id exists with different content.
  final int skippedAnnotations;

  /// Books already in the library whose current reading position is kept.
  final int keptProgress;

  int get booksMissingFiles =>
      booksToAdd.where((record) => record.publication == null).length;

  bool get hasChanges =>
      add.books.isNotEmpty ||
      add.progress.isNotEmpty ||
      add.bookmarks.isNotEmpty ||
      add.highlights.isNotEmpty ||
      add.collections.isNotEmpty ||
      add.memberships.isNotEmpty;
}

/// Plans a merge of [contents] into the [local] library. [occupiedBookIds]
/// are ids whose storage directory already exists without a library record.
RestorePlan planRestore(
  BackupContents contents,
  LibrarySnapshot local, {
  Set<String> occupiedBookIds = const {},
}) {
  final localBooks = {for (final book in local.books) book.id: book};
  final localChecksums = {for (final book in local.books) book.fileChecksum};

  final booksToAdd = <BackupBookRecord>[];
  final skippedBooks = <SkippedBook>[];
  var alreadyPresent = 0;
  // Books whose related records may be merged: new and already present.
  final usable = <String>{};
  final added = <String>{};
  for (final record in contents.books) {
    final book = record.book;
    final existing = localBooks[book.id];
    if (existing != null) {
      if (existing.fileChecksum == book.fileChecksum) {
        alreadyPresent++;
        usable.add(book.id);
      } else {
        skippedBooks.add(SkippedBook(book, RestoreBookConflict.differentFile));
      }
    } else if (localChecksums.contains(book.fileChecksum)) {
      skippedBooks.add(SkippedBook(book, RestoreBookConflict.duplicate));
    } else if (occupiedBookIds.contains(book.id)) {
      skippedBooks.add(SkippedBook(book, RestoreBookConflict.occupied));
    } else {
      booksToAdd.add(record);
      usable.add(book.id);
      added.add(book.id);
    }
  }

  final localProgress = {for (final p in local.progress) p.bookId};
  final progress = <ReadingProgress>[];
  var keptProgress = 0;
  for (final entry in contents.records.progress) {
    if (!usable.contains(entry.bookId)) continue;
    if (localProgress.contains(entry.bookId)) {
      keptProgress++;
    } else {
      progress.add(entry);
    }
  }

  var skippedAnnotations = 0;
  final localBookmarks = {for (final b in local.bookmarks) b.id: b};
  final bookmarks = <Bookmark>[];
  for (final bookmark in contents.records.bookmarks) {
    if (!usable.contains(bookmark.bookId)) continue;
    final existing = localBookmarks[bookmark.id];
    if (existing == null) {
      bookmarks.add(bookmark);
    } else if (!_sameBookmark(existing, bookmark)) {
      skippedAnnotations++;
    }
  }
  final localHighlights = {for (final h in local.highlights) h.id: h};
  final highlights = <Highlight>[];
  for (final highlight in contents.records.highlights) {
    if (!usable.contains(highlight.bookId)) continue;
    final existing = localHighlights[highlight.id];
    if (existing == null) {
      highlights.add(highlight);
    } else if (!_sameHighlight(existing, highlight)) {
      skippedAnnotations++;
    }
  }

  final localCollections = {for (final c in local.collections) c.id: c};
  final collections = <Collection>[];
  final skippedCollections = <Collection>[];
  final usableCollections = <String>{};
  for (final collection in contents.records.collections) {
    final existing = localCollections[collection.id];
    if (existing == null) {
      collections.add(collection);
      usableCollections.add(collection.id);
    } else if (existing.name == collection.name) {
      usableCollections.add(collection.id);
    } else {
      skippedCollections.add(collection);
    }
  }
  final localPairs = {
    for (final m in local.memberships) (m.collectionId, m.bookId),
  };
  final memberships = [
    for (final membership in contents.records.memberships)
      if (usableCollections.contains(membership.collectionId) &&
          usable.contains(membership.bookId) &&
          !localPairs.contains((membership.collectionId, membership.bookId)))
        membership,
  ];

  return RestorePlan(
    add: LibrarySnapshot(
      books: [for (final record in booksToAdd) record.book],
      progress: progress,
      bookmarks: bookmarks,
      highlights: highlights,
      collections: collections,
      memberships: memberships,
    ),
    booksToAdd: booksToAdd,
    booksAlreadyPresent: alreadyPresent,
    skippedBooks: skippedBooks,
    skippedCollections: skippedCollections,
    skippedAnnotations: skippedAnnotations,
    keptProgress: keptProgress,
  );
}

bool _sameBookmark(Bookmark a, Bookmark b) =>
    a.bookId == b.bookId && a.locator == b.locator && a.label == b.label;

bool _sameHighlight(Highlight a, Highlight b) =>
    a.bookId == b.bookId &&
    a.locator == b.locator &&
    a.selectedText == b.selectedText &&
    a.color == b.color &&
    a.note == b.note;
