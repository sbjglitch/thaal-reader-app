import 'package:flutter/material.dart';

import '../../app/theme/app_color_tokens.dart';
import '../../app/theme/app_spacing_tokens.dart';

/// Centred explanation of missing content, with at most one next action
/// (UI/UX spec §11: "Explain what is missing and provide one clear next
/// action"). Omit [action] when the action is not available yet; never show a
/// control for unsupported functionality.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colorTokens;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(icon, size: 40, color: colors.textTertiary),
            ),
            const SizedBox(height: AppSpacing.space16),
            Text(title, style: text.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.space8),
            Text(
              message,
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (action case final action?) ...[
              const SizedBox(height: AppSpacing.space24),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
