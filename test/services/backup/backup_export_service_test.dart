import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaal/core/logging/app_logger.dart';
import 'package:thaal/data/database/app_database.dart';
import 'package:thaal/data/preferences/backup_preferences.dart';
import 'package:thaal/data/repositories/drift_book_repository.dart';
import 'package:thaal/data/repositories/drift_bookmark_repository.dart';
import 'package:thaal/data/repositories/drift_collection_repository.dart';
import 'package:thaal/data/repositories/drift_highlight_repository.dart';
import 'package:thaal/data/repositories/drift_library_snapshot_repository.dart';
import 'package:thaal/data/repositories/drift_reading_progress_repository.dart';
import 'package:thaal/domain/entities/book.dart';
import 'package:thaal/domain/entities/enums.dart';
import 'package:thaal/domain/entities/managed_path.dart';
import 'package:thaal/domain/entities/reading_data.dart';
import 'package:thaal/services/backup/backup_archive.dart';
import 'package:thaal/services/backup/backup_export_service.dart';
import 'package:thaal/services/backup/backup_format.dart';
import 'package:thaal/services/backup/backup_saver.dart';
import 'package:thaal/services/storage/library_storage.dart';

import '../../support/fixtures.dart';
import 'backup_test_support.dart';

/// Copies the archive to [destination], like the system dialog would, or
/// simulates a cancel or a failed write.
class FakeSaver implements BackupSaver {
  FakeSaver(this.destination);

  final String destination;
  bool cancel = false;
  BackupSaveException? failure;
  String? suggestedName;
  int calls = 0;

  @override
  bool get isSupported => true;

  @override
  Future<String?> save(File file, {required String suggestedName}) async {
    calls++;
    this.suggestedName = suggestedName;
    if (failure case final failure?) throw failure;
    if (cancel) return null;
    await file.copy(destination);
    return 'Saved name.readerbackup';
  }
}

void main() {
  late Directory temp;
  late AppDatabase db;
  late LibraryStorage storage;
  late SharedPreferences prefs;
  late FakeSaver saver;
  late List<LogRecord> logs;
  late BackupExportService service;
  late String saved;

  final created = DateTime.utc(2026, 11, 8, 9, 30, 15);

  setUp(() async {
    temp = createTempDir();
    db = openTestDatabase();
    storage = await LibraryStorage.open(Directory('${temp.path}/library'));
    SharedPreferences.setMockInitialValues({
      'app.theme': 'dark',
      'reader.epub.fontScale': 1.25,
      'library.sort': 'title',
      // Not allowlisted: must never be exported.
      'other.secret': 'value',
      // Allowlisted key with the wrong type is skipped.
      'reader.theme': 3,
    });
    prefs = await SharedPreferences.getInstance();
    saved = '${temp.path}/saved.readerbackup';
    saver = FakeSaver(saved);
    logs = [];
    service = BackupExportService(
      snapshots: DriftLibrarySnapshotRepository(db),
      storage: storage,
      saver: saver,
      appInfo: () async => const BackupAppInfo(
        name: 'Thaal',
        version: '1.2.3',
        buildNumber: '7',
      ),
      readPreferences: () => BackupPreferences.read(prefs),
      logger: AppLogger(sink: logs.add, minimumLevel: LogLevel.debug),
      clock: () => created,
    );
  });

  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  /// Adds a book whose library file holds [bytes].
  Future<Book> addBook(
    String id,
    List<int> bytes, {
    PublicationFormat format = PublicationFormat.epub,
    List<int>? cover,
  }) async {
    final path = storage.publicationPath(id, format);
    await storage.file(path).parent.create(recursive: true);
    await storage.file(path).writeAsBytes(bytes);
    ManagedPath? coverPath;
    if (cover != null) {
      coverPath = ManagedPath.join(['books', id, 'cover.jpg']);
      await storage.file(coverPath).writeAsBytes(cover);
    }
    final book = Book(
      id: id,
      title: 'Title $id',
      authors: const ['Author'],
      format: format,
      filePath: path,
      coverPath: coverPath,
      fileSizeBytes: bytes.length,
      fileChecksum: sha256Of(bytes),
      readingStatus: ReadingStatus.reading,
      addedAt: fixedTime,
      lastOpenedAt: fixedTime,
      updatedAt: fixedTime,
    );
    await DriftBookRepository(db).addBook(book);
    return book;
  }

  Future<void> addReadingData(String bookId) async {
    await DriftReadingProgressRepository(db).saveProgress(
      ReadingProgress(
        bookId: bookId,
        locator: sampleLocator(href: 'ch3.xhtml'),
        progression: 0.5,
        updatedAt: fixedTime,
      ),
    );
    await DriftBookmarkRepository(db).addBookmark(
      Bookmark(
        id: 'bm-1',
        bookId: bookId,
        locator: sampleLocator(),
        label: 'Mark',
        createdAt: fixedTime,
        updatedAt: fixedTime,
      ),
    );
    await DriftHighlightRepository(db).addHighlight(
      Highlight(
        id: 'hl-1',
        bookId: bookId,
        locator: sampleLocator(),
        selectedText: 'Selected',
        color: HighlightColor.green,
        note: 'A note',
        createdAt: fixedTime,
        updatedAt: fixedTime,
      ),
    );
    final collections = DriftCollectionRepository(db);
    await collections.createCollection(
      Collection(
        id: 'col-1',
        name: 'Favourites',
        createdAt: fixedTime,
        updatedAt: fixedTime,
      ),
    );
    await collections.addBookToCollection('col-1', bookId);
  }

  /// The saved archive's entries, decoded.
  Map<String, List<int>> savedEntries() {
    final input = InputFileStream(saved);
    try {
      final archive = ZipDecoder().decodeStream(input);
      return {for (final file in archive.files) file.name: file.content};
    } finally {
      input.closeSync();
    }
  }

  List<Object?> records(Map<String, List<int>> entries, String path) =>
      (jsonDecode(utf8.decode(entries[path]!))
              as Map<String, Object?>)['records']!
          as List<Object?>;

  Future<List<FileSystemEntity>> stagingLeft() =>
      Directory('${temp.path}/library/staging').list().toList();

  test('a full backup contains every dataset, file and checksum', () async {
    final epub = utf8.encode('PK epub bytes');
    final pdf = List<int>.generate(200000, (i) => i % 256);
    final book = await addBook('book-a', epub, cover: [0xFF, 0xD8, 1]);
    await addBook('book-b', pdf, format: PublicationFormat.pdf);
    await addReadingData(book.id);

    final result = await service.export(BackupType.full, includeSettings: true);

    expect(result, isA<BackupExportSaved>());
    expect(
      saver.suggestedName,
      'reader-backup-20261108-093015-full.readerbackup',
    );
    final manifest = verifyBackupArchive(saved);
    expect(manifest.type, BackupType.full);
    expect(manifest.app.version, '1.2.3');
    expect(manifest.counts, {
      'books': 2,
      'readingProgress': 1,
      'bookmarks': 1,
      'highlights': 1,
      'collections': 1,
      'collectionBooks': 1,
    });
    expect(manifest.preferencesIncluded, isTrue);

    final entries = savedEntries();
    expect(entries.keys.first, BackupFormat.manifestPath);
    expect(entries['files/books/book-a/publication.epub'], epub);
    expect(entries['files/books/book-b/publication.pdf'], pdf);
    expect(entries['files/covers/book-a.jpg'], [0xFF, 0xD8, 1]);
    expect(entries.keys.where((k) => k.startsWith('files/')), hasLength(3));

    final books = records(entries, BackupFormat.booksPath);
    final a = books.first! as Map<String, Object?>;
    expect(a['id'], 'book-a');
    expect(a['file'], {
      'included': true,
      'archivePath': 'files/books/book-a/publication.epub',
      'sizeBytes': epub.length,
      'sha256': sha256Of(epub),
    });
    expect(a['readingStatus'], 'reading');
    expect(a['addedAt'], '2026-11-07T12:00:00.000Z');
    // No device paths anywhere in the data.
    for (final path in BackupFormat.requiredDataPaths) {
      expect(utf8.decode(entries[path]!), isNot(contains(temp.path)));
    }

    final progress =
        records(entries, BackupFormat.progressPath).single!
            as Map<String, Object?>;
    expect(
      progress['locator'],
      jsonDecode(sampleLocator(href: 'ch3.xhtml').json),
    );
    final highlight =
        records(entries, BackupFormat.highlightsPath).single!
            as Map<String, Object?>;
    expect(highlight['note'], 'A note');
    expect(highlight['color'], 'green');

    final preferences = (jsonDecode(
      utf8.decode(entries[BackupFormat.preferencesPath]!),
    ) as Map<String, Object?>)['records'];
    expect(preferences, {
      'app.theme': 'dark',
      'reader.epub.fontScale': 1.25,
      'library.sort': 'title',
    });

    expect(await stagingLeft(), isEmpty);
    final finished = logs.singleWhere(
      (r) => r.event == 'backup.export_finished',
    );
    expect(finished.fields['outcome'], 'saved');
  });

  test('a library-only backup has no files and marks them excluded', () async {
    await addBook('book-a', utf8.encode('epub'), cover: [1, 2]);

    final result = await service.export(
      BackupType.libraryOnly,
      includeSettings: false,
    );

    expect(result, isA<BackupExportSaved>());
    final manifest = verifyBackupArchive(saved);
    expect(manifest.type, BackupType.libraryOnly);
    expect(manifest.preferencesIncluded, isFalse);
    final entries = savedEntries();
    expect(entries.keys, [
      BackupFormat.manifestPath,
      ...BackupFormat.requiredDataPaths,
    ]);
    final book =
        records(entries, BackupFormat.booksPath).single!
            as Map<String, Object?>;
    expect(book['file'], {'included': false});
    expect(book['cover'], isNull);
    expect(book['fileChecksum'], sha256Of(utf8.encode('epub')));
    expect(saver.suggestedName, endsWith('-library.readerbackup'));
  });

  test('an empty library can be backed up', () async {
    final result = await service.export(BackupType.full, includeSettings: true);
    expect(result, isA<BackupExportSaved>());
    expect(verifyBackupArchive(saved).counts['books'], 0);
  });

  test('a full backup stops when a book file is missing', () async {
    final missing = await addBook('book-a', utf8.encode('epub'));
    await addBook('book-b', utf8.encode('fine'));
    await storage.file(missing.filePath).delete();

    final result = await service.export(BackupType.full, includeSettings: true);

    expect((result as BackupExportIncomplete).books.map((b) => b.id), [
      'book-a',
    ]);
    expect(saver.calls, 0);
    expect(await stagingLeft(), isEmpty);
  });

  test('a full backup stops when a book file has changed', () async {
    final book = await addBook('book-a', utf8.encode('original'));
    await storage.file(book.filePath).writeAsString('tampered');

    final result = await service.export(BackupType.full, includeSettings: true);

    expect(result, isA<BackupExportIncomplete>());
    expect(saver.calls, 0);
  });

  test('a library-only backup ignores missing files', () async {
    final book = await addBook('book-a', utf8.encode('epub'));
    await storage.file(book.filePath).delete();

    final result = await service.export(
      BackupType.libraryOnly,
      includeSettings: true,
    );

    expect(result, isA<BackupExportSaved>());
  });

  test('cancelling the save dialog cleans up', () async {
    await addBook('book-a', utf8.encode('epub'));
    saver.cancel = true;

    final result = await service.export(BackupType.full, includeSettings: true);

    expect(result, isA<BackupExportCancelled>());
    expect(File(saved).existsSync(), isFalse);
    expect(await stagingLeft(), isEmpty);
  });

  test('a failed save is reported, with out-of-space kept apart', () async {
    saver.failure = const BackupSaveException(outOfSpace: true);
    expect(
      await service.export(BackupType.libraryOnly, includeSettings: true),
      isA<BackupExportFailed>().having(
        (r) => r.reason,
        'reason',
        BackupExportFailure.insufficientStorage,
      ),
    );
    saver.failure = const BackupSaveException(outOfSpace: false);
    expect(
      await service.export(BackupType.libraryOnly, includeSettings: true),
      isA<BackupExportFailed>().having(
        (r) => r.reason,
        'reason',
        BackupExportFailure.failed,
      ),
    );
    expect(await stagingLeft(), isEmpty);
  });

  test('logs carry no titles, notes or paths', () async {
    await addBook('book-a', utf8.encode('epub'));
    await addReadingData('book-a');
    await service.export(BackupType.full, includeSettings: true);
    final text = logs.map((r) => '${r.event} ${r.fields}').join('\n');
    expect(text, isNot(contains('Title')));
    expect(text, isNot(contains('A note')));
    expect(text, isNot(contains(temp.path)));
  });
}
