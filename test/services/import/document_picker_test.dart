import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/services/import/document_picker.dart';

/// Stands in for the platform plugin: throws [error], or reports a
/// cancelled pick.
class _FakePlatform extends FilePickerPlatform {
  Object? error;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    dynamic Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    if (error case final error?) throw error;
    return const [];
  }
}

void main() {
  late _FakePlatform platform;
  const picker = FilePickerDocumentPicker();

  setUp(() {
    platform = _FakePlatform();
    FilePickerPlatform.instance = platform;
  });

  test('a cancelled pick is an empty list', () async {
    expect(await picker.pickPublications(), isEmpty);
  });

  test('files the plugin could not copy become PickedFilesUnreadable', () {
    platform.error = PlatformException(code: 'unknown_path');
    expect(picker.pickPublications(), throwsA(isA<PickedFilesUnreadable>()));
  });

  test('other plugin errors pass through unchanged', () {
    platform.error = PlatformException(code: 'already_active');
    expect(
      picker.pickPublications(),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'already_active',
        ),
      ),
    );
  });
}
