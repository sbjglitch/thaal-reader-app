import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../services/backup/backup_export_service.dart';
import '../../../services/backup/backup_format.dart';

/// Backup activity. One backup runs at a time.
sealed class BackupState {
  const BackupState();
}

final class BackupIdle extends BackupState {
  const BackupIdle();
}

final class BackupCreating extends BackupState {
  const BackupCreating(this.type);

  final BackupType type;
}

class BackupController extends Notifier<BackupState> {
  @override
  BackupState build() => const BackupIdle();

  /// Creates and saves a backup. Returns null if one is already running.
  Future<BackupExportResult?> create(
    BackupType type, {
    required bool includeSettings,
  }) async {
    if (state is BackupCreating) return null;
    state = BackupCreating(type);
    try {
      return await ref
          .read(backupExportServiceProvider)
          .export(type, includeSettings: includeSettings);
    } finally {
      state = const BackupIdle();
    }
  }
}

final backupControllerProvider =
    NotifierProvider<BackupController, BackupState>(BackupController.new);
