import 'package:file_picker/file_picker.dart';

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

/// System document picker for publications.
abstract interface class DocumentPicker {
  /// Lets the user choose one or more files. Returns an empty list when the
  /// user cancels.
  Future<List<ImportSource>> pickPublications();

  /// Deletes temporary copies the picker made. Never touches the user's
  /// original documents.
  Future<void> releaseTemporaryFiles();
}

/// [DocumentPicker] backed by `file_picker`, which uses the platform
/// document picker (Storage Access Framework on Android) and needs no
/// storage permission.
class FilePickerDocumentPicker implements DocumentPicker {
  const FilePickerDocumentPicker();

  @override
  Future<List<ImportSource>> pickPublications() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['epub', 'pdf'],
    );
    return [
      for (final file in files) ImportSource(name: file.name, path: file.path),
    ];
  }

  @override
  Future<void> releaseTemporaryFiles() => FilePicker.clearTemporaryFiles();
}
