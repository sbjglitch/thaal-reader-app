import 'package:drift/native.dart';
// DriftRemoteException is only exported from this experimental library. The
// background-isolate database wraps SQLite errors in it, and
// test/data/repositories cover the unwrapping so an API change is caught.
// ignore: experimental_member_use
import 'package:drift/remote.dart';

import '../../core/errors/app_errors.dart';

export '../../core/utils/clock.dart';

/// UTC epoch milliseconds, the storage format for every timestamp
/// (DATABASE_SCHEMA.md §4.2).
int toEpochMillis(DateTime value) => value.toUtc().millisecondsSinceEpoch;

DateTime fromEpochMillis(int value) =>
    DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);

DateTime? fromEpochMillisOrNull(int? value) =>
    value == null ? null : fromEpochMillis(value);

const int _sqliteConstraint = 19;

/// Runs [body] and converts database exceptions into [DatabaseError], keeping
/// the original stack trace. The message names the operation only; SQLite
/// error text is not forwarded.
Future<T> guardDatabase<T>(String operation, Future<T> Function() body) async {
  try {
    return await body();
  } on AppError {
    rethrow;
  } on ArgumentError {
    rethrow;
  } catch (error, stackTrace) {
    final kind = _isConstraintViolation(error)
        ? DatabaseErrorKind.constraintViolation
        : DatabaseErrorKind.failure;
    Error.throwWithStackTrace(
      DatabaseError(kind, '$operation failed'),
      stackTrace,
    );
  }
}

/// Throws [DatabaseErrorKind.notFound] when an update matched no rows.
void requireUpdated(int rowCount, String operation) {
  if (rowCount == 0) {
    throw DatabaseError(DatabaseErrorKind.notFound, '$operation: no such row');
  }
}

bool _isConstraintViolation(Object error) => switch (error) {
  SqliteException(:final resultCode) => resultCode == _sqliteConstraint,
  DriftRemoteException(:final remoteCause) => _isConstraintViolation(
    remoteCause,
  ),
  _ => false,
};
