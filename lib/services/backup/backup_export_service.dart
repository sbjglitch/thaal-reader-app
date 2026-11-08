import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../core/errors/app_errors.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utils/clock.dart';
import '../../domain/entities/book.dart';
import '../../domain/entities/library_snapshot.dart';
import '../../domain/entities/locator_envelope.dart';
import '../../domain/entities/managed_path.dart';
import '../../domain/repositories/library_snapshot_repository.dart';
import '../storage/library_storage.dart';
import 'backup_archive.dart';
import 'backup_datasets.dart';
import 'backup_format.dart';
import 'backup_saver.dart';

/// Outcome of creating a backup.
sealed class BackupExportResult {
  const BackupExportResult();
}

/// Saved through the system dialog under [fileName].
final class BackupExportSaved extends BackupExportResult {
  const BackupExportSaved(this.fileName);

  final String fileName;
}

/// The user closed the save dialog. Nothing was written.
final class BackupExportCancelled extends BackupExportResult {
  const BackupExportCancelled();
}

/// A full backup was not created because these books' files are missing or
/// no longer match the library record (BACKUP_FORMAT.md §7.2).
final class BackupExportIncomplete extends BackupExportResult {
  const BackupExportIncomplete(this.books);

  final List<Book> books;
}

enum BackupExportFailure { insufficientStorage, failed }

final class BackupExportFailed extends BackupExportResult {
  const BackupExportFailed(this.reason);

  final BackupExportFailure reason;
}

/// Creates full and library-only backups (BACKUP_FORMAT.md §7):
///
/// 1. Read every record in one transaction.
/// 2. For a full backup, hash each publication and cover. A book whose file
///    is missing or differs from its stored checksum stops the backup.
/// 3. Write the datasets and `manifest.json` into a staging workspace, then
///    the ZIP: manifest first, datasets, publications, covers. Publication
///    bytes are stored straight from the library, not copied first; the
///    verification in step 4 rehashes the archived bytes, so a file that
///    changed while it was being archived is still caught.
/// 4. Reopen the archive and verify it as a restore would.
/// 5. Hand it to the system save dialog.
///
/// The workspace is removed afterwards in every case; anything a crash
/// leaves behind is removed by startup staging cleanup.
class BackupExportService {
  BackupExportService({
    required this._snapshots,
    required this._storage,
    required this._saver,
    required this._appInfo,
    required this._readPreferences,
    required this._logger,
    this._clock = DateTime.now,
  });

  final LibrarySnapshotRepository _snapshots;
  final LibraryStorage _storage;
  final BackupSaver _saver;
  final Future<BackupAppInfo> Function() _appInfo;
  final Map<String, Object> Function() _readPreferences;
  final AppLogger _logger;
  final Clock _clock;

  Future<BackupExportResult> export(
    BackupType type, {
    required bool includeSettings,
  }) async {
    final stopwatch = Stopwatch()..start();
    var archiveBytes = 0;
    var books = 0;
    final result = await () async {
      ManagedPath? area;
      try {
        final snapshot = await _snapshots.readSnapshot();
        books = snapshot.books.length;
        area = await _storage.createStagingArea();
        final workspace = _storage.file(area).path;
        final built = await _build(snapshot, type, includeSettings, workspace);
        if (built case _Incomplete(:final books)) {
          return BackupExportIncomplete(books);
        }
        final archive = (built as _Built).archive;
        archiveBytes = await archive.length();
        final saved = await _saver.save(
          archive,
          suggestedName: BackupFormat.fileName(type, built.createdAt),
        );
        return saved == null
            ? const BackupExportCancelled()
            : BackupExportSaved(saved);
      } on BackupSaveException catch (error) {
        return BackupExportFailed(
          error.outOfSpace
              ? BackupExportFailure.insufficientStorage
              : BackupExportFailure.failed,
        );
      } on StorageError catch (error) {
        return BackupExportFailed(
          error.kind == StorageErrorKind.insufficientSpace
              ? BackupExportFailure.insufficientStorage
              : BackupExportFailure.failed,
        );
      } catch (error, stackTrace) {
        _logger.error('backup.export_error', error, stackTrace: stackTrace);
        return const BackupExportFailed(BackupExportFailure.failed);
      } finally {
        if (area != null) {
          try {
            await _storage.discardStagingArea(area);
          } on StorageError {
            // Left for startup staging cleanup.
          }
        }
      }
    }();
    _logger.info(
      'backup.export_finished',
      fields: {
        'type': type,
        'outcome': switch (result) {
          BackupExportSaved() => 'saved',
          BackupExportCancelled() => 'cancelled',
          BackupExportIncomplete(:final books) => 'incomplete:${books.length}',
          BackupExportFailed(:final reason) => reason,
        },
        'books': books,
        'settings': includeSettings,
        'bytes': archiveBytes,
        'elapsed': stopwatch.elapsed,
      },
    );
    return result;
  }

  Future<_BuildResult> _build(
    LibrarySnapshot snapshot,
    BackupType type,
    bool includeSettings,
    String workspace,
  ) async {
    Map<String, BackupBookFiles>? files;
    final fileSources = <ArchiveSource>[];
    if (type == BackupType.full) {
      final sources = [
        for (final book in snapshot.books)
          _BookSource(
            book: book,
            publicationPath: _storage.file(book.filePath).path,
            coverPath: _coverSource(book),
          ),
      ];
      final digests = await _digestAll(sources);
      files = {};
      final unavailable = <Book>[];
      for (final (index, source) in sources.indexed) {
        final book = source.book;
        final digest = digests[index];
        final publication = digest.publication;
        if (publication == null ||
            publication.sizeBytes != book.fileSizeBytes ||
            publication.sha256 != book.fileChecksum) {
          unavailable.add(book);
          continue;
        }
        final publicationEntry = BackupEntry(
          path: BackupFormat.publicationPath(book.id, book.format),
          role: BackupEntryRole.publication,
          bookId: book.id,
          sizeBytes: publication.sizeBytes,
          sha256: publication.sha256,
        );
        fileSources.add(
          ArchiveSource(
            archivePath: publicationEntry.path,
            sourcePath: source.publicationPath,
          ),
        );
        BackupEntry? coverEntry;
        // A cover is optional; one that cannot be read is left out.
        if ((source.coverPath, digest.cover) case (
          (final path, final extension)?,
          final cover?,
        )) {
          coverEntry = BackupEntry(
            path: BackupFormat.coverPath(book.id, extension),
            role: BackupEntryRole.cover,
            bookId: book.id,
            sizeBytes: cover.sizeBytes,
            sha256: cover.sha256,
          );
          fileSources.add(
            ArchiveSource(archivePath: coverEntry.path, sourcePath: path),
          );
        }
        files[book.id] = BackupBookFiles(
          publication: publicationEntry,
          cover: coverEntry,
        );
      }
      if (unavailable.isNotEmpty) return _Incomplete(unavailable);
    }

    final datasets = encodeBackupDatasets(
      snapshot,
      files: files,
      preferences: includeSettings ? _readPreferences() : null,
    );
    final dataSources = <ArchiveSource>[];
    final dataEntries = <BackupEntry>[];
    for (final MapEntry(key: archivePath, value: json) in datasets.entries) {
      final bytes = utf8.encode(jsonEncode(json));
      final target = p.join(workspace, 'content', archivePath);
      await _write(target, bytes);
      dataSources.add(
        ArchiveSource(archivePath: archivePath, sourcePath: target),
      );
      dataEntries.add(
        BackupEntry(
          path: archivePath,
          role: BackupEntryRole.data,
          sizeBytes: bytes.length,
          sha256: _sha256Hex(bytes),
        ),
      );
    }

    final createdAt = _clock().toUtc();
    final manifest = BackupManifest(
      createdAt: createdAt,
      type: type,
      app: await _appInfo(),
      locatorEnvelopeVersion: LocatorEnvelope.currentSchemaVersion,
      counts: backupCounts(snapshot),
      entries: [
        ...dataEntries,
        for (final entry in files?.values ?? const <BackupBookFiles>[]) ...[
          entry.publication,
          ?entry.cover,
        ],
      ],
      preferencesIncluded: includeSettings,
    );
    final manifestPath = p.join(
      workspace,
      'content',
      BackupFormat.manifestPath,
    );
    await _write(manifestPath, utf8.encode(jsonEncode(manifest.toJson())));

    final archivePath = p.join(
      workspace,
      BackupFormat.fileName(type, createdAt),
    );
    final sources = [
      ArchiveSource(
        archivePath: BackupFormat.manifestPath,
        sourcePath: manifestPath,
      ),
      ...dataSources,
      // Same order as the manifest: each publication, then its cover.
      ...fileSources,
    ];
    await _writeAndVerify(archivePath, sources);
    return _Built(File(archivePath), createdAt);
  }

  (String, String)? _coverSource(Book book) {
    final cover = book.coverPath;
    if (cover == null) return null;
    final extension = p.extension(cover.value).replaceFirst('.', '');
    final normalized = extension.toLowerCase() == 'jpeg'
        ? 'jpg'
        : extension.toLowerCase();
    if (!BackupFormat.coverExtensions.contains(normalized)) return null;
    return (_storage.file(cover).path, normalized);
  }

  static String _sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

  // Isolate bodies are built in static methods so the closures capture only
  // their arguments, never this service.
  static Future<List<({FileDigest? publication, FileDigest? cover})>>
  _digestAll(List<_BookSource> sources) =>
      _run(() => [for (final source in sources) source.digest()]);

  static Future<void> _writeAndVerify(
    String archivePath,
    List<ArchiveSource> sources,
  ) => _run(() {
    writeBackupArchive(archivePath, sources);
    verifyBackupArchive(archivePath);
  });

  static Future<void> _write(String path, List<int> bytes) async {
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } on FileSystemException catch (error) {
      throw _storageError(error);
    }
  }

  /// Runs blocking archive work off the UI isolate and maps file errors.
  static Future<T> _run<T>(T Function() body) async {
    try {
      return await Isolate.run(() {
        try {
          return body();
        } on FileSystemException catch (error) {
          throw _storageError(error);
        }
      });
    } on BackupError catch (error, stackTrace) {
      // The archive just written failed verification: a bug or a source
      // file that changed while it was archived. Never saved.
      Error.throwWithStackTrace(
        StorageError(StorageErrorKind.ioFailure, error.message),
        stackTrace,
      );
    }
  }

  // ENOSPC on Linux/Android and Darwin.
  static const int _errnoNoSpace = 28;

  static StorageError _storageError(FileSystemException error) => StorageError(
    error.osError?.errorCode == _errnoNoSpace
        ? StorageErrorKind.insufficientSpace
        : StorageErrorKind.ioFailure,
    'backup file operation failed',
  );
}

final class _BookSource {
  const _BookSource({
    required this.book,
    required this.publicationPath,
    required this.coverPath,
  });

  final Book book;
  final String publicationPath;

  /// Absolute path and archive extension.
  final (String, String)? coverPath;

  ({FileDigest? publication, FileDigest? cover}) digest() => (
    publication: _tryDigest(publicationPath),
    cover: coverPath == null ? null : _tryDigest(coverPath!.$1),
  );

  static FileDigest? _tryDigest(String path) {
    try {
      return digestFile(path);
    } on FileSystemException {
      return null;
    }
  }
}

sealed class _BuildResult {
  const _BuildResult();
}

final class _Built extends _BuildResult {
  const _Built(this.archive, this.createdAt);

  final File archive;
  final DateTime createdAt;
}

final class _Incomplete extends _BuildResult {
  const _Incomplete(this.books);

  final List<Book> books;
}
