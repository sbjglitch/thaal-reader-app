import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/data/database/app_database.dart';
import 'package:thaal/domain/entities/enums.dart';

import '../../support/fixtures.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  Future<List<String>> names(String type) async {
    final rows = await db
        .customSelect(
          'SELECT name FROM sqlite_master WHERE type = ? '
          "AND name NOT LIKE 'sqlite_%' ORDER BY name",
          variables: [Variable.withString(type)],
        )
        .get();
    return [for (final r in rows) r.read<String>('name')];
  }

  /// Inserts a books row with raw SQL so CHECK constraints are exercised
  /// without the domain validation in front of them.
  Future<void> insertRawBook(Map<String, Object?> overrides) {
    final values = <String, Object?>{
      'id': 'raw',
      'title': 'Raw',
      'authors_json': '[]',
      'format': 'epub',
      'file_path': 'books/raw/publication.epub',
      'file_size_bytes': 10,
      'file_checksum': sampleChecksum,
      'reading_status': 'unread',
      'added_at': 1,
      'updated_at': 1,
      ...overrides,
    };
    final columns = values.keys.join(', ');
    final placeholders = List.filled(values.length, '?').join(', ');
    return db.customStatement(
      'INSERT INTO books ($columns) VALUES ($placeholders)',
      values.values.toList(),
    );
  }

  test(
    'schema version 1 creates the six tables and documented indexes',
    () async {
      expect(db.schemaVersion, 1);
      expect(await names('table'), [
        'bookmarks',
        'books',
        'collection_books',
        'collections',
        'highlights',
        'reading_progress',
      ]);
      expect(await names('index'), [
        'idx_bookmarks_book_created',
        'idx_books_added_at',
        'idx_books_checksum',
        'idx_books_format',
        'idx_books_last_opened_at',
        'idx_books_status',
        'idx_books_title',
        'idx_collection_books_book',
        'idx_highlights_book_created',
      ]);
    },
  );

  test('foreign keys are enforced on the connection', () async {
    final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(row.data.values.single, 1);
  });

  test('a valid raw row is accepted', () async {
    await insertRawBook({});
  });

  group('books CHECK constraints reject', () {
    final invalid = <String, Map<String, Object?>>{
      'blank title': {'title': '   '},
      'unknown format': {'format': 'mobi'},
      'unknown status': {'reading_status': 'abandoned'},
      'zero size': {'file_size_bytes': 0},
      'short checksum': {'file_checksum': 'abc'},
      'uppercase checksum': {'file_checksum': sampleChecksum.toUpperCase()},
      'non-array authors': {'authors_json': '{"a":1}'},
      'invalid authors JSON': {'authors_json': '[x'},
      'absolute path': {'file_path': '/data/x.epub'},
      'traversal path': {'file_path': 'books/../../x.epub'},
      'dot segment': {'file_path': 'books/./x.epub'},
      'backslash path': {'file_path': r'books\x.epub'},
      'traversal cover': {'cover_path': '../cover.jpg'},
    };
    invalid.forEach((name, overrides) {
      test(name, () {
        expect(insertRawBook(overrides), throwsA(isA<Exception>()));
      });
    });
  });

  test('enum CHECK lists match the Dart enums', () async {
    var n = 0;
    for (final format in PublicationFormat.values) {
      for (final status in ReadingStatus.values) {
        n++;
        await insertRawBook({
          'id': 'b$n',
          'file_path': 'books/b$n/publication.x',
          'format': format.wireName,
          'reading_status': status.wireName,
        });
      }
    }
    await db.customStatement(
      'INSERT INTO books (id, title, format, file_path, file_size_bytes, '
      'file_checksum, added_at, updated_at) VALUES '
      "('h', 'H', 'epub', 'books/h/p.epub', 1, '$sampleChecksum', 1, 1)",
    );
    for (final color in HighlightColor.values) {
      await db.customStatement(
        'INSERT INTO highlights (id, book_id, locator_json, color, '
        "created_at, updated_at) VALUES (?, 'h', '{}', ?, 1, 1)",
        ['hl-${color.wireName}', color.wireName],
      );
    }
  });

  test('progress rejects out-of-range progression and invalid JSON', () async {
    await insertRawBook({});
    Future<void> progress(Object? progression, Object? locator) =>
        db.customStatement(
          'INSERT OR REPLACE INTO reading_progress '
          '(book_id, locator_json, progression, updated_at) '
          "VALUES ('raw', ?, ?, 1)",
          [locator, progression],
        );

    await progress(0.5, '{"a":1}');
    await expectLater(progress(1.5, null), throwsA(isA<Exception>()));
    await expectLater(progress(-0.1, null), throwsA(isA<Exception>()));
    await expectLater(progress(0.5, 'not json'), throwsA(isA<Exception>()));
  });

  test('data persists after closing and reopening the file', () async {
    final dir = await Directory.systemTemp.createTemp('thaal_db');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/thaal.sqlite');

    final first = AppDatabase.open(file);
    await first
        .into(first.collections)
        .insert(
          CollectionsCompanion.insert(
            id: 'c1',
            name: 'Kept',
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    await first.close();

    final second = AppDatabase.open(file);
    addTearDown(second.close);
    final rows = await second.select(second.collections).get();
    expect(rows.single.name, 'Kept');
  });
}
