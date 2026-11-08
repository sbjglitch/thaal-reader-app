import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/providers.dart';
import '../../../domain/entities/enums.dart';
import 'library_items.dart';

/// How books are laid out on the library screen.
enum LibraryLayout { list, grid }

/// Library sort orders (PRD FR-LIB-05).
enum LibrarySort {
  recentlyAdded('Recently added'),
  recentlyOpened('Recently opened'),
  title('Title (A–Z)'),
  progress('Reading progress');

  const LibrarySort(this.label);

  final String label;
}

/// What the library screen shows. [layout] and [sort] persist across
/// launches; search and filters reset.
final class LibraryViewState {
  const LibraryViewState({
    this.layout = LibraryLayout.list,
    this.sort = LibrarySort.recentlyAdded,
    this.search = '',
    this.format,
    this.status,
  });

  final LibraryLayout layout;
  final LibrarySort sort;
  final String search;

  /// Null shows every format.
  final PublicationFormat? format;

  /// Null shows every reading status.
  final ReadingStatus? status;

  bool get hasFilters => format != null || status != null;

  bool get isNarrowed => hasFilters || search.trim().isNotEmpty;

  LibraryViewState copyWith({
    LibraryLayout? layout,
    LibrarySort? sort,
    String? search,
    PublicationFormat? Function()? format,
    ReadingStatus? Function()? status,
  }) {
    return LibraryViewState(
      layout: layout ?? this.layout,
      sort: sort ?? this.sort,
      search: search ?? this.search,
      format: format == null ? this.format : format(),
      status: status == null ? this.status : status(),
    );
  }
}

/// Applies search, filters and sort to [items]. Pure, so it is unit-tested
/// directly. Search matches title and authors, case-insensitively.
List<LibraryItem> applyLibraryView(
  List<LibraryItem> items,
  LibraryViewState view,
) {
  final query = view.search.trim().toLowerCase();
  final matches = [
    for (final item in items)
      if (_matchesSearch(item, query) &&
          (view.format == null || item.book.format == view.format) &&
          (view.status == null || item.book.readingStatus == view.status))
        item,
  ];
  int byTitle(LibraryItem a, LibraryItem b) {
    final result = a.book.title.toLowerCase().compareTo(
      b.book.title.toLowerCase(),
    );
    return result != 0 ? result : a.book.id.compareTo(b.book.id);
  }

  int byAdded(LibraryItem a, LibraryItem b) {
    final result = b.book.addedAt.compareTo(a.book.addedAt);
    return result != 0 ? result : byTitle(a, b);
  }

  matches.sort(switch (view.sort) {
    LibrarySort.title => byTitle,
    // Furthest along first; books without progress last, newest first.
    LibrarySort.progress => (a, b) {
      final progressA = a.progression;
      final progressB = b.progression;
      if (progressA == null && progressB == null) return byAdded(a, b);
      if (progressA == null) return 1;
      if (progressB == null) return -1;
      final result = progressB.compareTo(progressA);
      return result != 0 ? result : byTitle(a, b);
    },
    LibrarySort.recentlyAdded => byAdded,
    // Never-opened books go last, newest import first.
    LibrarySort.recentlyOpened => (a, b) {
      final openedA = a.book.lastOpenedAt;
      final openedB = b.book.lastOpenedAt;
      if (openedA == null && openedB == null) return byAdded(a, b);
      if (openedA == null) return 1;
      if (openedB == null) return -1;
      final result = openedB.compareTo(openedA);
      return result != 0 ? result : byTitle(a, b);
    },
  });
  return matches;
}

bool _matchesSearch(LibraryItem item, String query) {
  if (query.isEmpty) return true;
  if (item.book.title.toLowerCase().contains(query)) return true;
  return item.book.authors.any((a) => a.toLowerCase().contains(query));
}

/// Holds the library view and persists layout and sort.
class LibraryViewController extends Notifier<LibraryViewState> {
  static const layoutKey = 'library.layout';
  static const sortKey = 'library.sort';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  LibraryViewState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    // Unknown stored values (e.g. from a later version) fall back to defaults.
    return LibraryViewState(
      layout:
          LibraryLayout.values.asNameMap()[prefs.getString(layoutKey)] ??
          LibraryLayout.list,
      sort:
          LibrarySort.values.asNameMap()[prefs.getString(sortKey)] ??
          LibrarySort.recentlyAdded,
    );
  }

  void setLayout(LibraryLayout layout) {
    state = state.copyWith(layout: layout);
    // Preferences are a convenience; a failed write keeps the in-memory value.
    _prefs.setString(layoutKey, layout.name).ignore();
  }

  void setSort(LibrarySort sort) {
    state = state.copyWith(sort: sort);
    _prefs.setString(sortKey, sort.name).ignore();
  }

  void setSearch(String search) => state = state.copyWith(search: search);

  void setFormat(PublicationFormat? format) =>
      state = state.copyWith(format: () => format);

  void setStatus(ReadingStatus? status) =>
      state = state.copyWith(status: () => status);

  void clearFilters() => state = state.copyWith(
    search: '',
    format: () => null,
    status: () => null,
  );
}

final libraryViewProvider =
    NotifierProvider<LibraryViewController, LibraryViewState>(
      LibraryViewController.new,
    );

/// The library after search, filters and sort.
final visibleLibraryItemsProvider = Provider<AsyncValue<List<LibraryItem>>>((
  ref,
) {
  final view = ref.watch(libraryViewProvider);
  return ref
      .watch(libraryItemsProvider)
      .whenData((items) => applyLibraryView(items, view));
});
