import 'package:flutter/material.dart';

import '../../../core/widgets/app_empty_state.dart';

/// Bookmarks tab. Only the empty state exists until the feature milestone lands
/// (see docs/IMPLEMENTATION_PLAN.md); no actions are offered before they work.
class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bookmarks')),
      body: const AppEmptyState(
        icon: Icons.bookmark_border,
        title: 'No bookmarks yet',
        message:
            'Saving reading locations as bookmarks is coming in a later build.',
      ),
    );
  }
}
