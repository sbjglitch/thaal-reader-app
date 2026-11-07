# Product Requirements Document (PRD)

## Offline-first Ebook & Document Reader

**Document status:** Draft v1.0\
**Product name:** TBD\
**Platform:** Android\
**Product category:** Ebook & Document Reader\
**Development approach:** AI-assisted development using Claude Code\
**Technology:** Kotlin, Jetpack Compose, Readium, Room

------------------------------------------------------------------------

# 1. Product Overview

## 1.1 Product Vision

Build a modern, minimalist and offline-first ebook and document reading
application that provides an excellent reading experience while giving
users complete control over their personal reading library.

The application should make it easy to import, organise, read and
annotate digital books without requiring user accounts, internet
connectivity or cloud services.

The initial product will focus on EPUB and PDF formats, with a strong
emphasis on reading comfort, reliable progress tracking, personal
organisation and user-controlled data backups.

## 1.2 Problem Statement

Existing ebook reader applications provide essential reading
functionality but often have opportunities for improvement in usability,
personalisation, library organisation and data ownership.

Users need an application that:

-   Provides a distraction-free reading experience.
-   Supports commonly used ebook and document formats.
-   Makes managing personal book collections effortless.
-   Preserves reading progress, bookmarks and annotations.
-   Works completely offline.
-   Gives users control over their documents and personal reading data.
-   Allows users to migrate their library between devices through manual
    backups.

## 1.3 Product Goals

1.  Deliver a reliable EPUB and PDF reading experience.
2.  Provide intuitive personal library management.
3.  Preserve reading progress across application restarts.
4.  Support bookmarks and text highlights.
5.  Offer customisable reading preferences.
6.  Provide manual backup and restore functionality.
7.  Maintain complete offline functionality.
8.  Establish a scalable architecture for future features.

## 1.4 Non-goals

The following are explicitly excluded from the initial MVP:

-   User registration and authentication.
-   Cloud synchronisation.
-   Social reading features.
-   Online book marketplace.
-   AI-powered reading assistant.
-   Subscription and payment systems.
-   DRM-protected ebook support.
-   Audiobook playback.
-   Web and desktop applications.
-   Advanced PDF editing.
-   PDF OCR.
-   Online content discovery.

------------------------------------------------------------------------

# 2. Target Audience

## Primary Audience: Digital ebook readers

People who maintain personal ebook collections and prefer reading on
mobile devices.

Needs:

-   Comfortable reading experience.
-   Easy book organisation.
-   Reliable reading progress.
-   Offline access.
-   Customisable typography.

## Secondary Audience: Students and knowledge seekers

People who read academic materials, reference documents and educational
content.

Needs:

-   PDF and EPUB support.
-   Bookmarks.
-   Highlights.
-   Quick document navigation.
-   Easy access to previously read materials.

## User Characteristics

-   Prefer reading personal documents over purchasing books through an
    integrated marketplace.
-   May maintain collections containing hundreds of documents.
-   Prefer offline access.
-   Value privacy and control over personal data.
-   Expect their reading progress to persist reliably.

------------------------------------------------------------------------

# 3. Product Scope

The MVP consists of six primary modules:

1.  Library Management
2.  EPUB Reader
3.  PDF Reader
4.  Reading Management
5.  Bookmarks and Highlights
6.  Backup and Restore

Settings and preferences will support these modules.

## 3.1 Feature Prioritisation

  Priority   Meaning
  ---------- -------------------------------
  P0         Essential for MVP
  P1         Important for initial release
  P2         Future enhancement

------------------------------------------------------------------------

# 4. Functional Requirements

## 4.1 Library Management

**Objective:** Allow users to import, browse, search and organise their
personal reading library.

### Requirements

**FR-LIB-01: Import Documents**

-   Users must be able to import EPUB and PDF files.
-   Use Android Storage Access Framework.
-   Support importing individual documents.
-   Copy imported files into application-managed local storage.
-   Display an import success or failure state.
-   Prevent duplicate imports where possible.

**FR-LIB-02: Book Metadata**

-   Extract available document metadata.
-   Display title, author, cover image and file format.
-   Allow users to edit title and author.
-   Support documents with missing metadata.
-   Generate a fallback cover when no cover is available.

**FR-LIB-03: Library Display**

-   Display imported documents in a library.
-   Provide grid and list layouts.
-   Display book covers, titles and authors.
-   Indicate reading progress.
-   Distinguish unread, currently reading and completed books.

**FR-LIB-04: Search**

-   Search by title.
-   Search by author.
-   Search imported documents.

**FR-LIB-05: Sorting**

-   Sort alphabetically.
-   Sort by recently added.
-   Sort by recently opened.
-   Sort by reading progress.

**FR-LIB-06: Collections**

-   Create custom collections.
-   Rename collections.
-   Delete collections.
-   Add books to collections.
-   Remove books from collections.
-   Allow a book to belong to multiple collections.

**FR-LIB-07: Book Management**

-   Remove documents from the library.
-   Delete imported files.
-   View document information.
-   Mark books as favourites.

Deleting a book from the library must include a clear distinction
between removing its library entry and deleting its stored file.

------------------------------------------------------------------------

## 4.2 EPUB Reader

**Objective:** Provide a comfortable and customisable EPUB reading
experience.

### Requirements

**FR-EPUB-01: Document Rendering**

-   Support EPUB 2 and EPUB 3 where supported by the selected reading
    engine.
-   Render text, images and document structure.
-   Support chapters and table of contents.
-   Support footnotes where available.
-   Handle different screen sizes.

**FR-EPUB-02: Reading Navigation**

-   Navigate between chapters.
-   Navigate between pages or reading positions.
-   Open the table of contents.
-   Resume from the previous reading position.
-   Display reading progress.

**FR-EPUB-03: Reading Customisation**

-   Adjust font size.
-   Change font family.
-   Adjust line spacing.
-   Adjust paragraph spacing.
-   Adjust page margins.
-   Support light, dark and sepia themes.
-   Support horizontal and vertical reading navigation where supported.

**FR-EPUB-04: Reading Progress**

-   Automatically save reading position.
-   Restore reading position when reopening a document.
-   Save the current chapter and precise reading location.
-   Store reading progress independently for each book.

**FR-EPUB-05: Text Selection**

-   Allow text selection.
-   Allow users to copy selected text.
-   Allow users to highlight selected text.
-   Allow users to remove highlights.

------------------------------------------------------------------------

## 4.3 PDF Reader

**Objective:** Provide reliable PDF viewing and navigation.

### Requirements

**FR-PDF-01: PDF Rendering**

-   Render PDF documents.
-   Support multi-page documents.
-   Support portrait and landscape layouts.
-   Handle different PDF page dimensions.

**FR-PDF-02: Navigation**

-   Scroll vertically through documents.
-   Navigate to specific pages.
-   Display current page and total pages.
-   Support zooming.
-   Restore the previous reading position.

**FR-PDF-03: Reading Progress**

-   Save the last viewed page.
-   Save the current reading position where supported.
-   Restore the previous position when reopening the document.

**FR-PDF-04: Bookmarks**

-   Allow users to bookmark PDF pages.
-   Display saved bookmarks.
-   Navigate to bookmarked pages.
-   Delete bookmarks.

**MVP limitation:** Advanced PDF text highlighting, handwritten
annotations and document editing are excluded from the first release.

------------------------------------------------------------------------

## 4.4 Reading Management

**Objective:** Ensure users can manage and resume their reading
activity.

### Requirements

**FR-READ-01: Reading Status**

Each book must have one of three reading statuses:

-   Unread
-   Currently Reading
-   Completed

**FR-READ-02: Reading Progress**

-   Store reading percentage.
-   Store the last reading location.
-   Store the last opened timestamp.
-   Automatically update progress.
-   Restore progress after application restarts.

**FR-READ-03: Reading History**

-   Display recently opened documents.
-   Display the last opened date.
-   Allow users to reopen previously read documents.

**FR-READ-04: Completion**

-   Automatically mark a book as completed when the user reaches the
    end, subject to a configurable completion threshold.
-   Allow users to manually change reading status.

------------------------------------------------------------------------

## 4.5 Bookmarks and Highlights

**Objective:** Allow users to save important reading positions and
passages.

### Requirements

**FR-ANNOT-01: EPUB Bookmarks**

-   Add bookmarks at the current reading location.
-   Add an optional bookmark label.
-   Display all bookmarks associated with a book.
-   Navigate to a saved location.
-   Delete bookmarks.

**FR-ANNOT-02: EPUB Highlights**

-   Select text.
-   Apply highlight colours.
-   Store the selected text.
-   Store its corresponding EPUB location.
-   Restore highlights when reopening the document.
-   Delete existing highlights.

**FR-ANNOT-03: Centralised Annotations**

-   Provide a centralised bookmarks section.
-   Provide a centralised highlights section.
-   Associate every annotation with its source book.
-   Allow navigation back to the original reading location.

**Important implementation requirement:** EPUB annotations must use
stable document locations such as EPUB CFI or the reading engine's
locator model rather than page numbers alone.

------------------------------------------------------------------------

## 4.6 Backup and Restore

**Objective:** Give users complete control over backing up and restoring
their personal reading library.

### Requirements

**FR-BACKUP-01: Full Backup**

-   Export imported EPUB and PDF files.
-   Export book metadata.
-   Export reading progress.
-   Export bookmarks.
-   Export highlights.
-   Export collections.
-   Export reading preferences.
-   Export custom fonts where applicable.

**FR-BACKUP-02: Library Backup**

-   Export book metadata.
-   Export reading progress.
-   Export bookmarks and highlights.
-   Export collections.
-   Exclude original document files.

**FR-BACKUP-03: Backup Format**

-   Use a ZIP archive.
-   Include a JSON manifest.
-   Include backup format version.
-   Include application version.
-   Include backup timestamp.
-   Include file integrity checksums.

**FR-BACKUP-04: Restore**

-   Allow users to select a backup file.
-   Validate the archive before restoration.
-   Display backup information.
-   Restore books and application data.
-   Handle unsupported backup versions.
-   Handle corrupted backup files.
-   Verify restored files.

**FR-BACKUP-05: Restore Safety**

-   Never overwrite existing data without confirmation.
-   Support restoration through a staging process.
-   Preserve the existing library if restoration fails.
-   Handle duplicate book entries.

**FR-BACKUP-06: Backup Location**

-   Allow users to save backups using Android's system file picker.
-   Allow users to restore backups from local storage or external
    storage.

------------------------------------------------------------------------

## 4.7 Settings and Preferences

**Objective:** Provide users with control over application and reading
preferences.

### Requirements

**FR-SET-01: Reading Preferences**

-   Default font size.
-   Default font family.
-   Default line spacing.
-   Default margins.
-   Default reading theme.
-   Default navigation mode.

**FR-SET-02: Application Preferences**

-   Library display mode.
-   Default sorting method.
-   Default library view.

**FR-SET-03: Storage Management**

-   Display total imported document storage.
-   Display individual document sizes.
-   Clear temporary cache.
-   Remove imported books.
-   Display backup information.

**FR-SET-04: Application Information**

-   Application version.
-   Privacy information.
-   Open-source licences.
-   Acknowledgements.

------------------------------------------------------------------------

# 5. Non-functional Requirements

## 5.1 Offline-first Architecture

The application must function without an internet connection.

Requirements:

-   No mandatory account.
-   No backend dependency.
-   No cloud database.
-   No network requirement for reading.
-   No network requirement for importing documents.
-   No network requirement for annotations.
-   No network requirement for backup and restore.

## 5.2 Performance

Initial engineering targets:

  Metric                    Target
  ------------------------- --------------------------------------
  Application launch        Under 3 seconds on reference devices
  Typical book opening      Under 3 seconds
  Library scrolling         Smooth, target 60 FPS
  Reading progress saving   No perceptible delay
  Database operations       Performed asynchronously
  Large document handling   No application crash or ANR

Performance targets must be validated against defined reference devices
and representative documents.

## 5.3 Reliability

-   Reading progress must survive application restarts.
-   Bookmarks must persist.
-   Highlights must persist.
-   Database migrations must preserve existing user data.
-   Corrupted documents must not crash the application.
-   Failed imports must not create incomplete library entries.
-   Backup restoration must validate data integrity.

## 5.4 Privacy

-   Reading activity remains on the device.
-   No analytics transmission by default.
-   No document uploads.
-   No mandatory registration.
-   No unnecessary permissions.
-   User-controlled data deletion.

------------------------------------------------------------------------

# 6. Technical Architecture

## 6.1 Technology Stack

  Layer                  Technology
  ---------------------- ------------------------------------------------
  Programming language   Kotlin
  UI framework           Jetpack Compose
  Architecture           MVVM + Repository
  EPUB engine            Readium Kotlin Toolkit
  PDF rendering          Readium-compatible PDF implementation / PDFium
  Local database         Room (SQLite)
  Preferences            Jetpack DataStore
  File management        Android Storage Access Framework
  Image loading          Coil
  Dependency injection   Hilt
  Background tasks       WorkManager
  Testing                JUnit, Compose UI Testing

## 6.2 Architecture Principles

-   Offline-first.
-   Local-first data ownership.
-   Separation of UI, domain and data layers.
-   Modular feature organisation.
-   Repository pattern.
-   Reactive data updates using Kotlin Flow.
-   Dependency injection.
-   Testable business logic.
-   Versioned database migrations.

## 6.3 Local Storage Strategy

**Room database:**

-   Book metadata.
-   Collections.
-   Collection relationships.
-   Reading progress.
-   Bookmarks.
-   Highlights.
-   Reading history.

**Internal application storage:**

-   Imported EPUB files.
-   Imported PDF files.
-   Extracted covers.
-   Custom fonts.

**DataStore:**

-   Reading preferences.
-   Application preferences.

Actual document files must never be stored as database blobs.

------------------------------------------------------------------------

# 7. Database Entities

Initial database entities:

  Entity            Purpose
  ----------------- -----------------------------------------
  Book              Document metadata and file references
  Collection        User-created bookshelves
  CollectionBook    Many-to-many book relationships
  ReadingProgress   Reading location and progress
  Bookmark          Saved reading positions
  Highlight         Selected text and annotation locations
  ReadingSession    Reading activity
  ReaderSettings    Reading configuration if stored in Room

Use DataStore for application preferences where appropriate rather than
duplicating settings unnecessarily.

### Book entity -- Conceptual structure

-   id
-   title
-   author
-   description
-   coverPath
-   filePath
-   format
-   fileSize
-   dateAdded
-   lastOpenedAt
-   readingStatus
-   isFavorite

### ReadingProgress entity -- Conceptual structure

-   id
-   bookId
-   percentage
-   locator
-   currentPage
-   totalPages
-   lastUpdatedAt

The locator field must preserve the format-specific reading position.

### Highlight entity -- Conceptual structure

-   id
-   bookId
-   selectedText
-   locator
-   color
-   createdAt

The final schema should be refined during technical implementation.

------------------------------------------------------------------------

# 8. User Experience and Navigation

## 8.1 Main Navigation

The application should have a simple navigation structure.

**Library**

-   All books.
-   Collections.
-   Favourites.

**Recent**

-   Recently opened documents.
-   Reading history.

**Bookmarks**

-   Saved reading positions.

**Highlights**

-   Collected passages.

**Settings**

-   Reading preferences.
-   Application preferences.
-   Storage management.
-   Backup and restore.

## 8.2 Primary User Journey

1.  User launches the application.
2.  User imports an EPUB or PDF.
3.  Application extracts metadata and cover information.
4.  Document appears in the library.
5.  User opens the document.
6.  User reads and customises the experience.
7.  User bookmarks a position or highlights a passage.
8.  Application automatically saves reading progress.
9.  User exits the application.
10. User returns later and resumes reading from the saved location.

## 8.3 UX Principles

-   Minimalist visual language.
-   Reading-first interface.
-   Low cognitive load.
-   Clear navigation.
-   Consistent interaction patterns.
-   Minimal interruptions.
-   Accessible typography and controls.
-   Responsive layouts.
-   Clear feedback for file operations.

------------------------------------------------------------------------

# 9. MVP Acceptance Criteria

The MVP is considered functionally complete when the following
conditions are met.

### Library

-   [ ] EPUB files can be imported.
-   [ ] PDF files can be imported.
-   [ ] Book metadata is extracted.
-   [ ] Books appear in the library.
-   [ ] Search works.
-   [ ] Collections work.
-   [ ] Books can be removed safely.

### EPUB Reader

-   [ ] EPUB documents render correctly.
-   [ ] Reading settings work.
-   [ ] Navigation works.
-   [ ] Reading progress is saved.
-   [ ] Reading progress is restored.
-   [ ] EPUB bookmarks work.
-   [ ] EPUB highlights work.

### PDF Reader

-   [ ] PDF documents render correctly.
-   [ ] Zooming works.
-   [ ] Page navigation works.
-   [ ] PDF bookmarks work.
-   [ ] Reading progress is saved and restored.

### Backup and Restore

-   [ ] Full backup can be created.
-   [ ] Library-only backup can be created.
-   [ ] Backup can be exported.
-   [ ] Backup validation works.
-   [ ] Backup can be restored.
-   [ ] Corrupted backups are handled safely.
-   [ ] Existing data is protected during failed restoration.

### Offline Operation

-   [ ] Application launches offline.
-   [ ] Documents can be imported offline.
-   [ ] Documents can be opened offline.
-   [ ] Reading progress is saved offline.
-   [ ] Annotations work offline.
-   [ ] Backup and restore work offline.

------------------------------------------------------------------------

# 10. Development Roadmap

  Phase                    Deliverable                              Estimated duration
  ------------------------ ---------------------------------------- --------------------
  1\. Foundation           Project setup and architecture           1 week
  2\. Library              Importing and library management         1 week
  3\. Reading engine       EPUB and PDF readers                     2 weeks
  4\. Reading management   Progress and bookmarks                   1 week
  5\. Annotations          Highlights and centralised annotations   1 week
  6\. Backup               Export and restore                       1 week
  7\. Refinement           Reading preferences and UI refinement    1 week
  8\. QA                   Testing and bug fixing                   2 weeks

**Estimated MVP duration: 10 weeks.**

This is an initial planning estimate and will depend on integration
complexity, development experience and testing requirements.

------------------------------------------------------------------------

# 11. Future Roadmap (Post-MVP)

The following features are intentionally reserved for future releases.

## Release 1.1 -- Reading Enhancements

-   Advanced PDF annotations.
-   Custom fonts management.
-   Reading statistics.
-   Reading goals.
-   Text-to-speech.
-   Advanced library filters.
-   More document formats.

## Release 1.2 -- Intelligent Reading

-   AI-powered book assistant.
-   Chapter summaries.
-   Contextual explanations.
-   Cross-book search.
-   Smart highlights.
-   Flashcard generation.

## Release 2.0 -- Connected Ecosystem

-   Optional cloud synchronisation.
-   Cross-device reading progress.
-   Web reader.
-   Desktop application.
-   Advanced document management.
-   Third-party integrations.

------------------------------------------------------------------------

# 12. Product Success Metrics

The initial MVP should be evaluated through a small group of beta users.

  Metric                                         Initial target
  -------------------------------------- ----------------------
  Successful EPUB imports                                  98%+
  Successful PDF imports                                   98%+
  Reading progress restoration             100% in tested cases
  Annotation persistence                   100% in tested cases
  Crash-free sessions                                      99%+
  Successful backup restoration            100% in tested cases
  Core functionality available offline                     100%

Additional qualitative feedback should measure:

-   Ease of importing books.
-   Reading comfort.
-   Ease of finding documents.
-   Reliability of saved progress.
-   Satisfaction with the annotation experience.
-   Confidence in backup and restore.

------------------------------------------------------------------------

# 13. Product Constraints and Development Guidelines

1.  Android is the only target platform for the initial MVP.
2.  The application must remain fully functional without internet
    access.
3.  No backend or cloud services should be introduced.
4.  Room is the source of truth for structured application data.
5.  Original document files must remain separate from the database.
6.  Readium should be preferred over implementing ebook rendering from
    scratch.
7.  All critical operations must handle failures gracefully.
8.  Database migrations must be implemented when the schema changes.
9.  Backup archives must be versioned.
10. Features outside the MVP scope must not be implemented without
    explicit approval.
11. Each feature must be tested before moving to the next major
    milestone.
12. The UI should initially prioritise functional clarity; detailed
    visual polish will follow once the core application is stable.

------------------------------------------------------------------------

# 14. Definition of Done

A feature is considered complete only when:

-   Requirements are implemented.
-   Relevant tests pass.
-   Error and empty states are handled.
-   Offline behaviour is verified where applicable.
-   Existing functionality is not broken.
-   Code follows the agreed architecture.
-   Changes are committed to version control.
-   Acceptance criteria are satisfied.

------------------------------------------------------------------------

## Final Product Principle

Build a reliable, privacy-focused reading application that gives users
complete ownership of their digital library and reading data.

The MVP should prioritise reliability, reading comfort and data
integrity over feature quantity.
