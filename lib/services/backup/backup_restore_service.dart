import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../../core/errors/app_errors.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/entities/managed_path.dart';
import '../../domain/repositories/book_repository.dart';
import '../../domain/repositories/library_snapshot_repository.dart';
import '../storage/library_storage.dart';
import 'backup_archive.dart';
import 'backup_contents.dart';
import 'backup_format.dart';
import 'restore_plan.dart';

/// Why a file cannot be restored. Mapped to user wording in the UI.
enum RestoreRejection {
  /// Not a ZIP, not this app's format, or breaks the format rules.
  notBackup,

  /// Made by a newer app version.
  unsupportedVersion,

  /// Sizes or checksums do not match: the file is damaged.
  damaged,

  /// Larger than the restore limits allow.
  tooLarge,

  /// The file could not be read.
  unreadable,
}

sealed class RestoreInspection {
  const RestoreInspection();
}

/// A valid backup and what restoring it would do to the current library.
final class RestoreReady extends RestoreInspection {
  const RestoreReady({
    required this.archivePath,
    required this.contents,
    required this.plan,
  });

  final String archivePath;
  final BackupContents contents;
  final RestorePlan plan;
}

final class RestoreRejected extends RestoreInspection {
  const RestoreRejected(this.reason);

  final RestoreRejection reason;
}

sealed class RestoreOutcome {
  const RestoreOutcome();
}

/// Committed and verified. [plan] is what was applied, recomputed against
/// the library at commit time.
final class RestoreCompleted extends RestoreOutcome {
  const RestoreCompleted(this.plan, {required this.settingsApplied});

  final RestorePlan plan;

  /// Settings written from the backup, 0 if none were applied.
  final int settingsApplied;
}

enum RestoreFailure { insufficientStorage, failed }

/// Nothing was changed.
final class RestoreFailed extends RestoreOutcome {
  const RestoreFailed(this.reason);

  final RestoreFailure reason;
}

/// Merge restore from a `.readerbackup` file (BACKUP_FORMAT.md §8):
///
/// 1. [inspect]: verify the archive and every entry's SHA-256, parse and
///    validate the datasets, and plan the merge against the library. The
///    library is not touched.
/// 2. [restore]: extract the new books' files into one staging area per
///    book, verifying each again while writing. Write a journal naming
///    those books, move their directories into `books/`, then insert all
///    records in one transaction. Delete the journal.
/// 3. [recoverInterrupted] at startup: if a journal remains, the app
///    stopped mid-commit. Books the transaction did not insert have their
///    moved directories removed; the transaction is atomic, so the library
///    ends up as before the restore or with the whole restore.
///
/// Existing books, files and records are never changed or removed.
class BackupRestoreService {
  BackupRestoreService({
    required this._snapshots,
    required this._books,
    required this._storage,
    required this._applyPreferences,
    required this._logger,
    this._limits = const BackupLimits(),
  });

  final LibrarySnapshotRepository _snapshots;
  final BookRepository _books;
  final LibraryStorage _storage;
  final Future<int> Function(Map<String, Object?> records) _applyPreferences;
  final AppLogger _logger;
  final BackupLimits _limits;

  static const String journalName = 'restore-journal.json';

  File get _journal => File(p.join(_storage.root.path, journalName));

  Future<RestoreInspection> inspect(String archivePath) async {
    final stopwatch = Stopwatch()..start();
    final RestoreInspection result;
    try {
      final contents = await _load(archivePath, _limits);
      result = RestoreReady(
        archivePath: archivePath,
        contents: contents,
        plan: await _plan(contents),
      );
    } on BackupError catch (error) {
      return _rejected(error.kind, stopwatch);
    } on FileSystemException {
      return _rejected(null, stopwatch);
    } on StorageError {
      return _rejected(null, stopwatch);
    } catch (error, stackTrace) {
      _logger.error('restore.inspect_error', error, stackTrace: stackTrace);
      return _rejected(null, stopwatch);
    }
    final ready = result as RestoreReady;
    _logger.info(
      'restore.inspected',
      fields: {
        'outcome': 'ready',
        'type': ready.contents.manifest.type,
        'books': ready.contents.books.length,
        'new': ready.plan.booksToAdd.length,
        'skipped': ready.plan.skippedBooks.length,
        'elapsed': stopwatch.elapsed,
      },
    );
    return result;
  }

  RestoreRejected _rejected(BackupErrorKind? kind, Stopwatch stopwatch) {
    final reason = switch (kind) {
      BackupErrorKind.invalidArchive => RestoreRejection.notBackup,
      BackupErrorKind.unsupportedVersion => RestoreRejection.unsupportedVersion,
      BackupErrorKind.checksumMismatch => RestoreRejection.damaged,
      BackupErrorKind.limitExceeded => RestoreRejection.tooLarge,
      null => RestoreRejection.unreadable,
    };
    _logger.info(
      'restore.inspected',
      fields: {'outcome': reason, 'elapsed': stopwatch.elapsed},
    );
    return RestoreRejected(reason);
  }

  /// Applies [ready]. The plan is recomputed first, so changes made to the
  /// library since [inspect] are respected.
  Future<RestoreOutcome> restore(
    RestoreReady ready, {
    required bool applySettings,
  }) async {
    final stopwatch = Stopwatch()..start();
    final outcome = await _restore(ready, applySettings);
    _logger.info(
      'restore.finished',
      fields: switch (outcome) {
        RestoreCompleted(:final plan, :final settingsApplied) => {
          'outcome': 'completed',
          'books': plan.add.books.length,
          'missingFiles': plan.booksMissingFiles,
          'bookmarks': plan.add.bookmarks.length,
          'highlights': plan.add.highlights.length,
          'collections': plan.add.collections.length,
          'skippedBooks': plan.skippedBooks.length,
          'settings': settingsApplied,
          'elapsed': stopwatch.elapsed,
        },
        RestoreFailed(:final reason) => {
          'outcome': reason,
          'elapsed': stopwatch.elapsed,
        },
      },
    );
    return outcome;
  }

  Future<RestoreOutcome> _restore(
    RestoreReady ready,
    bool applySettings,
  ) async {
    // Areas holding each new book's extracted files, by book id.
    final areas = <String, ManagedPath>{};
    final moved = <String>[];
    var committed = false;
    try {
      final plan = await _plan(ready.contents);
      final requests = <ExtractRequest>[];
      for (final record in plan.booksToAdd) {
        final publication = record.publication;
        if (publication == null) continue;
        final area = await _storage.createStagingArea();
        areas[record.book.id] = area;
        requests.add(
          ExtractRequest(
            entry: publication,
            destinationPath: _staged(area, record.book.filePath),
          ),
        );
        if ((record.cover, record.book.coverPath) case (
          final cover?,
          final coverPath?,
        )) {
          requests.add(
            ExtractRequest(
              entry: cover,
              destinationPath: _staged(area, coverPath),
            ),
          );
        }
      }
      await _extract(ready.archivePath, requests);

      if (areas.isNotEmpty) await _writeJournal(areas);
      try {
        for (final MapEntry(key: bookId, value: area) in areas.entries) {
          await _storage.restoreBookFromStaging(area, bookId);
          moved.add(bookId);
        }
        await _verify(plan);
        await _snapshots.insertRecords(plan.add);
      } catch (_) {
        await _rollBack(moved);
        rethrow;
      }
      committed = true;
      await _deleteJournalQuietly();

      var settings = 0;
      final preferences = ready.contents.preferences;
      if (applySettings && preferences != null) {
        try {
          settings = await _applyPreferences(preferences);
        } catch (error, stackTrace) {
          // The library is restored; settings are a convenience.
          _logger.error(
            'restore.settings_failed',
            error,
            stackTrace: stackTrace,
          );
        }
      }
      return RestoreCompleted(plan, settingsApplied: settings);
    } on StorageError catch (error) {
      return RestoreFailed(
        error.kind == StorageErrorKind.insufficientSpace
            ? RestoreFailure.insufficientStorage
            : RestoreFailure.failed,
      );
    } catch (error, stackTrace) {
      _logger.error('restore.failed', error, stackTrace: stackTrace);
      return const RestoreFailed(RestoreFailure.failed);
    } finally {
      if (!committed && moved.isEmpty) await _deleteJournalQuietly();
      for (final area in areas.values) {
        try {
          await _storage.discardStagingArea(area);
        } on StorageError {
          // Left for startup staging cleanup.
        }
      }
    }
  }

  /// Removes the directories moved in before a failed commit. The journal
  /// is deleted only if that succeeded; otherwise startup recovery retries.
  Future<void> _rollBack(List<String> moved) async {
    try {
      for (final bookId in moved) {
        await _storage.deleteBookFiles(bookId);
      }
    } on StorageError catch (error, stackTrace) {
      _logger.error('restore.rollback_failed', error, stackTrace: stackTrace);
      return;
    }
    moved.clear();
    await _deleteJournalQuietly();
  }

  /// Finishes or rolls back a restore that was interrupted mid-commit.
  /// Safe to call when there is nothing to recover.
  Future<void> recoverInterrupted() async {
    final journal = _journal;
    if (!await journal.exists()) return;
    var removed = 0;
    var kept = 0;
    try {
      final areas = _readJournal(await journal.readAsString());
      for (final MapEntry(key: bookId, value: area) in areas.entries) {
        if (await _books.getBook(bookId) != null) {
          kept++;
        } else {
          // Only directories this restore moved in are listed, and only for
          // books that have no record, so nothing else is deleted.
          await _storage.deleteBookFiles(bookId);
          removed++;
        }
        try {
          await _storage.discardStagingArea(area);
        } on StorageError {
          // Left for staging cleanup.
        }
      }
      await journal.delete();
    } catch (error, stackTrace) {
      _logger.error('restore.recovery_failed', error, stackTrace: stackTrace);
      return;
    }
    _logger.warning(
      'restore.recovered',
      fields: {'removed': removed, 'kept': kept},
    );
  }

  Future<RestorePlan> _plan(BackupContents contents) async {
    final local = await _snapshots.readSnapshot();
    final occupied = <String>{};
    final localIds = {for (final book in local.books) book.id};
    for (final record in contents.books) {
      final id = record.book.id;
      if (localIds.contains(id)) continue;
      if (await Directory(_storage.file(_storage.bookDirectory(id)).path)
          .exists()) {
        occupied.add(id);
      }
    }
    return planRestore(contents, local, occupiedBookIds: occupied);
  }

  /// Checks, before the records are written, that every new book's file is
  /// where its record will point.
  Future<void> _verify(RestorePlan plan) async {
    for (final record in plan.booksToAdd) {
      if (record.publication == null) continue;
      final size = await _storage.fileSize(record.book.filePath);
      if (size != record.book.fileSizeBytes) {
        throw const StorageError(
          StorageErrorKind.missingFile,
          'restored file missing before commit',
        );
      }
    }
  }

  /// Path inside [area] for a book file at [target] (`books/<id>/<name>`),
  /// laid out as [LibraryStorage.restoreBookFromStaging] expects.
  String _staged(ManagedPath area, ManagedPath target) => _storage
      .file(ManagedPath.join([...area.segments, 'book', target.segments.last]))
      .path;

  Future<void> _writeJournal(Map<String, ManagedPath> areas) async {
    final temporary = File('${_journal.path}.tmp');
    try {
      await temporary.writeAsString(
        jsonEncode({
          'version': 1,
          'areas': {
            for (final MapEntry(:key, :value) in areas.entries)
              key: value.value,
          },
        }),
        flush: true,
      );
      // Rename is atomic, so a crash leaves either no journal or a whole one.
      await temporary.rename(_journal.path);
    } on FileSystemException catch (error) {
      throw _storageError(error);
    }
  }

  static Map<String, ManagedPath> _readJournal(String text) {
    final json = jsonDecode(text);
    if (json is! Map<String, Object?> || json['version'] != 1) {
      throw const FormatException('unknown restore journal');
    }
    final areas = json['areas'];
    if (areas is! Map<String, Object?>) {
      throw const FormatException('malformed restore journal');
    }
    return {
      for (final MapEntry(:key, :value) in areas.entries)
        if (RegExp(r'^[A-Za-z0-9-]{1,64}$').hasMatch(key) && value is String)
          key: ManagedPath.parse(value),
    };
  }

  Future<void> _deleteJournal() async {
    try {
      if (await _journal.exists()) await _journal.delete();
    } on FileSystemException catch (error) {
      throw _storageError(error);
    }
  }

  Future<void> _deleteJournalQuietly() async {
    try {
      await _deleteJournal();
    } on StorageError {
      // A stale journal only lists books without records, whose directories
      // were already removed; recovery at startup finishes the cleanup.
    }
  }

  // Isolate bodies are built in static methods so the closures capture only
  // their arguments.
  static Future<BackupContents> _load(String path, BackupLimits limits) =>
      _run(() {
        final loaded = loadBackupData(path, limits: limits);
        return parseBackupContents(loaded.manifest, loaded.datasets);
      });

  static Future<void> _extract(String path, List<ExtractRequest> requests) =>
      requests.isEmpty
      ? Future.value()
      : _run(() => extractBackupEntries(path, requests));

  static Future<T> _run<T>(T Function() body) => Isolate.run(() {
    try {
      return body();
    } on FileSystemException catch (error) {
      throw _storageError(error);
    }
  });

  // ENOSPC on Linux/Android and Darwin.
  static const int _errnoNoSpace = 28;

  static StorageError _storageError(FileSystemException error) => StorageError(
    error.osError?.errorCode == _errnoNoSpace
        ? StorageErrorKind.insufficientSpace
        : StorageErrorKind.ioFailure,
    'restore file operation failed',
  );
}
