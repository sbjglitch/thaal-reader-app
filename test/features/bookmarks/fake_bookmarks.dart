import 'dart:async';

import 'package:thaal/core/errors/app_errors.dart';
import 'package:thaal/domain/entities/book.dart';
import 'package:thaal/domain/entities/locator_envelope.dart';
import 'package:thaal/domain/entities/reading_data.dart';
import 'package:thaal/domain/repositories/bookmark_repository.dart';
import 'package:thaal/features/bookmarks/application/bookmarks.dart';
import 'package:thaal/services/reader/publication_reader.dart';

/// In-memory [BookmarkRepository] that re-emits after every change.
class MemoryBookmarkRepository implements BookmarkRepository {
  final List<Bookmark> items = [];
  final _changes = StreamController<void>.broadcast();

  /// When set, writes throw this.
  AppError? failWrites;

  Stream<List<Bookmark>> _watch(List<Bookmark> Function() select) async* {
    yield select();
    yield* _changes.stream.map((_) => select());
  }

  @override
  Stream<List<Bookmark>> watchBookmarks(String bookId) => _watch(
    () => [
      for (final b in items)
        if (b.bookId == bookId) b,
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
  );

  @override
  Stream<List<Bookmark>> watchAllBookmarks() => _watch(
    () => [...items]..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
  );

  void _write(void Function() change) {
    if (failWrites case final error?) throw error;
    change();
    _changes.add(null);
  }

  @override
  Future<void> addBookmark(Bookmark bookmark) async =>
      _write(() => items.add(bookmark));

  @override
  Future<void> updateBookmark(Bookmark bookmark) async => _write(() {
    final index = items.indexWhere((b) => b.id == bookmark.id);
    items[index] = bookmark;
  });

  @override
  Future<void> deleteBookmark(String bookmarkId) async =>
      _write(() => items.removeWhere((b) => b.id == bookmarkId));
}

/// Treats locators with the same href as the same place.
class HrefLocatorInterpreter implements LocatorInterpreter {
  const HrefLocatorInterpreter();

  @override
  ReaderPosition describe(LocatorEnvelope locator) => ReaderPosition(
    locator: locator,
    progression: (locator.locator['progression'] as num?)?.toDouble(),
    chapterTitle: locator.locator['title'] as String?,
  );

  @override
  bool isSameLocation(LocatorEnvelope a, LocatorEnvelope b) =>
      a.locator['href'] == b.locator['href'];
}

/// Entries for [repository]'s bookmarks, as the real providers build them.
Stream<List<BookmarkEntry>> entriesOf(
  Stream<List<Bookmark>> bookmarks,
  Map<String, Book> books, {
  Set<String> missingFiles = const {},
}) {
  const interpreter = HrefLocatorInterpreter();
  return bookmarks.map(
    (list) => [
      for (final bookmark in list)
        if (books[bookmark.bookId] case final book?)
          BookmarkEntry(
            bookmark: bookmark,
            book: book,
            location: switch (bookmark.locator.decode(book.format)) {
              final envelope? => interpreter.describe(envelope),
              null => null,
            },
            fileAvailable: !missingFiles.contains(book.id),
          ),
    ],
  );
}
