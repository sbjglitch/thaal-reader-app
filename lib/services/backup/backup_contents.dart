import 'dart:convert';

import '../../core/errors/app_errors.dart';
import '../../domain/entities/book.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/library_snapshot.dart';
import '../../domain/entities/locator_envelope.dart';
import '../../domain/entities/managed_path.dart';
import '../../domain/entities/reading_data.dart';
import 'backup_format.dart';

/// A book record from a backup, with the archive entries holding its files.
final class BackupBookRecord {
  const BackupBookRecord({required this.book, this.publication, this.cover});

  /// The book as it will be stored. Its managed paths are where the restore
  /// puts the files: `books/<id>/publication.<ext>` and, with a cover,
  /// `books/<id>/cover.<ext>`.
  final Book book;

  /// Null in a library-only backup.
  final BackupEntry? publication;
  final BackupEntry? cover;
}

/// The validated contents of a backup (BACKUP_FORMAT.md §8.1 steps 5–7).
final class BackupContents {
  const BackupContents({
    required this.manifest,
    required this.books,
    required this.records,
    required this.preferences,
  });

  final BackupManifest manifest;
  final List<BackupBookRecord> books;

  /// Every record, books included, in the snapshot shape used for restore.
  final LibrarySnapshot records;

  /// Raw `preferences.json` records, or null when not included. Values are
  /// validated key by key when applied.
  final Map<String, Object?>? preferences;
}

/// Parses and validates the datasets of a verified archive: field types,
/// enum values, timestamps, unique ids, references between datasets, counts
/// against the manifest, and that file entries match their book records.
/// [datasets] maps archive path to the entry's bytes. Throws [BackupError].
BackupContents parseBackupContents(
  BackupManifest manifest,
  Map<String, List<int>> datasets,
) {
  final full = manifest.type == BackupType.full;
  final entries = {for (final entry in manifest.entries) entry.path: entry};
  final referenced = <String>{};

  BackupEntry? fileEntry(
    Map<String, Object?>? json,
    String expectedPath,
    BackupEntryRole role,
    String bookId,
  ) {
    if (json == null) return null;
    if (json['included'] != true) {
      throw _invalid('only included files may be described');
    }
    final path = _string(json, 'archivePath');
    final entry = entries[path];
    if (path != expectedPath ||
        entry == null ||
        entry.role != role ||
        entry.bookId != bookId ||
        entry.sizeBytes != _int(json, 'sizeBytes') ||
        entry.sha256 != _string(json, 'sha256')) {
      throw _invalid('file does not match the manifest');
    }
    referenced.add(path);
    return entry;
  }

  final bookRecords = <BackupBookRecord>[];
  final bookIds = <String>{};
  for (final json in _records(datasets, BackupFormat.booksPath)) {
    final id = _id(json, 'id', pathSafe: true);
    if (!bookIds.add(id)) throw _invalid('duplicate book id');
    final format = _enum(PublicationFormat.values, json, 'format');
    final fileJson = _object(json['file'], 'file');
    final included = fileJson['included'];
    if (included is! bool || included != full) {
      throw _invalid('book file inclusion does not match the backup type');
    }
    final publication = fileEntry(
      included ? fileJson : null,
      BackupFormat.publicationPath(id, format),
      BackupEntryRole.publication,
      id,
    );
    final coverJson = json['cover'] == null
        ? null
        : _object(json['cover'], 'cover');
    if (coverJson != null && !full) {
      throw _invalid('library-only backup describes a cover');
    }
    final coverExtension = coverJson == null
        ? null
        : _string(coverJson, 'archivePath').split('.').last;
    final cover = coverJson == null
        ? null
        : fileEntry(
            coverJson,
            BackupFormat.coverPath(id, coverExtension!),
            BackupEntryRole.cover,
            id,
          );
    final size = _int(json, 'fileSizeBytes');
    final checksum = _string(json, 'fileChecksum');
    if (publication != null &&
        (publication.sizeBytes != size || publication.sha256 != checksum)) {
      throw _invalid('publication does not match its book record');
    }
    final book = _guard(
      () => Book(
        id: id,
        title: _string(json, 'title'),
        authors: _stringList(json, 'authors'),
        description: _optionalString(json, 'description'),
        language: _optionalString(json, 'language'),
        identifier: _optionalString(json, 'identifier'),
        publisher: _optionalString(json, 'publisher'),
        publishedAt: _optionalString(json, 'publishedAt'),
        format: format,
        filePath: ManagedPath.join([
          'books',
          id,
          'publication.${format.wireName}',
        ]),
        coverPath: cover == null
            ? null
            : ManagedPath.join(['books', id, 'cover.$coverExtension']),
        fileSizeBytes: size,
        fileChecksum: checksum,
        readingStatus: _enum(ReadingStatus.values, json, 'readingStatus'),
        addedAt: _time(json, 'addedAt'),
        lastOpenedAt: _optionalTime(json, 'lastOpenedAt'),
        updatedAt: _time(json, 'updatedAt'),
        metadataJson: json['metadata'] == null
            ? null
            : jsonEncode(json['metadata']),
      ),
    );
    bookRecords.add(
      BackupBookRecord(book: book, publication: publication, cover: cover),
    );
  }
  final fileEntries = manifest.entries.where(
    (entry) => entry.role != BackupEntryRole.data,
  );
  if (!fileEntries.every((entry) => referenced.contains(entry.path))) {
    throw _invalid('file entry without a book record');
  }

  void requireBook(String bookId) {
    if (!bookIds.contains(bookId)) throw _invalid('unknown book reference');
  }

  final progress = <ReadingProgress>[];
  final progressBooks = <String>{};
  for (final json in _records(datasets, BackupFormat.progressPath)) {
    final bookId = _id(json, 'bookId');
    requireBook(bookId);
    if (!progressBooks.add(bookId)) throw _invalid('duplicate progress');
    final progression = json['progression'];
    if (progression != null && progression is! num) {
      throw _invalid('progression must be a number');
    }
    progress.add(
      _guard(
        () => ReadingProgress(
          bookId: bookId,
          locator: json['locator'] == null ? null : _locator(json),
          pageNumber: _optionalInt(json, 'pageNumber'),
          progression: (progression as num?)?.toDouble(),
          updatedAt: _time(json, 'updatedAt'),
        ),
      ),
    );
  }

  final bookmarks = <Bookmark>[];
  final bookmarkIds = <String>{};
  for (final json in _records(datasets, BackupFormat.bookmarksPath)) {
    final id = _id(json, 'id');
    if (!bookmarkIds.add(id)) throw _invalid('duplicate bookmark id');
    final bookId = _id(json, 'bookId');
    requireBook(bookId);
    bookmarks.add(
      Bookmark(
        id: id,
        bookId: bookId,
        locator: _locator(json),
        label: _optionalString(json, 'label'),
        createdAt: _time(json, 'createdAt'),
        updatedAt: _time(json, 'updatedAt'),
      ),
    );
  }

  final highlights = <Highlight>[];
  final highlightIds = <String>{};
  for (final json in _records(datasets, BackupFormat.highlightsPath)) {
    final id = _id(json, 'id');
    if (!highlightIds.add(id)) throw _invalid('duplicate highlight id');
    final bookId = _id(json, 'bookId');
    requireBook(bookId);
    highlights.add(
      Highlight(
        id: id,
        bookId: bookId,
        locator: _locator(json),
        selectedText: _optionalString(json, 'selectedText'),
        color: _enum(HighlightColor.values, json, 'color'),
        note: _optionalString(json, 'note'),
        createdAt: _time(json, 'createdAt'),
        updatedAt: _time(json, 'updatedAt'),
      ),
    );
  }

  final collections = <Collection>[];
  final collectionIds = <String>{};
  for (final json in _records(datasets, BackupFormat.collectionsPath)) {
    final id = _id(json, 'id');
    if (!collectionIds.add(id)) throw _invalid('duplicate collection id');
    collections.add(
      _guard(
        () => Collection(
          id: id,
          name: _string(json, 'name'),
          createdAt: _time(json, 'createdAt'),
          updatedAt: _time(json, 'updatedAt'),
        ),
      ),
    );
  }

  final memberships = <CollectionMembership>[];
  final pairs = <(String, String)>{};
  for (final json in _records(datasets, BackupFormat.collectionBooksPath)) {
    final collectionId = _id(json, 'collectionId');
    final bookId = _id(json, 'bookId');
    if (!collectionIds.contains(collectionId)) {
      throw _invalid('unknown collection reference');
    }
    requireBook(bookId);
    if (!pairs.add((collectionId, bookId))) {
      throw _invalid('duplicate collection membership');
    }
    memberships.add(
      CollectionMembership(
        collectionId: collectionId,
        bookId: bookId,
        addedAt: _time(json, 'addedAt'),
      ),
    );
  }

  final records = LibrarySnapshot(
    books: [for (final record in bookRecords) record.book],
    progress: progress,
    bookmarks: bookmarks,
    highlights: highlights,
    collections: collections,
    memberships: memberships,
  );
  final counts = {
    'books': records.books.length,
    'readingProgress': progress.length,
    'bookmarks': bookmarks.length,
    'highlights': highlights.length,
    'collections': collections.length,
    'collectionBooks': memberships.length,
  };
  for (final MapEntry(:key, :value) in counts.entries) {
    if (manifest.counts[key] != value) {
      throw _invalid('manifest count does not match the data');
    }
  }

  Map<String, Object?>? preferences;
  if (manifest.preferencesIncluded) {
    preferences = _object(
      _dataset(datasets, BackupFormat.preferencesPath)['records'],
      'preferences',
    );
  }
  return BackupContents(
    manifest: manifest,
    books: bookRecords,
    records: records,
    preferences: preferences,
  );
}

/// Deeper JSON is rejected before decoding (BACKUP_FORMAT.md §9.2).
const int maxJsonDepth = 64;

Map<String, Object?> _dataset(Map<String, List<int>> datasets, String path) {
  final bytes = datasets[path];
  if (bytes == null) throw _invalid('missing dataset');
  if (_nestingDepth(bytes) > maxJsonDepth) {
    throw const BackupError(BackupErrorKind.limitExceeded, 'JSON too deep');
  }
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw _invalid('dataset is not valid UTF-8 JSON');
  }
  final root = _object(json, 'dataset');
  if (root['schemaVersion'] != BackupFormat.dataSchemaVersion) {
    throw const BackupError(
      BackupErrorKind.unsupportedVersion,
      'unsupported dataset schemaVersion',
    );
  }
  return root;
}

Iterable<Map<String, Object?>> _records(
  Map<String, List<int>> datasets,
  String path,
) {
  final records = _dataset(datasets, path)['records'];
  if (records is! List<Object?>) throw _invalid('records must be an array');
  return records.map((record) => _object(record, 'record'));
}

/// Maximum bracket depth outside strings. A cheap scan so that hostile
/// nesting cannot exhaust the stack in the decoder.
int _nestingDepth(List<int> bytes) {
  var depth = 0;
  var deepest = 0;
  var inString = false;
  var escaped = false;
  for (final byte in bytes) {
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (byte == 0x5C) {
        escaped = true;
      } else if (byte == 0x22) {
        inString = false;
      }
    } else if (byte == 0x22) {
      inString = true;
    } else if (byte == 0x7B || byte == 0x5B) {
      depth++;
      if (depth > deepest) deepest = depth;
    } else if (byte == 0x7D || byte == 0x5D) {
      depth--;
    }
  }
  return deepest;
}

final RegExp _pathSafeId = RegExp(r'^[A-Za-z0-9-]{1,64}$');

String _id(Map<String, Object?> json, String key, {bool pathSafe = false}) {
  final value = _string(json, key);
  if (value.isEmpty || value.length > 128) throw _invalid('$key is invalid');
  // Book ids become directory names.
  if (pathSafe && !_pathSafeId.hasMatch(value)) {
    throw _invalid('$key is not a safe id');
  }
  return value;
}

SerializedLocator _locator(Map<String, Object?> json) {
  final locator = json['locator'];
  if (locator is! Map<String, Object?>) {
    throw _invalid('locator must be an object');
  }
  // Kept as opaque JSON (BACKUP_FORMAT.md §10.1); interpreted when used.
  return SerializedLocator.stored(jsonEncode(locator));
}

T _enum<T extends WireEnum>(
  List<T> values,
  Map<String, Object?> json,
  String key,
) {
  try {
    return parseWireEnum(values, _string(json, key));
  } on FormatException {
    throw _invalid('unknown $key');
  }
}

DateTime _time(Map<String, Object?> json, String key) {
  final value = DateTime.tryParse(_string(json, key));
  if (value == null || !value.isUtc) throw _invalid('$key is not UTC');
  return value;
}

DateTime? _optionalTime(Map<String, Object?> json, String key) =>
    json[key] == null ? null : _time(json, key);

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map<String, Object?>) {
    throw _invalid('$name is not an object');
  }
  return value;
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) throw _invalid('$key must be a string');
  return value;
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value != null && value is! String) {
    throw _invalid('$key must be a string');
  }
  return value as String?;
}

int _int(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) throw _invalid('$key must be an integer');
  return value;
}

int? _optionalInt(Map<String, Object?> json, String key) =>
    json[key] == null ? null : _int(json, key);

List<String> _stringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw _invalid('$key must be a string array');
  }
  return value.cast<String>();
}

/// Entity constructors validate too (empty title, bad checksum, range).
T _guard<T>(T Function() build) {
  try {
    return build();
  } on ArgumentError {
    throw _invalid('record failed validation');
  }
}

BackupError _invalid(String message) =>
    BackupError(BackupErrorKind.invalidArchive, 'data: $message');
