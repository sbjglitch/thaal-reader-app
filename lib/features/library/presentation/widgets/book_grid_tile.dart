import 'package:flutter/material.dart';

import '../../../../app/theme/app_color_tokens.dart';
import '../../../../app/theme/app_spacing_tokens.dart';
import '../../application/library_items.dart';
import 'book_cover.dart';
import 'book_list_item.dart' show bookStatusLine;

/// Grid cell: cover, title, author and status. Long-press (or the overflow
/// button) opens book actions.
class BookGridTile extends StatelessWidget {
  const BookGridTile({
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
    final status = bookStatusLine(item, colors);

    return InkWell(
      onTap: onTap,
      onLongPress: onMore,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Center(
                child: BookCover(
                  format: book.format,
                  file: item.coverFile,
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.space8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: MergeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        style: text.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        [
                          book.format.wireName.toUpperCase(),
                          if (book.authors.isNotEmpty) book.authors.first,
                        ].join(' · '),
                        style: text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      ?status,
                    ],
                  ),
                ),
              ),
              SizedBox.square(
                dimension: 32,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  tooltip: 'More actions for ${book.title}',
                  icon: const Icon(Icons.more_vert),
                  onPressed: onMore,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
