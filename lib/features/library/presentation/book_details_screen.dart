import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_color_tokens.dart';
import '../../../app/theme/app_radius_tokens.dart';
import '../../../app/theme/app_spacing_tokens.dart';
import '../../../core/utils/byte_format.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_error_state.dart';
import '../../../core/widgets/app_loading_indicator.dart';
import '../../../domain/entities/enums.dart';
import '../application/library_items.dart';
import 'book_actions.dart';
import 'widgets/book_cover.dart';

/// The book with [bookId], or null once it is no longer in the library.
final libraryItemProvider = Provider.family<AsyncValue<LibraryItem?>, String>((
  ref,
  bookId,
) {
  return ref.watch(libraryItemsProvider).whenData((items) {
    for (final item in items) {
      if (item.book.id == bookId) return item;
    }
    return null;
  });
});

/// Document information and management for one book (PRD FR-LIB-07).
class BookDetailsScreen extends ConsumerWidget {
  const BookDetailsScreen({super.key, required this.bookId});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(libraryItemProvider(bookId));
    return Scaffold(
      appBar: AppBar(title: const Text('Details')),
      body: item.when(
        loading: () => const AppLoadingIndicator(),
        error: (_, _) => AppErrorState(
          title: 'This book could not be loaded',
          message: 'Your library has not been changed. Try again.',
          onRetry: () => ref.invalidate(libraryItemsProvider),
        ),
        data: (item) => item == null
            ? AppEmptyState(
                icon: Icons.search_off,
                title: 'Book not found',
                message: 'This book is no longer in your library.',
                action: TextButton(
                  onPressed: () => context.go(AppRoutes.library.path),
                  child: const Text('Go to library'),
                ),
              )
            : _Details(item: item),
      ),
    );
  }
}

class _Details extends ConsumerWidget {
  const _Details({required this.item});

  final LibraryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = context.colorTokens;
    final localizations = MaterialLocalizations.of(context);
    final book = item.book;
    final lastOpened = book.lastOpenedAt;

    final facts = <(String, String)>[
      ('Format', book.format.wireName.toUpperCase()),
      (
        'Status',
        switch (book.readingStatus) {
          ReadingStatus.unread => 'Not started',
          ReadingStatus.reading => 'Reading',
          ReadingStatus.finished => 'Finished',
        },
      ),
      ('File size', formatBytes(book.fileSizeBytes)),
      ('Added', localizations.formatMediumDate(book.addedAt.toLocal())),
      if (lastOpened != null)
        ('Last opened', localizations.formatMediumDate(lastOpened.toLocal())),
      if (book.publisher case final publisher?) ('Publisher', publisher),
      if (book.publishedAt case final published?) ('Published', published),
      if (book.language case final language?) ('Language', language),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenEdge,
        AppSpacing.space16,
        AppSpacing.screenEdge,
        AppSpacing.space32,
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BookCover(
              format: book.format,
              file: item.coverFile,
              width: 96,
              height: 140,
            ),
            const SizedBox(width: AppSpacing.space16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(book.title, style: text.titleLarge),
                  if (book.authors.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.space4),
                    Text(
                      book.authors.join(', '),
                      style: text.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space20),
        if (item.fileAvailable)
          FilledButton.icon(
            onPressed: () => context.push(AppRoutes.readerLocation(book.id)),
            icon: const Icon(Icons.menu_book_outlined),
            label: Text(
              book.readingStatus == ReadingStatus.unread
                  ? 'Start reading'
                  : 'Continue reading',
            ),
          )
        else
          const _MissingFileNotice(),
        const SizedBox(height: AppSpacing.space24),
        for (final (label, value) in facts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.space8),
            child: MergeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 112,
                    child: Text(
                      label,
                      style: text.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(child: Text(value, style: text.bodyMedium)),
                ],
              ),
            ),
          ),
        if (book.description case final description?) ...[
          const SizedBox(height: AppSpacing.space16),
          Text('Description', style: text.titleSmall),
          const SizedBox(height: AppSpacing.space8),
          Text(description, style: text.bodyMedium),
        ],
        const SizedBox(height: AppSpacing.space32),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.danger,
            side: BorderSide(color: colors.border),
          ),
          onPressed: () async {
            final removed = await confirmAndRemoveBook(context, ref, book);
            if (removed && context.mounted) {
              await Navigator.of(context).maybePop();
            }
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text('Remove from library'),
        ),
      ],
    );
  }
}

class _MissingFileNotice extends StatelessWidget {
  const _MissingFileNotice();

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.space12),
      decoration: BoxDecoration(
        border: Border.all(color: colors.warning),
        borderRadius: AppRadius.mediumAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(Icons.warning_amber_rounded, color: colors.warning),
          ),
          const SizedBox(width: AppSpacing.space12),
          const Expanded(
            child: Text(
              'The file for this book is missing, so it cannot be opened. '
              'You can remove it and import the file again.',
            ),
          ),
        ],
      ),
    );
  }
}
