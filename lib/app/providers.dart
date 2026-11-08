import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/logging/app_logger.dart';
import '../data/database/app_database.dart';
import '../data/preferences/reader_preferences_store.dart';
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
import '../domain/services/publication_inspector.dart';
import '../services/import/document_picker.dart';
import '../services/import/import_service.dart';
import '../services/library/book_removal_service.dart';
import '../services/reader/publication_reader.dart';
import '../services/reader/readium_publication_inspector.dart';
import '../services/reader/readium_publication_reader.dart';
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

/// Small global settings (CLAUDE.md §5). Bootstrap (or a test) must override
/// this with a loaded instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) =>
      throw UnimplementedError('sharedPreferencesProvider is not overridden'),
);

final readerPreferencesStoreProvider = Provider<ReaderPreferencesStore>(
  (ref) => ReaderPreferencesStore(ref.watch(sharedPreferencesProvider)),
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

/// The plugin instance. Only reader-service adapters may use it
/// (ADR-012); features depend on app-owned contracts instead.
final readiumProvider = Provider<FlutterReadium>((ref) => FlutterReadium());

/// The single reader engine session (READER_ENGINE_SPECIFICATION.md §5.3).
final publicationReaderProvider = Provider<PublicationReader>(
  (ref) => ReadiumPublicationReader(ref.watch(readiumProvider)),
);

final locatorInterpreterProvider = Provider<LocatorInterpreter>(
  (ref) => const ReadiumLocatorInterpreter(),
);

final publicationInspectorProvider = Provider<PublicationInspector>((ref) {
  final reader = ref.watch(publicationReaderProvider);
  return ReadiumPublicationInspector(
    ref.watch(readiumProvider),
    readerIsOpen: () => reader.isOpen,
  );
});

final documentPickerProvider = Provider<DocumentPicker>(
  (ref) => const FilePickerDocumentPicker(),
);

final importServiceProvider = Provider<ImportService>(
  (ref) => ImportService(
    storage: ref.watch(libraryStorageProvider),
    books: ref.watch(bookRepositoryProvider),
    inspector: ref.watch(publicationInspectorProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

final bookRemovalServiceProvider = Provider<BookRemovalService>(
  (ref) => BookRemovalService(
    storage: ref.watch(libraryStorageProvider),
    books: ref.watch(bookRepositoryProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);
