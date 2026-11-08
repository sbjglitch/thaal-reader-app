import 'dart:convert';

import '../../domain/entities/book.dart';
import '../../domain/entities/library_snapshot.dart';
import 'backup_format.dart';

/// The archive entries a full backup stores for one book.
final class BackupBookFiles {
  const BackupBookFiles({required this.publication, this.cover});

  final BackupEntry publication;
  final BackupEntry? cover;
}

/// Encodes the library snapshot as the backup datasets (BACKUP_FORMAT.md
/// §6), keyed by archive path in archive order.
///
/// [files] holds the stored entries per book id for a full backup and is
/// null for a library-only backup. [preferences] is null when settings are
/// not included. Locators are written as the stored envelope JSON, so the
/// plugin payload is preserved unchanged. Device paths are never written.
Map<String, Map<String, Object?>> encodeBackupDatasets(
  LibrarySnapshot snapshot, {
  required Map<String, BackupBookFiles>? files,
  required Map<String, Object>? preferences,
}) {
  Map<String, Object?> dataset(Object records) => {
    'schemaVersion': BackupFormat.dataSchemaVersion,
    'records': records,
  };
  return {
    BackupFormat.booksPath: dataset([
      for (final book in snapshot.books) _book(book, files?[book.id]),
    ]),
    BackupFormat.progressPath: dataset([
      for (final progress in snapshot.progress)
        {
          'bookId': progress.bookId,
          'locator': _locator(progress.locator?.json),
          'pageNumber': progress.pageNumber,
          'progression': progress.progression,
          'updatedAt': _time(progress.updatedAt),
        },
    ]),
    BackupFormat.bookmarksPath: dataset([
      for (final bookmark in snapshot.bookmarks)
        {
          'id': bookmark.id,
          'bookId': bookmark.bookId,
          'locator': _locator(bookmark.locator.json),
          'label': bookmark.label,
          'createdAt': _time(bookmark.createdAt),
          'updatedAt': _time(bookmark.updatedAt),
        },
    ]),
    BackupFormat.highlightsPath: dataset([
      for (final highlight in snapshot.highlights)
        {
          'id': highlight.id,
          'bookId': highlight.bookId,
          'locator': _locator(highlight.locator.json),
          'selectedText': highlight.selectedText,
          'color': highlight.color.wireName,
          'note': highlight.note,
          'createdAt': _time(highlight.createdAt),
          'updatedAt': _time(highlight.updatedAt),
        },
    ]),
    BackupFormat.collectionsPath: dataset([
      for (final collection in snapshot.collections)
        {
          'id': collection.id,
          'name': collection.name,
          'createdAt': _time(collection.createdAt),
          'updatedAt': _time(collection.updatedAt),
        },
    ]),
    BackupFormat.collectionBooksPath: dataset([
      for (final membership in snapshot.memberships)
        {
          'collectionId': membership.collectionId,
          'bookId': membership.bookId,
          'addedAt': _time(membership.addedAt),
        },
    ]),
    if (preferences != null) BackupFormat.preferencesPath: dataset(preferences),
  };
}

/// Manifest `counts` for [snapshot].
Map<String, int> backupCounts(LibrarySnapshot snapshot) => {
  'books': snapshot.books.length,
  'readingProgress': snapshot.progress.length,
  'bookmarks': snapshot.bookmarks.length,
  'highlights': snapshot.highlights.length,
  'collections': snapshot.collections.length,
  'collectionBooks': snapshot.memberships.length,
};

Map<String, Object?> _book(Book book, BackupBookFiles? files) {
  final publication = files?.publication;
  final cover = files?.cover;
  return {
    'id': book.id,
    'title': book.title,
    'authors': book.authors,
    'description': book.description,
    'language': book.language,
    'identifier': book.identifier,
    'publisher': book.publisher,
    'publishedAt': book.publishedAt,
    'format': book.format.wireName,
    'file': publication == null
        ? {'included': false}
        : {'included': true, ..._fileFields(publication)},
    'cover': cover == null ? null : {'included': true, ..._fileFields(cover)},
    // The library's own record of the file, kept even when the file is not
    // included so a library-only restore can recognise the publication when
    // it is re-imported.
    'fileSizeBytes': book.fileSizeBytes,
    'fileChecksum': book.fileChecksum,
    'readingStatus': book.readingStatus.wireName,
    'addedAt': _time(book.addedAt),
    'lastOpenedAt': book.lastOpenedAt == null
        ? null
        : _time(book.lastOpenedAt!),
    'updatedAt': _time(book.updatedAt),
    'metadata': _json(book.metadataJson),
  };
}

Map<String, Object?> _fileFields(BackupEntry entry) => {
  'archivePath': entry.path,
  'sizeBytes': entry.sizeBytes,
  'sha256': entry.sha256,
};

/// Stored locator envelopes are valid JSON (a database CHECK constraint).
Object? _locator(String? json) => json == null ? null : jsonDecode(json);

Object? _json(String? json) {
  if (json == null) return null;
  try {
    return jsonDecode(json);
  } on FormatException {
    return null;
  }
}

String _time(DateTime value) => value.toUtc().toIso8601String();
