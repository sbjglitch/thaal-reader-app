import '../entities/library_snapshot.dart';

/// Reads and writes the whole library for backup and restore.
abstract interface class LibrarySnapshotRepository {
  /// All records from one consistent read. Throws `DatabaseError` on
  /// failure.
  Future<LibrarySnapshot> readSnapshot();

  /// Inserts every record in [records] in one transaction, keeping their
  /// ids and timestamps. Nothing is replaced: if any record conflicts with
  /// an existing one the whole insert is rolled back and `DatabaseError` is
  /// thrown.
  Future<void> insertRecords(LibrarySnapshot records);
}
