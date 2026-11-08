import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/core/errors/app_errors.dart';
import 'package:thaal/services/backup/backup_format.dart';

import 'backup_test_support.dart';

const String _book = '7b7d6b6e-7e7c-4a20-a1b4-1d1f4c9a0001';

void main() {
  group('isSafeArchivePath', () {
    test('accepts relative slash-separated paths', () {
      expect(isSafeArchivePath('manifest.json'), isTrue);
      expect(isSafeArchivePath('files/books/$_book/publication.epub'), isTrue);
    });

    test('rejects absolute, traversal, drive and odd paths', () {
      for (final path in [
        '',
        '/etc/passwd',
        '../evil',
        'data/../../evil',
        'data/./books.json',
        'data//books.json',
        'data/',
        r'data\books.json',
        'C:/books.json',
        'data/books\u0000.json',
        'data/\nbooks.json',
      ]) {
        expect(isSafeArchivePath(path), isFalse, reason: path);
      }
    });
  });

  test('file names use the UTC timestamp and backup type', () {
    final time = DateTime.utc(2026, 11, 7, 18, 45, 3);
    expect(
      BackupFormat.fileName(BackupType.full, time),
      'reader-backup-20261107-184503-full.readerbackup',
    );
    expect(
      BackupFormat.fileName(BackupType.libraryOnly, time),
      'reader-backup-20261107-184503-library.readerbackup',
    );
  });

  group('BackupManifest.parse', () {
    Map<String, Object?> valid({BackupType type = BackupType.libraryOnly}) =>
        manifestJson(
          type: type,
          entries: [
            for (final entry in emptyDatasets())
              entryFor(entry.name, entry.bytes),
          ],
        );

    Matcher throwsKind(BackupErrorKind kind) =>
        throwsA(isA<BackupError>().having((error) => error.kind, 'kind', kind));

    test('round-trips a manifest', () {
      final manifest = BackupManifest.parse(valid());
      expect(manifest.type, BackupType.libraryOnly);
      expect(manifest.entries, hasLength(6));
      expect(manifest.createdAt, DateTime.utc(2026, 11, 8, 10));
      expect(manifest.app.name, 'Thaal');
      expect(manifest.preferencesIncluded, isFalse);
    });

    test('ignores unknown optional fields', () {
      final json = valid()..['futureField'] = {'anything': true};
      expect(() => BackupManifest.parse(json), returnsNormally);
    });

    test('rejects a newer format version as unsupported', () {
      final json = valid()..['formatVersion'] = 2;
      expect(
        () => BackupManifest.parse(json),
        throwsKind(BackupErrorKind.unsupportedVersion),
      );
    });

    test('rejects a foreign format id, unknown type and missing fields', () {
      for (final edit in <void Function(Map<String, Object?>)>[
        (m) => m['format'] = 'com.example.other',
        (m) => m['backupType'] = 'partial',
        (m) => m.remove('createdAt'),
        (m) => m['createdAt'] = '2026-11-08T10:00:00',
        (m) => m['counts'] = {'books': 0},
        (m) => m['preferencesIncluded'] = 'yes',
        (m) => m['entries'] = 'none',
      ]) {
        final json = valid();
        edit(json);
        expect(
          () => BackupManifest.parse(json),
          throwsKind(BackupErrorKind.invalidArchive),
        );
      }
    });

    test('rejects entries that break the path and role rules', () {
      final bytes = [1, 2, 3];
      for (final bad in [
        entryFor('../evil.json', bytes),
        entryFor('data/other.json', bytes),
        entryFor(
          'files/books/$_book/publication.exe',
          bytes,
          role: BackupEntryRole.publication,
          bookId: _book,
        ),
        // Path names a different book than bookId.
        entryFor(
          'files/books/other/publication.epub',
          bytes,
          role: BackupEntryRole.publication,
          bookId: _book,
        ),
        entryFor('data/books.json', bytes),
      ]) {
        final json = valid(type: BackupType.full);
        (json['entries']! as List<Object?>).add(bad.toJson());
        expect(
          () => BackupManifest.parse(json),
          throwsKind(BackupErrorKind.invalidArchive),
          reason: bad.path,
        );
      }
    });

    test('rejects a malformed digest', () {
      final json = valid();
      final first = (json['entries']! as List<Object?>).first!;
      (first as Map<String, Object?>)['sha256'] = 'ABC';
      expect(
        () => BackupManifest.parse(json),
        throwsKind(BackupErrorKind.invalidArchive),
      );
    });

    test('rejects a library-only backup that carries files', () {
      final json = valid();
      (json['entries']! as List<Object?>).add(
        entryFor(
          'files/books/$_book/publication.epub',
          [1],
          role: BackupEntryRole.publication,
          bookId: _book,
        ).toJson(),
      );
      expect(
        () => BackupManifest.parse(json),
        throwsKind(BackupErrorKind.invalidArchive),
      );
    });

    test('requires every dataset and a matching preferences flag', () {
      final missing = valid();
      (missing['entries']! as List<Object?>).removeLast();
      expect(
        () => BackupManifest.parse(missing),
        throwsKind(BackupErrorKind.invalidArchive),
      );
      final flag = valid()..['preferencesIncluded'] = true;
      expect(
        () => BackupManifest.parse(flag),
        throwsKind(BackupErrorKind.invalidArchive),
      );
    });
  });
}
