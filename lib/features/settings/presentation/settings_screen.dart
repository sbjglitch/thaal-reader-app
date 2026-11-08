import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_color_tokens.dart';
import '../../../app/theme/app_spacing_tokens.dart';
import '../../../domain/entities/app_preferences.dart';
import '../../backup/presentation/backup_section.dart';
import '../application/app_theme_controller.dart';

/// Settings tab (UI/UX §7.10). Only settings that work are shown.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(appThemeProvider);
    final backupSupported = ref.watch(backupSaverProvider).isSupported;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Appearance'),
          RadioGroup<AppThemePreference>(
            groupValue: theme,
            onChanged: (value) {
              if (value != null) _select(context, ref, value);
            },
            child: Column(
              children: [
                for (final option in AppThemePreference.values)
                  RadioListTile<AppThemePreference>(
                    value: option,
                    title: Text(_label(option)),
                    subtitle: option == AppThemePreference.system
                        ? const Text('Match the device setting')
                        : null,
                  ),
              ],
            ),
          ),
          if (backupSupported) ...[
            const _SectionHeader('Data'),
            const BackupSection(),
          ],
        ],
      ),
    );
  }

  static String _label(AppThemePreference theme) => switch (theme) {
    AppThemePreference.system => 'System',
    AppThemePreference.light => 'Light',
    AppThemePreference.dark => 'Dark',
  };

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    AppThemePreference theme,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = await ref.read(appThemeProvider.notifier).select(theme);
    if (!saved) {
      messenger.showSnackBar(
        const SnackBar(content: Text('The theme could not be changed.')),
      );
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenEdge,
        AppSpacing.space16,
        AppSpacing.screenEdge,
        AppSpacing.space4,
      ),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: context.colorTokens.textSecondary),
        ),
      ),
    );
  }
}
