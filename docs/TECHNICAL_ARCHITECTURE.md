# Technical Architecture --- Offline-First Ebook Reader

**Document version:** 1.0\
**Date:** 7 November 2026\
**Status:** Proposed architecture\
**Platforms:** Android first, iOS second\
**Framework:** Flutter\
**Primary language:** Dart

------------------------------------------------------------------------

## 1. Executive summary

Build the application as an offline-first Flutter app with a shared Dart
codebase for Android and iOS. Flutter owns the application UI,
navigation, business logic, local data management, library experience,
settings, and backup/restore workflows.

Use **Readium through the `flutter_readium` plugin** as the initial
EPUB/PDF reading engine. The plugin provides a unified Dart-facing API
while delegating rendering and publication handling to the native
Readium toolkits on Android and iOS.

Use **Drift (SQLite)** for structured local data, app-private file
storage for imported publications, and a versioned ZIP archive with a
JSON manifest for manual backup and restore.

The product remains entirely usable offline. There are no accounts,
backend services, mandatory network calls, cloud sync, or analytics
dependency in the MVP.

> **Important dependency risk:** `flutter_readium` is actively evolving
> and its 0.9.0 release was published very recently as of this document
> date. Treat it as a high-risk integration dependency: pin the exact
> version initially, build a proof of concept, and validate all required
> Android and iOS behaviors before implementing the full reader
> experience.

## 2. Product and architecture goals

### 2.1 Product goals

1.  Provide a reliable personal library for EPUB and PDF files.
2.  Support comfortable offline reading.
3.  Preserve reading progress, bookmarks, and EPUB highlights.
4.  Keep user data and book files under the user's control.
5.  Support manual backup and restore without an account.
6.  Launch Android first while keeping iOS implementation feasible from
    the same codebase.

### 2.2 Architecture goals

-   Share UI and application logic across Android and iOS.
-   Isolate platform-specific behavior behind services and adapters.
-   Keep the database and file store as the local source of truth.
-   Make import, reading progress, and restore resilient to app
    termination.
-   Keep the reader engine replaceable if the Flutter Readium
    integration becomes unsuitable.
-   Make core business logic testable without launching a device or
    reader view.

### 2.3 Non-goals for the MVP

-   User accounts, authentication, backend, cloud sync.
-   Online bookstore or book discovery.
-   Social features or shared libraries.
-   DRM/LCP-protected publications.
-   Audiobooks, TTS, OCR, comic formats, or WebPub.
-   Advanced PDF annotation and editing.
-   Desktop or web releases.
-   Automatic cloud backup.

## 3. Architecture decisions

  -----------------------------------------------------------------------
  Area                    Decision                Rationale
  ----------------------- ----------------------- -----------------------
  Cross-platform          Flutter                 One shared UI and
  framework                                       application codebase

  Language                Dart                    Native Flutter
                                                  development language

  App architecture        MVVM + Repository       Clear separation of UI
                                                  state and data access

  State management / DI   Riverpod                Testable providers and
                                                  dependency wiring

  Navigation              go_router               Declarative navigation
                                                  and deep-link-ready
                                                  route structure

  EPUB/PDF engine         `flutter_readium`       Unified Dart API over
                                                  native Readium toolkits

  Local database          Drift + SQLite          Typed queries,
                                                  migrations,
                                                  transactions, reactive
                                                  streams

  Preferences             SharedPreferences       Small, non-relational
                          initially               settings only

  File import             file_picker + platform  User-selected documents
                          APIs as needed          

  App file paths          path_provider           App-private storage
                                                  locations

  Archive                 archive package or      Portable backup
                          equivalent maintained   container
                          ZIP library             

  Cover loading           Local file paths +      No network dependency
                          Flutter image widgets   

  Tests                   flutter_test +          Unit, widget, and
                          integration_test        device-level
                                                  verification
  -----------------------------------------------------------------------

These are initial decisions, not reasons to add abstractions everywhere.
Introduce extra packages only when they solve a real requirement.

## 4. High-level architecture

``` text
┌────────────────────────────────────────────────────────────┐
│                         Flutter UI                          │
│  Library · Book details · Reader shell · Bookmarks · Settings│
└──────────────────────────────┬─────────────────────────────┘
                               │ user actions / UI state
┌──────────────────────────────▼─────────────────────────────┐
│                    Presentation layer                        │
│              Screens · Widgets · ViewModels                  │
└──────────────────────────────┬─────────────────────────────┘
                               │
┌──────────────────────────────▼─────────────────────────────┐
│                      Domain layer                            │
│       Entities · Repository contracts · Use cases            │
│       Reading rules · Import rules · Backup rules             │
└──────────────────────────────┬─────────────────────────────┘
                               │
┌──────────────────────────────▼─────────────────────────────┐
│                        Data layer                            │
│    Repository implementations · Mappers · Data sources       │
└───────────────┬───────────────────────────────┬─────────────┘
                │                               │
┌───────────────▼──────────────┐  ┌─────────────▼────────────┐
│        Local persistence     │  │      Platform services   │
│  Drift / SQLite              │  │  File picker             │
│  App-private publication     │  │  File system             │
│  files                       │  │  Reader plugin            │
│  SharedPreferences           │  │  Lifecycle integration   │
└──────────────────────────────┘  └──────────────────────────┘
```

### 4.1 Dependency direction

-   UI depends on ViewModels/controllers.
-   ViewModels depend on repository contracts and/or use cases.
-   Repository implementations depend on data sources.
-   Data sources wrap Drift, the file system, and the reader plugin.
-   Domain models must not import Flutter widgets, Drift-generated
    classes, or Readium plugin types.
-   Platform-specific code must not leak into domain models.

### 4.2 Architectural style

Use feature-oriented MVVM with a lightweight domain layer:

-   **View:** renders state and forwards user events.
-   **ViewModel/controller:** coordinates UI state and user actions.
-   **Repository:** source of truth for app data.
-   **Service/data source:** wraps a concrete system such as SQLite,
    local files, document picker, or Readium.
-   **Use case:** add when a workflow has meaningful business rules or
    is reused. Do not create a use-case class for every trivial database
    call.

## 5. Suggested project structure

``` text
reader_app/
├── android/
├── ios/
├── assets/
│   ├── fonts/
│   ├── icons/
│   └── images/
├── lib/
│   ├── app/
│   │   ├── app.dart
│   │   ├── router.dart
│   │   ├── bootstrap.dart
│   │   └── providers.dart
│   │
│   ├── core/
│   │   ├── errors/
│   │   ├── extensions/
│   │   ├── logging/
│   │   ├── result/
│   │   ├── theme/
│   │   └── utils/
│   │
│   ├── domain/
│   │   ├── entities/
│   │   ├── enums/
│   │   ├── repositories/
│   │   └── use_cases/
│   │
│   ├── data/
│   │   ├── database/
│   │   │   ├── app_database.dart
│   │   │   ├── tables/
│   │   │   ├── daos/
│   │   │   └── migrations/
│   │   ├── repositories/
│   │   ├── datasources/
│   │   │   ├── local/
│   │   │   ├── files/
│   │   │   └── reader/
│   │   └── mappers/
│   │
│   ├── services/
│   │   ├── import/
│   │   ├── storage/
│   │   ├── backup/
│   │   └── reader/
│   │
│   ├── features/
│   │   ├── library/
│   │   │   ├── presentation/
│   │   │   └── application/
│   │   ├── book_details/
│   │   ├── reader/
│   │   ├── bookmarks/
│   │   ├── highlights/
│   │   ├── history/
│   │   └── settings/
│   │
│   └── main.dart
│
├── test/
│   ├── domain/
│   ├── data/
│   ├── services/
│   └── features/
├── integration_test/
├── docs/
│   ├── PRD.md
│   ├── TECHNICAL_ARCHITECTURE.md
│   ├── DATABASE_SCHEMA.md
│   ├── BACKUP_FORMAT.md
│   └── IMPLEMENTATION_PLAN.md
├── pubspec.yaml
└── README.md
```

Keep feature-specific screens and ViewModels within `features/`. Put
reusable infrastructure and data contracts in the shared layers. Avoid
creating a separate Flutter package for every feature in the MVP.

## 6. Core application modules

### 6.1 Library

Responsibilities: - List imported publications. - Display covers, title,
author, format, and reading status. - Search, sort, and filter the
library. - Open book details and reader. - Remove a publication from the
library, with a clear distinction between removing metadata and deleting
the stored file.

### 6.2 Import and file management

Import workflow:

1.  User selects one or more EPUB/PDF files through the system document
    picker.
2.  Validate file extension, MIME type where available, file size, and
    readable content.
3.  Copy the selected file into app-private storage. Do not depend on a
    temporary picker URI or the original external file remaining
    accessible.
4.  Extract publication metadata and cover using the reader engine where
    supported.
5.  Generate a stable internal book ID.
6.  Store the publication record and file path in Drift.
7.  If any step fails, clean up the partially copied file and report a
    recoverable error.

Use a staging directory during import. Move the file into its final
location only after validation succeeds.

Suggested file layout:

``` text
<ApplicationSupportDirectory>/
└── library/
    ├── books/
    │   └── <book-id>/
    │       ├── publication.epub
    │       └── cover.jpg
    ├── staging/
    └── backups/
```

Do not use the original filename as the only identifier. Sanitize
filenames and avoid path traversal. The database stores relative paths
where practical, not hard-coded absolute paths.

### 6.3 Reader

The reader module has two parts:

1.  **Reader shell (Flutter):** app bar, back navigation, table of
    contents entry point, reading controls, theme/font controls,
    bookmark/highlight controls, progress UI.
2.  **Publication navigator (Readium):** renders EPUB/PDF content and
    handles pagination, scrolling, text selection, and format-specific
    navigation.

Keep the reader plugin behind an application-owned interface, for
example:

``` dart
abstract interface class PublicationReaderService {
  Future<OpenedPublication> open({
    required String bookId,
    required String localPath,
    required PublicationFormat format,
    String? initialLocatorJson,
  });

  Future<void> close(String bookId);

  Stream<ReaderEvent> get events;

  Future<void> goToLocator(String locatorJson);
  Future<void> goToNext();
  Future<void> goToPrevious();
  Future<void> setPreferences(ReaderPreferences preferences);
  Future<void> addBookmark(String locatorJson);
}
```

This is an application contract, not a claim that the plugin exposes
these exact methods. Implement an adapter that maps the actual
`flutter_readium` API to this contract. Keep plugin types inside the
adapter.

The reader service must: - Open only locally stored files in the MVP. -
Restore a saved locator when reopening a book. - Emit position changes
and reader errors. - Close publications and release resources when
leaving the reader. - Translate plugin events into app-owned
`ReaderEvent` models. - Persist progress without blocking page
navigation.

### 6.4 Reading progress

-   EPUB: store the serialized Readium locator, including its href,
    type, text context, and CFI/location information when supplied.
-   PDF: store page number and any stable location fields supplied by
    the reader engine.
-   Store progression as a display aid, not the only restoration key.
-   Debounce high-frequency locator events before database writes.
-   Persist on meaningful navigation, a short inactivity debounce, app
    backgrounding, and reader close.
-   Do not rely only on an app-close callback; mobile operating systems
    may terminate the process without one.
-   Restore only after the reader reports that the publication is ready.

A shared app model should not assume that EPUB and PDF locators have
identical semantics.

### 6.5 Bookmarks and highlights

-   A bookmark is a saved location with an optional label and timestamp.
-   EPUB highlights are stored with their locator, selected text,
    color/style, and optional note.
-   Use the reader engine's annotation/decorator API for rendering EPUB
    highlights.
-   PDF annotation support beyond basic page bookmarks is out of MVP
    unless the integration spike proves a reliable supported
    implementation.
-   Store serialized locator data and a schema version so it can be
    migrated if the reader engine changes.

### 6.6 Settings

Store global preferences separately from relational library data: - App
theme: system/light/dark. - Default reading theme. - Default font size
and font family. - Default pagination/scroll mode where supported. -
Default sort order. - Import and library display preferences.

Use SharedPreferences for small primitive settings. If preferences
become relational, require transactional updates, or need complex
queries, move them to Drift rather than splitting state across stores
without reason.

## 7. Data model

The following is a conceptual schema. Exact Drift column types and
indexes should be finalized in `DATABASE_SCHEMA.md`.

### 7.1 Books

  Field           Type          Notes
  --------------- ------------- -----------------------------------
  id              TEXT / UUID   Primary key
  title           TEXT          Required
  authors         TEXT          Normalized or serialized list
  format          TEXT          EPUB or PDF
  filePath        TEXT          App-private relative path
  coverPath       TEXT?         Local cover image
  fileSizeBytes   INTEGER       Imported file size
  fileChecksum    TEXT          Integrity and duplicate detection
  addedAt         INTEGER       UTC epoch
  lastOpenedAt    INTEGER?      UTC epoch
  readingStatus   TEXT          unread, reading, finished
  metadataJson    TEXT?         Optional source metadata

### 7.2 ReadingProgress

  Field         Type       Notes
  ------------- ---------- ----------------------------------
  bookId        TEXT       Primary key and FK to Books
  locatorJson   TEXT?      Serialized reader locator
  pageNumber    INTEGER?   PDF/current page when applicable
  progression   REAL?      Display percentage/progression
  updatedAt     INTEGER    UTC epoch

### 7.3 Bookmarks

  Field         Type          Notes
  ------------- ------------- ---------------------
  id            TEXT / UUID   Primary key
  bookId        TEXT          FK to Books
  locatorJson   TEXT          Serialized location
  label         TEXT?         User-defined label
  createdAt     INTEGER       UTC epoch

### 7.4 Highlights

  Field          Type          Notes
  -------------- ------------- -------------------------------
  id             TEXT / UUID   Primary key
  bookId         TEXT          FK to Books
  locatorJson    TEXT          Serialized selection/location
  selectedText   TEXT?         Extracted text, if available
  color          TEXT          App-owned color token
  note           TEXT?         User note
  createdAt      INTEGER       UTC epoch
  updatedAt      INTEGER       UTC epoch

### 7.5 Collections

  Field       Type          Notes
  ----------- ------------- -------------
  id          TEXT / UUID   Primary key
  name        TEXT          Required
  createdAt   INTEGER       UTC epoch

### 7.6 CollectionBooks

Join table with `collectionId`, `bookId`, and `addedAt`. Add a unique
constraint on the pair.

### 7.7 ReadingHistory

Use a separate history table only if the product needs a timeline of
sessions. Otherwise `lastOpenedAt` and current progress are sufficient
for the MVP. Avoid storing redundant data.

### 7.8 Database constraints

-   Enable foreign keys.
-   Use transactions for multi-table workflows.
-   Index book title, author/search fields, added date, and foreign
    keys.
-   Use explicit migrations and test every migration from a prior schema
    version.
-   Store timestamps in UTC.
-   Never store entire publication file bytes in SQLite.

## 8. Backup and restore architecture

### 8.1 Backup types

**Full backup** - Book files. - Metadata. - Collections. - Reading
progress. - Bookmarks. - EPUB highlights and notes. - Relevant user
preferences.

**Library-only backup** - Metadata and library organization. - Progress,
bookmarks, highlights and notes. - No publication files.

### 8.2 Archive structure

``` text
reader-backup-<timestamp>.zip
├── manifest.json
├── database/
│   └── library.json
└── books/
    ├── <book-id>/
    │   ├── publication.epub
    │   └── cover.jpg
    └── <book-id>/
        └── publication.pdf
```

Prefer a portable, explicit JSON export rather than blindly copying a
live SQLite database file. This avoids SQLite WAL/SHM consistency
problems and allows schema migration across app versions.

### 8.3 Manifest

Include: - Backup format identifier. - Backup format version. - App
version. - Creation timestamp. - Backup type (`full` or
`library_only`). - Book records and archive-relative file paths. - File
sizes and SHA-256 checksums. - Database/export schema version.

### 8.4 Restore workflow

1.  User selects a backup archive.
2.  Validate ZIP structure, manifest, supported version, file paths,
    sizes, and checksums.
3.  Show a restore summary and explain conflict behavior.
4.  Extract into a staging directory.
5.  Validate imported publications.
6.  Build the restored database state in a temporary database or
    transactional import operation.
7.  Commit only after validation succeeds.
8.  Preserve the current library if restore fails.
9.  Clean up staging files after success or failure.

Never overwrite the current library without explicit confirmation.
Define duplicate behavior by stable book ID and checksum; do not
silently create duplicate books.

### 8.5 Security and robustness

-   Reject absolute paths and `../` traversal in archive entries.
-   Limit total expanded archive size and individual file size.
-   Protect against ZIP bombs and malformed manifests.
-   Verify checksums before importing.
-   Never execute scripts or macros from imported publications.
-   Do not upload backup contents to a server.

## 9. Offline-first and privacy requirements

-   Core library and reader features must work in airplane mode.
-   Do not require account creation.
-   Do not require a network connection to import, open, or read local
    publications.
-   Do not add analytics or crash-reporting SDKs without an explicit
    product decision and privacy review.
-   Avoid requesting broad storage permissions when the system document
    picker can provide access to user-selected files.
-   Do not log book contents, selected text, notes, or full local paths.
-   Provide a clear delete flow and distinguish removing a book from
    deleting its file.
-   The app must not depend on a cloud service for database
    initialization or reader startup.

## 10. Platform-specific considerations

### 10.1 Android

-   Minimum SDK: follow the selected `flutter_readium` release
    requirements; currently documented as API 24 or higher.
-   Configure compile SDK, Android Gradle Plugin, Gradle, Kotlin plugin
    and desugaring exactly as required by the pinned plugin release.
-   Verify the required Activity base class and manifest configuration
    from the plugin's installation guide.
-   Use Android's system document picker for imports and the Storage
    Access Framework for user-selected export destinations.
-   Test process death, low-memory conditions, rotation, split-screen,
    and app backgrounding.

### 10.2 iOS

-   Deployment target: follow the pinned plugin release requirements;
    currently documented as iOS 15 or higher.
-   Use the iOS document picker for imports and exports.
-   Verify CocoaPods / Swift package setup and minimum deployment target
    against the plugin's installation guide.
-   Test app suspension, termination, file protection behavior, and
    restoration.
-   Validate reader view lifecycle and memory use on smaller devices and
    iPad.

### 10.3 Shared behavior

Keep product rules, models, repositories, backup schema, and screens
shared. Use platform adapters only for capabilities that genuinely
differ, such as document picker, file URLs, lifecycle events, and native
plugin configuration.

## 11. Error handling and reliability

Define typed application errors, for example: - `ImportError`:
unsupported format, invalid file, inaccessible source, insufficient
storage. - `PublicationOpenError`: corrupted publication, unsupported
feature, reader initialization failure. - `StorageError`: read/write
failure, missing file, permission loss. - `BackupError`: invalid
archive, unsupported version, checksum mismatch, insufficient storage. -
`DatabaseError`: migration failure, constraint violation, transaction
failure.

User-facing errors should explain what happened and what the user can
do. Internal logs should include diagnostic context without exposing
private reading content.

Critical operations (import, delete, restore) must be idempotent or
recoverable. Use staging directories and database transactions to
prevent partial state.

## 12. Performance requirements

Initial targets to validate on representative low- and mid-range Android
devices: - Library screen renders without waiting for every cover image
to decode. - Large libraries use paginated/lazy lists. - Database
queries are indexed and do not block the UI isolate. - File hashing,
archive compression, metadata extraction and large file operations run
off the UI isolate where appropriate. - Progress writes are debounced. -
Reader open time and memory usage are measured separately for EPUB and
PDF. - Large PDF tests include memory pressure and repeated open/close
cycles.

Do not set arbitrary performance claims before measuring representative
files and devices.

## 13. Testing strategy

### Unit tests

-   Domain models and reading status rules.
-   Repository behavior.
-   Import validation and duplicate detection.
-   Locator serialization/deserialization.
-   Backup manifest validation and checksum verification.
-   Restore conflict and rollback logic.

### Database tests

-   DAO CRUD operations.
-   Foreign key behavior.
-   Transactions.
-   Schema migrations.
-   Large-library queries.

### Widget tests

-   Library loading, empty and error states.
-   Search, sort and filter behavior.
-   Book details and settings.
-   Bookmark/highlight lists.
-   Restore confirmation and progress states.

### Integration tests

-   Import EPUB and PDF.
-   Open, close, and reopen a publication.
-   Restore reading position after process restart.
-   Create and retrieve bookmarks.
-   Create EPUB highlights and restore them.
-   Full backup and restore.
-   Library-only backup and restore.
-   Corrupt archive and insufficient-storage failure paths.
-   Airplane-mode operation.
-   Android and iOS parity for required MVP features.

### Reader engine compatibility tests

Run a dedicated compatibility suite against the pinned `flutter_readium`
version. Test: - EPUB 2 and EPUB 3 samples. - Reflowable EPUB and
fixed-layout EPUB if in scope. - PDFs with different page sizes and
large file sizes. - Internal links and table of contents. - Font, theme,
pagination and scrolling preferences. - Position restoration after
closing and reopening. - Text selection, highlights, and annotation
persistence. - Search behavior and known platform differences.

## 14. Implementation plan

### Phase 0 --- Technical spike (mandatory)

-   Create a minimal Flutter project.
-   Pin the selected `flutter_readium` version.
-   Configure Android and iOS builds.
-   Import and open local EPUB/PDF on Android.
-   Validate position, bookmarks, EPUB highlights, preferences, and
    lifecycle.
-   Run the same critical checks on an iOS simulator.
-   Record plugin limitations and any native workarounds.

**Exit criterion:** The core reader capabilities required by the MVP
work on both platforms, or there is a documented mitigation and
acceptable fallback.

### Phase 1 --- Foundation

-   Establish project structure and lint rules.
-   Configure Riverpod and go_router.
-   Add Drift and database migrations.
-   Implement app-private storage and file import abstractions.
-   Set up unit/widget test infrastructure.

### Phase 2 --- Library

-   Import EPUB/PDF.
-   Extract metadata and covers.
-   Library list/grid.
-   Search, sort, filter.
-   Book details and remove/delete behavior.

### Phase 3 --- Reader

-   Readium adapter.
-   EPUB/PDF reader shell.
-   Progress persistence and restoration.
-   Reading preferences.
-   Bookmarks.
-   EPUB highlights and notes.

### Phase 4 --- Backup and restore

-   Portable JSON export schema.
-   Full and library-only ZIP backups.
-   Validation, staging, restore preview and safe commit.
-   Cross-platform backup compatibility tests.

### Phase 5 --- Android MVP hardening and release

-   Accessibility and responsive layout.
-   Performance and memory testing.
-   Data-loss and process-death testing.
-   Crash and error-path testing.
-   Android distribution preparation.

### Phase 6 --- iOS release

-   Complete iOS-specific import/export and lifecycle integration.
-   Verify reader parity.
-   Test iPhone and iPad layouts.
-   Validate backup interoperability.
-   Prepare signing and App Store release.

The iOS build target should be kept compiling throughout Android
development. Do not wait until Android release to discover that a shared
dependency or plugin has broken iOS builds.

## 15. Risks and mitigations

  -----------------------------------------------------------------------
  Risk                    Impact                  Mitigation
  ----------------------- ----------------------- -----------------------
  `flutter_readium` is    Reader bugs or breaking Pin exact version,
  new and rapidly         APIs                    maintain a
  changing                                        compatibility suite,
                                                  upgrade deliberately

  Feature behavior        Android/iOS             Test both platforms
  differs by platform     inconsistency           during Phase 0 and
                                                  every release candidate

  Plugin does not expose  MVP scope blocked       Verify APIs early;
  a needed Readium                                contribute upstream or
  feature                                         build a small native
                                                  extension

  EPUB locator format     Lost                    Store serialized
  changes                 progress/annotations    locator plus
                                                  schema/version
                                                  metadata; test
                                                  migration

  Large PDFs cause memory Crashes or poor reading Device testing,
  pressure                experience              lifecycle cleanup,
                                                  representative
                                                  large-file tests

  Backup archive is       Data loss or resource   Validate paths, limits,
  malformed or malicious  exhaustion              checksums, and stage
                                                  before commit

  iOS file access expires Missing imported books  Copy selected files
                                                  into app-private
                                                  storage during import

  Database/file           Orphaned files or       Staging, transactions,
  operations become       records                 cleanup and recovery
  inconsistent                                    routines
  -----------------------------------------------------------------------

### Specific dependency note

At the time of writing, `flutter_readium` 0.9.0 is a very recent
release. Do not automatically track a floating dependency range during
the initial implementation. Pin the exact tested version in
`pubspec.yaml`, record the corresponding native toolkit versions, and
upgrade only after the compatibility suite passes.

## 16. Definition of done for the MVP

The MVP is complete when:

-   A user can import EPUB and PDF files without an account.
-   Imported books remain available after app restart and work offline.
-   The library can be searched, sorted and organized.
-   EPUB and PDF can be opened and read.
-   Reading position is restored reliably.
-   Users can create bookmarks.
-   Users can create and retrieve EPUB highlights and notes.
-   Reading preferences persist.
-   Full and library-only backups can be created.
-   Restore validates archives and does not destroy the current library
    on failure.
-   Core functionality passes Android tests.
-   iOS builds successfully and the shared core behavior has been
    validated on iOS.
-   No core feature requires a backend or network connection.

## 17. Architecture rules for contributors and coding agents

1.  Keep application business logic in Dart and independent of Flutter
    widgets.
2.  Do not use Readium plugin types outside the reader adapter.
3.  Do not store publication file bytes in SQLite.
4.  Do not treat a temporary document-picker URI as permanent storage.
5.  Do not use page percentage as the only reading-position key.
6.  Do not perform long-running file, hashing, or archive work on the UI
    isolate.
7.  Use Drift migrations for every schema change.
8.  Use transactions for related database changes.
9.  Keep backup format portable and versioned.
10. Test Android and iOS behavior for every reader-engine upgrade.
11. Do not add cloud, account, analytics, or network dependencies
    without an explicit product decision.
12. Keep the iOS target buildable while implementing Android-first
    features.
13. Document deviations from this architecture in an Architecture
    Decision Record (ADR).

## 18. References

-   Flutter app architecture:
    https://docs.flutter.dev/app-architecture/guide
-   Flutter architecture recommendations:
    https://docs.flutter.dev/app-architecture/recommendations
-   `flutter_readium` package: https://pub.dev/packages/flutter_readium
-   `flutter_readium` API documentation:
    https://pub.dev/documentation/flutter_readium/latest/
-   Drift documentation: https://pub.dev/packages/drift
-   Riverpod documentation: https://riverpod.dev/
-   go_router documentation: https://pub.dev/packages/go_router

------------------------------------------------------------------------

**Decision summary:** Flutter + Dart, feature-oriented MVVM, Riverpod,
go_router, Drift/SQLite, `flutter_readium` behind an application-owned
reader adapter, app-private publication files, and a versioned portable
backup format. Android is the first release target; iOS compatibility is
validated from the beginning.
