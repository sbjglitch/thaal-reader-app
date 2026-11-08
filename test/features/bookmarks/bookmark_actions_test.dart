import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/domain/entities/enums.dart';
import 'package:thaal/domain/entities/locator_envelope.dart';
import 'package:thaal/features/bookmarks/application/bookmarks.dart';

import '../../support/fixtures.dart';
import 'fake_bookmarks.dart';

void main() {
  late MemoryBookmarkRepository repository;
  late BookmarkActions actions;
  var now = fixedTime;

  setUp(() {
    repository = MemoryBookmarkRepository();
    now = fixedTime;
    actions = BookmarkActions(
      repository,
      clock: () => now,
      newId: () => 'bm-${repository.items.length + 1}',
    );
  });

  const locator = LocatorEnvelope(
    format: PublicationFormat.epub,
    locator: {'href': 'c1.xhtml'},
  );

  test('adds a bookmark at the given locator', () async {
    final bookmark = await actions.add('book-1', locator);
    expect(repository.items.single.id, 'bm-1');
    expect(bookmark.bookId, 'book-1');
    expect(bookmark.label, isNull);
    expect(bookmark.createdAt, fixedTime);
    expect(
      bookmark.locator.decode(PublicationFormat.epub)?.locator['href'],
      'c1.xhtml',
    );
  });

  test('rename trims, caps the length and clears a blank label', () async {
    final bookmark = await actions.add('book-1', locator);
    now = fixedTime.add(const Duration(minutes: 1));

    await actions.rename(bookmark, '  Favourite scene  ');
    expect(repository.items.single.label, 'Favourite scene');
    expect(repository.items.single.updatedAt, now);
    expect(repository.items.single.createdAt, fixedTime);

    await actions.rename(repository.items.single, 'x' * 150);
    expect(repository.items.single.label, hasLength(100));

    await actions.rename(repository.items.single, '   ');
    expect(repository.items.single.label, isNull);
  });

  test('a deleted bookmark can be restored unchanged', () async {
    final bookmark = await actions.add('book-1', locator);
    await actions.delete(bookmark);
    expect(repository.items, isEmpty);
    await actions.restore(bookmark);
    expect(repository.items.single.id, bookmark.id);
    expect(repository.items.single.createdAt, bookmark.createdAt);
  });
}
