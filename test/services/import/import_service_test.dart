import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/core/errors/app_errors.dart';
import 'package:thaal/core/logging/app_logger.dart';
import 'package:thaal/data/database/app_database.dart';
import 'package:thaal/data/repositories/drift_book_repository.dart';
import 'package:thaal/domain/entities/book.dart';
import 'package:thaal/domain/entities/enums.dart';
import 'package:thaal/domain/repositories/book_repository.dart';
import 'package:thaal/domain/services/publication_inspector.dart';
import 'package:thaal/services/import/document_picker.dart';
import 'package:thaal/services/import/import_service.dart';
import 'package:thaal/services/storage/library_storage.dart';

import '../../support/fixtures.dart';

/// Inspector double: returns [details], writes a cover when [writeCover] is
/// set, or throws [PublicationError] when [fail] is set.
class FakeInspector implements PublicationInspector {
  FakeInspector({this.details = const PublicationDetails(), this.fail = false});

  PublicationDetails details;
  bool fail;
  bool writeCover = false;
  String? coverOverride;
  int calls = 0;

  @override
  Future<PublicationDetails> inspect(
    String publicationPath, {
    required String coverDirectory,
  }) async {
    calls++;
    if (fail) {
      throw const PublicationError(PublicationErrorKind.unreadable, 'fake');
    }
    String? cover = coverOverride;
    if (writeCover) {
      cover = '$coverDirectory/cover.jpg';
      await File(cover).writeAsBytes([0xFF, 0xD8, 0xFF]);
    }
    return PublicationDetails(
      title: details.title,
      authors: details.authors,
      coverFilePath: cover,
    );
  }
}

/// Repository whose inserts always fail, to exercise rollback.
class FailingInsertRepository implements BookRepository {
  FailingInsertRepository(this._inner);

  final BookRepository _inner;

  @override
  Future<void> addBook(Book book) async =>
      throw const DatabaseError(DatabaseErrorKind.failure, 'fake');

  @override
  Future<List<Book>> findBooksByChecksum(String checksum) =>
      _inner.findBooksByChecksum(checksum);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory temp;
  late LibraryStorage storage;
  late AppDatabase db;
  late DriftBookRepository books;
  late FakeInspector inspector;
  var nextId = 0;

  ImportService service({BookRepository? repository}) => ImportService(
    storage: storage,
    books: repository ?? books,
    inspector: inspector,
    logger: AppLogger(sink: (_) {}),
    clock: () => fixedTime,
    newId: () => 'id-${++nextId}',
  );

  Future<ImportSource> sourceFile(String name, List<int> bytes) async {
    final file = File('${temp.path}/picked/$name');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    return ImportSource(name: name, path: file.path);
  }

  final epubBytes = [0x50, 0x4B, 0x03, 0x04, ...List.filled(64, 0x20)];
  final pdfBytes = '%PDF-1.4\n%fake\n'.codeUnits;

  Future<List<String>> stagingEntries() =>
      Directory('${storage.root.path}/staging')
          .list()
          .map((e) => e.path)
          .toList();

  Future<bool> bookDirExists(String id) =>
      Directory('${storage.root.path}/books/$id').exists();

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('thaal_import');
    storage = await LibraryStorage.open(Directory('${temp.path}/library'));
    db = openTestDatabase();
    books = DriftBookRepository(db);
    inspector = FakeInspector(
      details: const PublicationDetails(title: 'Declared', authors: ['Ann']),
    );
    nextId = 0;
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  test(
    'imports an EPUB: files in place, record saved, source untouched',
    () async {
      inspector.writeCover = true;
      final source = await sourceFile('My Book.epub', epubBytes);

      final result = await service().importFile(source);

      final book = (result as ImportSucceeded).book;
      expect(book.id, 'id-1');
      expect(book.title, 'Declared');
      expect(book.authors, ['Ann']);
      expect(book.format, PublicationFormat.epub);
      expect(book.filePath.value, 'books/id-1/publication.epub');
      expect(book.coverPath?.value, 'books/id-1/cover.jpg');
      expect(book.fileSizeBytes, epubBytes.length);
      expect(Book.isSha256Hex(book.fileChecksum), isTrue);
      expect(await storage.exists(book.filePath), isTrue);
      expect(await storage.exists(book.coverPath!), isTrue);
      expect((await books.getBook('id-1'))?.title, 'Declared');
      expect(await stagingEntries(), isEmpty);
      expect(await File(source.path!).readAsBytes(), epubBytes);
    },
  );

  test('imports a PDF and falls back to the file name for the title', () async {
    inspector.details = const PublicationDetails(title: '  ');
    final result = await service().importFile(
      await sourceFile('Annual Report.PDF', pdfBytes),
    );

    final book = (result as ImportSucceeded).book;
    expect(book.title, 'Annual Report');
    expect(book.format, PublicationFormat.pdf);
    expect(book.coverPath, isNull);
  });

  test('rejects unsupported extensions without writing anything', () async {
    final result = await service().importFile(
      await sourceFile('notes.txt', epubBytes),
    );

    expect(
      (result as ImportFailed).reason,
      ImportFailureReason.unsupportedFormat,
    );
    expect(await stagingEntries(), isEmpty);
    expect(inspector.calls, 0);
  });

  test('rejects content that does not match the format', () async {
    final result = await service().importFile(
      await sourceFile('fake.epub', pdfBytes),
    );

    expect((result as ImportFailed).reason, ImportFailureReason.invalidFile);
    expect(await stagingEntries(), isEmpty);
    expect(await books.watchBooks().first, isEmpty);
  });

  test('empty files are invalid', () async {
    final result = await service().importFile(await sourceFile('e.pdf', []));
    expect((result as ImportFailed).reason, ImportFailureReason.invalidFile);
  });

  test(
    'a file the reader engine cannot parse leaves no record or files',
    () async {
      inspector.fail = true;
      final result = await service().importFile(
        await sourceFile('broken.epub', epubBytes),
      );

      expect((result as ImportFailed).reason, ImportFailureReason.invalidFile);
      expect(await books.watchBooks().first, isEmpty);
      expect(await stagingEntries(), isEmpty);
      expect(
        await Directory('${storage.root.path}/books').list().toList(),
        isEmpty,
      );
    },
  );

  test('a failed database insert removes the moved files', () async {
    inspector.writeCover = true;
    final result = await service(repository: FailingInsertRepository(books))
        .importFile(await sourceFile('a.epub', epubBytes));

    expect((result as ImportFailed).reason, ImportFailureReason.failed);
    expect(await bookDirExists('id-1'), isFalse);
    expect(await stagingEntries(), isEmpty);
  });

  test('duplicates are reported, then imported only when allowed', () async {
    final source = await sourceFile('a.epub', epubBytes);
    await service().importFile(source);

    final second = await service().importFile(source);
    expect((second as ImportDuplicate).existing.single.id, 'id-1');
    expect(await books.watchBooks().first, hasLength(1));
    expect(await stagingEntries(), isEmpty);

    final third = await service().importFile(source, allowDuplicate: true);
    expect((third as ImportSucceeded).book.id, isNot('id-1'));
    expect(await books.watchBooks().first, hasLength(2));
  });

  test('a source without a readable path fails cleanly', () async {
    final result = await service().importFile(
      const ImportSource(name: 'cloud.epub', path: null),
    );
    expect((result as ImportFailed).reason, ImportFailureReason.failed);
  });

  test('a missing source file fails without leaving staging files', () async {
    final result = await service().importFile(
      ImportSource(name: 'gone.epub', path: '${temp.path}/gone.epub'),
    );
    expect((result as ImportFailed).reason, ImportFailureReason.failed);
    expect(await stagingEntries(), isEmpty);
  });

  test('ignores a cover path outside the staging area', () async {
    final outside = File('${temp.path}/elsewhere.jpg');
    await outside.writeAsBytes([1, 2, 3]);
    inspector.coverOverride = outside.path;

    final result = await service().importFile(
      await sourceFile('a.epub', epubBytes),
    );

    expect((result as ImportSucceeded).book.coverPath, isNull);
    expect(await outside.exists(), isTrue);
  });

  test('logs outcomes without file names or titles', () async {
    final records = <LogRecord>[];
    final logged = ImportService(
      storage: storage,
      books: books,
      inspector: inspector,
      logger: AppLogger(sink: records.add, minimumLevel: LogLevel.debug),
    );

    await logged.importFile(await sourceFile('Secret Title.epub', epubBytes));

    final line = records.single.toString();
    expect(line, contains('outcome=imported'));
    expect(line, isNot(contains('Secret')));
    expect(line, isNot(contains('Declared')));
    expect(line, isNot(contains(temp.path)));
  });
}
