import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/core/errors/app_errors.dart';
import 'package:thaal/services/backup/backup_archive.dart';
import 'package:thaal/services/backup/backup_format.dart';

import 'backup_test_support.dart';

const String _book = '7b7d6b6e-7e7c-4a20-a1b4-1d1f4c9a0001';

void main() {
  late Directory temp;
  late String archive;

  setUp(() {
    temp = createTempDir();
    archive = '${temp.path}/test.readerbackup';
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Matcher throwsKind(BackupErrorKind kind) =>
      throwsA(isA<BackupError>().having((error) => error.kind, 'kind', kind));

  void expectRejected(BackupErrorKind kind, {BackupLimits? limits}) => expect(
    () => verifyBackupArchive(archive, limits: limits ?? const BackupLimits()),
    throwsKind(kind),
  );

  test('digestFile streams size and SHA-256', () {
    final file = File('${temp.path}/f')..writeAsBytesSync(utf8.encode('abc'));
    final digest = digestFile(file.path);
    expect(digest.sizeBytes, 3);
    expect(
      digest.sha256,
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  test('writeBackupArchive keeps order and the result verifies', () {
    final datasets = emptyDatasets();
    final publication = List<int>.generate(300000, (i) => i % 251);
    final cover = [0xFF, 0xD8, 0xFF, 0x00];
    final contents = [
      ...datasets,
      (name: 'files/books/$_book/publication.epub', bytes: publication),
      (name: 'files/covers/$_book.jpg', bytes: cover),
    ];
    final manifest = manifestJson(
      type: BackupType.full,
      entries: [
        for (final entry in datasets) entryFor(entry.name, entry.bytes),
        entryFor(
          contents[6].name,
          publication,
          role: BackupEntryRole.publication,
          bookId: _book,
        ),
        entryFor(
          contents[7].name,
          cover,
          role: BackupEntryRole.cover,
          bookId: _book,
        ),
      ],
    );
    final sources = <ArchiveSource>[];
    for (final (index, entry) in [
      (
        name: BackupFormat.manifestPath,
        bytes: utf8.encode(jsonEncode(manifest)),
      ),
      ...contents,
    ].indexed) {
      final file = File('${temp.path}/src$index')
        ..writeAsBytesSync(entry.bytes);
      sources.add(
        ArchiveSource(archivePath: entry.name, sourcePath: file.path),
      );
    }
    writeBackupArchive(archive, sources);

    final parsed = verifyBackupArchive(archive);
    expect(parsed.type, BackupType.full);
    expect(parsed.entries.map((e) => e.path), [
      ...BackupFormat.requiredDataPaths,
      'files/books/$_book/publication.epub',
      'files/covers/$_book.jpg',
    ]);
  });

  test('accepts deflated entries', () {
    writeBackup(archive, deflate: true);
    expect(verifyBackupArchive(archive).type, BackupType.libraryOnly);
  });

  test('rejects a file that is not a ZIP', () {
    File(archive).writeAsStringSync('not a zip at all');
    expectRejected(BackupErrorKind.invalidArchive);
  });

  test('rejects an archive without manifest.json first', () {
    writeRawZip(archive, emptyDatasets());
    expectRejected(BackupErrorKind.invalidArchive);
  });

  test('rejects a manifest that is not UTF-8 JSON', () {
    writeRawZip(archive, [
      (name: BackupFormat.manifestPath, bytes: [0xC3, 0x28]),
      ...emptyDatasets(),
    ]);
    expectRejected(BackupErrorKind.invalidArchive);
  });

  test('rejects an unsupported format version', () {
    writeBackup(archive, editManifest: (m) => m['formatVersion'] = 99);
    expectRejected(BackupErrorKind.unsupportedVersion);
  });

  test('rejects an undeclared entry', () {
    writeBackup(
      archive,
      extra: [
        (name: 'data/extra.json', bytes: [1]),
      ],
    );
    expectRejected(BackupErrorKind.invalidArchive);
  });

  test('rejects a traversal path even if undeclared', () {
    writeBackup(
      archive,
      extra: [
        (name: '../escape.txt', bytes: [1]),
      ],
    );
    expectRejected(BackupErrorKind.invalidArchive);
  });

  test('rejects duplicate entry names', () {
    final datasets = emptyDatasets();
    writeBackup(archive, extra: [datasets.first]);
    expectRejected(BackupErrorKind.invalidArchive);
  });

  test('rejects a declared entry that is absent', () {
    writeBackup(
      archive,
      editManifest: (m) {
        final entries = m['entries']! as List<Object?>;
        entries.add(entryFor(BackupFormat.preferencesPath, [1]).toJson());
        m['preferencesIncluded'] = true;
      },
    );
    expectRejected(BackupErrorKind.invalidArchive);
  });

  test('rejects a wrong SHA-256', () {
    writeBackup(
      archive,
      editManifest: (m) {
        final first = (m['entries']! as List<Object?>).first!;
        (first as Map<String, Object?>)['sha256'] = '0' * 64;
      },
    );
    expectRejected(BackupErrorKind.checksumMismatch);
  });

  test('rejects a wrong size', () {
    writeBackup(
      archive,
      editManifest: (m) {
        final first = (m['entries']! as List<Object?>).first!;
        (first as Map<String, Object?>)['sizeBytes'] = 1;
      },
    );
    expectRejected(BackupErrorKind.checksumMismatch);
  });

  test('rejects corrupted entry bytes', () {
    writeBackup(archive);
    final bytes = File(archive).readAsBytesSync();
    final text = latin1.decode(bytes);
    // Flip a byte inside the first dataset's stored content.
    final at = text.indexOf('"records"');
    expect(at, greaterThan(0));
    bytes[at + 1] ^= 0x01;
    File(archive).writeAsBytesSync(bytes);
    expectRejected(BackupErrorKind.checksumMismatch);
  });

  test('enforces entry count, archive size and entry size limits', () {
    writeBackup(archive);
    expectRejected(
      BackupErrorKind.limitExceeded,
      limits: const BackupLimits(maxEntries: 3),
    );
    expectRejected(
      BackupErrorKind.limitExceeded,
      limits: const BackupLimits(maxArchiveBytes: 100),
    );
    expectRejected(
      BackupErrorKind.limitExceeded,
      limits: const BackupLimits(maxDataEntryBytes: 10),
    );
    expectRejected(
      BackupErrorKind.limitExceeded,
      limits: const BackupLimits(maxManifestBytes: 10),
    );
  });

  test('rejects a highly compressed entry (ZIP bomb)', () {
    final datasets = emptyDatasets();
    final bomb = (
      name: 'files/books/$_book/publication.epub',
      bytes: List<int>.filled(8 * 1024 * 1024, 0),
    );
    writeBackup(
      archive,
      type: BackupType.full,
      entries: [...datasets, bomb],
      deflate: true,
    );
    expectRejected(BackupErrorKind.limitExceeded);
  });
}
