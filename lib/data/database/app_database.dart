import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../../domain/entities/enums.dart';
import 'converters.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// The single application database (DATABASE_SCHEMA.md §8.2). Generated
/// row classes stay inside the data layer; repositories map them to domain
/// entities.
@DriftDatabase(
  tables: [
    Books,
    ReadingProgressEntries,
    Bookmarks,
    Highlights,
    Collections,
    CollectionBooks,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Opens the database file at [file] on a background isolate so queries
  /// never block the UI isolate.
  factory AppDatabase.open(File file) =>
      AppDatabase(NativeDatabase.createInBackground(file));

  /// Increase for every schema change and add an explicit, tested step to
  /// [migration]. Never use a destructive migration (DATABASE_SCHEMA.md §10).
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    beforeOpen: (details) async {
      // SQLite disables foreign keys per connection by default; cascades and
      // references depend on this being on for every open.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
