# Testing Strategy

**Project:** Offline-first EPUB and PDF reader  
**Platforms:** Android first, iOS second  
**Stack:** Flutter, Dart, Riverpod, go_router, Drift/SQLite, `flutter_readium`  
**Status:** Working test strategy for the MVP

---

## 1. Purpose

This document defines how the reader app will be tested throughout development and before release. It establishes the test layers, platform coverage, critical user journeys, quality gates, and release criteria.

The strategy prioritises the risks that could cause data loss or make the core reading experience unreliable:

1. Imported publications must remain available offline.
2. Reading position must be saved and restored accurately.
3. EPUB and PDF rendering and navigation must behave correctly.
4. Bookmarks, highlights, notes, and library metadata must remain consistent.
5. Backup and restore must preserve user data and handle invalid archives safely.
6. Android and iOS must behave consistently where the underlying platform capabilities permit.

Testing must be incremental. Do not wait until the entire app is implemented to validate the reader engine, file handling, or backup system.

## 2. Quality objectives

| Area | Quality objective |
|---|---|
| Functional correctness | Every MVP feature meets its documented acceptance criteria |
| Data integrity | No silent loss or corruption of books, annotations, or progress |
| Offline reliability | Core reading and library workflows work without network access |
| Reading continuity | A publication reopens at the last successfully saved locator |
| Platform compatibility | Supported features work on Android and iOS |
| Performance | Library and reader remain responsive with realistic libraries and large files |
| Accessibility | Core flows support screen readers, text scaling, and adequate contrast |
| Privacy | Imported files and reading data remain local; no unexpected network traffic |
| Recoverability | Interrupted imports and restores do not leave the library in an inconsistent state |

## 3. Test levels

Use the smallest test level that can reliably verify the behaviour. Add higher-level tests for critical user journeys.

### 3.1 Static analysis and code quality

Run these checks during development and in CI:

- `dart format --output=none --set-exit-if-changed .`
- `flutter analyze`
- Dependency and lockfile review.
- Review for unhandled asynchronous errors, unsafe casts, and unawaited futures.
- Review file-path handling and archive extraction for path traversal risks.

Static analysis is necessary but does not replace runtime tests.

### 3.2 Unit tests

Test isolated domain logic and pure functions without launching Flutter widgets or the reader engine.

Examples:

- Reading status and progress calculations.
- Locator envelope serialization, parsing, and version migration.
- File-name sanitisation and supported-format validation.
- Backup manifest validation.
- SHA-256 checksum comparison.
- Backup conflict-resolution rules.
- Import and restore state transitions.
- Sorting, filtering, and collection membership rules.
- Preference validation and defaults.

Use deterministic fixtures. Avoid depending on the current time, device locale, or filesystem ordering unless those are explicitly part of the test.

### 3.3 Repository and database tests

Test repositories against a real Drift database configured for tests, preferably using an in-memory SQLite database for most cases.

Verify:

- CRUD operations for every table.
- Foreign-key constraints and cascade behaviour.
- Unique constraints and indexes.
- Transactions and rollback behaviour.
- Migration from every supported previous schema version.
- Handling of missing or invalid related records.
- Correct ordering and filtering of library results.
- Progress and annotation persistence.
- Collection membership consistency.

At least one test suite must use a file-backed SQLite database to verify close/reopen persistence. In-memory tests alone are insufficient for validating persistence behaviour.

### 3.4 File-storage and import tests

Use temporary directories and test files. Do not use a developer's real ebook library as test data.

Verify:

- Import copies the selected file into app-private storage.
- The original source file is not modified or deleted.
- Duplicate detection follows the documented product rule.
- File names with spaces, Unicode, punctuation, and long names are handled safely.
- Large files can be imported without loading the entire file into memory.
- Interrupted imports are cleaned up or recoverable.
- A database record is not left pointing to a nonexistent file.
- Missing files are surfaced as recoverable library states.
- Deleting a book removes only the app-managed copy, after the user confirms the action.
- Temporary files are removed after success, cancellation, and failure.

Test file operations together with database updates. Treat import, deletion, and restore as multi-step operations that need explicit recovery behaviour.

### 3.5 Reader-engine adapter tests

Keep `flutter_readium` behind an app-owned adapter/service boundary. Test the app-owned contract independently using a fake implementation, then test the real adapter against the exact pinned plugin version.

Fake-adapter tests should cover:

- Opening and closing a publication.
- One active reader session at a time.
- Loading and reporting publication metadata.
- Table-of-contents retrieval.
- Locator updates and restoration.
- Forward/backward navigation.
- Search result mapping.
- Preference updates.
- Bookmark and highlight decoration mapping.
- External-link handling.
- Reader errors and lifecycle events.
- Disposal and cancellation during navigation or opening.

Real-plugin tests must verify that the adapter's mappings match the installed package API. Do not mock away the native bridge in every test: at least a small integration suite must exercise the actual Android and iOS plugin implementations.

### 3.6 Widget tests

Use Flutter widget tests for UI behaviour that can be tested without a native publication renderer.

Examples:

- Library empty, loading, populated, and error states.
- Search and filter interactions.
- Book cards and metadata presentation.
- Collection creation and editing.
- Import progress and failure messages.
- Bookmark and annotation lists.
- Settings controls and preference persistence wiring.
- Confirmation dialogs and destructive actions.
- Accessibility labels and semantic order for important controls.

For reader screens, test the app-owned surrounding UI and state handling with a fake reader surface. Validate the real rendering surface in integration tests.

### 3.7 Integration and end-to-end tests

Run tests on real or representative Android and iOS environments. Cover complete user journeys across UI, state management, database, filesystem, and native reader integration.

Prioritise critical paths over exhaustive UI automation. Keep a smaller stable smoke suite for every pull request and a broader regression suite for release candidates.

## 4. Test environments and platform matrix

### 4.1 Required environments

| Environment | Purpose |
|---|---|
| Flutter unit/widget test environment | Fast feedback on domain, state, repositories, and UI |
| Android emulator | Android integration and end-to-end tests |
| Android physical device | File picker, lifecycle, storage, rendering, and performance validation |
| iOS simulator | iOS build, integration, and UI validation |
| iOS physical device | Native reader, document picker, lifecycle, and performance validation |
| CI environment | Repeatable formatting, analysis, tests, and build checks |

Use at least one lower/mid-range Android device in addition to a current flagship-class device. Test on the minimum supported OS version and a current OS version before release.

### 4.2 Platform-specific coverage

| Capability | Android | iOS |
|---|---:|---:|
| App build and launch | Required | Required |
| Document picker import | Required | Required |
| Private file persistence after restart | Required | Required |
| EPUB rendering and navigation | Required | Required |
| PDF rendering and navigation | Required | Required |
| Progress save and restore | Required | Required |
| Bookmarks | Required | Required |
| EPUB highlights and notes | Required | Required |
| Search | Required | Required |
| Backup export and restore | Required | Required |
| App background/foreground lifecycle | Required | Required |
| Interrupted import/restore recovery | Required | Required |
| Accessibility smoke test | Required | Required |

A feature must not be marked cross-platform complete based only on an Android test. Record any known platform-specific differences explicitly.

## 5. Test data and fixtures

Maintain a small, legally usable fixture library in the repository or a dedicated test-assets location. Do not commit copyrighted commercial books or personal documents.

Recommended fixtures:

| Fixture | Purpose |
|---|---|
| EPUB 2, reflowable | Legacy EPUB compatibility |
| EPUB 3, reflowable | Main EPUB reading path |
| EPUB with nested table of contents | TOC hierarchy and navigation |
| EPUB with embedded fonts and images | Resource loading and typography |
| EPUB with right-to-left text | Direction and layout validation |
| EPUB with long chapters | Scrolling and progress persistence |
| EPUB with unusual metadata | Metadata parsing and fallback behaviour |
| EPUB with malformed package data | Error handling |
| Small text-based PDF | Basic PDF rendering |
| Multi-page PDF | Page navigation and progress |
| Large PDF | Memory and performance |
| Scanned/image-heavy PDF | Rendering and resource use |
| Corrupt or truncated PDF | Error handling |
| Duplicate-content files with different names | Duplicate policy |
| Backup archives: valid, invalid, old-version, incomplete | Backup validation and migration |

For each fixture, record its origin, licence, expected behaviour, and checksum. Keep fixtures minimal and deterministic.

## 6. Critical user journeys

These end-to-end journeys are release-critical.

### Journey A: Import and read an EPUB

1. Launch the app.
2. Import a valid EPUB using the system document picker.
3. Confirm the book appears in the library with expected metadata.
4. Open the book.
5. Navigate to another chapter.
6. Change a reading preference.
7. Leave the reader and reopen the book.
8. Confirm the last saved position and preference are restored.

**Pass criteria:** The book is copied into app-private storage, opens successfully, and restores the expected reading state after reopening and app restart.

### Journey B: Import and read a PDF

1. Import a valid PDF.
2. Open it from the library.
3. Navigate between pages.
4. Change supported PDF viewing preferences.
5. Close and reopen the PDF.
6. Confirm the saved page/locator is restored.

**Pass criteria:** Pages render correctly, navigation is stable, and progress is restored within the accuracy supported by the reader engine.

### Journey C: Save and restore reading progress

1. Open a publication.
2. Read or navigate to a known location.
3. Wait for the app's progress-save mechanism to complete.
4. Force-close and relaunch the app.
5. Reopen the publication.

**Pass criteria:** The publication returns to the most recently committed locator. The app must not claim that progress is saved before persistence succeeds.

### Journey D: Create and revisit annotations

1. Open an EPUB.
2. Select text and create a highlight.
3. Add a note to the highlight, if supported by the product design.
4. Navigate away and close the publication.
5. Reopen it and inspect the annotation.
6. Open the annotation list and navigate back to its location.

**Pass criteria:** Annotation text, locator, colour/style metadata, and note content remain associated with the correct publication and can be revisited.

### Journey E: Export and restore a full backup

1. Import multiple publications.
2. Create collections, bookmarks, highlights, notes, and reading progress.
3. Export a full backup.
4. Validate the archive manifest and checksums.
5. Restore into a clean app installation or isolated test profile.
6. Compare the restored library and user data with the source.

**Pass criteria:** All included records and publication files are restored and usable. The restore process reports any skipped or failed item clearly.

### Journey F: Restore a library-only backup

1. Export a library-only backup.
2. Restore it into a clean installation.
3. Inspect the restored book records.
4. Attempt to open a publication whose file was not included.

**Pass criteria:** Metadata and supported library data are restored. Missing publication files are clearly represented as unavailable and do not cause crashes or false claims that the book is readable.

### Journey G: Work fully offline

1. Disable network connectivity.
2. Launch the app.
3. Browse and search the library.
4. Open EPUB and PDF files.
5. Navigate, bookmark, highlight, and update progress.
6. Export a backup to an available local destination.

**Pass criteria:** All core local workflows function without a network connection. No account, server, or cloud dependency blocks reading.

## 7. Feature-specific test cases

### 7.1 Library and metadata

- Empty library state.
- Import one file and multiple files.
- Unsupported extension and invalid file content.
- Missing title, author, cover, or publication metadata.
- Duplicate import according to the defined duplicate policy.
- Search by title and author.
- Sort by title, author, date added, and last read where implemented.
- Filter by reading status.
- Create, rename, and delete a collection.
- Add and remove books from collections.
- Delete a book and verify related data follows the documented deletion policy.

### 7.2 EPUB reader

- EPUB 2 and EPUB 3 opening.
- Reflowable content and chapter transitions.
- TOC hierarchy and chapter navigation.
- Font size, font family, line spacing, margins, and theme where supported.
- Portrait and landscape orientation.
- Text selection and highlight creation.
- Annotation persistence and navigation.
- Search within publication.
- External links and embedded resources.
- RTL and Unicode content.
- Large chapters and long publications.
- Invalid or unsupported publication error handling.

### 7.3 PDF reader

- Open and render first page.
- Navigate forward and backward.
- Jump to a page where supported.
- Restore page/progression after reopening.
- Zoom and fit behaviour where supported.
- Portrait/landscape pages and mixed page sizes.
- Large and image-heavy documents.
- Corrupt document handling.
- Confirm unsupported annotation capabilities are not exposed as working features.

### 7.4 Reading progress

- Save progress after navigation.
- Save progress after a defined debounce or lifecycle event.
- Restore from a valid locator.
- Handle malformed or outdated locator data.
- Handle a locator that no longer resolves.
- Distinguish EPUB progression from PDF page position.
- Preserve the last valid locator if a later save fails.
- Avoid excessive database writes during continuous scrolling.

Do not rely on percentage alone as the source of truth. Persist the reader engine's locator in the app's versioned locator envelope, along with any useful fallback position fields defined by the data model.

### 7.5 Bookmarks, highlights, and notes

- Create, edit, and delete bookmarks.
- Navigate from a bookmark to its location.
- Create and delete highlights.
- Add, edit, and delete notes where supported.
- Verify annotation-to-publication relationships.
- Handle deleted or unavailable publication files.
- Handle locator resolution failures without crashing.
- Verify that EPUB-specific annotation behaviour is not incorrectly assumed to work for PDF.

### 7.6 Backup and restore

- Full backup with zero books.
- Full backup with multiple books and annotations.
- Library-only backup.
- Archive with missing manifest.
- Unsupported backup schema version.
- Invalid JSON.
- Missing archive entry.
- Checksum mismatch.
- Duplicate archive entries.
- Path traversal entry such as `../outside-file`.
- Unexpected absolute paths.
- Excessive file count or uncompressed size.
- Insufficient storage during export or restore.
- User cancellation.
- App termination during export or restore.
- Restore conflict with existing library records.
- Repeated restore of the same backup.
- Restore from an older supported backup version.

Never extract archive entries directly to arbitrary paths. Validate every path, size, count, checksum, and manifest field before committing restored data.

## 8. Performance and reliability testing

Establish baselines early and measure on representative physical devices. Avoid setting arbitrary universal performance numbers before the first working prototype; record initial measurements, then define product-specific budgets.

Measure:

- Cold app launch time.
- Library load time with 100, 500, and 1,000 book records.
- Search response time for a large library.
- Import time and peak memory for small, medium, and large publications.
- Time to first rendered page after opening a publication.
- Reader scrolling and page-turn responsiveness.
- Progress-save latency and write frequency.
- Backup export and restore duration.
- Peak memory while reading large EPUBs and PDFs.
- Stability during repeated open/close cycles.

Reliability scenarios:

- Open and close the same publication repeatedly.
- Switch rapidly between library and reader.
- Background and resume while a publication is open.
- Receive an interruption during import or backup.
- Run with low available storage.
- Rotate the device during reading.
- Lock and unlock the device while reading.
- Force-stop and relaunch during a reading session.

Use Flutter DevTools and platform-native profiling tools to investigate memory, frame rendering, and CPU usage. Test release/profile builds for performance; debug-build measurements are not representative.

## 9. Accessibility and usability checks

Perform manual accessibility checks in addition to automated semantics tests.

- TalkBack on Android and VoiceOver on iOS can identify key navigation controls.
- Buttons and icon-only actions have meaningful accessible labels.
- Focus order is logical and predictable.
- Text remains usable with larger system text settings.
- Contrast is sufficient in light and dark themes.
- Touch targets are large enough for reliable interaction.
- Important states are not communicated by colour alone.
- Dialogs, menus, and error messages are announced appropriately.
- Reader controls can be reached without obscuring the reading content unnecessarily.

Conduct usability checks with representative EPUB and PDF files, not only placeholder content.

## 10. Privacy and security testing

The app is designed to operate locally without accounts, backend services, or cloud sync.

Verify:

- No unexpected network requests occur during core workflows.
- Imported publication files are stored in app-private storage.
- The app does not expose private files through unintended public paths.
- Temporary files are cleaned up after import, export, and restore.
- Backup extraction rejects path traversal and unsafe archive entries.
- Error logs do not include publication contents or sensitive personal notes.
- File deletion and restore behaviour match the documented user confirmation and recovery rules.
- No secrets, tokens, or private user data are committed to the repository.

Use the platform document picker rather than requesting broad filesystem access when possible.

## 11. Automation and CI

### 11.1 Pull request checks

Run on every pull request:

1. Formatting check.
2. `flutter analyze`.
3. Unit tests.
4. Repository/database tests.
5. Widget tests.
6. Android debug build.
7. iOS simulator build where the CI environment supports macOS.

Keep the pull-request suite fast and deterministic. Do not make it depend on network access or external services.

### 11.2 Scheduled and release-candidate checks

Run a broader suite on a schedule and before release:

- Android integration tests.
- iOS integration tests.
- Real-device smoke tests.
- Reader-engine compatibility tests.
- Backup/restore regression suite.
- Database migration suite.
- Performance and memory checks.
- Accessibility smoke tests.
- Offline-mode verification.

### 11.3 Example local commands

```bash
# Format check
dart format --output=none --set-exit-if-changed .

# Static analysis
flutter analyze

# All Flutter tests
flutter test

# Focused test directory
flutter test test/features/library/

# Android build validation
flutter build apk --debug

# iOS simulator build validation (run on macOS with Xcode configured)
flutter build ios --simulator --debug
```

Add integration-test commands once the project's integration test harness and device configuration are established. Keep the exact commands in the repository README or CI workflow.

## 12. Defect severity and release blocking

| Severity | Definition | Release treatment |
|---|---|---|
| Critical | Data loss/corruption, unsafe restore, app cannot launch, or core reading unusable | Release blocker |
| High | Core workflow fails or major platform-specific feature is broken | Release blocker unless explicitly accepted with mitigation |
| Medium | Non-core feature is impaired; workaround exists | Fix before release where practical; document accepted issues |
| Low | Cosmetic issue or minor inconsistency | May be deferred with a tracked issue |

Any defect that can silently lose reading progress, annotations, or publication files is at least High severity. Any defect that can overwrite or expose unrelated files during restore is Critical.

## 13. Release acceptance criteria

An MVP release candidate is ready only when all of the following are true:

- [ ] Formatting and static analysis pass.
- [ ] All unit, repository, database, and widget tests pass.
- [ ] All supported database migrations pass from the oldest supported schema.
- [ ] EPUB and PDF smoke tests pass on Android.
- [ ] EPUB and PDF smoke tests pass on iOS before the iOS release.
- [ ] Import, close, relaunch, and reopen workflows pass.
- [ ] Reading progress restores to the expected location.
- [ ] Bookmarks and EPUB annotations persist and can be revisited.
- [ ] Full backup and restore pass with a representative library.
- [ ] Library-only backup restores records and represents missing files correctly.
- [ ] Invalid and malicious archive cases are rejected safely.
- [ ] Core workflows pass in airplane mode.
- [ ] No unresolved Critical or High severity defects remain.
- [ ] Physical-device lifecycle and low-storage checks are complete.
- [ ] Privacy and accessibility smoke checks are complete.
- [ ] Known limitations are documented in release notes.

Android release acceptance is independent of iOS release acceptance. Android may ship first, but the shared codebase must retain a buildable iOS target and avoid architectural decisions that make the iOS implementation unnecessarily difficult.

## 14. Reader-engine compatibility gate

`flutter_readium` is a critical native dependency. Treat every dependency upgrade as a compatibility event, not a routine package update.

Before adopting or upgrading the package:

1. Pin the exact package version in `pubspec.yaml` and commit `pubspec.lock`.
2. Review the package changelog and platform setup instructions.
3. Verify Flutter, Dart, Android SDK, Kotlin, Gradle, iOS deployment target, and CocoaPods requirements.
4. Build the smallest EPUB and PDF reader spike on Android and iOS.
5. Test open/close lifecycle, TOC, navigation, locator restore, preferences, search, and annotations that the app intends to support.
6. Test app background/foreground transitions and repeated reader sessions.
7. Record platform differences and known limitations.
8. Upgrade only when the compatibility suite passes on both platforms.

Do not invent or assume plugin methods. Inspect the exact installed package API, examples, and changelog, then map those APIs through the app-owned reader adapter.

## 15. Test organisation

A suggested structure:

```text
test/
├── core/
│   ├── errors/
│   ├── files/
│   └── utils/
├── domain/
│   ├── entities/
│   └── use_cases/
├── data/
│   ├── database/
│   ├── repositories/
│   └── backup/
├── features/
│   ├── library/
│   ├── reader/
│   ├── bookmarks/
│   ├── annotations/
│   └── settings/
├── fixtures/
└── support/

integration_test/
├── import_and_library_test.dart
├── epub_reading_test.dart
├── pdf_reading_test.dart
├── progress_restore_test.dart
├── annotations_test.dart
├── backup_restore_test.dart
└── offline_workflows_test.dart
```

Adapt the structure to the actual repository conventions. Keep fixtures and test helpers reusable, and avoid duplicating the same test logic across feature folders.

## 16. Definition of done for a feature

A feature is complete only when:

- Acceptance criteria are covered by tests at the appropriate level.
- Loading, empty, success, error, and cancellation states are handled where relevant.
- Persistence and recovery behaviour are verified.
- Android behaviour is tested.
- iOS behaviour is tested or the remaining platform work is explicitly tracked.
- Accessibility semantics are present for user-facing controls.
- No unrelated regressions are introduced.
- Formatting, static analysis, and relevant tests pass.
- Documentation is updated for new behaviour, limitations, and decisions.

## 17. Recommended testing sequence

Follow this sequence to reduce risk:

1. **M0 — Reader-engine spike:** Verify the pinned `flutter_readium` version on Android and iOS using real EPUB and PDF fixtures.
2. **Foundation:** Add CI, formatting, analysis, test utilities, and fixture management.
3. **Database and storage:** Test schema, migrations, import transactions, file recovery, and missing-file states.
4. **Library:** Test import, metadata, search, sorting, collections, and deletion.
5. **Reader:** Test real native rendering, navigation, preferences, lifecycle, and locator restoration.
6. **Annotations:** Test bookmarks, highlights, notes, and locator resolution.
7. **Backup:** Test archive validation, full/library-only restore, conflict handling, and interrupted operations.
8. **Hardening:** Run performance, accessibility, privacy, offline, and physical-device regression checks.

The reader-engine spike and data-integrity tests should happen before substantial UI polish. These areas carry the highest technical and user-trust risk.
