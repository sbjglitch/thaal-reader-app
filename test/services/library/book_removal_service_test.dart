import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/core/errors/app_errors.dart';
import 'package:thaal/core/logging/app_logger.dart';
import 'package:thaal/data/database/app_database.dart';
import 'package:thaal/data/repositories/drift_book_repository.dart';
import 'package:thaal/domain/entities/book.dart';
import 'package:thaal/domain/repositories/book_repository.dart';
import 'package:thaal/services/library/book_removal_service.dart';
import 'package:thaal/services/storage/library_storage.dart';

import '../../support/fixtures.dart';

class _FailingRemoveRepository implements BookRepository {
  @override
  Future<void> removeBook(String bookId) async =>
      throw const DatabaseError(DatabaseErrorKind.failure, 'fake');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory temp;
  late LibraryStorage storage;
  late AppDatabase db;
  late DriftBookRepository books;

  BookRemovalService service([BookRepository? repository]) =>
      BookRemovalService(
        storage: storage,
        books: repository ?? books,
        logger: AppLogger(sink: (_) {}),
      );

  Future<Book> addWithFiles(String id) async {
    final book = sampleBook(id: id);
    final file = storage.file(book.filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString('publication');
    await File('${file.parent.path}/cover.jpg').writeAsString('cover');
    await books.addBook(book);
    return book;
  }

  Future<List<FileSystemEntity>> staging() =>
      Directory('${storage.root.path}/staging').list().toList();

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('thaal_removal');
    storage = await LibraryStorage.open(Directory('${temp.path}/library'));
    db = openTestDatabase();
    books = DriftBookRepository(db);
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  test('removes the record and all of the book files', () async {
    final book = await addWithFiles('gone');
    final kept = await addWithFiles('kept');

    await service().removeBook(book.id);

    expect(await books.getBook('gone'), isNull);
    expect(
      await Directory('${storage.root.path}/books/gone').exists(),
      isFalse,
    );
    expect(await staging(), isEmpty);
    expect(await books.getBook('kept'), isNotNull);
    expect(await storage.exists(kept.filePath), isTrue);
  });

  test('a book whose files are already missing is still removed', () async {
    await books.addBook(sampleBook(id: 'orphan'));

    await service().removeBook('orphan');

    expect(await books.getBook('orphan'), isNull);
  });

  test('a failed database delete puts the files back', () async {
    final book = await addWithFiles('stays');

    await expectLater(
      service(_FailingRemoveRepository()).removeBook(book.id),
      throwsA(isA<DatabaseError>()),
    );

    expect(await books.getBook('stays'), isNotNull);
    expect(await storage.file(book.filePath).readAsString(), 'publication');
    expect(await staging(), isEmpty);
  });

  test('restoring refuses to overwrite files that reappeared', () async {
    final book = await addWithFiles('race');
    final area = await storage.moveBookToStaging(book.id);
    final reappeared = storage.file(book.filePath);
    await reappeared.parent.create(recursive: true);
    await reappeared.writeAsString('new');

    await expectLater(
      storage.restoreBookFromStaging(area!, book.id),
      throwsA(isA<StorageError>()),
    );
    expect(await reappeared.readAsString(), 'new');
  });
}
