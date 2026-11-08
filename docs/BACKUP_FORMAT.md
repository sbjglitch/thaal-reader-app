# Backup Format --- Offline-First Ebook Reader

**Document version:** 1.0\
**Date:** 7 November 2026\
**Status:** Proposed format specification\
**Platforms:** Android first, iOS second\
**Archive format:** ZIP\
**Manifest/data format:** UTF-8 JSON\
**Integrity digest:** SHA-256

------------------------------------------------------------------------

## 0. Thaal implementation notes

These notes record decisions made while implementing format version 1.
Where they differ from the illustrative examples below, the notes apply.

-   `format` is `com.sbjglitch.thaal.backup`.
-   Archive entries are stored without compression. Readers accept
    stored and deflated entries only.
-   Each `books.json` record also carries `fileSizeBytes` and
    `fileChecksum` (lowercase hex SHA-256), the library's record of the
    publication file. They are present in library-only backups too, so a
    restored book can be matched when its file is imported again.
-   `cover` is `null` when no cover is included.
-   `preferences.json` is present only when `preferencesIncluded` is true.
    Its `records` object uses the app's storage keys (`app.theme`,
    `reader.theme`, `reader.epub.fontScale`, `reader.epub.layout`,
    `reader.pdf.layout`, `reader.pdf.fit`, `library.layout`,
    `library.sort`); only these allowlisted keys are written.
-   Locators are written as the stored locator envelope, unchanged.
-   Resource limits used when reading an archive: archive 16 GiB,
    50,000 entries, manifest 32 MiB, each dataset 256 MiB, each
    publication 2 GiB, each cover 32 MiB, 16 GiB uncompressed in total,
    and a compression ratio of at most 100:1 for deflated entries over
    1 MiB.
-   A full backup is refused when any book's file is missing or does not
    match its stored checksum; there is no partial full backup.
-   Restore is merge-only (replace mode is deferred) and skips and
    reports every conflict (§8.3). Local reading positions are kept.
    Dataset JSON deeper than 64 levels is rejected before decoding.
-   A library-only restore stores each book at its normal managed path
    (`books/<id>/publication.<ext>`) without a file there, which the app
    shows as "File missing". Importing the same file later fills it in.
-   Restore commit uses `restore-journal.json` in the library root;
    see IMPLEMENTATION_PLAN.md §10 (Milestone 6b notes).

## 1. Purpose

This document defines the portable backup archive used to export and
restore the user's ebook library.

The format must: - Work entirely offline. - Be platform-independent: an
archive created on Android must be restorable on iOS, and vice versa. -
Preserve library metadata, collections, reading progress, bookmarks,
EPUB highlights, and notes. - Support backups with and without
publication files. - Be versioned so future app versions can evolve the
format safely. - Detect corruption and malformed archives before
modifying the user's current library. - Avoid depending on SQLite's
internal file format or Drift-generated schema.

The backup is a portable interchange format, not a copy of the live
SQLite database.

## 2. Backup types

The app supports two backup types.

### 2.1 Full backup

Includes: - All library records. - Reading progress. - Bookmarks. - EPUB
highlights and notes. - Collections and collection membership. -
Imported EPUB/PDF publication files. - Cover images when available. -
Portable reading preferences selected for backup.

Use this for device migration or complete recovery.

### 2.2 Library-only backup

Includes: - Library metadata. - Reading progress. - Bookmarks. - EPUB
highlights and notes. - Collections and collection membership. -
Portable reading preferences.

Does not include EPUB/PDF publication files or cover image files.

A library-only restore must not imply that the publication files are
present. The app should mark books with unavailable local files as
**Missing file** and provide a relink/import recovery action.

## 3. File naming

Suggested filename:

``` text
reader-backup-YYYYMMDD-HHmmss-full.readerbackup
reader-backup-YYYYMMDD-HHmmss-library.readerbackup
```

Examples:

``` text
reader-backup-20261107-184500-full.readerbackup
reader-backup-20261107-184500-library.readerbackup
```

Use UTC for the timestamp in the filename and manifest. The custom
`.readerbackup` extension identifies the app's backup format; the file
contents are a standard ZIP archive.

The export destination is selected by the user through the platform's
document picker/share flow. Do not assume the app can write to an
arbitrary path.

## 4. Archive layout

### 4.1 Full backup

``` text
reader-backup-20261107-184500-full.readerbackup
└── ZIP archive
    ├── manifest.json
    ├── data/
    │   ├── books.json
    │   ├── reading_progress.json
    │   ├── bookmarks.json
    │   ├── highlights.json
    │   ├── collections.json
    │   ├── collection_books.json
    │   └── preferences.json
    └── files/
        ├── books/
        │   ├── <book-id>/
        │   │   └── publication.epub
        │   └── <book-id>/
        │       └── publication.pdf
        └── covers/
            └── <book-id>.jpg
```

### 4.2 Library-only backup

``` text
reader-backup-20261107-184500-library.readerbackup
└── ZIP archive
    ├── manifest.json
    └── data/
        ├── books.json
        ├── reading_progress.json
        ├── bookmarks.json
        ├── highlights.json
        ├── collections.json
        ├── collection_books.json
        └── preferences.json
```

### 4.3 Archive path rules

-   All archive paths use `/` as the separator, regardless of platform.
-   Paths are relative to the archive root.
-   No entry may contain an absolute path, drive prefix, `..` segment,
    or null byte.
-   Each publication file is stored under a directory named with its
    stable `book_id`.
-   Archive entry names are generated by the app, not copied from
    untrusted source filenames.
-   The original filename may be retained as display metadata, but it
    must never determine the extraction path.
-   The archive must not contain executable app code or
    platform-specific database files.

## 5. Manifest specification

`manifest.json` is the first required archive entry. It describes the
backup, schema versions, included files, and integrity information.

### 5.1 Example manifest

The following is illustrative. Values such as file sizes and hashes must
be calculated from the actual exported content.

``` json
{
  "format": "com.example.reader.backup",
  "formatVersion": 1,
  "createdAt": "2026-11-07T13:15:00.000Z",
  "backupType": "full",
  "app": {
    "name": "Reader",
    "version": "1.0.0",
    "buildNumber": "1"
  },
  "dataSchemaVersion": 1,
  "locatorEnvelopeVersion": 1,
  "counts": {
    "books": 12,
    "readingProgress": 8,
    "bookmarks": 21,
    "highlights": 35,
    "collections": 3,
    "collectionBooks": 9
  },
  "entries": [
    {
      "path": "data/books.json",
      "role": "data",
      "sizeBytes": 8200,
      "sha256": "hex-encoded-sha256-digest"
    },
    {
      "path": "files/books/7b7d.../publication.epub",
      "role": "publication",
      "bookId": "7b7d...",
      "sizeBytes": 1450000,
      "sha256": "hex-encoded-sha256-digest"
    }
  ],
  "preferencesIncluded": true
}
```

### 5.2 Required manifest fields

  ----------------------------------------------------------------------------------
  Field                      Type                          Required Description
  -------------------------- ---------------- --------------------- ----------------
  `format`                   string                             Yes Stable format
                                                                    identifier

  `formatVersion`            integer                            Yes Backup format
                                                                    version

  `createdAt`                string                             Yes ISO 8601 UTC
                                                                    timestamp

  `backupType`               string                             Yes `full` or
                                                                    `library_only`

  `app.name`                 string                             Yes Application name

  `app.version`              string                             Yes App version that
                                                                    created backup

  `app.buildNumber`          string                             Yes Build identifier

  `dataSchemaVersion`        integer                            Yes Exported data
                                                                    schema version

  `locatorEnvelopeVersion`   integer                            Yes App-owned
                                                                    locator envelope
                                                                    version

  `counts`                   object                             Yes Record counts by
                                                                    dataset

  `entries`                  array                              Yes Archive entries
                                                                    with size and
                                                                    digest

  `preferencesIncluded`      boolean                            Yes Whether portable
                                                                    preferences are
                                                                    included
  ----------------------------------------------------------------------------------

### 5.3 Manifest validation

Reject a backup when: - `format` does not match the expected
identifier. - `formatVersion` is unsupported. - Required fields are
absent or have incorrect types. - `backupType` is unknown. - An entry
path is unsafe or duplicated. - An entry size is negative or exceeds
configured limits. - A digest is malformed or does not match the
extracted content. - A full backup is missing a publication file that
its book record declares as included. - A library-only backup contains
publication entries contrary to the format rules.

Unknown optional fields may be ignored for forward-compatible minor
additions. Unknown required semantics must not be guessed.

## 6. Data JSON files

All JSON files: - Use UTF-8 encoding. - Contain a top-level object with
`schemaVersion` and `records`. - Use stable application-owned field
names. - Preserve stable UUIDs from the source database. - Do not
include SQLite row IDs, Drift-generated fields, absolute device paths,
or platform-specific URI values. - Represent timestamps as ISO 8601 UTC
strings. - Represent optional values as JSON `null` or omit them
consistently according to the field definition. - Must be validated
before restore.

### 6.1 `data/books.json`

Example:

``` json
{
  "schemaVersion": 1,
  "records": [
    {
      "id": "7b7d6b6e-7e7c-4a20-a1b4-1d1f4c9a0001",
      "title": "Example Book",
      "authors": ["Example Author"],
      "description": null,
      "language": "en",
      "identifier": null,
      "publisher": null,
      "publishedAt": null,
      "format": "epub",
      "file": {
        "included": true,
        "archivePath": "files/books/7b7d6b6e-7e7c-4a20-a1b4-1d1f4c9a0001/publication.epub",
        "sizeBytes": 1450000,
        "sha256": "hex-encoded-sha256-digest"
      },
      "cover": {
        "included": true,
        "archivePath": "files/covers/7b7d6b6e-7e7c-4a20-a1b4-1d1f4c9a0001.jpg",
        "sizeBytes": 42000,
        "sha256": "hex-encoded-sha256-digest"
      },
      "readingStatus": "reading",
      "addedAt": "2026-10-01T10:00:00.000Z",
      "lastOpenedAt": "2026-11-07T12:30:00.000Z",
      "updatedAt": "2026-11-07T12:30:00.000Z",
      "metadata": null
    }
  ]
}
```

For library-only backups, set `file.included` to `false` and omit
`archivePath`, `sizeBytes`, and `sha256`. Do not export the original
absolute file path.

If the cover is not included, set `cover` to `null` or use
`included: false` consistently. The restore process may regenerate a
cover from the publication when possible.

### 6.2 `data/reading_progress.json`

``` json
{
  "schemaVersion": 1,
  "records": [
    {
      "bookId": "7b7d6b6e-7e7c-4a20-a1b4-1d1f4c9a0001",
      "locator": {
        "schemaVersion": 1,
        "engine": "readium",
        "engineLocatorVersion": null,
        "format": "epub",
        "locator": {
          "href": "chapter-01.xhtml",
          "type": "application/xhtml+xml",
          "locations": {},
          "text": {}
        }
      },
      "pageNumber": null,
      "progression": 0.42,
      "updatedAt": "2026-11-07T12:30:00.000Z"
    }
  ]
}
```

The nested locator is illustrative. The app must preserve the actual
serialized locator returned by the pinned reader integration. Do not
synthesize a locator from the example fields.

### 6.3 `data/bookmarks.json`

``` json
{
  "schemaVersion": 1,
  "records": [
    {
      "id": "d14d6b6e-7e7c-4a20-a1b4-1d1f4c9a0002",
      "bookId": "7b7d6b6e-7e7c-4a20-a1b4-1d1f4c9a0001",
      "locator": {
        "schemaVersion": 1,
        "engine": "readium",
        "format": "epub",
        "locator": {}
      },
      "label": "Important passage",
      "createdAt": "2026-11-07T12:40:00.000Z",
      "updatedAt": "2026-11-07T12:40:00.000Z"
    }
  ]
}
```

### 6.4 `data/highlights.json`

``` json
{
  "schemaVersion": 1,
  "records": [
    {
      "id": "e24d6b6e-7e7c-4a20-a1b4-1d1f4c9a0003",
      "bookId": "7b7d6b6e-7e7c-4a20-a1b4-1d1f4c9a0001",
      "locator": {
        "schemaVersion": 1,
        "engine": "readium",
        "format": "epub",
        "locator": {}
      },
      "selectedText": "Example selected text",
      "color": "yellow",
      "note": "My note",
      "createdAt": "2026-11-07T12:45:00.000Z",
      "updatedAt": "2026-11-07T12:45:00.000Z"
    }
  ]
}
```

Highlights are EPUB-only in the MVP. A future format may add PDF
annotations without changing the meaning of existing EPUB highlight
records.

### 6.5 `data/collections.json`

``` json
{
  "schemaVersion": 1,
  "records": [
    {
      "id": "f34d6b6e-7e7c-4a20-a1b4-1d1f4c9a0004",
      "name": "Design",
      "createdAt": "2026-10-01T10:00:00.000Z",
      "updatedAt": "2026-10-01T10:00:00.000Z"
    }
  ]
}
```

### 6.6 `data/collection_books.json`

``` json
{
  "schemaVersion": 1,
  "records": [
    {
      "collectionId": "f34d6b6e-7e7c-4a20-a1b4-1d1f4c9a0004",
      "bookId": "7b7d6b6e-7e7c-4a20-a1b4-1d1f4c9a0001",
      "addedAt": "2026-10-02T10:00:00.000Z"
    }
  ]
}
```

### 6.7 `data/preferences.json`

Only portable, user-facing preferences belong in the backup.

Example:

``` json
{
  "schemaVersion": 1,
  "records": {
    "themeMode": "system",
    "defaultReadingTheme": "sepia",
    "defaultFontSize": 18,
    "defaultReadingMode": "paginated",
    "librarySort": "recently_added"
  }
}
```

Do not include: - Device-specific settings. - OS permission states. -
Temporary file paths. - Authentication tokens or secrets. - Debug
settings. - Platform window dimensions or device identifiers.

Preference keys must be allowlisted. Never export every key from a
generic preferences store automatically.

## 7. Export workflow

### 7.1 Consistent snapshot

The export should represent one consistent logical snapshot.

1.  Start an export operation and prevent conflicting destructive
    library operations while snapshotting.
2.  Read the relational datasets in a consistent database transaction or
    equivalent snapshot mechanism.
3.  Copy publication and cover files into a temporary export workspace.
4.  Calculate sizes and SHA-256 digests from the copied bytes.
5.  Write JSON dataset files and the manifest.
6.  Build the ZIP archive in a temporary location.
7.  Re-open and validate the completed archive.
8.  Present the finished archive to the platform's save/share flow.
9.  Clean temporary workspace files after completion or cancellation.

Do not hold a database transaction open for the entire duration of large
file compression. Capture the logical record snapshot first, then copy
files while protecting against concurrent deletion or mutation. If a
source file disappears or changes during export, fail the backup or
explicitly report the affected book; do not silently create a backup
that claims to be complete.

### 7.2 Full backup export

-   Include every book record.
-   Include a publication file for every book marked as included.
-   Include cover files when present.
-   Include all related progress, bookmarks, highlights, collections and
    join records.
-   Include portable preferences if the user has opted to include them.

If a book's file is missing, the app must not silently label the result
as a complete full backup. Show the missing item and let the user cancel
or proceed with an explicitly reported incomplete selection only if that
behavior is deliberately supported by the product.

### 7.3 Library-only export

-   Include all relational records.
-   Set each book's file inclusion state to false.
-   Omit publication and cover entries.
-   Do not export local absolute paths.
-   Clearly label the backup as library-only in the UI.

## 8. Restore workflow

Restore is a high-risk operation. It must be staged and validated before
changing the active library.

### 8.1 Restore stages

1.  **Select:** user chooses a `.readerbackup` file.
2.  **Inspect:** read the ZIP central directory and locate
    `manifest.json`.
3.  **Validate archive:** check entry paths, duplicates, entry counts,
    compressed/uncompressed sizes, supported format version, and
    manifest structure.
4.  **Validate integrity:** stream each declared entry and verify size
    and SHA-256.
5.  **Parse data:** decode UTF-8 JSON and validate each dataset schema
    and record.
6.  **Check references:** ensure progress/bookmark/highlight records
    reference books, and collection links reference valid collections
    and books.
7.  **Check publications:** verify that each included publication exists
    and its format, size and digest match the book record.
8.  **Preview:** show backup type, creation date, record counts,
    included file count and any compatibility warnings.
9.  **Resolve conflicts:** apply the selected restore mode and duplicate
    policy.
10. **Stage:** extract publication files to a temporary app-private
    directory.
11. **Commit:** write database records and move validated files into
    final storage using a recoverable commit procedure.
12. **Verify:** check restored database/file references.
13. **Cleanup:** remove staging files and temporary data.

The existing library must remain usable if any pre-commit validation
step fails.

### 8.2 Restore modes

The MVP should provide two explicit restore modes:

**Merge into current library** - Preserve existing books not present in
the backup. - Add books and related records from the backup. - Resolve
ID and checksum conflicts using the policy below. - Do not overwrite
newer local progress or annotations without a defined merge rule.

**Replace current library** - Replace the current library records with
the validated backup contents. - Require a strong confirmation that
existing library data will be replaced. - Prefer creating an automatic
pre-restore safety backup when storage permits. - Do not delete the
current library until all archive validation and staging steps have
succeeded.

If replace mode cannot safely preserve the existing library until
commit, do not offer it in the first release.

### 8.3 Conflict resolution

Use these rules as the initial policy:

  -----------------------------------------------------------------------
  Conflict                            Merge behavior
  ----------------------------------- -----------------------------------
  Same book ID and same checksum      Treat as the same publication;
                                      merge related records by stable IDs

  Same book ID but different checksum Do not overwrite automatically;
                                      flag conflict and ask user to keep
                                      existing or import as a separate
                                      copy with a new ID

  Different book IDs, same checksum   Treat as a possible duplicate; show
                                      a duplicate warning and let user
                                      keep both or skip the incoming copy

  Same bookmark/highlight ID          If content matches, treat as
                                      already present; if different,
                                      preserve existing and create a new
                                      ID for incoming record

  Same collection ID, different name  Preserve existing collection;
                                      create a new collection with a new
                                      ID or ask the user

  Same preference key                 Ask whether to keep current
                                      preferences or apply backup
                                      preferences; never silently replace
                                      device-specific settings
  -----------------------------------------------------------------------

For MVP simplicity, it is acceptable to make merge behavior
conservative: skip conflicting incoming records and report them rather
than attempt a sophisticated semantic merge.

### 8.4 Missing publication files

For library-only backups: - Restore metadata and annotations. - Mark the
book as missing its local publication file. - Do not create a fake file
path. - Provide a relink or re-import action. - Keep its metadata and
reading data so they can be recovered when the publication is supplied.

For a full backup with a missing declared file, fail validation unless
the user explicitly chooses a documented partial-recovery mode.

## 9. Archive and resource security

Treat every backup as untrusted input, even if it was created by the
app.

### 9.1 Path validation

Reject: - Absolute paths. - Windows drive paths. - `..` traversal
segments. - Empty path components where invalid. - Duplicate normalized
paths. - Null bytes. - Unexpected file extensions or paths for declared
roles. - Symlinks or special filesystem entries unless explicitly
supported (MVP: reject them).

Never extract an archive entry by concatenating its path directly with
the destination directory. Normalize and verify that the final
destination remains inside the staging root.

### 9.2 Resource limits

Before extraction, enforce configurable limits for: - Total archive file
size. - Number of archive entries. - Maximum individual uncompressed
entry size. - Maximum total uncompressed size. - Maximum compression
ratio. - JSON document size and nesting depth. - Publication file size.

Choose initial limits based on realistic device storage and
representative ebook sizes, then document and test them. Do not rely
only on the ZIP library's defaults.

### 9.3 Integrity and authenticity

-   SHA-256 detects accidental corruption and mismatch; it does not
    prove who created the archive.
-   The MVP does not need encryption or digital signatures.
-   Do not describe a checksum-only archive as encrypted or
    tamper-proof.
-   If backup encryption is added later, use a well-reviewed
    authenticated-encryption design and a user-controlled recovery
    mechanism. Do not invent custom cryptography.

### 9.4 Privacy

-   Backups can contain book files, selected text, highlights and
    personal notes.
-   Explain what is included before export.
-   Use the platform's save/share mechanisms.
-   Do not transmit backups to a server.
-   Do not log archive contents, notes, selected text, or local file
    paths.

## 10. Versioning and compatibility

There are separate version numbers for separate concerns:

  -----------------------------------------------------------------------
  Version                             Purpose
  ----------------------------------- -----------------------------------
  `formatVersion`                     Overall archive structure and
                                      required semantics

  `dataSchemaVersion`                 JSON record schema

  `locatorEnvelopeVersion`            App-owned wrapper around serialized
                                      reader locators

  App version                         Application release that created
                                      the backup
  -----------------------------------------------------------------------

### 10.1 Compatibility rules

-   The app must support the current format version.
-   Older supported format versions must be upgraded through explicit
    conversion code before restore.
-   A newer unsupported major format version must be rejected with a
    clear message.
-   Unknown optional fields may be ignored.
-   Unknown enum values in required fields must not be silently mapped
    to arbitrary defaults.
-   Locator payloads that cannot be interpreted should be preserved as
    opaque data where safe; warn that position restoration may not work.
-   Never discard annotations simply because the current reader engine
    cannot reapply them.

### 10.2 Migration process

1.  Validate the source format version.
2.  Convert old archive JSON into the current in-memory backup model.
3.  Validate the converted model.
4.  Apply the current restore process.
5.  Do not modify the original archive.

Keep format migration code separate from SQLite/Drift database
migrations. The backup format and local database schema evolve
independently.

## 11. Failure handling and recovery

  -----------------------------------------------------------------------
  Failure                             Required behavior
  ----------------------------------- -----------------------------------
  User cancels export                 Remove temporary archive/workspace;
                                      leave library unchanged

  Storage runs out during export      Delete partial output; report
                                      failure

  Source file changes/disappears      Fail or explicitly report omission;
  during export                       never claim a complete backup

  Archive is corrupt                  Reject before changing the library

  Unsupported format version          Explain that a newer app version is
                                      required

  Checksum mismatch                   Reject affected archive entry; do
                                      not silently restore it

  Insufficient storage during restore Stop before commit; preserve
                                      current library

  Database commit fails               Roll back transaction and clean
                                      staged files

  File move fails during commit       Recover using staging/operation
                                      journal; keep current data
                                      recoverable

  App is terminated during restore    On next launch, detect incomplete
                                      staging/commit state and recover or
                                      roll back

  Some library-only books have no     Restore records as missing-file
  files                               entries
  -----------------------------------------------------------------------

The implementation should use a small restore-operation journal or
another recoverable commit strategy for the boundary between database
transactions and filesystem moves. SQLite transactions do not include
filesystem operations.

## 12. Testing requirements

### Export tests

-   Full backup contains all required datasets and publication files.
-   Library-only backup excludes publication files.
-   Manifest counts match exported datasets.
-   Entry sizes and SHA-256 hashes match actual bytes.
-   Export works with empty libraries and large libraries.
-   Export cancellation and low-storage paths clean up temporary files.

### Validation tests

-   Missing manifest.
-   Invalid JSON and invalid UTF-8.
-   Unsupported format version.
-   Duplicate archive paths.
-   Path traversal and absolute paths.
-   ZIP bomb/resource-limit cases.
-   Wrong size or checksum.
-   Missing publication file.
-   Mismatched book ID and archive path.
-   Broken foreign-key references in JSON records.

### Restore tests

-   Full restore on a clean installation.
-   Library-only restore.
-   Cross-platform Android-to-iOS and iOS-to-Android archive
    compatibility.
-   Merge and replace behavior.
-   Duplicate book and ID conflict behavior.
-   Restore rollback on database failure.
-   Recovery after simulated process termination.
-   Insufficient storage.
-   Existing library remains usable after every failed restore.

### Round-trip tests

For each fixture: 1. Create representative database records and
publication files. 2. Export a backup. 3. Restore into a fresh app
database and file store. 4. Compare logical records, relationships, file
checksums, and locator payloads. 5. Open restored books and verify
reading position where the reader engine supports it.

## 13. Implementation checklist

-   [x] Define backup domain models independent of Drift.
-   [x] Define JSON serializers and strict validators.
-   [x] Implement manifest generation and parsing.
-   [x] Implement safe archive path validation.
-   [x] Implement streaming SHA-256 and file-size validation.
-   [x] Implement full backup export.
-   [x] Implement library-only export.
-   [x] Implement temporary export workspace and cleanup.
-   [x] Implement restore preview.
-   [x] Implement merge conflict policy.
-   [x] Implement safe replace mode or defer it. (Deferred.)
-   [x] Implement staged extraction and recoverable commit.
-   [x] Implement restore-operation recovery after process termination.
-   [ ] Add cross-platform archive fixtures.
-   [x] Add corruption, path traversal and resource-limit tests.
-   [ ] Document backup compatibility policy in release notes.

## 14. MVP decisions

  Area                  MVP decision
  --------------------- -------------------------------------------------------
  Container             ZIP with `.readerbackup` extension
  Manifest              UTF-8 JSON
  Data files            Separate JSON file per dataset
  Integrity             SHA-256 for every declared file
  Full backup           Includes publication files and optional covers
  Library-only backup   Metadata and reading data only
  Encryption            Not in MVP
  Cloud storage         Not in MVP; user chooses save/share destination
  Restore               Validate and stage before commit
  Merge                 Conservative conflict handling
  Replace               Only if safe rollback is implemented; otherwise defer
  Cross-platform        Same archive format on Android and iOS

## 15. Definition of done

The backup feature is ready when: - Full and library-only archives can
be created offline. - The archive contains a valid manifest and
versioned JSON datasets. - Every declared entry has a verified size and
SHA-256 digest. - Unsafe paths and oversized archives are rejected. - A
full backup restores books and associated reading data. - A library-only
backup restores metadata and marks publication files as missing. -
Android-created backups can be restored on iOS and vice versa. -
Conflicts are reported and never silently overwrite user data. - A
failed restore leaves the pre-existing library usable. - Process
termination during restore is recoverable. - Backup and restore
round-trip tests pass.

------------------------------------------------------------------------

**Format decision summary:** Use a versioned ZIP archive with a JSON
manifest, one JSON file per relational dataset, and publication files
stored under stable book IDs. Validate all entries and checksums before
restore, stage files before commit, and keep the archive independent of
SQLite and platform-specific paths.
