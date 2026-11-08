import '../../core/errors/app_errors.dart';
import '../../domain/entities/enums.dart';

/// Backup archive format, version 1 (BACKUP_FORMAT.md). The format version
/// is independent of the SQLite schema version.
abstract final class BackupFormat {
  static const String formatId = 'com.sbjglitch.thaal.backup';
  static const int formatVersion = 1;
  static const int dataSchemaVersion = 1;
  static const String extension = 'readerbackup';

  static const String manifestPath = 'manifest.json';
  static const String booksPath = 'data/books.json';
  static const String progressPath = 'data/reading_progress.json';
  static const String bookmarksPath = 'data/bookmarks.json';
  static const String highlightsPath = 'data/highlights.json';
  static const String collectionsPath = 'data/collections.json';
  static const String collectionBooksPath = 'data/collection_books.json';
  static const String preferencesPath = 'data/preferences.json';

  /// Datasets every backup contains, in archive order.
  static const List<String> requiredDataPaths = [
    booksPath,
    progressPath,
    bookmarksPath,
    highlightsPath,
    collectionsPath,
    collectionBooksPath,
  ];

  /// Keys of the manifest `counts` object.
  static const List<String> countKeys = [
    'books',
    'readingProgress',
    'bookmarks',
    'highlights',
    'collections',
    'collectionBooks',
  ];

  static const Set<String> coverExtensions = {'jpg', 'png', 'webp', 'gif'};

  static String publicationPath(String bookId, PublicationFormat format) =>
      'files/books/$bookId/publication.${format.wireName}';

  static String coverPath(String bookId, String extension) =>
      'files/covers/$bookId.$extension';

  /// `reader-backup-YYYYMMDD-HHmmss-full.readerbackup` in UTC (§3).
  static String fileName(BackupType type, DateTime createdAt) {
    final t = createdAt.toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${t.year.toString().padLeft(4, '0')}${two(t.month)}${two(t.day)}'
        '-${two(t.hour)}${two(t.minute)}${two(t.second)}';
    final suffix = switch (type) {
      BackupType.full => 'full',
      BackupType.libraryOnly => 'library',
    };
    return 'reader-backup-$stamp-$suffix.$extension';
  }
}

enum BackupType implements WireEnum {
  /// Library records plus publication and cover files.
  full('full'),

  /// Library records only; restored books are marked as missing their file.
  libraryOnly('library_only');

  const BackupType(this.wireName);

  @override
  final String wireName;
}

enum BackupEntryRole implements WireEnum {
  data('data'),
  publication('publication'),
  cover('cover');

  const BackupEntryRole(this.wireName);

  @override
  final String wireName;
}

/// Resource limits for reading an archive (BACKUP_FORMAT.md §9.2). The
/// defaults allow a large personal library while bounding what an untrusted
/// archive can make the app write or hold in memory.
final class BackupLimits {
  const BackupLimits({
    this.maxArchiveBytes = 16 * _gib,
    this.maxEntries = 50000,
    this.maxManifestBytes = 32 * _mib,
    this.maxDataEntryBytes = 256 * _mib,
    this.maxPublicationBytes = 2 * _gib,
    this.maxCoverBytes = 32 * _mib,
    this.maxTotalBytes = 16 * _gib,
    this.maxCompressionRatio = 100,
  });

  static const int _mib = 1024 * 1024;
  static const int _gib = 1024 * _mib;

  final int maxArchiveBytes;
  final int maxEntries;
  final int maxManifestBytes;
  final int maxDataEntryBytes;
  final int maxPublicationBytes;
  final int maxCoverBytes;

  /// Sum of all uncompressed entry sizes.
  final int maxTotalBytes;

  /// Uncompressed size ÷ compressed size, checked for compressed entries
  /// larger than 1 MiB.
  final int maxCompressionRatio;

  int maxBytesFor(BackupEntryRole role) => switch (role) {
    BackupEntryRole.data => maxDataEntryBytes,
    BackupEntryRole.publication => maxPublicationBytes,
    BackupEntryRole.cover => maxCoverBytes,
  };
}

/// One declared archive entry with its integrity data.
final class BackupEntry {
  const BackupEntry({
    required this.path,
    required this.role,
    this.bookId,
    required this.sizeBytes,
    required this.sha256,
  });

  final String path;
  final BackupEntryRole role;

  /// Set for publication and cover entries.
  final String? bookId;
  final int sizeBytes;

  /// Lowercase hex SHA-256 of the uncompressed bytes.
  final String sha256;

  Map<String, Object?> toJson() => {
    'path': path,
    'role': role.wireName,
    'bookId': ?bookId,
    'sizeBytes': sizeBytes,
    'sha256': sha256,
  };
}

final class BackupAppInfo {
  const BackupAppInfo({
    required this.name,
    required this.version,
    required this.buildNumber,
  });

  final String name;
  final String version;
  final String buildNumber;
}

/// `manifest.json` (BACKUP_FORMAT.md §5).
final class BackupManifest {
  const BackupManifest({
    required this.createdAt,
    required this.type,
    required this.app,
    required this.locatorEnvelopeVersion,
    required this.counts,
    required this.entries,
    required this.preferencesIncluded,
    this.dataSchemaVersion = BackupFormat.dataSchemaVersion,
  });

  final DateTime createdAt;
  final BackupType type;
  final BackupAppInfo app;
  final int dataSchemaVersion;
  final int locatorEnvelopeVersion;

  /// Record count per dataset, keyed by [BackupFormat.countKeys].
  final Map<String, int> counts;
  final List<BackupEntry> entries;
  final bool preferencesIncluded;

  Map<String, Object?> toJson() => {
    'format': BackupFormat.formatId,
    'formatVersion': BackupFormat.formatVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'backupType': type.wireName,
    'app': {
      'name': app.name,
      'version': app.version,
      'buildNumber': app.buildNumber,
    },
    'dataSchemaVersion': dataSchemaVersion,
    'locatorEnvelopeVersion': locatorEnvelopeVersion,
    'counts': counts,
    'entries': [for (final entry in entries) entry.toJson()],
    'preferencesIncluded': preferencesIncluded,
  };

  /// Strictly parses and checks a decoded manifest (§5.3). Unknown optional
  /// fields are ignored. Throws [BackupError].
  static BackupManifest parse(Object? json) {
    final root = _object(json, 'manifest');
    if (root['format'] != BackupFormat.formatId) {
      throw _invalid('unexpected format identifier');
    }
    final formatVersion = _int(root, 'formatVersion');
    if (formatVersion != BackupFormat.formatVersion) {
      throw const BackupError(
        BackupErrorKind.unsupportedVersion,
        'unsupported formatVersion',
      );
    }
    final dataSchemaVersion = _int(root, 'dataSchemaVersion');
    if (dataSchemaVersion != BackupFormat.dataSchemaVersion) {
      throw const BackupError(
        BackupErrorKind.unsupportedVersion,
        'unsupported dataSchemaVersion',
      );
    }
    final createdAt = DateTime.tryParse(_string(root, 'createdAt'));
    if (createdAt == null || !createdAt.isUtc) {
      throw _invalid('createdAt is not an ISO 8601 UTC timestamp');
    }
    final BackupType type;
    try {
      type = parseWireEnum(BackupType.values, _string(root, 'backupType'));
    } on FormatException {
      throw _invalid('unknown backupType');
    }
    final app = _object(root['app'], 'app');
    final locatorEnvelopeVersion = _int(root, 'locatorEnvelopeVersion');
    if (locatorEnvelopeVersion < 1) {
      throw _invalid('locatorEnvelopeVersion must be ≥ 1');
    }
    final countsJson = _object(root['counts'], 'counts');
    final counts = <String, int>{
      for (final key in BackupFormat.countKeys) key: _int(countsJson, key),
    };
    if (counts.values.any((count) => count < 0)) {
      throw _invalid('negative count');
    }
    final preferencesIncluded = root['preferencesIncluded'];
    if (preferencesIncluded is! bool) {
      throw _invalid('preferencesIncluded must be a boolean');
    }
    final entriesJson = root['entries'];
    if (entriesJson is! List<Object?>) {
      throw _invalid('entries must be an array');
    }
    final entries = [for (final entry in entriesJson) _entry(entry)];
    _checkEntries(entries, type, preferencesIncluded);
    return BackupManifest(
      createdAt: createdAt,
      type: type,
      app: BackupAppInfo(
        name: _string(app, 'name'),
        version: _string(app, 'version'),
        buildNumber: _string(app, 'buildNumber'),
      ),
      dataSchemaVersion: dataSchemaVersion,
      locatorEnvelopeVersion: locatorEnvelopeVersion,
      counts: counts,
      entries: entries,
      preferencesIncluded: preferencesIncluded,
    );
  }

  static final RegExp _bookId = RegExp(r'^[A-Za-z0-9-]{1,64}$');
  static final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');

  static BackupEntry _entry(Object? json) {
    final map = _object(json, 'entry');
    final path = _string(map, 'path');
    if (!isSafeArchivePath(path)) throw _invalid('unsafe entry path');
    final BackupEntryRole role;
    try {
      role = parseWireEnum(BackupEntryRole.values, _string(map, 'role'));
    } on FormatException {
      throw _invalid('unknown entry role');
    }
    final size = _int(map, 'sizeBytes');
    if (size < 0) throw _invalid('negative entry size');
    final sha = _string(map, 'sha256');
    if (!_sha256.hasMatch(sha)) throw _invalid('malformed sha256');
    final bookId = map['bookId'];
    if (bookId != null && (bookId is! String || !_bookId.hasMatch(bookId))) {
      throw _invalid('malformed bookId');
    }
    if (!_pathMatchesRole(path, role, bookId as String?)) {
      throw _invalid('entry path does not match its role');
    }
    return BackupEntry(
      path: path,
      role: role,
      bookId: bookId,
      sizeBytes: size,
      sha256: sha,
    );
  }

  static bool _pathMatchesRole(
    String path,
    BackupEntryRole role,
    String? bookId,
  ) {
    switch (role) {
      case BackupEntryRole.data:
        return bookId == null &&
            (BackupFormat.requiredDataPaths.contains(path) ||
                path == BackupFormat.preferencesPath);
      case BackupEntryRole.publication:
        return bookId != null &&
            PublicationFormat.values.any(
              (format) => path == BackupFormat.publicationPath(bookId, format),
            );
      case BackupEntryRole.cover:
        return bookId != null &&
            BackupFormat.coverExtensions.any(
              (ext) => path == BackupFormat.coverPath(bookId, ext),
            );
    }
  }

  static void _checkEntries(
    List<BackupEntry> entries,
    BackupType type,
    bool preferencesIncluded,
  ) {
    final seen = <String>{};
    final publicationBooks = <String>{};
    final coverBooks = <String>{};
    for (final entry in entries) {
      // Lowercased as well, so two names that collide on a case-insensitive
      // filesystem are rejected too.
      if (!seen.add(entry.path.toLowerCase())) {
        throw _invalid('duplicate entry path');
      }
      final bookId = entry.bookId;
      if (entry.role == BackupEntryRole.publication &&
          !publicationBooks.add(bookId!)) {
        throw _invalid('two publications for one book');
      }
      if (entry.role == BackupEntryRole.cover && !coverBooks.add(bookId!)) {
        throw _invalid('two covers for one book');
      }
    }
    for (final path in BackupFormat.requiredDataPaths) {
      if (!seen.contains(path)) throw _invalid('missing dataset');
    }
    if (preferencesIncluded != seen.contains(BackupFormat.preferencesPath)) {
      throw _invalid('preferencesIncluded does not match the entries');
    }
    if (type == BackupType.libraryOnly &&
        (publicationBooks.isNotEmpty || coverBooks.isNotEmpty)) {
      throw _invalid('library-only backup contains files');
    }
  }

  static Map<String, Object?> _object(Object? value, String name) {
    if (value is! Map<String, Object?>) {
      throw _invalid('$name is not an object');
    }
    return value;
  }

  static String _string(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! String) throw _invalid('$key must be a string');
    return value;
  }

  static int _int(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! int) throw _invalid('$key must be an integer');
    return value;
  }

  static BackupError _invalid(String message) =>
      BackupError(BackupErrorKind.invalidArchive, 'manifest: $message');
}

/// Archive path rules (BACKUP_FORMAT.md §4.3, §9.1): relative, `/`
/// separated, no empty, `.` or `..` segments, no backslash, drive prefix,
/// colon or control characters.
bool isSafeArchivePath(String path) {
  if (path.isEmpty || path.length > 512) return false;
  if (path.startsWith('/') || path.endsWith('/')) return false;
  if (path.contains('\\') || path.contains(':')) return false;
  if (path.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) return false;
  for (final segment in path.split('/')) {
    if (segment.isEmpty || segment == '.' || segment == '..') return false;
  }
  return true;
}
