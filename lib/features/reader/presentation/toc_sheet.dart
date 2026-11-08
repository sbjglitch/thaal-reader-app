import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing_tokens.dart';
import '../../../services/reader/publication_reader.dart';

/// Shows the table of contents and returns the chosen entry
/// (READER_ENGINE_SPECIFICATION.md §7.2). Nesting is shown by indentation.
Future<TocEntry?> showTocSheet(BuildContext context, List<TocEntry> toc) {
  return showModalBottomSheet<TocEntry>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenEdge,
              0,
              AppSpacing.screenEdge,
              AppSpacing.space8,
            ),
            child: Text(
              'Contents',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: toc.length,
              itemBuilder: (context, index) {
                final entry = toc[index];
                return ListTile(
                  contentPadding: EdgeInsets.only(
                    left:
                        AppSpacing.screenEdge +
                        entry.depth * AppSpacing.space20,
                    right: AppSpacing.screenEdge,
                  ),
                  title: Text(entry.title),
                  onTap: () => Navigator.of(context).pop(entry),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
