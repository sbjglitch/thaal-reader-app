import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../services/backup/backup_export_service.dart';
import '../../../services/backup/backup_format.dart';
import '../../../services/backup/backup_restore_service.dart';
import '../../library/application/library_view.dart';
import '../../reader/application/reader_preferences_controller.dart';
import '../../settings/application/app_theme_controller.dart';

/// Backup and restore activity. One operation runs at a time.
sealed class BackupState {
  const BackupState();

  bool get isBusy => this is! BackupIdle;
}

final class BackupIdle extends BackupState {
  const BackupIdle();
}

final class BackupCreating extends BackupState {
  const BackupCreating(this.type);

  final BackupType type;
}

/// The backup file picker is open or the chosen file is being checked.
final class BackupInspecting extends BackupState {
  const BackupInspecting();
}

final class BackupRestoring extends BackupState {
  const BackupRestoring();
}

/// Result of choosing a backup to restore.
sealed class RestoreSelection {
  const RestoreSelection();
}

/// The picker was closed without a choice.
final class RestoreSelectionCancelled extends RestoreSelection {
  const RestoreSelectionCancelled();
}

/// The picker could not be opened or returned no readable file.
final class RestoreSelectionFailed extends RestoreSelection {
  const RestoreSelectionFailed();
}

final class RestoreSelectionInspected extends RestoreSelection {
  const RestoreSelectionInspected(this.inspection);

  final RestoreInspection inspection;
}

class BackupController extends Notifier<BackupState> {
  @override
  BackupState build() => const BackupIdle();

  /// Creates and saves a backup. Returns null if one is already running.
  Future<BackupExportResult?> create(
    BackupType type, {
    required bool includeSettings,
  }) async {
    if (state.isBusy) return null;
    state = BackupCreating(type);
    try {
      return await ref
          .read(backupExportServiceProvider)
          .export(type, includeSettings: includeSettings);
    } finally {
      state = const BackupIdle();
    }
  }

  /// Lets the user choose a backup and checks it. Returns null if another
  /// operation is running. Call [releaseRestoreFile] when done with it.
  Future<RestoreSelection?> pickAndInspect() async {
    if (state.isBusy) return null;
    state = const BackupInspecting();
    try {
      final picked = await ref.read(documentPickerProvider).pickBackup();
      if (picked == null) return const RestoreSelectionCancelled();
      final path = picked.path;
      if (path == null) return const RestoreSelectionFailed();
      return RestoreSelectionInspected(
        await ref.read(backupRestoreServiceProvider).inspect(path),
      );
    } on Exception catch (error, stackTrace) {
      ref
          .read(appLoggerProvider)
          .error('restore.picker_failed', error, stackTrace: stackTrace);
      return const RestoreSelectionFailed();
    } finally {
      state = const BackupIdle();
    }
  }

  /// Restores [ready]. Returns null if another operation is running.
  Future<RestoreOutcome?> restore(
    RestoreReady ready, {
    required bool applySettings,
  }) async {
    if (state.isBusy) return null;
    state = const BackupRestoring();
    try {
      final outcome = await ref
          .read(backupRestoreServiceProvider)
          .restore(ready, applySettings: applySettings);
      if (outcome case RestoreCompleted(:final settingsApplied)
          when settingsApplied > 0) {
        // These read their settings once; rebuild them from storage.
        ref
          ..invalidate(appThemeProvider)
          ..invalidate(readerPreferencesProvider)
          ..invalidate(libraryViewProvider);
      }
      return outcome;
    } finally {
      state = const BackupIdle();
    }
  }

  /// Deletes the picker's temporary copy of the backup file.
  Future<void> releaseRestoreFile() async {
    try {
      await ref.read(documentPickerProvider).releaseTemporaryFiles();
    } on Exception catch (error) {
      ref
          .read(appLoggerProvider)
          .warning('restore.release_failed', error: error);
    }
  }
}

final backupControllerProvider =
    NotifierProvider<BackupController, BackupState>(BackupController.new);
