/// Typed application errors (TECHNICAL_ARCHITECTURE.md §11).
///
/// Messages are for diagnostics only. They must not contain file paths,
/// publication text or notes; UI code maps the error kind to user wording.
sealed class AppError implements Exception {
  const AppError(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

enum DatabaseErrorKind {
  /// The referenced record does not exist.
  notFound,

  /// A foreign-key, uniqueness or check constraint rejected the change.
  constraintViolation,

  /// Any other database failure.
  failure,
}

final class DatabaseError extends AppError {
  const DatabaseError(this.kind, super.message);

  final DatabaseErrorKind kind;
}

enum StorageErrorKind {
  /// A managed file or directory does not exist.
  missingFile,

  /// A path failed validation or escaped the library root.
  unsafePath,

  /// The device has no space left for the write.
  insufficientSpace,

  /// Reading, writing, moving or deleting failed.
  ioFailure,
}

final class StorageError extends AppError {
  const StorageError(this.kind, super.message);

  final StorageErrorKind kind;
}

enum PublicationErrorKind {
  /// The reader engine could not parse the file as a publication.
  unreadable,
}

/// The reader engine could not open or inspect a publication.
final class PublicationError extends AppError {
  const PublicationError(this.kind, super.message);

  final PublicationErrorKind kind;
}

enum BackupErrorKind {
  /// The file is not a readable backup archive, or breaks the format rules
  /// (paths, duplicates, required fields, entry roles).
  invalidArchive,

  /// The archive declares a format version this app cannot read.
  unsupportedVersion,

  /// An entry's size or SHA-256 does not match the manifest.
  checksumMismatch,

  /// The archive exceeds a resource limit (BACKUP_FORMAT.md §9.2).
  limitExceeded,
}

/// A backup archive failed validation.
final class BackupError extends AppError {
  const BackupError(this.kind, super.message);

  final BackupErrorKind kind;
}
