import 'package:flutter/material.dart';

import '../../app/theme/app_color_tokens.dart';
import '../../app/theme/app_spacing_tokens.dart';

/// Recoverable error presentation (UI/UX spec §11).
///
/// [message] must be written for the user. Never pass raw exception text,
/// stack traces or plugin error strings.
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Try again',
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

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
              child: Icon(Icons.error_outline, size: 40, color: colors.danger),
            ),
            const SizedBox(height: AppSpacing.space16),
            Text(title, style: text.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.space8),
            Text(
              message,
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.space24),
              FilledButton(onPressed: onRetry, child: Text(retryLabel)),
            ],
          ],
        ),
      ),
    );
  }
}
