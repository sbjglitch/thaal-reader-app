import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:thaal/services/backup/backup_format.dart';

/// A ZIP entry for hand-built test archives.
typedef ZipEntry = ({String name, List<int> bytes});

/// Writes [entries] in order, stored (or deflated when [deflate]), without
/// any of the app's own checks, so tests can build malformed archives.
void writeRawZip(String path, List<ZipEntry> entries, {bool deflate = false}) {
  final encoder = ZipFileEncoder()
    ..create(path, level: deflate ? 6 : ZipFileEncoder.store);
  for (final entry in entries) {
    encoder.addArchiveFile(ArchiveFile.bytes(entry.name, entry.bytes));
  }
  encoder.closeSync();
}

String sha256Of(List<int> bytes) => sha256.convert(bytes).toString();

BackupEntry entryFor(
  String path,
  List<int> bytes, {
  BackupEntryRole role = BackupEntryRole.data,
  String? bookId,
}) => BackupEntry(
  path: path,
  role: role,
  bookId: bookId,
  sizeBytes: bytes.length,
  sha256: sha256Of(bytes),
);

/// The six required datasets, empty.
List<ZipEntry> emptyDatasets() => [
  for (final path in BackupFormat.requiredDataPaths)
    (
      name: path,
      bytes: utf8.encode(
        jsonEncode({'schemaVersion': 1, 'records': <Object?>[]}),
      ),
    ),
];

Map<String, Object?> manifestJson({
  BackupType type = BackupType.libraryOnly,
  required List<BackupEntry> entries,
  bool preferencesIncluded = false,
}) => BackupManifest(
  createdAt: DateTime.utc(2026, 11, 8, 10),
  type: type,
  app: const BackupAppInfo(name: 'Thaal', version: '1.0.0', buildNumber: '1'),
  locatorEnvelopeVersion: 1,
  counts: {for (final key in BackupFormat.countKeys) key: 0},
  entries: entries,
  preferencesIncluded: preferencesIncluded,
).toJson();

/// A valid archive: manifest, then [entries] (default: empty datasets),
/// with the manifest optionally edited by [editManifest].
void writeBackup(
  String path, {
  List<ZipEntry>? entries,
  BackupType type = BackupType.libraryOnly,
  void Function(Map<String, Object?> manifest)? editManifest,
  List<ZipEntry> extra = const [],
  bool deflate = false,
}) {
  final contents = entries ?? emptyDatasets();
  final manifest = manifestJson(
    type: type,
    entries: [
      for (final entry in contents)
        entryFor(
          entry.name,
          entry.bytes,
          role: entry.name.startsWith('files/books/')
              ? BackupEntryRole.publication
              : entry.name.startsWith('files/covers/')
              ? BackupEntryRole.cover
              : BackupEntryRole.data,
          bookId: entry.name.startsWith('files/books/')
              ? entry.name.split('/')[2]
              : entry.name.startsWith('files/covers/')
              ? entry.name.split('/')[2].split('.').first
              : null,
        ),
    ],
  );
  editManifest?.call(manifest);
  writeRawZip(path, [
    (name: BackupFormat.manifestPath, bytes: utf8.encode(jsonEncode(manifest))),
    ...contents,
    ...extra,
  ], deflate: deflate);
}

Directory createTempDir() => Directory.systemTemp.createTempSync('backup_test');
