import 'package:flutter/material.dart';

import '../../../core/widgets/app_empty_state.dart';

/// Library tab. Only the empty state exists until the feature milestone lands
/// (see docs/IMPLEMENTATION_PLAN.md); no actions are offered before they work.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: const AppEmptyState(
        icon: Icons.auto_stories_outlined,
        title: 'Your library is empty',
        message: 'Importing EPUB and PDF books is coming in a later build.',
      ),
    );
  }
}
