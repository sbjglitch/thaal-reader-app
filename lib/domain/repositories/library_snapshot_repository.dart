import '../entities/library_snapshot.dart';

/// Reads the whole library for backup.
abstract interface class LibrarySnapshotRepository {
  /// All records from one consistent read. Throws `DatabaseError` on
  /// failure.
  Future<LibrarySnapshot> readSnapshot();
}
