import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_color_tokens.dart';
import '../../../app/theme/app_spacing_tokens.dart';
import '../../../domain/entities/enums.dart';
import '../../../domain/entities/reading_data.dart';
import '../application/bookmarks.dart';

/// "Chapter 3 · 42%" or "Page 12": what is known about where a bookmark
/// points. Empty when the locator carries nothing displayable.
String bookmarkLocationText(BookmarkEntry entry) {
  final location = entry.location;
  if (location == null) return 'Location unavailable';
  final parts = <String>[
    if (location.chapterTitle case final chapter?
        when chapter.trim().isNotEmpty)
      chapter.trim(),
    if (entry.book.format == PublicationFormat.pdf &&
        location.pageNumber != null)
      'Page ${location.pageNumber}'
    else if (location.progression case final progression?)
      '${(progression * 100).round()}%',
  ];
  return parts.join(' · ');
}

/// One bookmark row (UI/UX §7.7): label or location, then book and place.
class BookmarkTile extends StatelessWidget {
  const BookmarkTile({
    super.key,
    required this.entry,
    required this.showBookTitle,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final BookmarkEntry entry;

  /// The Bookmarks tab mixes books; the in-reader list does not.
  final bool showBookTitle;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colorTokens;
    final location = bookmarkLocationText(entry);
    final label = entry.bookmark.label;
    final title = label ?? (location.isEmpty ? 'Bookmark' : location);
    final details = [
      if (showBookTitle) entry.book.title,
      if (label != null && location.isNotEmpty) location,
      MaterialLocalizations.of(context)
          .formatShortDate(entry.bookmark.createdAt.toLocal()),
    ].join(' · ');

    return ListTile(
      contentPadding: const EdgeInsets.only(
        left: AppSpacing.screenEdge,
        right: AppSpacing.space4,
      ),
      leading: Icon(
        entry.location == null ? Icons.bookmark_border : Icons.bookmark,
        color: entry.location == null ? colors.warning : colors.textSecondary,
      ),
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        details,
        style: text.bodySmall,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onOpen,
      trailing: PopupMenuButton<_Action>(
        tooltip: 'More actions for this bookmark',
        onSelected: (action) => switch (action) {
          _Action.rename => onRename(),
          _Action.delete => onDelete(),
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: _Action.rename, child: Text('Rename')),
          PopupMenuItem(value: _Action.delete, child: Text('Delete')),
        ],
      ),
    );
  }
}

enum _Action { rename, delete }

/// Asks for a new label and saves it. A blank label removes it.
Future<void> renameBookmark(
  BuildContext context,
  WidgetRef ref,
  Bookmark bookmark,
) async {
  final label = await showDialog<String>(
    context: context,
    builder: (context) => _RenameDialog(initial: bookmark.label ?? ''),
  );
  if (label == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(bookmarkActionsProvider).rename(bookmark, label);
  } on Object {
    messenger.showSnackBar(
      const SnackBar(content: Text('The bookmark could not be renamed.')),
    );
  }
}

/// Deletes [bookmark] and offers undo (UI/UX §7.7).
Future<void> deleteBookmarkWithUndo(
  BuildContext context,
  WidgetRef ref,
  Bookmark bookmark,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final actions = ref.read(bookmarkActionsProvider);
  try {
    await actions.delete(bookmark);
  } on Object {
    messenger.showSnackBar(
      const SnackBar(content: Text('The bookmark could not be deleted.')),
    );
    return;
  }
  messenger.showSnackBar(
    SnackBar(
      content: const Text('Bookmark deleted.'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          try {
            await actions.restore(bookmark);
          } on Object {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('The bookmark could not be restored.'),
              ),
            );
          }
        },
      ),
    ),
  );
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    void submit() => Navigator.of(context).pop(_controller.text);
    return AlertDialog(
      title: const Text('Rename bookmark'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: BookmarkActions.maxLabelLength,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Label',
          helperText: 'Leave empty to show the location instead.',
        ),
        onSubmitted: (_) => submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: submit, child: const Text('Save')),
      ],
    );
  }
}
