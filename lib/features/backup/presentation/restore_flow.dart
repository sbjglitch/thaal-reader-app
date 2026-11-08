import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_spacing_tokens.dart';
import '../../../services/backup/backup_format.dart';
import '../../../services/backup/backup_restore_service.dart';
import '../../../services/backup/restore_plan.dart';
import '../application/backup_controller.dart';
import 'backup_section.dart';

/// Restore flow (UI/UX §7.11): choose a file, check it, preview what a
/// merge will add and skip, confirm, restore, then report.
Future<void> startRestore(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(backupControllerProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final selection = await _withProgress(
      context,
      'Checking backup…',
      controller.pickAndInspect,
    );
    if (!context.mounted) return;
    switch (selection) {
      case null || RestoreSelectionCancelled():
        return;
      case RestoreSelectionFailed():
        messenger.showSnackBar(
          const SnackBar(content: Text('The backup file could not be opened.')),
        );
        return;
      case RestoreSelectionInspected(
        inspection: RestoreRejected(:final reason),
      ):
        await showDialog<void>(
          context: context,
          builder: (context) => _RejectedDialog(reason: reason),
        );
        return;
      case RestoreSelectionInspected(inspection: final RestoreReady ready):
        final applySettings = await showDialog<bool>(
          context: context,
          builder: (context) => _PreviewDialog(ready: ready),
        );
        if (applySettings == null || !context.mounted) return;
        final outcome = await _withProgress(
          context,
          'Restoring…',
          () => controller.restore(ready, applySettings: applySettings),
        );
        if (outcome == null || !context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => _OutcomeDialog(outcome: outcome),
        );
    }
  } finally {
    await controller.releaseRestoreFile();
  }
}

Future<T> _withProgress<T>(
  BuildContext context,
  String label,
  Future<T> Function() body,
) async {
  final navigator = Navigator.of(context);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BackupProgressDialog(label),
  );
  navigator.push(route).ignore();
  try {
    return await body();
  } finally {
    if (route.isActive) navigator.removeRoute(route);
  }
}

class _RejectedDialog extends StatelessWidget {
  const _RejectedDialog({required this.reason});

  final RestoreRejection reason;

  @override
  Widget build(BuildContext context) {
    final message = switch (reason) {
      RestoreRejection.notBackup => 'This file is not a Thaal backup.',
      RestoreRejection.unsupportedVersion =>
        'This backup was made by a newer version of Thaal. Update the app '
            'to restore it.',
      RestoreRejection.damaged =>
        'This backup is damaged: its contents do not match their checksums.',
      RestoreRejection.tooLarge =>
        'This backup is larger than Thaal can restore.',
      RestoreRejection.unreadable => 'The backup file could not be read.',
    };
    return AlertDialog(
      title: const Text('This backup can’t be restored'),
      content: Text('$message Your library was not changed.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Pops with the "apply settings" choice, or null when cancelled.
class _PreviewDialog extends StatefulWidget {
  const _PreviewDialog({required this.ready});

  final RestoreReady ready;

  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  var _applySettings = false;

  @override
  Widget build(BuildContext context) {
    final manifest = widget.ready.contents.manifest;
    final plan = widget.ready.plan;
    final kind = manifest.type == BackupType.full
        ? 'Full backup'
        : 'Library-only backup';
    final header = Text('$kind from ${formatBackupDate(manifest.createdAt)}');
    if (!plan.hasChanges) {
      return AlertDialog(
        title: const Text('Nothing to restore'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            const SizedBox(height: AppSpacing.space12),
            const Text('Everything in this backup is already in your library.'),
            ..._conflicts(plan),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    }
    final hasSettings = widget.ready.contents.preferences != null;
    return AlertDialog(
      title: const Text('Restore backup?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            const SizedBox(height: AppSpacing.space12),
            for (final line in _additions(plan)) Text('• $line'),
            if (plan.booksAlreadyPresent > 0)
              Text(
                '• ${_count(plan.booksAlreadyPresent, 'book')} already in '
                'your library',
              ),
            if (plan.booksMissingFiles > 0) ...[
              const SizedBox(height: AppSpacing.space12),
              Text(
                'Book files are not in this backup. '
                '${plan.booksMissingFiles == 1 ? 'This book' : 'These books'} '
                'will show “File missing” until you import the same '
                '${plan.booksMissingFiles == 1 ? 'file' : 'files'} again.',
              ),
            ],
            ..._conflicts(plan),
            if (plan.keptProgress > 0) ...[
              const SizedBox(height: AppSpacing.space12),
              Text(
                'Your current reading position is kept for '
                '${_count(plan.keptProgress, 'book')}.',
              ),
            ],
            const SizedBox(height: AppSpacing.space12),
            const Text('Nothing in your library is changed or removed.'),
            if (hasSettings)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _applySettings,
                onChanged: (value) =>
                    setState(() => _applySettings = value ?? false),
                title: const Text('Apply settings from the backup'),
                subtitle: const Text(
                  'Replaces your theme, reading and library settings',
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_applySettings),
          child: const Text('Restore'),
        ),
      ],
    );
  }
}

class _OutcomeDialog extends StatelessWidget {
  const _OutcomeDialog({required this.outcome});

  final RestoreOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final (title, children) = switch (outcome) {
      RestoreCompleted(:final plan, :final settingsApplied) => (
        'Restore complete',
        <Widget>[
          if (_additions(plan).isEmpty)
            const Text('Nothing was added.')
          else ...[
            const Text('Added:'),
            for (final line in _additions(plan)) Text('• $line'),
          ],
          if (plan.booksMissingFiles > 0) ...[
            const SizedBox(height: AppSpacing.space12),
            Text(
              'Import the same files again to read '
              '${plan.booksMissingFiles == 1 ? 'the restored book' : 'the '
                        '${plan.booksMissingFiles} restored books'}.',
            ),
          ],
          ..._conflicts(plan, skipped: true),
          if (settingsApplied > 0) ...[
            const SizedBox(height: AppSpacing.space12),
            const Text('Settings from the backup were applied.'),
          ],
        ],
      ),
      RestoreFailed(:final reason) => (
        'Restore failed',
        <Widget>[
          Text(
            reason == RestoreFailure.insufficientStorage
                ? 'There is not enough storage to restore this backup. '
                      'Your library was not changed.'
                : 'The backup could not be restored. Your library was not '
                      'changed.',
          ),
        ],
      ),
    };
    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

List<String> _additions(RestorePlan plan) {
  final add = plan.add;
  return [
    if (add.books.isNotEmpty) _count(add.books.length, 'book'),
    if (add.bookmarks.isNotEmpty) _count(add.bookmarks.length, 'bookmark'),
    if (add.highlights.isNotEmpty) _count(add.highlights.length, 'highlight'),
    if (add.collections.isNotEmpty)
      _count(add.collections.length, 'collection'),
    if (add.progress.isNotEmpty)
      _count(add.progress.length, 'reading position'),
  ];
}

const int _shownTitles = 5;

/// What conflicts with the library and is left out.
List<Widget> _conflicts(RestorePlan plan, {bool skipped = false}) {
  final books = plan.skippedBooks;
  final collections = plan.skippedCollections.length;
  final annotations = plan.skippedAnnotations;
  if (books.isEmpty && collections == 0 && annotations == 0) return const [];
  final more = books.length - _shownTitles;
  return [
    const SizedBox(height: AppSpacing.space12),
    Text(
      skipped
          ? 'Skipped because they conflict with your library:'
          : 'These conflict with your library and will be skipped:',
    ),
    for (final skippedBook in books.take(_shownTitles))
      Text(
        '• ${skippedBook.book.title} (${_reason(skippedBook.reason)})',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    if (more > 0) Text('• and ${_count(more, 'more book')}'),
    if (collections > 0)
      Text(
        '• ${_count(collections, 'collection')} named differently in your '
        'library',
      ),
    if (annotations > 0)
      Text(
        '• ${_count(annotations, 'bookmark or highlight', plural: 'bookmarks or highlights')} '
        'that differ from yours',
      ),
  ];
}

String _reason(RestoreBookConflict reason) => switch (reason) {
  RestoreBookConflict.differentFile => 'a different file is in your library',
  RestoreBookConflict.duplicate => 'already in your library',
  RestoreBookConflict.occupied => 'its storage is in use',
};

String _count(int count, String noun, {String? plural}) =>
    '$count ${count == 1 ? noun : (plural ?? '${noun}s')}';

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `8 Nov 2026, 12:35` in local time.
String formatBackupDate(DateTime value) {
  final local = value.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.day} ${_months[local.month - 1]} ${local.year}, '
      '${two(local.hour)}:${two(local.minute)}';
}
