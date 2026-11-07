import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_logger.dart';
import '../data/database/app_database.dart';
import '../data/repositories/drift_book_repository.dart';
import '../data/repositories/drift_bookmark_repository.dart';
import '../data/repositories/drift_collection_repository.dart';
import '../data/repositories/drift_highlight_repository.dart';
import '../data/repositories/drift_reading_progress_repository.dart';
import '../domain/repositories/book_repository.dart';
import '../domain/repositories/bookmark_repository.dart';
import '../domain/repositories/collection_repository.dart';
import '../domain/repositories/highlight_repository.dart';
import '../domain/repositories/reading_progress_repository.dart';
import '../services/storage/library_storage.dart';

// Composition root. Features depend on the domain contracts exposed here;
// only this file knows the Drift-backed implementations.

/// App-wide logger. Bootstrap overrides this with the instance it uses for
/// global error handlers, so there is a single logger per app run.
final appLoggerProvider = Provider<AppLogger>((ref) => AppLogger());

/// The opened database. Bootstrap (or a test) must override this.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('appDatabaseProvider is not overridden'),
);

/// The opened library storage. Bootstrap (or a test) must override this.
final libraryStorageProvider = Provider<LibraryStorage>(
  (ref) => throw UnimplementedError('libraryStorageProvider is not overridden'),
);

final bookRepositoryProvider = Provider<BookRepository>(
  (ref) => DriftBookRepository(ref.watch(appDatabaseProvider)),
);

final readingProgressRepositoryProvider = Provider<ReadingProgressRepository>(
  (ref) => DriftReadingProgressRepository(ref.watch(appDatabaseProvider)),
);

final bookmarkRepositoryProvider = Provider<BookmarkRepository>(
  (ref) => DriftBookmarkRepository(ref.watch(appDatabaseProvider)),
);

final highlightRepositoryProvider = Provider<HighlightRepository>(
  (ref) => DriftHighlightRepository(ref.watch(appDatabaseProvider)),
);

final collectionRepositoryProvider = Provider<CollectionRepository>(
  (ref) => DriftCollectionRepository(ref.watch(appDatabaseProvider)),
);
