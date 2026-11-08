import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaal/core/errors/app_errors.dart';
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
import 'package:thaal/domain/entities/library_snapshot.dart';
import 'package:thaal/domain/entities/managed_path.dart';
import 'package:thaal/domain/entities/reading_data.dart';
import 'package:thaal/domain/repositories/library_snapshot_repository.dart';
import 'package:thaal/services/backup/backup_export_service.dart';
import 'package:thaal/services/backup/backup_format.dart';
import 'package:thaal/services/backup/backup_restore_service.dart';
import 'package:thaal/services/backup/backup_saver.dart';
import 'package:thaal/services/backup/restore_plan.dart';
import 'package:thaal/services/storage/library_storage.dart';

import '../../support/fixtures.dart';
import 'backup_test_support.dart';

/// One app install: database, storage and preferences.
class Install {
  Install._(this.db, this.storage, this.root);

  final AppDatabase db;
  final LibraryStorage storage;
  final Directory root;

  static Future<Install> create(Directory parent, String name) async {
    final root = Directory('${parent.path}/$name')..createSync();
    return Install._(
      openTestDatabase(),
      await LibraryStorage.open(Directory('${root.path}/library')),
      root,
    );
  }

  LibrarySnapshotRepository get snapshots => DriftLibrarySnapshotRepository(db);

  Future<LibrarySnapshot> snapshot() => snapshots.readSnapshot();

  Future<Book> addBook(
    String id,
    List<int> bytes, {
    List<int>? cover,
    String? title,
  }) async {
    final path = storage.publicationPath(id, PublicationFormat.epub);
    await storage.file(path).parent.create(recursive: true);
    await storage.file(path).writeAsBytes(bytes);
    ManagedPath? coverPath;
    if (cover != null) {
      coverPath = ManagedPath.join(['books', id, 'cover.png']);
      await storage.file(coverPath).writeAsBytes(cover);
    }
    final book = Book(
      id: id,
      title: title ?? 'Title $id',
      authors: const ['Author'],
      format: PublicationFormat.epub,
      filePath: path,
      coverPath: coverPath,
      fileSizeBytes: bytes.length,
      fileChecksum: sha256Of(bytes),
      addedAt: fixedTime,
      updatedAt: fixedTime,
    );
    await DriftBookRepository(db).addBook(book);
    return book;
  }

  Future<void> addReadingData(String bookId, {String suffix = ''}) async {
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
        id: 'bm-$bookId$suffix',
        bookId: bookId,
        locator: sampleLocator(),
        label: 'Mark',
        createdAt: fixedTime,
        updatedAt: fixedTime,
      ),
    );
    await DriftHighlightRepository(db).addHighlight(
      Highlight(
        id: 'hl-$bookId$suffix',
        bookId: bookId,
        locator: sampleLocator(),
        selectedText: 'Selected',
        color: HighlightColor.blue,
        note: 'Note',
        createdAt: fixedTime,
        updatedAt: fixedTime,
      ),
    );
  }

  Future<void> close() => db.close();
}

class _CopySaver implements BackupSaver {
  _CopySaver(this.destination);

  final String destination;

  @override
  bool get isSupported => true;

  @override
  Future<String?> save(File file, {required String suggestedName}) async {
    await file.copy(destination);
    return suggestedName;
  }
}

/// Fails the record insert after the files have been moved.
class _FailingInsert implements LibrarySnapshotRepository {
  _FailingInsert(this._inner);

  final LibrarySnapshotRepository _inner;

  @override
  Future<LibrarySnapshot> readSnapshot() => _inner.readSnapshot();

  @override
  Future<void> insertRecords(LibrarySnapshot records) async =>
      throw const DatabaseError(DatabaseErrorKind.failure, 'fake');
}

void main() {
  late Directory temp;
  late Install source;
  late Install target;
  late List<LogRecord> logs;

  // Two installs, so two separate in-memory databases on purpose.
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() async {
    temp = createTempDir();
    source = await Install.create(temp, 'source');
    target = await Install.create(temp, 'target');
    logs = [];
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await source.close();
    await target.close();
    temp.deleteSync(recursive: true);
  });

  AppLogger logger() => AppLogger(sink: logs.add, minimumLevel: LogLevel.debug);

  Future<String> exportFrom(
    Install install,
    BackupType type, {
    Map<String, Object> preferences = const {},
  }) async {
    final path = '${temp.path}/${type.wireName}.readerbackup';
    final result = await BackupExportService(
      snapshots: install.snapshots,
      storage: install.storage,
      saver: _CopySaver(path),
      appInfo: () async => const BackupAppInfo(
        name: 'Thaal',
        version: '1.0.0',
        buildNumber: '1',
      ),
      readPreferences: () => preferences,
      logger: logger(),
    ).export(type, includeSettings: preferences.isNotEmpty);
    expect(result, isA<BackupExportSaved>());
    return path;
  }

  BackupRestoreService restorer(
    Install install, {
    LibrarySnapshotRepository? snapshots,
    Future<int> Function(Map<String, Object?>)? applyPreferences,
  }) => BackupRestoreService(
    snapshots: snapshots ?? install.snapshots,
    books: DriftBookRepository(install.db),
    storage: install.storage,
    applyPreferences: applyPreferences ?? (_) async => 0,
    logger: logger(),
  );

  Future<RestoreReady> inspect(
    BackupRestoreService service,
    String path,
  ) async => await service.inspect(path) as RestoreReady;

  Future<List<FileSystemEntity>> stagingOf(Install install) =>
      Directory('${install.root.path}/library/staging').list().toList();

  File journalOf(Install install) =>
      File('${install.root.path}/library/${BackupRestoreService.journalName}');

  test(
    'a full backup restores every record and file on a new install',
    () async {
      final epub = List<int>.generate(150000, (i) => (i * 7) % 256);
      await source.addBook('book-a', epub, cover: [0x89, 0x50, 0x4E, 0x47]);
      await source.addBook('book-b', utf8.encode('second book'));
      await source.addReadingData('book-a');
      final collections = DriftCollectionRepository(source.db);
      await collections.createCollection(
        Collection(
          id: 'col',
          name: 'Shelf',
          createdAt: fixedTime,
          updatedAt: fixedTime,
        ),
      );
      await collections.addBookToCollection('col', 'book-b');
      final path = await exportFrom(source, BackupType.full);

      final service = restorer(target);
      final ready = await inspect(service, path);
      expect(ready.plan.booksToAdd, hasLength(2));
      expect(ready.plan.skippedBooks, isEmpty);
      final outcome = await service.restore(ready, applySettings: false);

      expect(outcome, isA<RestoreCompleted>());
      final before = await source.snapshot();
      final after = await target.snapshot();
      expect(
        after.books.map((b) => (b.id, b.title, b.fileChecksum, b.coverPath)),
        before.books.map((b) => (b.id, b.title, b.fileChecksum, b.coverPath)),
      );
      expect(after.progress.single.locator, before.progress.single.locator);
      expect(after.progress.single.progression, 0.5);
      expect(after.bookmarks.single.locator, before.bookmarks.single.locator);
      expect(after.highlights.single.note, 'Note');
      expect(after.collections.single.name, 'Shelf');
      expect(
        after.memberships.single.addedAt,
        before.memberships.single.addedAt,
      );

      final restored = target.storage.file(after.books.first.filePath);
      expect(sha256Of(restored.readAsBytesSync()), sha256Of(epub));
      expect(
        target.storage.file(after.books.first.coverPath!).readAsBytesSync(),
        [0x89, 0x50, 0x4E, 0x47],
      );
      expect(await stagingOf(target), isEmpty);
      expect(journalOf(target).existsSync(), isFalse);
    },
  );

  test(
    'a library-only restore keeps the records and marks files missing',
    () async {
      await source.addBook('book-a', utf8.encode('epub'));
      await source.addReadingData('book-a');
      final path = await exportFrom(source, BackupType.libraryOnly);

      final service = restorer(target);
      final ready = await inspect(service, path);
      expect(ready.plan.booksMissingFiles, 1);
      final outcome = await service.restore(ready, applySettings: false);

      expect(outcome, isA<RestoreCompleted>());
      final book = (await target.snapshot()).books.single;
      expect(book.filePath.value, 'books/book-a/publication.epub');
      expect(await target.storage.exists(book.filePath), isFalse);
      expect(book.coverPath, isNull);
      expect((await target.snapshot()).bookmarks, hasLength(1));
    },
  );

  test(
    'merging keeps local data, adds new records and skips conflicts',
    () async {
      await source.addBook('same', utf8.encode('same file'));
      await source.addBook('changed', utf8.encode('backup version'));
      await source.addBook('dup-in-backup', utf8.encode('shared file'));
      await source.addBook('new', utf8.encode('new file'));
      await source.addReadingData('same', suffix: '-1');
      final path = await exportFrom(source, BackupType.full);

      await target.addBook('same', utf8.encode('same file'));
      await target.addBook('changed', utf8.encode('local version'));
      await target.addBook('dup-local', utf8.encode('shared file'));
      await DriftReadingProgressRepository(target.db).saveProgress(
        ReadingProgress(bookId: 'same', progression: 0.9, updatedAt: fixedTime),
      );
      final localBefore = await target.snapshot();

      final service = restorer(target);
      final ready = await inspect(service, path);
      final plan = ready.plan;
      expect(plan.booksToAdd.map((r) => r.book.id), ['new']);
      expect(plan.booksAlreadyPresent, 1);
      expect(
        {for (final s in plan.skippedBooks) s.book.id: s.reason},
        {
          'changed': RestoreBookConflict.differentFile,
          'dup-in-backup': RestoreBookConflict.duplicate,
        },
      );
      expect(plan.keptProgress, 1);

      await service.restore(ready, applySettings: false);
      final after = await target.snapshot();
      expect(after.books.map((b) => b.id).toSet(), {
        'same',
        'changed',
        'dup-local',
        'new',
      });
      // The local file and progress are untouched.
      expect(
        after.books.firstWhere((b) => b.id == 'changed').fileChecksum,
        localBefore.books.firstWhere((b) => b.id == 'changed').fileChecksum,
      );
      expect(after.progress.single.progression, 0.9);
      // Annotations of the book already present are merged in.
      expect(after.bookmarks.map((b) => b.id), ['bm-same-1']);

      // Restoring the same backup again adds nothing.
      final again = await inspect(service, path);
      expect(again.plan.hasChanges, isFalse);
    },
  );

  test('a failed commit removes moved files and changes nothing', () async {
    await source.addBook('book-a', utf8.encode('epub'));
    final path = await exportFrom(source, BackupType.full);

    final service = restorer(
      target,
      snapshots: _FailingInsert(target.snapshots),
    );
    final outcome = await service.restore(
      await inspect(service, path),
      applySettings: false,
    );

    expect(
      outcome,
      isA<RestoreFailed>().having(
        (o) => o.reason,
        'reason',
        RestoreFailure.failed,
      ),
    );
    expect((await target.snapshot()).books, isEmpty);
    expect(
      Directory('${target.root.path}/library/books/book-a').existsSync(),
      isFalse,
    );
    expect(journalOf(target).existsSync(), isFalse);
    expect(await stagingOf(target), isEmpty);
  });

  test('startup recovery removes files of an uncommitted restore', () async {
    await target.addBook('kept', utf8.encode('committed'));
    final orphan = Directory('${target.root.path}/library/books/orphan')
      ..createSync(recursive: true);
    File('${orphan.path}/publication.epub').writeAsStringSync('partial');
    final area = await target.storage.createStagingArea();
    journalOf(target).writeAsStringSync(
      jsonEncode({
        'version': 1,
        'areas': {'kept': area.value, 'orphan': area.value},
      }),
    );

    await restorer(target).recoverInterrupted();

    expect(orphan.existsSync(), isFalse);
    expect(
      await target.storage.exists(
        target.storage.publicationPath('kept', PublicationFormat.epub),
      ),
      isTrue,
    );
    expect(journalOf(target).existsSync(), isFalse);
    expect(logs.any((r) => r.event == 'restore.recovered'), isTrue);
  });

  test('recovery without a journal does nothing', () async {
    await restorer(target).recoverInterrupted();
    expect(logs, isEmpty);
  });

  test(
    'a damaged or foreign file is rejected before anything changes',
    () async {
      await source.addBook('book-a', utf8.encode('epub'));
      final path = await exportFrom(source, BackupType.full);
      final bytes = File(path).readAsBytesSync();
      final at = latin1.decode(bytes).indexOf('epub', bytes.length ~/ 2);
      bytes[at] ^= 0x20;
      File(path).writeAsBytesSync(bytes);

      final service = restorer(target);
      final damaged = await service.inspect(path);
      expect(damaged, isA<RestoreRejected>());

      File(path).writeAsStringSync('hello');
      expect(
        await service.inspect(path),
        isA<RestoreRejected>().having(
          (r) => r.reason,
          'reason',
          RestoreRejection.notBackup,
        ),
      );
      expect((await target.snapshot()).books, isEmpty);
    },
  );

  test('settings are applied only when asked, and only valid ones', () async {
    await source.addBook('book-a', utf8.encode('epub'));
    final path = await exportFrom(
      source,
      BackupType.libraryOnly,
      preferences: {'app.theme': 'dark', 'reader.epub.fontScale': 1.5},
    );
    final prefs = await SharedPreferences.getInstance();
    final service = restorer(
      target,
      applyPreferences: prefs.applyBackupPreferences,
    );

    final first = await service.restore(
      await inspect(service, path),
      applySettings: false,
    );
    expect((first as RestoreCompleted).settingsApplied, 0);
    expect(prefs.getString('app.theme'), isNull);

    final second = await service.restore(
      await inspect(service, path),
      applySettings: true,
    );
    expect((second as RestoreCompleted).settingsApplied, 2);
    expect(prefs.getString('app.theme'), 'dark');
    expect(prefs.getDouble('reader.epub.fontScale'), 1.5);
  });

  test('logs carry no titles or paths', () async {
    await source.addBook('book-a', utf8.encode('epub'), title: 'Secret Title');
    final path = await exportFrom(source, BackupType.full);
    final service = restorer(target);
    await service.restore(await inspect(service, path), applySettings: false);
    final text = logs.map((r) => '${r.event} ${r.fields}').join('\n');
    expect(text, isNot(contains('Secret Title')));
    expect(text, isNot(contains(temp.path)));
  });
}
