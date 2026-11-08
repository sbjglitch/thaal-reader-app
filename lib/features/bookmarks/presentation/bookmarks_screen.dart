import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_error_state.dart';
import '../../../core/widgets/app_loading_indicator.dart';
import '../application/bookmarks.dart';
import 'bookmark_widgets.dart';

/// Bookmarks tab (UI/UX §7.7): every bookmark, newest first.
class BookmarksScreen extends ConsumerWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarks = ref.watch(allBookmarksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Bookmarks')),
      body: bookmarks.when(
        loading: () => const AppLoadingIndicator(),
        error: (_, _) => AppErrorState(
          title: 'Bookmarks could not be loaded',
          message: 'Your bookmarks have not been changed.',
          onRetry: () => ref.invalidate(allBookmarksProvider),
        ),
        data: (list) => list.isEmpty
            ? const AppEmptyState(
                icon: Icons.bookmark_border,
                title: 'No bookmarks yet',
                message:
                    'While reading, tap the bookmark button at the top to '
                    'save your place.',
              )
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final entry = list[index];
                  return BookmarkTile(
                    key: ValueKey(entry.bookmark.id),
                    entry: entry,
                    showBookTitle: true,
                    onOpen: () => _open(context, entry),
                    onRename: () =>
                        renameBookmark(context, ref, entry.bookmark),
                    onDelete: () =>
                        deleteBookmarkWithUndo(context, ref, entry.bookmark),
                  );
                },
              ),
      ),
    );
  }

  void _open(BuildContext context, BookmarkEntry entry) {
    if (!entry.fileAvailable) {
      context.push(AppRoutes.bookDetailsLocation(entry.book.id));
      return;
    }
    context.push(
      AppRoutes.readerLocation(entry.book.id, bookmarkId: entry.bookmark.id),
    );
  }
}
