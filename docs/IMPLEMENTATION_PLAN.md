# Implementation Plan --- Offline-First Ebook Reader

**Document version:** 1.0\
**Date:** 7 November 2026\
**Status:** Proposed delivery plan\
**Platforms:** Android first, iOS second\
**Framework:** Flutter\
**Primary language:** Dart

------------------------------------------------------------------------

## 1. Purpose

This document translates the product requirements and technical
architecture into an incremental implementation plan for the MVP.

The plan is designed for a small team or solo developer using Claude
Code. Work is divided into milestones with: - A clear objective. -
Concrete implementation tasks. - Dependencies and risk notes. -
Acceptance criteria. - Test expectations. - A definition of done.

Implement and verify one milestone at a time. Do not ask a coding agent
to generate the entire application in one pass.

## 2. Product scope

### 2.1 MVP scope

1.  Local library management.
2.  EPUB import and reading.
3.  PDF import and reading.
4.  Reading progress persistence and restoration.
5.  Reading status and recently opened books.
6.  Bookmarks.
7.  EPUB highlights and notes, subject to verified reader-engine
    support.
8.  Reading preferences.
9.  Full backup and restore.
10. Library-only backup and restore.
11. Offline operation without accounts or a backend.

### 2.2 Explicitly out of scope

-   Accounts, authentication, backend, cloud sync.
-   Online bookstore, discovery, or social features.
-   DRM/LCP-protected publications.
-   Audiobooks and TTS.
-   OCR.
-   Advanced PDF highlighting or annotation.
-   Desktop and web apps.
-   Automatic cloud backup.
-   Subscription or payment functionality.

Any scope change must be recorded in the PRD and reviewed for
architecture impact.

## 3. Delivery strategy

### Android-first, cross-platform from the beginning

Android is the first release target, but the project must remain an
Android+iOS Flutter project from the start.

This means: - Configure both platform targets during the foundation
milestone. - Keep iOS compiling throughout development. - Validate the
reader plugin on an iOS simulator during the technical spike. - Keep
business logic, UI, data models, backup format, and database
implementation shared. - Isolate native/plugin behavior behind app-owned
interfaces. - Do not postpone all iOS validation until after Android
release.

### Milestone sequence

``` text
M0  Technical spike and dependency validation
 ↓
M1  Project foundation and development workflow
 ↓
M2  Local database and file storage foundation
 ↓
M3  Import pipeline and library experience
 ↓
M4  Reader integration and reading experience
 ↓
M5  Bookmarks, highlights, and preferences
 ↓
M6  Backup and restore
 ↓
M7  Android MVP hardening and release
 ↓
M8  iOS completion and release
```

M0 is a hard gate. Do not implement the complete application until the
EPUB/PDF engine has been validated on both platforms or an acceptable
fallback has been documented.

## 4. Milestone 0 --- Technical spike

**Objective:** Prove that the chosen Flutter Readium integration can
support the required reading workflows on Android and iOS.

**Why this milestone matters:** The reader engine is the highest-risk
dependency. A package feature list is not sufficient evidence that the
required APIs, lifecycle behavior, and platform parity work in the
actual app.

### Tasks

#### Project and dependency validation

-   [ ] Create a minimal Flutter project.
-   [ ] Configure Android and iOS targets.
-   [ ] Add the selected `flutter_readium` release.
-   [ ] Pin the exact tested package version.
-   [ ] Follow the package's current Android Gradle, Kotlin, Activity,
    iOS deployment target, and CocoaPods requirements.
-   [ ] Record the native Readium versions and required platform
    configuration.
-   [ ] Build and launch the empty app on Android.
-   [ ] Build and launch the empty app on an iOS simulator.

#### EPUB validation

-   [ ] Import a local EPUB through the system document picker.
-   [ ] Copy it into app-private storage.
-   [ ] Open and render the EPUB offline.
-   [ ] Verify EPUB 2 and EPUB 3 sample files.
-   [ ] Verify table of contents and internal links.
-   [ ] Verify pagination and scrolling behavior where supported.
-   [ ] Change font size and reading theme.
-   [ ] Retrieve and serialize a reading locator.
-   [ ] Close and reopen the publication at the saved position.
-   [ ] Create a bookmark.
-   [ ] Create an EPUB highlight and verify that it can be restored.
-   [ ] Verify text selection behavior.

#### PDF validation

-   [ ] Import a local PDF.
-   [ ] Open and render it offline.
-   [ ] Test page navigation.
-   [ ] Retrieve and restore the current page/location.
-   [ ] Test different page sizes and a large PDF.
-   [ ] Open and close multiple PDFs to check resource cleanup.

#### Platform and lifecycle validation

-   [ ] Repeat critical EPUB/PDF tests on an iOS simulator.
-   [ ] Test app backgrounding and resuming.
-   [ ] Test closing and reopening the reader.
-   [ ] Test process termination and progress recovery.
-   [ ] Record any API or feature differences between platforms.

### Deliverables

-   Minimal reader prototype.
-   `READER_ENGINE_SPIKE.md` with tested package version, setup
    requirements, supported behavior, limitations, and screenshots/logs
    where useful.
-   App-owned reader service interface proposal.
-   Decision to proceed, mitigate, or change the reader integration.

### Acceptance criteria

-   Local EPUB and PDF files open offline on Android.
-   Critical EPUB/PDF flows are validated on iOS simulator.
-   Reading position can be saved and restored.
-   Required MVP bookmarks and EPUB highlights are demonstrated or a
    documented mitigation is approved.
-   The app can release reader resources without repeated-open memory
    growth or lifecycle failures in basic tests.
-   No unresolved blocker exists for a core MVP requirement.

**Exit gate:** If the plugin cannot provide the required behavior, stop
and evaluate a native bridge, an alternative maintained reader
integration, or a change in MVP scope before proceeding.

## 5. Milestone 1 --- Project foundation

**Objective:** Establish a maintainable Flutter codebase and repeatable
development workflow.

### Tasks

#### Repository and tooling

-   [x] Create the Git repository.
-   [x] Add Flutter project and platform folders.
-   [x] Configure `.gitignore`.
-   [x] Add a `README.md` with prerequisites and setup instructions.
-   [x] Add `CLAUDE.md` with project-specific coding rules.
-   [x] Configure Dart formatting and lint rules.
-   [x] Configure CI or a repeatable local validation script for
    formatting, analysis, and tests. (`tool/check.sh`; no CI yet.)
-   [x] Record Flutter and Dart SDK versions used by the project.
-   [x] Pin package versions and commit the lockfile.

#### Application structure

-   [x] Create the feature-oriented folder structure from
    `TECHNICAL_ARCHITECTURE.md`. (Folders are added as layers gain code;
    `domain/` and `data/` arrive with Milestone 2.)
-   [x] Configure Riverpod providers and dependency wiring.
-   [x] Configure `go_router`.
-   [x] Create app bootstrap and error handling.
-   [x] Create the application theme and typography foundations.
-   [x] Add app-level loading, empty, and error state patterns.
-   [x] Add logging that avoids book contents, notes, selected text, and
    private file paths.

#### Platform build

-   [x] Confirm Android debug build.
-   [ ] Confirm iOS simulator build. **Deferred:** iOS work is on hold
    by user decision (7 Nov 2026).
-   [x] Add app identifiers and display name.
-   [x] Configure required permissions and document-picker integration
    only as needed. (None needed yet; the release manifest requests no
    permissions. The document picker arrives with import.)
-   [ ] Confirm both targets continue to build after dependency changes.
    (Android only while iOS is deferred.)

### Deliverables

-   Clean Flutter project.
-   Working app shell on Android and iOS simulator.
-   Repeatable build, analyze, and test commands.
-   Repository instructions for Claude Code.

### Acceptance criteria

-   `flutter analyze` passes.
-   `flutter test` runs successfully.
-   Android debug build launches.
-   iOS simulator build launches.
-   No business logic depends directly on widget code or reader-plugin
    classes.

## 6. Milestone 2 --- Database and local storage foundation

**Objective:** Implement durable local persistence and safe app-private
file management.

### Tasks

#### Drift database

-   [x] Add Drift and the required SQLite runtime.
-   [x] Configure database creation for Android and iOS. (Android
    validated on a physical phone; iOS deferred.)
-   [x] Implement `books`.
-   [x] Implement `reading_progress`.
-   [x] Implement `bookmarks`.
-   [x] Implement `highlights`.
-   [x] Implement `collections`.
-   [x] Implement `collection_books`.
-   [x] Add foreign keys, checks, unique constraints, and indexes.
-   [x] Add typed enum and JSON converters.
-   [x] Set the initial schema version.
-   [x] Add explicit migration strategy.
-   [x] Add database tests using an in-memory or temporary database.

#### Storage service

-   [x] Resolve the app-private support/document directory.
-   [x] Create `library/books`, `library/staging`, and temporary work
    directories. (Each operation gets its own `staging/<operation-id>/`.)
-   [x] Implement safe relative-path generation and validation.
-   [x] Implement file existence and file-size checks.
-   [x] Implement SHA-256 hashing.
-   [x] Implement safe copy, move, and cleanup helpers.
-   [x] Implement startup reconciliation for abandoned staging files.
-   [x] Ensure file operations do not block the UI isolate.

#### Domain and repositories

-   [x] Define domain entities independent of Drift.
-   [x] Define repository interfaces.
-   [x] Implement Drift-backed repositories.
-   [x] Map Drift rows to domain models.
-   [x] Expose observable library queries through streams where
    appropriate.

### Deliverables

-   Working local database.
-   Storage service.
-   Repository layer.
-   Database schema tests.

### Acceptance criteria

-   All six tables can be created and queried.
-   Foreign-key cascades behave as specified.
-   Data persists after app restart.
-   Android and iOS use the same schema and repository contracts.
-   Publication file bytes are never stored in SQLite.
-   A failed file copy does not leave a completed book record.

## 7. Milestone 3 --- Import pipeline and library experience

**Objective:** Allow users to import publications and manage their local
library.

### 3.1 Import pipeline

-   [x] Integrate a system document picker for EPUB and PDF.
-   [x] Support selecting one or multiple files if reliable on both
    platforms. (Android; iOS deferred.)
-   [x] Validate file extension and content where possible.
-   [x] Handle unsupported formats and malformed files.
-   [x] Copy selected files into app-private staging storage.
-   [x] Calculate file size and SHA-256 checksum.
-   [x] Extract metadata using the reader integration where supported.
-   [x] Extract or generate a cover where supported. (EPUB covers via
    `flutter_readium`; this briefly opens the publication, so Milestone 4
    must not run import inspection while a reader session is open.)
-   [x] Create a stable UUID for each imported book.
-   [x] Move validated files into final storage.
-   [x] Insert the book record only after the import is ready.
-   [x] Clean up partial files and records after failure.
-   [x] Detect same-checksum imports and show a duplicate warning.

### 3.2 Library UI

-   [x] Build the library home screen.
-   [x] Build book grid and list presentation. (Choice persists in
    SharedPreferences.)
-   [x] Display title, author, format, cover, and reading status.
-   [x] Implement recently added sorting.
-   [x] Implement recently opened sorting. (Never-opened books sort
    last; `last_opened_at` is set once the reader exists in Milestone 4.)
-   [x] Implement title and author search.
-   [x] Implement format and reading-status filters.
-   [x] Add empty library state and import entry point.
-   [x] Add loading, error, and missing-file states.
-   [x] Build book details screen. (Tapping a book opens details until
    the reader exists.)
-   [x] Add remove/delete confirmation and clear file-deletion
    semantics. (One action, "Remove from library": it deletes the
    record, its reading data and the app's private copy; the user's
    original file is never touched. Two actions would behave the same,
    per DATABASE_SCHEMA.md §7.2.)

### Deliverables

-   Functional offline library.
-   Reliable EPUB/PDF import.
-   Book details and library search/sort/filter.

### Acceptance criteria

-   A user can import EPUB and PDF files without an account.
-   Imported files remain available after app restart.
-   Imported books open from app-private storage even if the original
    source is moved or deleted.
-   Duplicate imports are handled explicitly.
-   Failed imports leave no misleading library record.
-   Library UI remains responsive with a representative large library.
-   Missing or deleted files are surfaced as recoverable states.

## 8. Milestone 4 --- Reader integration and reading experience

**Objective:** Deliver the core reading experience for EPUB and PDF.

Carried over from Milestone 3 and done in 4a: tapping a library book opens
the reader, `last_opened_at` is set on open, the "reading progress" library
sort exists, and import cover extraction is skipped while a reader session
is open.

Split: **4a** (done) reader contract, adapter, session controller, EPUB/PDF
reading, TOC, progress persistence. **4b** (done) reading preferences:
EPUB theme (system/light/dark from the colour tokens), text size (80–200%)
and pages/scroll; PDF pages/scroll and fit width/whole page; reset to
defaults. Preferences are global (SharedPreferences) with no per-book
overrides. A change is applied to the engine first and saved only if the
engine accepts it; after an EPUB reflow the reader returns to the last
known position (spike finding 10). Text selection
uses the engine's native selection; it is ticked after an on-device check.

Reading status: an unread book becomes "reading" when it is first opened
and "finished" when the engine reports the end of the publication.

### 4.1 Reader abstraction

-   [x] Define an app-owned `PublicationReaderService` interface.
-   [x] Define app-owned reader event, error, position, and preference
    models. (`lib/services/reader/publication_reader.dart`; the
    interface is named `PublicationReader`. Preference models arrive in
    4b with the settings.)
-   [x] Implement a `flutter_readium` adapter.
-   [x] Keep plugin-specific models inside the adapter.
-   [x] Define reader open/close lifecycle.
-   [x] Define event subscription and cleanup behavior.
-   [x] Handle unsupported features and plugin errors without crashing
    the app.

### 4.2 EPUB reader

-   [x] Open a locally stored EPUB.
-   [x] Render publication content.
-   [x] Display and navigate table of contents.
-   [x] Support next/previous navigation.
-   [x] Support pagination/scroll mode where available.
-   [x] Support font size and reading theme controls.
-   [ ] Support text selection.
-   [x] Retrieve and serialize the reader locator.
-   [x] Restore the last saved locator.
-   [x] Handle malformed or unsupported EPUBs with a clear error state.

### 4.3 PDF reader

-   [x] Open a locally stored PDF.
-   [x] Render PDF pages.
-   [x] Support page navigation.
-   [ ] Display current page and total page count where available.
    (Current page shown; the 0.9.0 locator carries no total page count.)
-   [x] Save and restore the current PDF position.
-   [ ] Handle large files and memory pressure.
-   [x] Handle corrupt or unsupported PDFs.

### 4.4 Progress persistence

-   [x] Persist locator JSON through `ReadingProgressRepository`.
-   [x] Store supplementary page number and progression where
    meaningful.
-   [x] Debounce frequent position events.
-   [x] Save after meaningful navigation.
-   [x] Save after inactivity.
-   [x] Save when app enters background.
-   [x] Save when reader closes.
-   [x] Restore only after publication navigator is ready.
-   [ ] Test recovery after process termination.
-   [x] Update `last_opened_at` and reading status consistently.

### Deliverables

-   Functional EPUB reader.
-   Functional PDF reader.
-   Reliable reading-progress restoration.
-   Reader shell integrated with the shared Flutter UI.

### Acceptance criteria

-   EPUB and PDF open offline.
-   User can navigate through content.
-   Reading preferences apply where supported.
-   Progress survives app restart and process termination.
-   Reader resources are released on close.
-   Reader-plugin implementation details do not leak into domain or
    database layers.

## 9. Milestone 5 --- Bookmarks, highlights, and preferences

**Objective:** Add the personal reading tools required by the MVP.

### 5.1 Bookmarks

-   [x] Create a bookmark at the current reader location.
-   [x] Save the serialized locator.
-   [x] List bookmarks for a book.
-   [x] Navigate to a selected bookmark.
-   [x] Rename or edit a bookmark label.
-   [x] Delete a bookmark.
-   [x] Restore bookmarks after app restart.

Implementation notes (Milestone 5a):

-   The reader's top bar has a bookmark toggle and a Bookmarks button.
    The toggle is filled when a bookmark matches the current position
    (same chapter and progression within 0.001 for EPUB; same page for
    PDF). Tapping it there removes that bookmark, with undo.
-   The in-reader list shows the open book's bookmarks oldest first;
    choosing one moves the reader there after saving the current
    position. A bookmark whose location cannot be found is kept and the
    reader explains.
-   The Bookmarks tab lists every bookmark newest first. Opening one
    opens the reader at it (`/reader/<bookId>?bookmark=<id>`), or the
    book's details when its file is missing. Rename (blank clears the
    label, 100 characters at most) and delete with undo are on each
    row's menu.
-   Undo re-inserts the deleted record with its original id and dates.
-   Persistence across restarts comes from the database; it is covered
    by tests but still needs a check on the phone.

### 5.2 EPUB highlights and notes

-   [x] Validate highlight creation through the reader engine.
-   [x] Capture the selected text and locator where available.
-   [x] Apply an app-owned highlight color.
-   [x] Persist the highlight record.
-   [x] Reapply saved highlights when reopening a publication.
-   [x] Add and edit a note.
-   [x] List highlights and notes for a book.
-   [x] Navigate from a highlight list item to its location.
-   [x] Delete a highlight.
-   [x] Handle stale or unresolvable locators without deleting user
    notes.

Implementation notes (Milestone 5b):

-   Selecting text in an EPUB adds **Highlight** and **Note** to the
    system text menu. Highlight saves a yellow highlight; Note saves one
    and opens the editor. PDFs show no highlight controls.
-   Tapping a highlight opens the editor: the saved passage, colour
    (yellow, green, blue, pink; each named and marked with a check, not
    by colour alone), a note of up to 5,000 characters, Copy text, and
    Delete with undo. Save errors show inside the sheet.
-   The reader's Highlights button lists the book's highlights oldest
    first with note previews; choosing one moves there after saving the
    current position. A location that cannot be found keeps the
    highlight and explains.
-   Highlights are kept in the app schema and rebuilt as plugin
    decorations on every change and when the reader becomes ready (spike
    finding 12). Ones whose locator cannot be read are listed but not
    drawn.
-   The tints are defined in `lib/app/theme/highlight_colors.dart`; the
    UI spec gives no values for them.
-   Snack bars from inside the bookmark and highlight lists now appear in
    the sheet, so Undo can be tapped there.

Verified on the Android phone (8 Nov 2026): creating a highlight and a
note, editing, deleting with undo, and redrawing after reopening.

Known limitations:

-   The engine does not clear the text selection after Highlight or Note
    (spike finding 13); there is no API for it in 0.9.0. Tapping
    elsewhere clears it.
-   A passage repeated with identical surrounding text is anchored at its
    first occurrence (spike finding 11).
-   The library-wide highlights list (PRD FR-ANNOT-03, UI spec §7.9,
    P2) is not built; where it lives in the navigation is undecided.

PDF text highlighting remains out of scope unless the technical spike
establishes a stable, low-risk implementation and the PRD is updated.

### 5.3 Reading preferences

-   [x] Implement system/light/dark app theme.
-   [x] Implement reading themes supported by the reader engine.
-   [x] Implement font size controls.
-   [x] Persist preferences locally.
-   [x] Apply preferences on the next reader launch.
-   [x] Decide which preferences are global and which are per-book.
-   [ ] Keep device-specific preferences out of portable backups unless
    explicitly approved. (Milestone 6.)

Reading themes, EPUB text size, page layout and PDF fit were built in
Milestone 4 as global settings (none are per-book). After phone testing
(8 Nov 2026), paginated PDFs show one fixed page that swipes turn, and the page fit
choice is hidden on Android because the engine ignores "whole page" (see
READER_ENGINE_SPECIFICATION.md §8.2).

Implementation notes (Milestone 5c):

-   Settings has an Appearance section with Theme: System / Light /
    Dark, stored as `app.theme` in SharedPreferences (default System;
    an unknown value reads as System). The app switches only after the
    value has been saved; a failed save keeps the current theme and
    says so.
-   The reader's "System" reading theme now follows the app's
    appearance rather than the device's (UI/UX §3.4: "follows the
    application/system theme"). Light and Dark reading themes are
    unchanged.
-   Other suggested Settings sections are not shown yet: reading
    defaults live in the reader settings sheet, backup arrives with
    Milestone 6, and app version needs a new dependency.

Verified on the Android phone (8 Nov 2026): switching System / Light /
Dark, and the choice kept after restarting the app.

### Deliverables

-   Bookmark management.
-   EPUB highlight and note management.
-   Persistent reading preferences.

### Acceptance criteria

-   Bookmarks and EPUB highlights survive app restart.
-   Selecting a bookmark/highlight navigates to the saved location when
    the locator remains valid.
-   Notes remain available even if a highlight cannot be reapplied.
-   Preference changes persist and apply consistently.


## 10. Milestone 6 --- Backup and restore

**Objective:** Give users a portable way to protect and migrate their
library.

Implement according to `BACKUP_FORMAT.md`.

### 6.1 Export

-   [x] Implement backup domain models independent of Drift.
-   [x] Implement JSON serializers for each dataset.
-   [x] Implement manifest generation.
-   [x] Implement full backup export.
-   [x] Implement library-only backup export.
-   [x] Include publication files and covers for full backups.
-   [x] Calculate SHA-256 and sizes for every declared entry.
-   [x] Build ZIP archives in a temporary workspace.
-   [x] Re-open and validate the completed archive.
-   [x] Export through the platform save/share flow.
-   [x] Clean up temporary files after success or cancellation.

Implementation notes (Milestone 6a):

-   Settings has a Data section with "Create full backup" and "Create
    library-only backup" (Android only, while iOS is on hold). Each
    explains what the backup includes and that it is not encrypted, and
    offers "Include settings" (default on).
-   The archive is built in a staging area: manifest first, then the
    datasets, then each publication and its cover, stored without
    compression (`archive` 4.6.0). Archive work and hashing run on a
    background isolate.
-   Publication files are archived straight from the library rather than
    copied into the workspace first (BACKUP_FORMAT.md §7.1 step 3). Each is
    hashed first and compared with the library's stored checksum; the
    finished archive is then reopened and every entry rehashed, so a file
    that changed during the export still fails the backup.
-   A full backup stops if any book's file is missing or no longer matches
    its stored checksum, and lists those books with an offer to create a
    library-only backup instead. Partial full backups are not supported.
-   Saving uses the system Save dialog (`ACTION_CREATE_DOCUMENT`) through a
    small channel in `MainActivity`; the app gets access to the chosen
    file only and needs no permission. A failed write removes the partial
    file where the provider allows it.
-   The archive verifier (`verifyBackupArchive`) is the same one restore
    will use: limits, entry types, paths, duplicates, manifest structure,
    and size and SHA-256 of every entry. Dataset contents are parsed in
    Milestone 6b.

Verified on the Android phone (8 Nov 2026): a full backup (2 books,
9.5 MB, about 5 s) and a library-only backup (7.9 KB) saved to Downloads
through the Save dialog with the `.readerbackup` name kept. Both pulled
files passed `verifyBackupArchive`, with the expected entries, counts and
allowlisted settings, and the staging area was empty afterwards.

Known limitations:

-   A backup that is being created cannot be cancelled except at the Save
    dialog.
-   If Android recreates the activity while the Save dialog is open, that
    backup is abandoned; its workspace is removed by startup staging
    cleanup.

### 6.2 Restore

-   [x] Select a backup through the system document picker.
-   [x] Inspect archive entries before extraction.
-   [x] Validate paths, duplicate entries, sizes, and resource limits.
-   [x] Validate manifest and format version.
-   [x] Verify entry sizes and SHA-256 hashes.
-   [x] Parse and validate all JSON datasets.
-   [x] Validate relationships and referenced book IDs.
-   [x] Stage publication files in app-private storage.
-   [x] Show a restore preview.
-   [x] Implement conservative merge conflict behavior.
-   [x] Implement replace mode only if safe recovery is complete;
    otherwise defer it. (Deferred: merge only.)
-   [x] Commit database and file changes using a recoverable workflow.
-   [x] Recover or roll back interrupted restore operations.
-   [x] Clean up staging files.

Implementation notes (Milestone 6b):

-   Settings > Data > Restore backup. The file is checked (archive,
    checksums, datasets, references) before anything changes, then a
    preview shows the backup type and date, what will be added, books
    already present, conflicts that will be skipped, and, for a
    library-only backup, that its books will show "File missing".
-   Merge rules (BACKUP_FORMAT.md §8.3, conservative): a book with the
    same id and file is kept and its new bookmarks, highlights and
    collection memberships are added; a book with the same id but a
    different file, or the same file under another id, is skipped and
    named. Collections with the same id but another name, and bookmarks
    or highlights whose id exists with different content, are skipped
    and counted. A book's current reading position is always kept.
    Nothing in the library is changed or removed.
-   Settings from the backup are applied only if the user ticks "Apply
    settings from the backup" (default off), and only allowlisted, valid
    values.
-   Commit: each new book's files are extracted into its own staging area
    and hashed again while written; a journal (`restore-journal.json`)
    lists those books; their directories are moved into `books/`, checked,
    and then every record is inserted in one transaction. A failure
    removes the moved directories. At startup, a leftover journal means
    the app stopped mid-commit: directories of books without a record
    are removed, so the library is as before or fully restored.
-   Relink: importing a file whose checksum matches a book with a missing
    file puts the file back for that book (and extracts a cover if it has
    none), keeping its reading data. The import reports "Restored the
    file for 1 book."

Verified on the Android phone (8 Nov 2026): choosing the full and the
library-only backups made in 6a passed every check (full: 0.6 s) and
showed "Nothing to restore", since both books were already in the
library; the library, staging area and journal were unchanged. After
removing the PDF book, restoring the full backup added it back with its
bookmark and reading position (inspect 0.2 s, restore 0.2 s): the file's
SHA-256 matched its record, the other book's highlight and progress were
untouched, and the staging area was empty with no journal left. A
library-only restore followed by a relinking import has not yet been run
on the phone.

Known limitations:

-   Replace mode is not offered.
-   The document picker copies the backup into the app cache before it is
    read, so a full restore temporarily needs space for the backup, its
    extracted books and the library.
-   Conflicting books cannot yet be imported as separate copies from the
    restore preview.
-   A restore cannot be cancelled once it has started.

### 6.3 Cross-platform verification

-   [ ] Create an Android full backup and restore it on Android.
-   [ ] Create an Android backup and restore it on iOS.
-   [ ] Create an iOS backup and restore it on Android.
-   [ ] Verify metadata, collections, progress, bookmarks, and
    highlights.
-   [ ] Verify publication file checksums.
-   [ ] Verify missing-file behavior for library-only backups.

### Deliverables

-   Full backup.
-   Library-only backup.
-   Validated restore flow.
-   Cross-platform backup compatibility tests.

### Acceptance criteria

-   Backup creation works offline.
-   Invalid archives are rejected before the current library is changed.
-   Restore conflicts are visible and do not silently overwrite user
    data.
-   Failed restores leave the current library usable.
-   Full backups restore files and library data.
-   Library-only backups restore metadata and clearly mark publication
    files as missing.
-   Cross-platform round-trip tests pass.

## 11. Milestone 7 --- Android MVP hardening and release

**Objective:** Prepare the Android app for real-world use.

### Quality and usability

-   [ ] Review all loading, empty, error, and confirmation states.
-   [ ] Test accessibility labels, semantics, contrast, and text
    scaling.
-   [ ] Test narrow and large Android screens.
-   [ ] Test system theme changes.
-   [ ] Review import and delete confirmation copy.
-   [ ] Verify app behavior in airplane mode.
-   [ ] Review privacy disclosures and permissions.

Progress (7a, 8 Nov 2026):

-   Release permissions: flutter_readium declares network, foreground
    media playback, notification and download permissions, a cleartext
    traffic flag and an exported media service for its read-aloud,
    audiobook and remote-publication features. Thaal uses none of them,
    so the app manifest removes them; the release APK now requests no
    permissions at all. Debug and profile builds keep INTERNET for the
    Flutter tool. The WebView opts out of usage metrics and Safe
    Browsing. Re-check the merged manifest when upgrading
    flutter_readium.
-   Android backup: off (decided 8 Nov 2026). `allowBackup="false"` and
    data extraction rules exclude everything from Google cloud backup
    and device-to-device transfer, so the library never leaves the
    device; people move it with Thaal's own backup file. Mention this in
    the store listing's privacy information.
-   Temporary files: none left in the app cache or staging area on the
    phone after imports, backups and restores.
-   Logs: fields are ids, counts, formats and outcomes; paths and long
    text are redacted by the logger, and release builds log warnings and
    errors only.
-   Accessible labels: every icon button has a tooltip; book covers are
    decorative and excluded from semantics, with the title read instead.
-   Small phone with large text: widget tests render the library (list
    and grid, empty, error, missing file), book details, reader (open,
    contents, problems), bookmarks, settings and the restore preview at
    320×568 with 200% text; nothing overflows.
-   Release build on the phone (8 Nov 2026): with no permissions and
    R8 shrinking, importing an EPUB, reading it and adding a bookmark
    worked; the position and bookmark were saved, the log showed no app
    errors and no blocked network calls. A PDF has not yet been opened
    in a release build.
-   Still to do on the device: airplane mode, TalkBack, a tablet-size
    screen and system theme changes.

### Reliability

-   [ ] Test app process death during reading.
-   [x] Test app process death during import.
-   [x] Test app process death during backup and restore.
-   [ ] Test insufficient storage.
-   [x] Test missing or externally removed files (library-only restore
    shows "File missing"; re-importing the file relinks it).
-   [x] Test corrupted EPUB/PDF files.
-   [x] Test corrupted backup archives.
-   [ ] Test database migration from the prior released schema.
-   [ ] Test repeated reader open/close cycles.
-   [ ] Test large libraries and representative large publications.

Phone session (7b, 8 Nov 2026, debug build, synthetic test files). The
app was force-stopped over adb at the moment an operation was in
progress, then relaunched; after each step every book file matched its
stored checksum and no reading data pointed at a missing book.

-   Import of a 320 MB PDF killed after the copy: no book added.
-   Full backup killed while the archive was written: library unchanged,
    nothing saved to Downloads.
-   Restore commit: a kill on the journal's appearance landed after the
    commit (it takes well under 100 ms), so the restore completed; a
    full restore of a 300 MB EPUB took 4.8 s. Recovery was tested by
    recreating the state a mid-commit crash leaves (a moved-in book
    directory without a record, plus the journal) with the app stopped:
    on launch it removed that directory, kept the journal's book that
    had a record, and removed the journal and staging areas.
-   Broken files (empty, random bytes, text named .pdf, truncated EPUB
    and PDF, a ZIP that is not an EPUB) were refused; nothing was added.
-   Damaged backups (truncated, one flipped byte, random bytes) were
    refused before anything changed.
-   Library-only restore brought a removed book back as "File missing";
    importing the same file relinked it, keeping its id and checksum.
-   Large files: a 300 MB EPUB imported in 5.3 s.
-   Finding: an interrupted operation's staging files (here 320 MB) stay
    until a launch at least an hour later, because startup cleanup only
    removed entries older than an hour. Fixed: startup now clears all of
    `staging/` (DATABASE_SCHEMA.md §12).
-   Not yet run: process death while reading, low storage, repeated
    reader open/close, large libraries.

### Release preparation

-   [ ] Configure app icon and launch screen. Launch screen done (app
    background colour, light and dark; system splash on Android 12+).
    The icon is still Flutter's default; the final icon will be supplied.
-   [x] Configure package/application ID (`com.sbjglitch.thaal`).
-   [x] Configure signing and release build. Release builds use the
    upload key from `android/key.properties` (git-ignored) and fall back
    to the debug key with a warning; verified with a throwaway key. The
    real upload key is still to be created (`docs/RELEASE.md` §1).
-   [x] Verify app version and build number (`1.0.0+1` from
    `pubspec.yaml`).
-   [ ] Prepare store listing assets and privacy information. Draft
    listing text, data safety answers and privacy policy are in
    `docs/RELEASE.md`; the icon, feature graphic, screenshots and a
    hosted policy URL are still needed.
-   [ ] Run release-mode smoke tests.
-   [ ] Create a release candidate.
-   [ ] Resolve all critical and high-severity defects.
-   [ ] Publish to an internal/closed testing track before public
    release.

### Deliverable

Android MVP release candidate and release package.

### Acceptance criteria

-   No known critical data-loss or restore-corruption issue.
-   Core workflows pass on representative Android devices.
-   Offline behavior is verified.
-   Release build installs and runs successfully.
-   User data survives app updates and database migrations.

## 12. Milestone 8 --- iOS completion and release

**Objective:** Complete iOS-specific integration while retaining the
shared Flutter UI and application logic.

### Tasks

-   [ ] Verify iOS build with the pinned Flutter and reader
    dependencies.
-   [ ] Complete iOS document import and export behavior.
-   [ ] Verify app-private file storage and file protection.
-   [ ] Verify Readium navigator lifecycle on iOS.
-   [ ] Test EPUB and PDF on iPhone simulator and physical device.
-   [ ] Test reading progress, bookmarks, and EPUB highlights.
-   [ ] Test app suspension and process termination.
-   [ ] Test iPad layout and resizing.
-   [ ] Test Android-created backup restore on iOS.
-   [ ] Test iOS-created backup restore on Android.
-   [ ] Configure signing, bundle ID, and App Store metadata.
-   [ ] Run release-mode smoke tests.
-   [ ] Prepare TestFlight build and resolve release blockers.

### Deliverable

iOS release candidate.

### Acceptance criteria

-   Core MVP workflows work on iOS.
-   Shared library and settings UI behave correctly.
-   Reader engine behavior is validated on supported iOS devices.
-   Backup interchange works in both directions.
-   iOS-specific permissions, file access, and lifecycle behavior are
    verified.

## 13. Cross-cutting engineering tasks

These tasks apply throughout all milestones.

### Architecture discipline

-   Keep domain models independent of Flutter widgets, Drift rows, and
    reader-plugin types.
-   Keep `flutter_readium` calls inside the reader adapter.
-   Keep platform-specific APIs behind small services.
-   Use repository contracts for data access.
-   Avoid unnecessary abstractions and premature modularization.
-   Record architecture changes and dependency substitutions.

### Claude Code workflow

-   Read `CLAUDE.md`, PRD, architecture, and relevant specification
    before implementation.
-   Give Claude Code one bounded task at a time.
-   Ask it to inspect existing code before changing files.
-   Require a short implementation summary and list of changed files.
-   Require tests for business logic and data workflows.
-   Run formatting, static analysis, tests, and platform builds after
    meaningful changes.
-   Review dependency changes and generated code.
-   Do not accept a feature as complete based only on code generation;
    run it on a device or simulator.
-   Do not allow silent changes to the product scope or architecture.

### Quality gates for each task

A task is done only when: 1. Acceptance criteria are met. 2. Code is
formatted. 3. Static analysis passes. 4. Relevant automated tests pass.
5. Android build remains healthy. 6. iOS build remains healthy where the
task affects shared code or native integration. 7. No unrelated scope
has been introduced. 8. Documentation is updated if behavior or
architecture changed.

## 14. Suggested task breakdown for a solo developer

Avoid estimating the entire project as one large delivery. Use short,
reviewable work items.

Suggested task size: - Small: one focused change, usually a few hours. -
Medium: one feature slice with tests, typically one to two working
days. - Large: split into smaller tasks before implementation.

Example backlog structure:

  -----------------------------------------------------------------------
  Epic                                Example tasks
  ----------------------------------- -----------------------------------
  Reader integration spike            Configure plugin; open EPUB; open
                                      PDF; save locator; validate iOS

  Foundation                          App shell; router; Riverpod;
                                      linting; CI

  Persistence                         Drift setup; tables; DAOs;
                                      repositories; migrations

  Import                              Picker; validation; copy; metadata;
                                      duplicate detection

  Library                             Grid/list; search; sort; filters;
                                      details

  Reader                              EPUB view; PDF view; preferences;
                                      progress restoration

  Annotations                         Bookmarks; highlights; notes;
                                      navigation

  Backup                              Export models; manifest; ZIP;
                                      validation; restore staging

  Release                             Accessibility; performance;
                                      reliability; Android release
  -----------------------------------------------------------------------

Do not assign dates until the technical spike has established the reader
integration effort.

## 15. Risk register and decision gates

  -----------------------------------------------------------------------
  Risk                    When to resolve         Mitigation / gate
  ----------------------- ----------------------- -----------------------
  Reader plugin lacks a   M0                      Prove each critical
  required API                                    workflow before
                                                  building app screens

  Android/iOS feature     M0 and ongoing          Test both platforms
  parity differs                                  early and on every
                                                  plugin upgrade

  Plugin API changes      Every dependency        Pin exact version and
                          upgrade                 run compatibility suite

  Locator cannot be       M0/M4                   Persist complete
  restored reliably                               serialized locator and
                                                  test round trips

  Import and DB state     M2/M3                   Staging, cleanup, and
  become inconsistent                             recoverable file
                                                  operations

  Restore causes data     M6                      Validate first, stage
  loss                                            files, transactional DB
                                                  commit, recovery
                                                  journal

  Large PDF performance   M0/M4/M7                Test representative
  is poor                                         large files and memory
                                                  behavior

  iOS build breaks while  Every milestone         Keep iOS target
  Android evolves                                 compiling continuously

  Scope expands           Every planning review   Require explicit PRD
                                                  change and impact
                                                  assessment
  -----------------------------------------------------------------------

### Go/no-go gates

**Gate A --- End of M0:** Reader integration is feasible on Android and
iOS.

**Gate B --- End of M3:** Imports and library records remain consistent
after failures and app restarts.

**Gate C --- End of M4:** Reading and progress restoration are reliable
for representative EPUB/PDF samples.

**Gate D --- End of M6:** Backup and restore preserve data and do not
destroy the existing library on failure.

**Gate E --- End of M7:** Android release candidate passes core
reliability and offline tests.

## 16. MVP completion checklist

-   [ ] User can import EPUB and PDF files.
-   [ ] Imported files are stored locally and survive app restart.
-   [ ] User can browse, search, sort, and filter the library.
-   [ ] User can read EPUB offline.
-   [ ] User can read PDF offline.
-   [ ] Reading position is restored after reopening.
-   [ ] Reading status and recently opened information are maintained.
-   [ ] User can create and manage bookmarks.
-   [ ] User can create and manage EPUB highlights and notes.
-   [ ] Reading preferences persist.
-   [ ] User can create a full backup.
-   [ ] User can create a library-only backup.
-   [ ] User can restore a valid backup safely.
-   [ ] Invalid or interrupted restore does not destroy the existing
    library.
-   [ ] App core functionality works without an account or network.
-   [ ] Android MVP passes release testing.
-   [ ] iOS target remains buildable and core compatibility has been
    verified.

## 17. Related project documents

  -----------------------------------------------------------------------
  Document                            Role
  ----------------------------------- -----------------------------------
  `PRD.md`                            Defines what the product must do

  `TECHNICAL_ARCHITECTURE.md`         Defines the system design and
                                      technology choices

  `DATABASE_SCHEMA.md`                Defines relational data and
                                      persistence rules

  `BACKUP_FORMAT.md`                  Defines portable archive and
                                      restore behavior

  `READER_ENGINE_SPECIFICATION.md`    Defines reader integration and
                                      EPUB/PDF behavior

  `IMPLEMENTATION_PLAN.md`            Defines milestones, tasks, and
                                      acceptance criteria

  `CLAUDE.md`                         Defines coding-agent rules

  `README.md`                         Defines project setup and developer
                                      commands
  -----------------------------------------------------------------------

------------------------------------------------------------------------

**Implementation decision summary:** Start with a short, mandatory
Readium integration spike on Android and iOS. Then build the shared
Flutter foundation, local persistence, import/library, reader,
annotations, and backup/restore in that order. Release Android first,
but keep the iOS target buildable and validate cross-platform behavior
throughout development.
