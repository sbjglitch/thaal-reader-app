import 'package:flutter/material.dart';

import '../../../core/widgets/app_empty_state.dart';

/// Settings tab. Only the empty state exists until the feature milestone lands
/// (see docs/IMPLEMENTATION_PLAN.md); no actions are offered before they work.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const AppEmptyState(
        icon: Icons.settings_outlined,
        title: 'Settings are not available yet',
        message: 'Theme, reader defaults and backup options are coming in a later build.',
      ),
    );
  }
}
