import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

/// A user-selected file ready to be imported.
final class ImportSource {
  const ImportSource({required this.name, required this.path});

  /// Display name of the file as chosen by the user. Shown in the UI only;
  /// never logged.
  final String name;

  /// Local path the app can read, or null when the platform returned no
  /// readable path (the import then fails for that file). On Android this is
  /// the picker's temporary copy in the app cache, not the user's original
  /// document.
  final String? path;
}

/// The user chose files, but the picker could not copy any of them to a
/// readable location (on Android: into the app cache). Not enough free
/// storage is the usual cause, but the platform does not say so.
final class PickedFilesUnreadable implements Exception {
  const PickedFilesUnreadable();

  @override
  String toString() => 'PickedFilesUnreadable';
}

/// System document picker for publications.
abstract interface class DocumentPicker {
  /// Lets the user choose one or more files. Returns an empty list when the
  /// user cancels. Throws [PickedFilesUnreadable] when files were chosen but
  /// none could be copied.
  Future<List<ImportSource>> pickPublications();

  /// Lets the user choose one backup file. Returns null when the user
  /// cancels.
  Future<ImportSource?> pickBackup();

  /// Deletes temporary copies the picker made. Never touches the user's
  /// original documents.
  Future<void> releaseTemporaryFiles();
}

/// [DocumentPicker] backed by `file_picker`, which uses the platform
/// document picker (Storage Access Framework on Android) and needs no
/// storage permission.
class FilePickerDocumentPicker implements DocumentPicker {
  const FilePickerDocumentPicker();

  /// The error code `android_file_picker` 2.1.3 reports when every chosen
  /// file failed to copy into the cache (the cause, such as no space left,
  /// is only logged natively). If only some fail, it silently returns the
  /// rest. Re-check when upgrading file_picker.
  static const _copyFailedCode = 'unknown_path';

  @override
  Future<List<ImportSource>> pickPublications() async {
    final List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['epub', 'pdf'],
      );
    } on PlatformException catch (error) {
      if (error.code == _copyFailedCode) throw const PickedFilesUnreadable();
      rethrow;
    }
    return [
      for (final file in files) ImportSource(name: file.name, path: file.path),
    ];
  }

  /// Any file type: Android does not know the `.readerbackup` extension, so
  /// a filter would hide backups. The restore validates the content.
  @override
  Future<ImportSource?> pickBackup() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return null;
    final file = files.first;
    return ImportSource(name: file.name, path: file.path);
  }

  @override
  Future<void> releaseTemporaryFiles() => FilePicker.clearTemporaryFiles();
}
