import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/app/providers.dart';
import 'package:thaal/data/database/app_database.dart';
import 'package:thaal/data/repositories/drift_book_repository.dart';
import 'package:thaal/data/repositories/drift_bookmark_repository.dart';
import 'package:thaal/domain/entities/reading_data.dart';
import 'package:thaal/features/bookmarks/application/bookmarks.dart';
import 'package:thaal/services/storage/library_storage.dart';

import '../../support/fixtures.dart';
import 'fake_bookmarks.dart';

void main() {
  late Directory temp;
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('thaal_bookmarks');
    db = openTestDatabase();
    container = ProviderContainer.test(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        libraryStorageProvider.overrideWithValue(
          await LibraryStorage.open(Directory('${temp.path}/library')),
        ),
        locatorInterpreterProvider.overrideWithValue(
          const HrefLocatorInterpreter(),
        ),
      ],
    );
    await DriftBookRepository(db).addBook(sampleBook(title: 'Middlemarch'));
  });
  tearDown(() async {
    container.dispose();
    await db.close();
    await temp.delete(recursive: true);
  });

  Bookmark bookmark(String id, {String bookId = 'book-1', int minute = 0}) =>
      Bookmark(
        id: id,
        bookId: bookId,
        locator: sampleLocator(href: 'c$minute'),
        createdAt: fixedTime.add(Duration(minutes: minute)),
        updatedAt: fixedTime,
      );

  Future<List<BookmarkEntry>> settled(
    ProviderListenable<AsyncValue<List<BookmarkEntry>>> provider,
    bool Function(List<BookmarkEntry>) until,
  ) async {
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    for (var i = 0; i < 200; i++) {
      final value = subscription.read().value;
      if (value != null && until(value)) return value;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('provider did not settle: ${subscription.read()}');
  }

  test('per-book bookmarks carry their book and decoded location', () async {
    final repository = DriftBookmarkRepository(db);
    await repository.addBookmark(bookmark('b', minute: 5));
    await repository.addBookmark(bookmark('a', minute: 1));

    final list = await settled(
      bookBookmarksProvider('book-1'),
      (list) => list.length == 2,
    );
    expect(list.map((e) => e.bookmark.id), ['a', 'b']);
    expect(list.first.book.title, 'Middlemarch');
    expect(list.first.locator?.locator['href'], 'c1');
  });

  test('the tab lists newest first and follows library changes', () async {
    final repository = DriftBookmarkRepository(db);
    await repository.addBookmark(bookmark('first', minute: 1));
    var list = await settled(allBookmarksProvider, (l) => l.length == 1);
    expect(list.single.fileAvailable, isFalse); // No file was written.

    // A book imported later shows up with its bookmarks.
    await DriftBookRepository(db).addBook(sampleBook(id: 'book-2'));
    await repository.addBookmark(
      bookmark('second', bookId: 'book-2', minute: 9),
    );
    list = await settled(allBookmarksProvider, (l) => l.length == 2);
    expect(list.map((e) => e.bookmark.id), ['second', 'first']);
  });
}
