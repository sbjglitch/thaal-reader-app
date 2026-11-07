import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../app/theme/app_color_tokens.dart';
import '../../../domain/entities/book.dart';

/// Contextual actions for a book (UI/UX §6.2: bottom sheet for actions that
/// do not need a full screen). Only actions that work today are listed;
/// open, edit metadata and add-to-collection arrive with their milestones.
Future<void> showBookActions(
  BuildContext context,
  WidgetRef ref,
  Book book,
) async {
  final action = await showModalBottomSheet<_BookAction>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              book.title,
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Details'),
            onTap: () => Navigator.of(context).pop(_BookAction.details),
          ),
          ListTile(
            leading: Icon(
              Icons.delete_outline,
              color: context.colorTokens.danger,
            ),
            title: Text(
              'Remove from library',
              style: TextStyle(color: context.colorTokens.danger),
            ),
            onTap: () => Navigator.of(context).pop(_BookAction.remove),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  switch (action) {
    case _BookAction.details:
      await context.push(AppRoutes.bookDetailsLocation(book.id));
    case _BookAction.remove:
      await confirmAndRemoveBook(context, ref, book);
    case null:
      break;
  }
}

enum _BookAction { details, remove }

/// Asks for confirmation, then removes [book]. Returns true when removed.
///
/// There is one removal action, not "remove" and "delete file" variants:
/// the app's copy is the only file it owns, so both would behave the same
/// (DATABASE_SCHEMA.md §7.2).
Future<bool> confirmAndRemoveBook(
  BuildContext context,
  WidgetRef ref,
  Book book,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Remove from library?'),
      content: Text(
        '“${book.title}” and its copy in Thaal will be deleted, along with '
        'its reading progress, bookmarks and highlights. This cannot be '
        'undone.\n\nThe original file on your device is not affected.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: context.colorTokens.danger,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (!(confirmed ?? false) || !context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(bookRemovalServiceProvider).removeBook(book.id);
  } on Object {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('The book could not be removed. Nothing was changed.'),
      ),
    );
    return false;
  }
  messenger.showSnackBar(SnackBar(content: Text('Removed “${book.title}”.')));
  return true;
}
