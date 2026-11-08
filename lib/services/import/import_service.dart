import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/errors/app_errors.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/uuid.dart';
import '../../domain/entities/book.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/managed_path.dart';
import '../../domain/repositories/book_repository.dart';
import '../../domain/services/publication_inspector.dart';
import '../storage/library_storage.dart';
import 'document_picker.dart';

/// Why a file could not be imported. Mapped to user wording in the UI.
enum ImportFailureReason {
  unsupportedFormat,
  invalidFile,
  insufficientStorage,
  failed,
}

/// Outcome of importing one file.
sealed class ImportResult {
  const ImportResult(this.source);

  final ImportSource source;
}

final class ImportSucceeded extends ImportResult {
  const ImportSucceeded(super.source, this.book);

  final Book book;
}

/// The file's checksum matches books already in the library. Nothing was
/// imported; the caller may retry with `allowDuplicate: true`.
final class ImportDuplicate extends ImportResult {
  const ImportDuplicate(super.source, this.existing);

  final List<Book> existing;
}

/// The file matched a library book whose file is missing (for example after
/// a library-only restore), and was put back in place for that book.
final class ImportRelinked extends ImportResult {
  const ImportRelinked(super.source, this.book);

  final Book book;
}

final class ImportFailed extends ImportResult {
  const ImportFailed(super.source, this.reason);

  final ImportFailureReason reason;
}

/// Imports one publication file into the library as a recoverable workflow
/// (TECHNICAL_ARCHITECTURE.md §6.2, DATABASE_SCHEMA.md §13):
///
/// 1. Copy the source into a private staging area (the source is only read).
/// 2. Validate extension, size and file signature; compute SHA-256.
/// 3. If the checksum matches a book whose file is missing, put the file
///    back for that book ([ImportRelinked]). Otherwise stop with
///    [ImportDuplicate] if the checksum is already in the library.
/// 4. Read metadata and the cover through the reader engine.
/// 5. Move files to `books/<id>/`, then insert the book record.
///
/// The record is inserted only after the files are in place; if the insert
/// fails, the moved files are deleted. The staging area is always removed.
/// Anything left by a crash is cleaned up by startup staging cleanup.
class ImportService {
  ImportService({
    required this._storage,
    required this._books,
    required this._inspector,
    required this._logger,
    this._clock = DateTime.now,
    this._newId = generateUuidV4,
  });

  final LibraryStorage _storage;
  final BookRepository _books;
  final PublicationInspector _inspector;
  final AppLogger _logger;
  final Clock _clock;
  final String Function() _newId;

  static const Map<String, PublicationFormat> _formatsByExtension = {
    '.epub': PublicationFormat.epub,
    '.pdf': PublicationFormat.pdf,
  };

  Future<ImportResult> importFile(
    ImportSource source, {
    bool allowDuplicate = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    final result = await _import(source, allowDuplicate);
    _logger.info(
      'import.finished',
      fields: {
        'outcome': switch (result) {
          ImportSucceeded() => 'imported',
          ImportDuplicate() => 'duplicate',
          ImportRelinked() => 'relinked',
          ImportFailed(:final reason) => reason,
        },
        if (result case ImportSucceeded(:final book)) ...{
          'format': book.format,
          'bytes': book.fileSizeBytes,
          'hasCover': book.coverPath != null,
        },
        'elapsed': stopwatch.elapsed,
      },
    );
    return result;
  }

  Future<ImportResult> _import(ImportSource source, bool allowDuplicate) async {
    final format =
        _formatsByExtension[p.extension(source.name).toLowerCase()] ??
        _formatsByExtension[p.extension(source.path ?? '').toLowerCase()];
    if (format == null) {
      return ImportFailed(source, ImportFailureReason.unsupportedFormat);
    }
    final sourcePath = source.path;
    if (sourcePath == null) {
      return ImportFailed(source, ImportFailureReason.failed);
    }

    ManagedPath? area;
    try {
      area = await _storage.createStagingArea();
      final staged = await _storage.copyIntoStaging(
        File(sourcePath),
        area,
        'publication.${format.wireName}',
      );

      final size = await _storage.fileSize(staged) ?? 0;
      if (size == 0 || !await _hasSignature(_storage.file(staged), format)) {
        return ImportFailed(source, ImportFailureReason.invalidFile);
      }
      final checksum = await _storage.sha256Hex(staged);

      final existing = await _books.findBooksByChecksum(checksum);
      for (final book in existing) {
        if (book.format == format && !await _storage.exists(book.filePath)) {
          return ImportRelinked(
            source,
            await _relink(book, staged, area, size),
          );
        }
      }
      if (!allowDuplicate && existing.isNotEmpty) {
        return ImportDuplicate(source, existing);
      }

      final PublicationDetails details;
      try {
        details = await _inspector.inspect(
          _storage.file(staged).path,
          coverDirectory: _storage.file(area).path,
        );
      } on PublicationError {
        return ImportFailed(source, ImportFailureReason.invalidFile);
      }

      final bookId = _newId();
      return ImportSucceeded(
        source,
        await _commit(
          bookId: bookId,
          source: source,
          format: format,
          staged: staged,
          area: area,
          size: size,
          checksum: checksum,
          details: details,
        ),
      );
    } on StorageError catch (error) {
      return ImportFailed(
        source,
        error.kind == StorageErrorKind.insufficientSpace
            ? ImportFailureReason.insufficientStorage
            : ImportFailureReason.failed,
      );
    } on AppError {
      return ImportFailed(source, ImportFailureReason.failed);
    } catch (error, stackTrace) {
      _logger.error('import.unexpected_error', error, stackTrace: stackTrace);
      return ImportFailed(source, ImportFailureReason.failed);
    } finally {
      if (area != null) {
        try {
          await _storage.discardStagingArea(area);
        } on StorageError {
          // Left for startup staging cleanup.
        }
      }
    }
  }

  /// Puts the staged file at [book]'s file path. A cover is extracted if the
  /// book has none; that is best effort. The record is touched so the
  /// library refreshes.
  Future<Book> _relink(
    Book book,
    ManagedPath staged,
    ManagedPath area,
    int size,
  ) async {
    if (size != book.fileSizeBytes) {
      throw const StorageError(StorageErrorKind.ioFailure, 'size mismatch');
    }
    await _storage.promote(staged, book.filePath);
    var cover = book.coverPath;
    if (cover == null || !await _storage.exists(cover)) {
      try {
        final details = await _inspector.inspect(
          _storage.file(book.filePath).path,
          coverDirectory: _storage.file(area).path,
        );
        cover = await _promoteCover(book.id, area, details);
      } on PublicationError {
        cover = null;
      }
    }
    final relinked = Book(
      id: book.id,
      title: book.title,
      authors: book.authors,
      description: book.description,
      language: book.language,
      identifier: book.identifier,
      publisher: book.publisher,
      publishedAt: book.publishedAt,
      format: book.format,
      filePath: book.filePath,
      coverPath: cover,
      fileSizeBytes: book.fileSizeBytes,
      fileChecksum: book.fileChecksum,
      readingStatus: book.readingStatus,
      addedAt: book.addedAt,
      lastOpenedAt: book.lastOpenedAt,
      updatedAt: _clock(),
      metadataJson: book.metadataJson,
    );
    await _books.updateBookMetadata(relinked);
    return relinked;
  }

  /// Moves files into place, then inserts the record. Undoes the move if
  /// anything after it fails.
  Future<Book> _commit({
    required String bookId,
    required ImportSource source,
    required PublicationFormat format,
    required ManagedPath staged,
    required ManagedPath area,
    required int size,
    required String checksum,
    required PublicationDetails details,
  }) async {
    final filePath = _storage.publicationPath(bookId, format);
    try {
      await _storage.promote(staged, filePath);
      final coverPath = await _promoteCover(bookId, area, details);
      final now = _clock();
      final book = Book(
        id: bookId,
        title: _title(details.title, source.name),
        authors: details.authors,
        description: details.description,
        language: details.language,
        identifier: details.identifier,
        publisher: details.publisher,
        publishedAt: details.publishedAt,
        format: format,
        filePath: filePath,
        coverPath: coverPath,
        fileSizeBytes: size,
        fileChecksum: checksum,
        addedAt: now,
        updatedAt: now,
      );
      await _books.addBook(book);
      return book;
    } catch (_) {
      await _storage.deleteBookFiles(bookId);
      rethrow;
    }
  }

  Future<ManagedPath?> _promoteCover(
    String bookId,
    ManagedPath area,
    PublicationDetails details,
  ) async {
    final coverFile = details.coverFilePath;
    if (coverFile == null) return null;
    final name = p.basename(coverFile);
    final staged = ManagedPath.tryParse('${area.value}/$name');
    // Only accept a cover the inspector wrote inside this staging area.
    if (staged == null || !p.equals(_storage.file(staged).path, coverFile)) {
      return null;
    }
    final target = ManagedPath.join([
      ...LibraryStorage.booksDir.segments,
      bookId,
      name,
    ]);
    try {
      await _storage.promote(staged, target);
      return target;
    } on StorageError {
      return null;
    }
  }

  /// The declared title, or the file name without its extension.
  static String _title(String? declared, String fileName) {
    final trimmed = declared?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
    final fromName = p.basenameWithoutExtension(fileName).trim();
    return fromName.isEmpty ? 'Untitled' : fromName;
  }

  /// Cheap content check before handing the file to the reader engine:
  /// EPUB is a ZIP container, PDF has a `%PDF-` header near the start.
  static Future<bool> _hasSignature(File file, PublicationFormat format) async {
    final RandomAccessFile handle;
    try {
      handle = await file.open();
    } on FileSystemException {
      return false;
    }
    try {
      final head = await handle.read(1024);
      return switch (format) {
        PublicationFormat.epub =>
          head.length >= 4 &&
              head[0] == 0x50 &&
              head[1] == 0x4B &&
              head[2] == 0x03 &&
              head[3] == 0x04,
        PublicationFormat.pdf => String.fromCharCodes(head).contains('%PDF-'),
      };
    } finally {
      await handle.close();
    }
  }
}
