import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_spacing_tokens.dart';
import '../../../domain/entities/book.dart';
import '../../../services/backup/backup_export_service.dart';
import '../../../services/backup/backup_format.dart';
import '../application/backup_controller.dart';

/// The backup actions in Settings (UI/UX §7.10–7.11).
class BackupSection extends ConsumerWidget {
  const BackupSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(backupControllerProvider) is BackupCreating;
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.inventory_2_outlined),
          title: const Text('Create full backup'),
          subtitle: const Text('Books, reading data and settings'),
          enabled: !busy,
          onTap: () => _start(context, ref, BackupType.full),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Create library-only backup'),
          subtitle: const Text('Reading data and settings, without book files'),
          enabled: !busy,
          onTap: () => _start(context, ref, BackupType.libraryOnly),
        ),
      ],
    );
  }

  static Future<void> _start(
    BuildContext context,
    WidgetRef ref,
    BackupType type,
  ) async {
    final includeSettings = await showDialog<bool>(
      context: context,
      builder: (context) => _ConfirmBackupDialog(type: type),
    );
    if (includeSettings == null || !context.mounted) return;
    await _create(context, ref, type, includeSettings);
  }

  static Future<void> _create(
    BuildContext context,
    WidgetRef ref,
    BackupType type,
    bool includeSettings,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final progress = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CreatingDialog(),
    );
    navigator.push(progress).ignore();
    final BackupExportResult? result;
    try {
      result = await ref
          .read(backupControllerProvider.notifier)
          .create(type, includeSettings: includeSettings);
    } finally {
      if (progress.isActive) navigator.removeRoute(progress);
    }
    if (result == null) return;

    void say(String text) =>
        messenger.showSnackBar(SnackBar(content: Text(text)));
    switch (result) {
      case BackupExportSaved(:final fileName):
        say('Backup saved as $fileName.');
      case BackupExportCancelled():
        say('Backup not saved.');
      case BackupExportFailed(reason: BackupExportFailure.insufficientStorage):
        say('There is not enough storage for the backup. Nothing was saved.');
      case BackupExportFailed():
        say('The backup could not be created. Nothing was saved.');
      case BackupExportIncomplete(:final books):
        if (!context.mounted) return;
        final libraryOnly = await showDialog<bool>(
          context: context,
          builder: (context) => _MissingFilesDialog(books: books),
        );
        if ((libraryOnly ?? false) && context.mounted) {
          await _create(context, ref, BackupType.libraryOnly, includeSettings);
        }
    }
  }
}

/// Explains what the backup contains; pops with the "include settings"
/// choice, or null when cancelled.
class _ConfirmBackupDialog extends StatefulWidget {
  const _ConfirmBackupDialog({required this.type});

  final BackupType type;

  @override
  State<_ConfirmBackupDialog> createState() => _ConfirmBackupDialogState();
}

class _ConfirmBackupDialogState extends State<_ConfirmBackupDialog> {
  var _includeSettings = true;

  @override
  Widget build(BuildContext context) {
    final full = widget.type == BackupType.full;
    return AlertDialog(
      title: Text(full ? 'Create full backup' : 'Create library-only backup'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              full
                  ? 'Includes your books and covers, reading progress, '
                        'bookmarks, highlights, notes and collections. '
                        'It can be large.'
                  : 'Includes reading progress, bookmarks, highlights, notes '
                        'and collections. Book files are not included: after '
                        'restoring, books must be imported again to be read.',
            ),
            const SizedBox(height: AppSpacing.space12),
            const Text(
              'The backup is not encrypted. Anyone with the file can read '
              'what it contains.',
            ),
            const SizedBox(height: AppSpacing.space8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _includeSettings,
              onChanged: (value) =>
                  setState(() => _includeSettings = value ?? true),
              title: const Text('Include settings'),
              subtitle: const Text('Theme, reading and library settings'),
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
          onPressed: () => Navigator.of(context).pop(_includeSettings),
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _CreatingDialog extends StatelessWidget {
  const _CreatingDialog();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Semantics(
          liveRegion: true,
          child: const Row(
            children: [
              SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(width: AppSpacing.space16),
              Expanded(child: Text('Creating backup…')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pops true when the user chooses a library-only backup instead.
class _MissingFilesDialog extends StatelessWidget {
  const _MissingFilesDialog({required this.books});

  static const int _shown = 5;

  final List<Book> books;

  @override
  Widget build(BuildContext context) {
    final more = books.length - _shown;
    return AlertDialog(
      title: const Text('Some book files are missing'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A full backup must include every book’s file, and these are '
              'missing or damaged:',
            ),
            const SizedBox(height: AppSpacing.space8),
            for (final book in books.take(_shown))
              Text(
                '• ${book.title}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            if (more > 0) Text('and $more more'),
            const SizedBox(height: AppSpacing.space12),
            const Text(
              'Create a library-only backup instead, or remove or import '
              'these books again first.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Close'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Create library-only backup'),
        ),
      ],
    );
  }
}
