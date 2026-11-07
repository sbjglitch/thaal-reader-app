import 'package:drift/drift.dart';

import 'converters.dart';

// Table definitions for schema version 1 (DATABASE_SCHEMA.md §5–6).
//
// Timestamps are UTC epoch milliseconds stored as INTEGER. Enum and JSON
// columns use converters from converters.dart. CHECK constraints mirror the
// domain validation so invalid rows are rejected even if a caller bypasses
// it. drift_dev reads `customConstraints` statically, so they must be string
// literals; enum value lists are checked against the Dart enums in tests.

@TableIndex(name: 'idx_books_title', columns: {#title})
@TableIndex(name: 'idx_books_added_at', columns: {#addedAt})
@TableIndex(name: 'idx_books_last_opened_at', columns: {#lastOpenedAt})
@TableIndex(name: 'idx_books_status', columns: {#readingStatus})
@TableIndex(name: 'idx_books_format', columns: {#format})
@TableIndex(name: 'idx_books_checksum', columns: {#fileChecksum})
@DataClassName('BookRow')
class Books extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get authorsJson =>
      text().withDefault(const Constant('[]')).map(const AuthorsConverter())();
  TextColumn get description => text().nullable()();
  TextColumn get language => text().nullable()();
  TextColumn get identifier => text().nullable()();
  TextColumn get publisher => text().nullable()();
  TextColumn get publishedAt => text().nullable()();
  TextColumn get format => text().map(publicationFormatConverter)();
  TextColumn get filePath => text().unique()();
  TextColumn get coverPath => text().nullable()();
  IntColumn get fileSizeBytes => integer()();
  TextColumn get fileChecksum => text()();
  TextColumn get readingStatus => text()
      .withDefault(const Constant('unread'))
      .map(readingStatusConverter)();
  IntColumn get addedAt => integer()();
  IntColumn get lastOpenedAt => integer().nullable()();
  IntColumn get updatedAt => integer()();
  TextColumn get metadataJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (length(trim(title)) > 0)',
    "CHECK (format IN ('epub', 'pdf'))",
    "CHECK (reading_status IN ('unread', 'reading', 'finished'))",
    'CHECK (file_size_bytes > 0)',
    'CHECK (length(file_checksum) = 64 '
        "AND file_checksum NOT GLOB '*[^0-9a-f]*')",
    "CHECK (json_valid(authors_json) AND json_type(authors_json) = 'array')",
    // Managed paths: relative, no backslashes, no `.` or `..` segments.
    "CHECK (file_path <> '' AND substr(file_path, 1, 1) <> '/' "
        'AND instr(file_path, char(92)) = 0 '
        "AND '/' || file_path || '/' NOT LIKE '%/../%' "
        "AND '/' || file_path || '/' NOT LIKE '%/./%')",
    "CHECK (cover_path IS NULL OR (cover_path <> '' "
        "AND substr(cover_path, 1, 1) <> '/' "
        'AND instr(cover_path, char(92)) = 0 '
        "AND '/' || cover_path || '/' NOT LIKE '%/../%' "
        "AND '/' || cover_path || '/' NOT LIKE '%/./%'))",
  ];
}

@DataClassName('ReadingProgressRow')
class ReadingProgressEntries extends Table {
  @override
  String get tableName => 'reading_progress';

  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();
  TextColumn get locatorJson => text().nullable()();
  IntColumn get pageNumber => integer().nullable()();
  RealColumn get progression => real().nullable()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {bookId};

  @override
  List<String> get customConstraints => [
    'CHECK (progression IS NULL OR (progression >= 0.0 AND progression <= 1.0))',
    'CHECK (page_number IS NULL OR page_number >= 1)',
    'CHECK (locator_json IS NULL OR json_valid(locator_json))',
  ];
}

@TableIndex(name: 'idx_bookmarks_book_created', columns: {#bookId, #createdAt})
@DataClassName('BookmarkRow')
class Bookmarks extends Table {
  TextColumn get id => text()();
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();
  TextColumn get locatorJson => text()();
  TextColumn get label => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (json_valid(locator_json))'];
}

@TableIndex(name: 'idx_highlights_book_created', columns: {#bookId, #createdAt})
@DataClassName('HighlightRow')
class Highlights extends Table {
  TextColumn get id => text()();
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();
  TextColumn get locatorJson => text()();
  TextColumn get selectedText => text().nullable()();
  TextColumn get color => text().map(highlightColorConverter)();
  TextColumn get note => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (json_valid(locator_json))',
    "CHECK (color IN ('yellow', 'green', 'blue', 'pink'))",
  ];
}

@DataClassName('CollectionRow')
class Collections extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (length(trim(name)) > 0)'];
}

@TableIndex(name: 'idx_collection_books_book', columns: {#bookId})
@DataClassName('CollectionBookRow')
class CollectionBooks extends Table {
  TextColumn get collectionId =>
      text().references(Collections, #id, onDelete: KeyAction.cascade)();
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();
  IntColumn get addedAt => integer()();

  @override
  Set<Column> get primaryKey => {collectionId, bookId};
}
