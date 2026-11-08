import 'package:flutter/material.dart';

import '../../../../app/theme/app_color_tokens.dart';
import '../../../../app/theme/app_spacing_tokens.dart';
import '../../../../domain/entities/enums.dart';
import '../../application/library_items.dart';
import 'book_cover.dart';

/// Compact library row: cover, title, format and author, status, and an
/// overflow button for book actions.
class BookListItem extends StatelessWidget {
  const BookListItem({
    super.key,
    required this.item,
    required this.onTap,
    required this.onMore,
  });

  final LibraryItem item;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colorTokens;
    final book = item.book;
    final details = [
      book.format.wireName.toUpperCase(),
      if (book.authors.isNotEmpty) book.authors.join(', '),
    ].join(' · ');

    final status = bookStatusLine(item, colors);

    return InkWell(
      onTap: onTap,
      onLongPress: onMore,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenEdge,
          AppSpacing.space12,
          AppSpacing.space4,
          AppSpacing.space12,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: MergeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BookCover(format: book.format, file: item.coverFile),
                    const SizedBox(width: AppSpacing.space16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            book.title,
                            style: text.titleMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: AppSpacing.space4),
                          Text(
                            details,
                            style: text.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (status != null) ...[
                            const SizedBox(height: AppSpacing.space4),
                            status,
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: 'More actions for ${book.title}',
              icon: const Icon(Icons.more_vert),
              onPressed: onMore,
            ),
          ],
        ),
      ),
    );
  }
}

/// The status line for [item]: missing file wins over reading status.
/// Null for unread books, which need no label.
Widget? bookStatusLine(LibraryItem item, AppColorTokens colors) {
  return !item.fileAvailable
      ? _StatusLine(
          icon: Icons.warning_amber_rounded,
          label: 'File missing',
          color: colors.warning,
        )
      : switch (item.book.readingStatus) {
          ReadingStatus.unread => null,
          ReadingStatus.reading => _StatusLine(
            label: switch (item.progression) {
              final progression? => 'Reading · ${(progression * 100).round()}%',
              null => 'Reading',
            },
            color: colors.textSecondary,
          ),
          ReadingStatus.finished => _StatusLine(
            icon: Icons.check,
            label: 'Finished',
            color: colors.textSecondary,
          ),
        };
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({this.icon, required this.label, required this.color});

  final IconData? icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium
        ?.copyWith(color: color);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon case final icon?) ...[
          ExcludeSemantics(child: Icon(icon, size: 14, color: color)),
          const SizedBox(width: AppSpacing.space4),
        ],
        // Ellipsis rather than overflow in narrow grid cells and at large
        // text sizes.
        Flexible(
          child: Text(
            label,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
