import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/core/errors/app_errors.dart';
import 'package:thaal/domain/entities/library_snapshot.dart';
import 'package:thaal/domain/entities/reading_data.dart';
import 'package:thaal/services/backup/backup_contents.dart';
import 'package:thaal/services/backup/backup_datasets.dart';
import 'package:thaal/services/backup/backup_format.dart';

import '../../support/fixtures.dart';
import 'backup_test_support.dart';

/// A library-only backup's manifest and datasets for [snapshot], with the
/// decoded JSON open to edits by [edit] before encoding.
({BackupManifest manifest, Map<String, List<int>> datasets}) build(
  LibrarySnapshot snapshot, {
  void Function(Map<String, Map<String, Object?>> json)? edit,
  Map<String, Object>? preferences,
}) {
  final json = encodeBackupDatasets(
    snapshot,
    files: null,
    preferences: preferences,
  );
  // Round-trip through text so edits work on plain JSON maps.
  final decoded = {
    for (final MapEntry(:key, :value) in json.entries)
      key: jsonDecode(jsonEncode(value)) as Map<String, Object?>,
  };
  edit?.call(decoded);
  final datasets = {
    for (final MapEntry(:key, :value) in decoded.entries)
      key: utf8.encode(jsonEncode(value)),
  };
  final manifest = BackupManifest(
    createdAt: DateTime.utc(2026, 11, 8),
    type: BackupType.libraryOnly,
    app: const BackupAppInfo(name: 'Thaal', version: '1', buildNumber: '1'),
    locatorEnvelopeVersion: 1,
    counts: backupCounts(snapshot),
    entries: [
      for (final MapEntry(:key, :value) in datasets.entries)
        entryFor(key, value),
    ],
    preferencesIncluded: preferences != null,
  );
  return (manifest: manifest, datasets: datasets);
}

LibrarySnapshot sample() => LibrarySnapshot(
  books: [sampleBook(id: 'book-1')],
  progress: [
    ReadingProgress(
      bookId: 'book-1',
      locator: sampleLocator(),
      pageNumber: 3,
      progression: 0.25,
      updatedAt: fixedTime,
    ),
  ],
  bookmarks: [
    Bookmark(
      id: 'bm',
      bookId: 'book-1',
      locator: sampleLocator(),
      createdAt: fixedTime,
      updatedAt: fixedTime,
    ),
  ],
  highlights: const [],
  collections: [
    Collection(
      id: 'c',
      name: 'Shelf',
      createdAt: fixedTime,
      updatedAt: fixedTime,
    ),
  ],
  memberships: [
    CollectionMembership(
      collectionId: 'c',
      bookId: 'book-1',
      addedAt: fixedTime,
    ),
  ],
);

List<Object?> records(Map<String, Map<String, Object?>> json, String path) =>
    json[path]!['records']! as List<Object?>;

Map<String, Object?> first(
  Map<String, Map<String, Object?>> json,
  String path,
) => records(json, path).first! as Map<String, Object?>;

void main() {
  Matcher throwsKind(BackupErrorKind kind) =>
      throwsA(isA<BackupError>().having((error) => error.kind, 'kind', kind));

  test('parses what the export writes', () {
    final snapshot = sample();
    final built = build(snapshot, preferences: {'app.theme': 'dark'});
    final contents = parseBackupContents(built.manifest, built.datasets);

    final book = contents.records.books.single;
    expect(book.id, 'book-1');
    expect(book.title, 'Sample Book');
    expect(book.fileChecksum, sampleChecksum);
    expect(book.filePath.value, 'books/book-1/publication.epub');
    expect(contents.books.single.publication, isNull);
    expect(contents.records.progress.single.locator, sampleLocator());
    expect(contents.records.progress.single.pageNumber, 3);
    expect(contents.records.bookmarks.single.locator, sampleLocator());
    expect(contents.records.memberships.single.addedAt, fixedTime);
    expect(contents.preferences, {'app.theme': 'dark'});
  });

  test('rejects broken records', () {
    final edits = <String, void Function(Map<String, Map<String, Object?>>)>{
      'unknown book reference': (j) =>
          first(j, BackupFormat.bookmarksPath)['bookId'] = 'nope',
      'duplicate book id': (j) => records(
        j,
        BackupFormat.booksPath,
      ).add(first(j, BackupFormat.booksPath)),
      'unknown enum': (j) =>
          first(j, BackupFormat.booksPath)['readingStatus'] = 'abandoned',
      'local time': (j) =>
          first(j, BackupFormat.booksPath)['addedAt'] = '2026-11-07T12:00:00',
      'empty title': (j) => first(j, BackupFormat.booksPath)['title'] = ' ',
      'unsafe id': (j) => first(j, BackupFormat.booksPath)['id'] = '../x',
      'progression out of range': (j) =>
          first(j, BackupFormat.progressPath)['progression'] = 1.5,
      'locator not an object': (j) =>
          first(j, BackupFormat.bookmarksPath)['locator'] = 'text',
      'file included in a library-only backup': (j) =>
          first(j, BackupFormat.booksPath)['file'] = {'included': true},
      'unknown collection': (j) =>
          first(j, BackupFormat.collectionBooksPath)['collectionId'] = 'x',
      'records not an array': (j) =>
          j[BackupFormat.highlightsPath]!['records'] = {},
    };
    for (final MapEntry(key: name, value: edit) in edits.entries) {
      final built = build(sample(), edit: edit);
      expect(
        () => parseBackupContents(built.manifest, built.datasets),
        throwsKind(BackupErrorKind.invalidArchive),
        reason: name,
      );
    }
  });

  test('rejects counts that disagree with the manifest', () {
    final built = build(
      sample(),
      edit: (j) => records(j, BackupFormat.bookmarksPath).clear(),
    );
    expect(
      () => parseBackupContents(built.manifest, built.datasets),
      throwsKind(BackupErrorKind.invalidArchive),
    );
  });

  test('rejects a newer dataset schema and deep nesting', () {
    final newer = build(
      sample(),
      edit: (j) => j[BackupFormat.highlightsPath]!['schemaVersion'] = 2,
    );
    expect(
      () => parseBackupContents(newer.manifest, newer.datasets),
      throwsKind(BackupErrorKind.unsupportedVersion),
    );
    final deep = build(sample());
    deep.datasets[BackupFormat.highlightsPath] = utf8.encode(
      '{"schemaVersion":1,"records":[${'[' * 100}${']' * 100}]}',
    );
    expect(
      () => parseBackupContents(deep.manifest, deep.datasets),
      throwsKind(BackupErrorKind.limitExceeded),
    );
  });
}
