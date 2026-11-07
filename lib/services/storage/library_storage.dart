import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../core/errors/app_errors.dart';
import '../../core/utils/uuid.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/managed_path.dart';

/// App-private publication storage (TECHNICAL_ARCHITECTURE.md §6.2, ADR-008).
///
/// Layout under [root] (`<ApplicationSupportDirectory>/library`):
///
/// ```text
/// books/<book-id>/publication.<ext>   final publication files
/// staging/<operation-id>/...          in-progress work, never referenced
///                                     by the database
/// ```
///
/// All paths handed in and out are [ManagedPath]s relative to [root]. This
/// class never reads or writes outside [root] and never modifies a source
/// file it copies from. Errors surface as [StorageError] without file paths.
class LibraryStorage {
  LibraryStorage._(this.root);

  static final ManagedPath booksDir = ManagedPath.parse('books');
  static final ManagedPath stagingDir = ManagedPath.parse('staging');

  /// Default age after which a staging directory counts as abandoned.
  static const Duration defaultStagingMaxAge = Duration(hours: 1);

  final Directory root;

  /// Creates the library directories under [libraryRoot] if needed.
  static Future<LibraryStorage> open(Directory libraryRoot) async {
    final storage = LibraryStorage._(libraryRoot);
    await _io('create library directories', () async {
      await storage._directory(booksDir).create(recursive: true);
      await storage._directory(stagingDir).create(recursive: true);
    });
    return storage;
  }

  /// Final location of a book's publication file.
  ManagedPath publicationPath(String bookId, PublicationFormat format) =>
      ManagedPath.join(['books', bookId, 'publication.${format.wireName}']);

  /// The directory holding all files of a book.
  ManagedPath bookDirectory(String bookId) =>
      ManagedPath.join(['books', bookId]);

  /// Resolves [path] to a file under [root].
  File file(ManagedPath path) => File(_absolute(path));

  Future<bool> exists(ManagedPath path) => file(path).exists();

  /// Size in bytes, or null when the file does not exist.
  Future<int?> fileSize(ManagedPath path) async {
    final target = file(path);
    if (!await target.exists()) return null;
    return _io('read file size', target.length);
  }

  /// Lowercase hex SHA-256 of the file at [path], computed on a background
  /// isolate in streamed chunks so large files neither block the UI nor load
  /// into memory at once.
  Future<String> sha256Hex(ManagedPath path) {
    final absolute = _absolute(path);
    return _io('hash file', () {
      return Isolate.run(() async {
        final digest = await sha256.bind(File(absolute).openRead()).first;
        return digest.toString();
      });
    });
  }

  /// Creates a fresh, uniquely named staging directory for one operation.
  Future<ManagedPath> createStagingArea() async {
    final area = ManagedPath.join([...stagingDir.segments, generateUuidV4()]);
    await _io('create staging area', () {
      return _directory(area).create(recursive: true);
    });
    return area;
  }

  /// Copies [source] into [stagingArea] as [fileName] and returns the staged
  /// path. The source is only read. A partially written copy is removed
  /// before the error is rethrown.
  Future<ManagedPath> copyIntoStaging(
    File source,
    ManagedPath stagingArea,
    String fileName,
  ) async {
    _requireWithin(stagingArea, stagingDir);
    final staged = ManagedPath.join([...stagingArea.segments, fileName]);
    final target = file(staged);
    try {
      await source.copy(target.path);
    } on FileSystemException {
      await _deleteIfExists(target);
      throw const StorageError(
        StorageErrorKind.ioFailure,
        'copy into staging failed',
      );
    }
    return staged;
  }

  /// Moves a staged file to its final [target] under `books/`. Refuses to
  /// overwrite an existing file. Uses a rename, which is atomic on the same
  /// filesystem, so the target is either absent or complete.
  Future<void> promote(ManagedPath staged, ManagedPath target) async {
    _requireWithin(staged, stagingDir);
    _requireWithin(target, booksDir);
    final destination = file(target);
    if (await destination.exists()) {
      throw const StorageError(
        StorageErrorKind.ioFailure,
        'promote target already exists',
      );
    }
    await _io('promote staged file', () async {
      await destination.parent.create(recursive: true);
      await file(staged).rename(destination.path);
    });
  }

  /// Removes a staging area and everything in it. Idempotent.
  Future<void> discardStagingArea(ManagedPath stagingArea) async {
    _requireWithin(stagingArea, stagingDir);
    if (stagingArea == stagingDir) {
      throw const StorageError(
        StorageErrorKind.unsafePath,
        'refusing to discard the staging root',
      );
    }
    await _io('discard staging area', () async {
      final directory = _directory(stagingArea);
      if (await directory.exists()) await directory.delete(recursive: true);
    });
  }

  /// Removes all files of [bookId]. Idempotent. Only ever touches
  /// `books/<bookId>/`.
  Future<void> deleteBookFiles(String bookId) async {
    final directory = _directory(bookDirectory(bookId));
    await _io('delete book files', () async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
  }

  /// Deletes staging entries last modified more than [maxAge] before [now].
  ///
  /// Staging entries are never referenced by the database, so an old one can
  /// only be left over from an interrupted operation. The age threshold
  /// protects work started moments ago (DATABASE_SCHEMA.md §12). Entries
  /// that cannot be deleted are kept and counted as [StagingCleanup.failed].
  Future<StagingCleanup> cleanUpStaging({
    required DateTime now,
    Duration maxAge = defaultStagingMaxAge,
  }) async {
    var removed = 0;
    var kept = 0;
    var failed = 0;
    final entries = await _io('list staging', () {
      return _directory(stagingDir).list(followLinks: false).toList();
    });
    for (final entry in entries) {
      try {
        final modified = (await entry.stat()).modified;
        if (now.difference(modified) < maxAge) {
          kept++;
          continue;
        }
        await entry.delete(recursive: true);
        removed++;
      } on FileSystemException {
        failed++;
      }
    }
    return StagingCleanup(removed: removed, kept: kept, failed: failed);
  }

  Directory _directory(ManagedPath path) => Directory(_absolute(path));

  String _absolute(ManagedPath path) =>
      p.joinAll([root.path, ...path.segments]);

  static void _requireWithin(ManagedPath path, ManagedPath parent) {
    if (!path.isWithin(parent)) {
      throw StorageError(
        StorageErrorKind.unsafePath,
        'path must be inside ${parent.value}/',
      );
    }
  }

  static Future<void> _deleteIfExists(File target) async {
    try {
      if (await target.exists()) await target.delete();
    } on FileSystemException {
      // Best effort: staging cleanup at the next startup removes it.
    }
  }

  static Future<T> _io<T>(String operation, Future<T> Function() body) async {
    try {
      return await body();
    } on FileSystemException catch (_, stackTrace) {
      Error.throwWithStackTrace(
        StorageError(StorageErrorKind.ioFailure, '$operation failed'),
        stackTrace,
      );
    }
  }
}

/// Result of [LibraryStorage.cleanUpStaging]. Counts only, so it is safe to
/// log.
final class StagingCleanup {
  const StagingCleanup({
    required this.removed,
    required this.kept,
    required this.failed,
  });

  final int removed;
  final int kept;
  final int failed;
}
