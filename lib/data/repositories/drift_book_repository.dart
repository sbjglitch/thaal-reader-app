import 'package:drift/drift.dart';

import '../../domain/entities/book.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/managed_path.dart';
import '../../domain/repositories/book_repository.dart';
import '../database/app_database.dart';
import 'database_support.dart';

class DriftBookRepository implements BookRepository {
  DriftBookRepository(this._db, {this._clock = DateTime.now});

  final AppDatabase _db;
  final Clock _clock;

  @override
  Stream<List<Book>> watchBooks() {
    final query = _db.select(_db.books)
      ..orderBy([(t) => OrderingTerm.desc(t.addedAt)]);
    return query.watch().map((rows) => rows.map(bookFromRow).toList());
  }

  @override
  Future<Book?> getBook(String bookId) => guardDatabase('getBook', () async {
    final row = await (_db.select(
      _db.books,
    )..where((t) => t.id.equals(bookId))).getSingleOrNull();
    return row == null ? null : bookFromRow(row);
  });

  @override
  Future<List<Book>> findBooksByChecksum(String checksum) =>
      guardDatabase('findBooksByChecksum', () async {
        final rows = await (_db.select(
          _db.books,
        )..where((t) => t.fileChecksum.equals(checksum))).get();
        return rows.map(bookFromRow).toList();
      });

  @override
  Future<void> addBook(Book book) => guardDatabase('addBook', () async {
    await _db
        .into(_db.books)
        .insert(
          BooksCompanion.insert(
            id: book.id,
            title: book.title,
            authorsJson: Value(book.authors),
            description: Value(book.description),
            language: Value(book.language),
            identifier: Value(book.identifier),
            publisher: Value(book.publisher),
            publishedAt: Value(book.publishedAt),
            format: book.format,
            filePath: book.filePath.value,
            coverPath: Value(book.coverPath?.value),
            fileSizeBytes: book.fileSizeBytes,
            fileChecksum: book.fileChecksum,
            readingStatus: Value(book.readingStatus),
            addedAt: toEpochMillis(book.addedAt),
            lastOpenedAt: Value(
              book.lastOpenedAt == null
                  ? null
                  : toEpochMillis(book.lastOpenedAt!),
            ),
            updatedAt: toEpochMillis(book.updatedAt),
            metadataJson: Value(book.metadataJson),
          ),
        );
  });

  @override
  Future<void> updateBookMetadata(Book book) =>
      guardDatabase('updateBookMetadata', () async {
        final count =
            await (_db.update(
              _db.books,
            )..where((t) => t.id.equals(book.id))).write(
              BooksCompanion(
                title: Value(book.title),
                authorsJson: Value(book.authors),
                description: Value(book.description),
                language: Value(book.language),
                identifier: Value(book.identifier),
                publisher: Value(book.publisher),
                publishedAt: Value(book.publishedAt),
                coverPath: Value(book.coverPath?.value),
                metadataJson: Value(book.metadataJson),
                updatedAt: Value(toEpochMillis(_clock())),
              ),
            );
        requireUpdated(count, 'updateBookMetadata');
      });

  @override
  Future<void> updateReadingStatus(String bookId, ReadingStatus status) =>
      guardDatabase('updateReadingStatus', () async {
        final count =
            await (_db.update(
              _db.books,
            )..where((t) => t.id.equals(bookId))).write(
              BooksCompanion(
                readingStatus: Value(status),
                updatedAt: Value(toEpochMillis(_clock())),
              ),
            );
        requireUpdated(count, 'updateReadingStatus');
      });

  /// Idempotent: removing a book that no longer exists succeeds, so cleanup
  /// and recovery workflows can safely retry.
  @override
  Future<void> recordOpened(String bookId, DateTime at) => guardDatabase(
    'recordOpened',
    () {
      return _db.transaction(() async {
        final count =
            await (_db.update(
              _db.books,
            )..where((t) => t.id.equals(bookId))).write(
              BooksCompanion(
                lastOpenedAt: Value(toEpochMillis(at)),
                updatedAt: Value(toEpochMillis(at)),
              ),
            );
        requireUpdated(count, 'recordOpened');
        await (_db.update(_db.books)..where(
              (t) =>
                  t.id.equals(bookId) &
                  t.readingStatus.equalsValue(ReadingStatus.unread),
            ))
            .write(
              const BooksCompanion(readingStatus: Value(ReadingStatus.reading)),
            );
      });
    },
  );

  @override
  Future<void> removeBook(String bookId) => guardDatabase('removeBook', () {
    return (_db.delete(_db.books)..where((t) => t.id.equals(bookId))).go();
  });
}

/// Maps a stored row to the domain entity. Visible for the other
/// repositories and tests in the data layer.
Book bookFromRow(BookRow row) {
  final coverPath = row.coverPath;
  return Book(
    id: row.id,
    title: row.title,
    authors: row.authorsJson,
    description: row.description,
    language: row.language,
    identifier: row.identifier,
    publisher: row.publisher,
    publishedAt: row.publishedAt,
    format: row.format,
    filePath: ManagedPath.parse(row.filePath),
    coverPath: coverPath == null ? null : ManagedPath.parse(coverPath),
    fileSizeBytes: row.fileSizeBytes,
    fileChecksum: row.fileChecksum,
    readingStatus: row.readingStatus,
    addedAt: fromEpochMillis(row.addedAt),
    lastOpenedAt: fromEpochMillisOrNull(row.lastOpenedAt),
    updatedAt: fromEpochMillis(row.updatedAt),
    metadataJson: row.metadataJson,
  );
}
