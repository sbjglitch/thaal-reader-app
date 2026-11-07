import 'package:flutter/material.dart';

import '../../../core/widgets/app_empty_state.dart';

/// Collections tab. Only the empty state exists until the feature milestone lands
/// (see docs/IMPLEMENTATION_PLAN.md); no actions are offered before they work.
class CollectionsScreen extends StatelessWidget {
  const CollectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Collections')),
      body: const AppEmptyState(
        icon: Icons.collections_bookmark_outlined,
        title: 'No collections yet',
        message: 'Grouping books into collections is coming in a later build.',
      ),
    );
  }
}
