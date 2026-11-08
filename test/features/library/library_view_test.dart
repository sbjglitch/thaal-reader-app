import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaal/app/providers.dart';
import 'package:thaal/domain/entities/book.dart';
import 'package:thaal/domain/entities/enums.dart';
import 'package:thaal/features/library/application/library_items.dart';
import 'package:thaal/features/library/application/library_view.dart';

import '../../support/fixtures.dart';

LibraryItem _item(
  String id,
  String title, {
  List<String> authors = const ['Someone'],
  PublicationFormat format = PublicationFormat.epub,
  ReadingStatus status = ReadingStatus.unread,
  int addedDay = 1,
  int? openedDay,
  double? progression,
}) {
  final book = sampleBook(id: id, title: title, format: format);
  return LibraryItem(
    book: Book(
      id: book.id,
      title: book.title,
      authors: authors,
      format: book.format,
      filePath: book.filePath,
      fileSizeBytes: book.fileSizeBytes,
      fileChecksum: book.fileChecksum,
      readingStatus: status,
      addedAt: DateTime.utc(2026, 1, addedDay),
      lastOpenedAt: openedDay == null ? null : DateTime.utc(2026, 2, openedDay),
      updatedAt: DateTime.utc(2026, 1, addedDay),
    ),
    fileAvailable: true,
    progression: progression,
  );
}

List<String> _ids(List<LibraryItem> items) => [
  for (final item in items) item.book.id,
];

void main() {
  final items = [
    _item('a', 'beta', authors: ['Zora Neale'], addedDay: 1, openedDay: 5),
    _item(
      'b',
      'Alpha',
      format: PublicationFormat.pdf,
      status: ReadingStatus.finished,
      addedDay: 3,
    ),
    _item(
      'c',
      'Gamma',
      status: ReadingStatus.reading,
      addedDay: 2,
      openedDay: 9,
    ),
  ];

  group('applyLibraryView', () {
    test('sorts by recently added, newest first', () {
      expect(_ids(applyLibraryView(items, const LibraryViewState())), [
        'b',
        'c',
        'a',
      ]);
    });

    test('sorts by title, ignoring case', () {
      const view = LibraryViewState(sort: LibrarySort.title);
      expect(_ids(applyLibraryView(items, view)), ['b', 'a', 'c']);
    });

    test('sorts by recently opened with never-opened books last', () {
      const view = LibraryViewState(sort: LibrarySort.recentlyOpened);
      expect(_ids(applyLibraryView(items, view)), ['c', 'a', 'b']);
    });

    test('sorts by reading progress with unread books last', () {
      final withProgress = [
        _item('x', 'X', addedDay: 1, progression: 0.2),
        _item('y', 'Y', addedDay: 5),
        _item('z', 'Z', addedDay: 2, progression: 0.9),
      ];
      const view = LibraryViewState(sort: LibrarySort.progress);
      expect(_ids(applyLibraryView(withProgress, view)), ['z', 'x', 'y']);
    });

    test('searches title and authors, case-insensitively', () {
      expect(
        _ids(applyLibraryView(items, const LibraryViewState(search: 'ALP'))),
        ['b'],
      );
      expect(
        _ids(applyLibraryView(items, const LibraryViewState(search: ' zora '))),
        ['a'],
      );
    });

    test('filters by format and status', () {
      expect(
        _ids(
          applyLibraryView(
            items,
            const LibraryViewState(format: PublicationFormat.epub),
          ),
        ),
        ['c', 'a'],
      );
      expect(
        _ids(
          applyLibraryView(
            items,
            const LibraryViewState(status: ReadingStatus.reading),
          ),
        ),
        ['c'],
      );
    });

    test('does not modify the input list', () {
      final copy = [...items];
      applyLibraryView(items, const LibraryViewState(sort: LibrarySort.title));
      expect(_ids(items), _ids(copy));
    });
  });

  group('LibraryViewController', () {
    Future<ProviderContainer> container(Map<String, Object> stored) async {
      SharedPreferences.setMockInitialValues(stored);
      final prefs = await SharedPreferences.getInstance();
      return ProviderContainer.test(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
    }

    test('restores layout and sort, ignoring unknown values', () async {
      var c = await container({
        LibraryViewController.layoutKey: 'grid',
        LibraryViewController.sortKey: 'title',
      });
      var state = c.read(libraryViewProvider);
      expect(state.layout, LibraryLayout.grid);
      expect(state.sort, LibrarySort.title);

      c = await container({
        LibraryViewController.layoutKey: 'carousel',
        LibraryViewController.sortKey: 'byMood',
      });
      state = c.read(libraryViewProvider);
      expect(state.layout, LibraryLayout.list);
      expect(state.sort, LibrarySort.recentlyAdded);
    });

    test('persists layout and sort but not search or filters', () async {
      final c = await container({});
      c.read(libraryViewProvider.notifier)
        ..setLayout(LibraryLayout.grid)
        ..setSort(LibrarySort.recentlyOpened)
        ..setSearch('x')
        ..setFormat(PublicationFormat.pdf);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(LibraryViewController.layoutKey), 'grid');
      expect(prefs.getString(LibraryViewController.sortKey), 'recentlyOpened');
      expect(prefs.getKeys(), hasLength(2));
    });

    test('clearFilters resets search, format and status only', () async {
      final c = await container({});
      c.read(libraryViewProvider.notifier)
        ..setSort(LibrarySort.title)
        ..setSearch('x')
        ..setFormat(PublicationFormat.pdf)
        ..setStatus(ReadingStatus.finished)
        ..clearFilters();

      final state = c.read(libraryViewProvider);
      expect(state.isNarrowed, isFalse);
      expect(state.sort, LibrarySort.title);
    });
  });
}
