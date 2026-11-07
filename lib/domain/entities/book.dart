import 'enums.dart';
import 'managed_path.dart';

/// A publication in the library (DATABASE_SCHEMA.md §5.1).
///
/// The publication file itself lives in app-private storage at [filePath];
/// this record never guarantees that the file still exists.
final class Book {
  Book({
    required this.id,
    required String title,
    this.authors = const [],
    this.description,
    this.language,
    this.identifier,
    this.publisher,
    this.publishedAt,
    required this.format,
    required this.filePath,
    this.coverPath,
    required this.fileSizeBytes,
    required this.fileChecksum,
    this.readingStatus = ReadingStatus.unread,
    required this.addedAt,
    this.lastOpenedAt,
    required this.updatedAt,
    this.metadataJson,
  }) : title = title.trim() {
    if (this.title.isEmpty) {
      throw ArgumentError.value(title, 'title', 'must not be empty');
    }
    if (fileSizeBytes <= 0) {
      throw ArgumentError.value(fileSizeBytes, 'fileSizeBytes', 'must be > 0');
    }
    if (!isSha256Hex(fileChecksum)) {
      throw ArgumentError.value(
        fileChecksum,
        'fileChecksum',
        'must be a lowercase SHA-256 hex digest',
      );
    }
  }

  static final RegExp _sha256Hex = RegExp(r'^[0-9a-f]{64}$');

  static bool isSha256Hex(String value) => _sha256Hex.hasMatch(value);

  final String id;
  final String title;
  final List<String> authors;
  final String? description;
  final String? language;
  final String? identifier;
  final String? publisher;

  /// The source publication date as supplied by the publication; not an app
  /// timestamp.
  final String? publishedAt;
  final PublicationFormat format;
  final ManagedPath filePath;
  final ManagedPath? coverPath;
  final int fileSizeBytes;
  final String fileChecksum;
  final ReadingStatus readingStatus;
  final DateTime addedAt;
  final DateTime? lastOpenedAt;
  final DateTime updatedAt;

  /// Optional source metadata not represented by columns, as JSON text.
  final String? metadataJson;

  Book copyWith({
    String? title,
    List<String>? authors,
    ReadingStatus? readingStatus,
    DateTime? lastOpenedAt,
    DateTime? updatedAt,
  }) {
    return Book(
      id: id,
      title: title ?? this.title,
      authors: authors ?? this.authors,
      description: description,
      language: language,
      identifier: identifier,
      publisher: publisher,
      publishedAt: publishedAt,
      format: format,
      filePath: filePath,
      coverPath: coverPath,
      fileSizeBytes: fileSizeBytes,
      fileChecksum: fileChecksum,
      readingStatus: readingStatus ?? this.readingStatus,
      addedAt: addedAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      metadataJson: metadataJson,
    );
  }
}
