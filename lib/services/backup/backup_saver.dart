import 'dart:io';

import 'package:flutter/services.dart';

/// Hands a finished backup to the platform so the user can choose where to
/// keep it (BACKUP_FORMAT.md §3).
abstract interface class BackupSaver {
  /// Whether this platform can save backups. The backup actions are hidden
  /// when it cannot.
  bool get isSupported;

  /// Shows the system save dialog for [file], suggesting [suggestedName].
  /// Returns the name the file was saved under, or null if the user
  /// cancelled. Throws [BackupSaveException] if writing failed; the partial
  /// destination file is then removed where the platform allows.
  Future<String?> save(File file, {required String suggestedName});
}

final class BackupSaveException implements Exception {
  const BackupSaveException({required this.outOfSpace});

  final bool outOfSpace;
}

/// Android: `ACTION_CREATE_DOCUMENT` through a small channel in
/// MainActivity, which copies the file to the chosen document in chunks.
/// The app gets access to that one document only and needs no storage
/// permission. iOS support is deferred with the rest of iOS work.
class PlatformBackupSaver implements BackupSaver {
  const PlatformBackupSaver();

  static const MethodChannel _channel = MethodChannel(
    'com.sbjglitch.thaal/backup',
  );

  @override
  bool get isSupported => Platform.isAndroid;

  @override
  Future<String?> save(File file, {required String suggestedName}) async {
    try {
      return await _channel.invokeMethod<String>('saveBackup', {
        'sourcePath': file.path,
        'suggestedName': suggestedName,
      });
    } on PlatformException catch (error) {
      throw BackupSaveException(outOfSpace: error.code == 'no_space');
    }
  }
}
