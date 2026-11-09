import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_spacing_tokens.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_error_state.dart';
import '../../../core/widgets/app_loading_indicator.dart';
import '../../../domain/entities/enums.dart';
import '../../../services/import/import_service.dart';
import '../application/import_controller.dart';
import '../application/library_items.dart';
import '../application/library_view.dart';
import 'book_actions.dart';
import 'widgets/book_grid_tile.dart';
import 'widgets/book_list_item.dart';

/// Library tab: imported books, search, sort and filters, and the import
/// entry point (UI/UX §7.1–7.2).
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryItemsProvider);
    final visible = ref.watch(visibleLibraryItemsProvider);
    final view = ref.watch(libraryViewProvider);
    final viewController = ref.read(libraryViewProvider.notifier);
    final importState = ref.watch(importControllerProvider);
    ref.listen(importControllerProvider, (previous, next) {
      if (next is ImportFinished) _reportResults(context, ref, next);
    });

    void startImport() =>
        ref.read(importControllerProvider.notifier).pickAndImport();
    final onImport = importState.isBusy ? null : startImport;
    final hasBooks = library.value?.isNotEmpty ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          if (hasBooks) ...[
            IconButton(
              tooltip: view.layout == LibraryLayout.list
                  ? 'Show as grid'
                  : 'Show as list',
              icon: Icon(
                view.layout == LibraryLayout.list
                    ? Icons.grid_view
                    : Icons.view_list,
              ),
              onPressed: () => viewController.setLayout(
                view.layout == LibraryLayout.list
                    ? LibraryLayout.grid
                    : LibraryLayout.list,
              ),
            ),
            IconButton(
              tooltip: view.hasFilters
                  ? 'Sort and filter, filters on'
                  : 'Sort and filter',
              icon: Badge(
                isLabelVisible: view.hasFilters,
                smallSize: 8,
                child: const Icon(Icons.tune),
              ),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                isScrollControlled: true,
                builder: (_) => const LibrarySortFilterSheet(),
              ),
            ),
          ],
          IconButton(
            tooltip: 'Import books',
            icon: const Icon(Icons.add),
            onPressed: onImport,
          ),
          const SizedBox(width: AppSpacing.space8),
        ],
      ),
      body: Column(
        children: [
          if (importState case ImportRunning(:final current, :final total))
            _ImportProgress(current: current, total: total),
          if (hasBooks) const _SearchField(),
          Expanded(
            child: visible.when(
              // Keep showing the previous list while the library re-emits.
              skipLoadingOnReload: true,
              loading: () => const AppLoadingIndicator(),
              error: (_, _) => AppErrorState(
                title: 'Your library could not be loaded',
                message:
                    'Your books and reading data have not been changed. '
                    'Try again.',
                onRetry: () => ref.invalidate(libraryItemsProvider),
              ),
              data: (list) {
                if (!hasBooks) {
                  return AppEmptyState(
                    icon: Icons.auto_stories_outlined,
                    title: 'Your library is empty',
                    message:
                        'Import EPUB or PDF files from your device. They are '
                        'copied into the app and work offline.',
                    action: FilledButton.icon(
                      onPressed: onImport,
                      icon: const Icon(Icons.add),
                      label: const Text('Import books'),
                    ),
                  );
                }
                if (list.isEmpty) {
                  return AppEmptyState(
                    icon: Icons.search_off,
                    title: 'No matching books',
                    message: 'Try a different search or clear the filters.',
                    action: TextButton(
                      onPressed: viewController.clearFilters,
                      child: const Text('Clear search and filters'),
                    ),
                  );
                }
                return _BookCollection(items: list, layout: view.layout);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Reports a finished batch: a snackbar for imported books, a dialog for
  /// failures, then a decision dialog for duplicates.
  static Future<void> _reportResults(
    BuildContext context,
    WidgetRef ref,
    ImportFinished finished,
  ) async {
    final controller = ref.read(importControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    if (finished.pickerFailure case final failure?) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (failure) {
            ImportPickerFailure.unavailable =>
              'The file picker could not be opened.',
            ImportPickerFailure.filesUnreadable =>
              'The file could not be copied. Check that there is enough '
                  'free storage and try again.',
          }),
        ),
      );
      return controller.dismiss();
    }

    final count = finished.imported.length;
    final relinked = finished.relinked.length;
    final messages = [
      if (count > 0) count == 1 ? 'Imported 1 book.' : 'Imported $count books.',
      // Files matching books whose file was missing, e.g. after a
      // library-only restore.
      if (relinked > 0)
        relinked == 1
            ? 'Restored the file for 1 book.'
            : 'Restored the files for $relinked books.',
    ];
    if (messages.isNotEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(messages.join(' '))));
    }

    if (finished.failures.isNotEmpty && context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => _FailuresDialog(failures: finished.failures),
      );
    }

    if (finished.duplicates.isNotEmpty && context.mounted) {
      final importAnyway = await showDialog<bool>(
        context: context,
        builder: (context) =>
            _DuplicatesDialog(duplicates: finished.duplicates),
      );
      if (importAnyway ?? false) return controller.importDuplicatesAnyway();
    }
    return controller.dismiss();
  }
}

class _ImportProgress extends StatelessWidget {
  const _ImportProgress({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final label = total == 1
        ? 'Importing book…'
        : 'Importing $current of $total…';
    return Semantics(
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenEdge,
            AppSpacing.space4,
            AppSpacing.screenEdge,
            AppSpacing.space8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: AppSpacing.space8),
              const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}

class _FailuresDialog extends StatelessWidget {
  const _FailuresDialog({required this.failures});

  final List<ImportFailed> failures;

  static String _reason(ImportFailureReason reason) => switch (reason) {
    ImportFailureReason.unsupportedFormat =>
      'Only EPUB and PDF files can be imported.',
    ImportFailureReason.invalidFile =>
      'The file is damaged or is not a valid EPUB or PDF.',
    ImportFailureReason.insufficientStorage =>
      'There is not enough free storage on this device.',
    ImportFailureReason.failed =>
      'Something went wrong while importing. Try again.',
  };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(
        failures.length == 1
            ? 'A file could not be imported'
            : '${failures.length} files could not be imported',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final failure in failures) ...[
              Text(failure.source.name, style: text.titleSmall),
              Text(_reason(failure.reason), style: text.bodySmall),
              const SizedBox(height: AppSpacing.space12),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

class _DuplicatesDialog extends StatelessWidget {
  const _DuplicatesDialog({required this.duplicates});

  final List<ImportDuplicate> duplicates;

  @override
  Widget build(BuildContext context) {
    final single = duplicates.length == 1;
    return AlertDialog(
      title: const Text('Already in your library'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              single
                  ? 'This file matches a book you have already imported. '
                        'Import another copy?'
                  : 'These files match books you have already imported. '
                        'Import another copy of each?',
            ),
            const SizedBox(height: AppSpacing.space12),
            for (final duplicate in duplicates)
              Text(
                duplicate.source.name,
                style: Theme.of(context).textTheme.titleSmall,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Skip'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(single ? 'Import copy' : 'Import copies'),
        ),
      ],
    );
  }
}

class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: ref.read(libraryViewProvider).search,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Follow external changes such as "Clear search and filters".
    ref.listen(libraryViewProvider.select((view) => view.search), (_, next) {
      if (next != _controller.text) _controller.text = next;
    });
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenEdge,
        AppSpacing.space4,
        AppSpacing.screenEdge,
        AppSpacing.space8,
      ),
      child: TextField(
        controller: _controller,
        onChanged: ref.read(libraryViewProvider.notifier).setSearch,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search title or author',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => _controller.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _controller.clear();
                      ref.read(libraryViewProvider.notifier).setSearch('');
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class _BookCollection extends ConsumerWidget {
  const _BookCollection({required this.items, required this.layout});

  final List<LibraryItem> items;
  final LibraryLayout layout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A book whose file is missing cannot be read; its details explain why.
    void open(LibraryItem item) => context.push(
      item.fileAvailable
          ? AppRoutes.readerLocation(item.book.id)
          : AppRoutes.bookDetailsLocation(item.book.id),
    );
    void more(LibraryItem item) => showBookActions(context, ref, item.book);

    return switch (layout) {
      LibraryLayout.list => ListView.separated(
        key: const PageStorageKey('library-list'),
        padding: const EdgeInsets.only(bottom: AppSpacing.space24),
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(
          indent: AppSpacing.screenEdge,
          endIndent: AppSpacing.screenEdge,
        ),
        itemBuilder: (_, index) {
          final item = items[index];
          return BookListItem(
            key: ValueKey(item.book.id),
            item: item,
            onTap: () => open(item),
            onMore: () => more(item),
          );
        },
      ),
      LibraryLayout.grid => GridView.builder(
        key: const PageStorageKey('library-grid'),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenEdge,
          AppSpacing.space8,
          AppSpacing.screenEdge,
          AppSpacing.space24,
        ),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160,
          mainAxisSpacing: AppSpacing.space20,
          crossAxisSpacing: AppSpacing.space16,
          childAspectRatio: 0.48,
        ),
        itemCount: items.length,
        itemBuilder: (_, index) {
          final item = items[index];
          return BookGridTile(
            key: ValueKey(item.book.id),
            item: item,
            onTap: () => open(item),
            onMore: () => more(item),
          );
        },
      ),
    };
  }
}

/// Sort order and filters for the library.
class LibrarySortFilterSheet extends ConsumerWidget {
  const LibrarySortFilterSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(libraryViewProvider);
    final controller = ref.read(libraryViewProvider.notifier);
    final text = Theme.of(context).textTheme;

    Widget heading(String label) => Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.space16,
        bottom: AppSpacing.space8,
      ),
      child: Text(label, style: text.titleSmall),
    );

    Widget chips<T>(
      List<(T?, String)> options,
      T? selected,
      ValueChanged<T?> onSelected,
    ) {
      return Wrap(
        spacing: AppSpacing.space8,
        runSpacing: AppSpacing.space8,
        children: [
          for (final (value, label) in options)
            ChoiceChip(
              label: Text(label),
              selected: value == selected,
              onSelected: (_) => onSelected(value),
            ),
        ],
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenEdge,
          0,
          AppSpacing.screenEdge,
          AppSpacing.space24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading('Sort by'),
            chips<LibrarySort>(
              [for (final sort in LibrarySort.values) (sort, sort.label)],
              view.sort,
              (sort) => controller.setSort(sort ?? LibrarySort.recentlyAdded),
            ),
            heading('Format'),
            chips<PublicationFormat>(
              const [
                (null, 'All'),
                (PublicationFormat.epub, 'EPUB'),
                (PublicationFormat.pdf, 'PDF'),
              ],
              view.format,
              controller.setFormat,
            ),
            heading('Status'),
            chips<ReadingStatus>(
              const [
                (null, 'All'),
                (ReadingStatus.unread, 'Not started'),
                (ReadingStatus.reading, 'Reading'),
                (ReadingStatus.finished, 'Finished'),
              ],
              view.status,
              controller.setStatus,
            ),
          ],
        ),
      ),
    );
  }
}
