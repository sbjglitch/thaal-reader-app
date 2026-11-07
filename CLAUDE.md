# CLAUDE.md

This file defines the working rules for Claude Code when developing this repository. Follow these instructions for every task unless the user explicitly changes the product requirements.

## 1. Project overview

Build an offline-first personal EPUB and PDF reader for Android and iOS.

The product is inspired by established ebook readers, but implementation decisions must follow this repository's specifications rather than copying another app's feature set.

### Product principles

- Reading and library management work without an internet connection.
- Imported publications and user reading data stay on the device.
- The MVP does not require accounts, a backend, cloud storage, or cloud sync.
- Reading progress must restore reliably.
- Import, backup, and restore must protect user data against partial failure.
- Android is the first release target; iOS remains a first-class platform.
- Prefer a dependable core reading experience over premature feature expansion.

### MVP scope

1. Local library management.
2. EPUB reading.
3. PDF reading.
4. Reading progress and reading status.
5. Bookmarks.
6. EPUB highlights and notes, subject to validated reader-engine support.
7. Manual full and library-only backup/restore.
8. Reader and application preferences.

### Explicitly out of scope unless the user changes the scope

- Accounts, backend, and cloud synchronisation.
- Social features, book discovery, and marketplaces.
- AI reading assistant.
- Audiobooks and text-to-speech.
- DRM/LCP-protected publications.
- OCR and advanced PDF editing.
- Additional publication formats beyond EPUB and PDF.
- Web and desktop applications.

Do not add out-of-scope features, dependencies, services, or permissions without asking.

## 2. Read the project documentation first

Before making a change, inspect the repository and read the relevant documentation. For architectural, data, reader, backup, or cross-cutting work, read all applicable documents.

The project specifications are expected to live in the repository root or under `docs/`. Locate the actual files rather than assuming their paths.

Core documents:

- `reader_app_prd.md` — product requirements and MVP scope.
- `TECHNICAL_ARCHITECTURE.md` — system architecture and project structure.
- `DATABASE_SCHEMA.md` — database entities, constraints, and migrations.
- `BACKUP_FORMAT.md` — backup archive format and restore rules.
- `IMPLEMENTATION_PLAN.md` — milestones, sequencing, and acceptance criteria.
- `READER_ENGINE_SPECIFICATION.md` — reader integration and adapter contract.
- `TESTING_STRATEGY.md` — test levels, critical journeys, and release gates.
- `ARCHITECTURE_DECISIONS.md` — accepted architecture decisions.
- `UI_UX_SPECIFICATION.md` — visual direction, design tokens, screens, and UI states.

If a referenced document is missing, do not silently invent its contents. Report the missing document and proceed only with requirements that are clear from the remaining specifications or the user's instruction.

When specifications conflict, identify the conflict before making a consequential change. Treat the latest explicit user decision as authoritative, then update the affected documentation so it remains consistent.

## 3. Technology stack

Use the following stack unless an ADR is explicitly revised:

| Concern | Technology |
|---|---|
| Cross-platform framework | Flutter |
| Language | Dart |
| State management and dependency injection | Riverpod |
| Navigation | go_router |
| Local relational database | Drift + SQLite |
| EPUB/PDF reader integration | `flutter_readium` |
| Small global preferences | SharedPreferences |
| Publication storage | App-private filesystem storage |
| Backup | Versioned ZIP archive with JSON manifest and checksums |

### Dependency discipline

- Pin exact versions for critical native dependencies, especially `flutter_readium`.
- Commit and maintain `pubspec.lock`.
- Do not upgrade critical dependencies as part of an unrelated task.
- Before upgrading a native dependency, inspect its changelog, API, examples, and platform requirements.
- Run the reader compatibility checks on both Android and iOS after an upgrade.
- Do not add a package when the existing Flutter SDK or an existing dependency can reasonably meet the need.
- Explain the purpose and maintenance implications of any new dependency.

The reviewed `flutter_readium` version for the current architecture is `0.9.0`. Verify the actual installed version and its current setup requirements before implementation. Its APIs and native setup must be taken from the installed version, not guessed from memory or old examples.

## 4. Architecture rules

Use feature-oriented MVVM with Repository boundaries.

Keep the dependency direction clear:

```text
Presentation
    ↓
Application / use cases
    ↓
Domain contracts
    ↑
Data and platform implementations
```

### Domain layer

- Contains app-owned entities, value objects, and contracts.
- Must not import Flutter widgets, Drift-generated database classes, or `flutter_readium` types.
- Must not depend on UI navigation or platform-specific file-picker implementations.
- Keep business rules deterministic and independently testable.

### Presentation layer

- Use Flutter widgets for UI.
- Use Riverpod for feature state and dependency injection.
- Keep widgets focused on rendering and user interaction.
- Do not put database queries, filesystem orchestration, or reader-plugin calls directly in widgets.
- Represent loading, empty, success, error, and cancellation states explicitly where relevant.

### Data layer

- Use repositories to coordinate persistence and data sources.
- Keep Drift queries and generated database types inside the data layer.
- Use transactions for related database changes.
- Map database rows to app-owned models at the repository boundary.

### Reader integration

- Keep `flutter_readium` behind an app-owned reader adapter/service.
- Do not allow plugin-specific types to leak into domain entities or unrelated features.
- Map the exact installed plugin API to app-owned reader contracts.
- Keep the active reader session lifecycle explicit.
- The app supports one active reader session at a time unless the product requirements change.
- Dispose native reader resources when the session ends.
- Fake reader implementations are appropriate for unit/widget tests, but native integration tests must exercise the real plugin.

### Navigation

- Use go_router with centrally defined route paths/names.
- Pass stable identifiers such as `bookId` through routes.
- Do not pass large mutable domain objects as the only source of route state.
- Reader navigation must coordinate with reader-session creation and disposal.

## 5. Data and storage rules

### Database

- Use Drift/SQLite for structured data such as books, progress, bookmarks, highlights, collections, and collection membership.
- Follow `DATABASE_SCHEMA.md`.
- Use explicit schema migrations.
- Test migrations from every supported previous schema version.
- Enforce documented foreign keys, uniqueness constraints, and indexes.
- Do not store EPUB/PDF file bytes as SQLite BLOBs.
- Do not store relational application data as loosely structured preference keys.

### Publication files

- Copy imported publications into app-private storage.
- Do not depend on a temporary document-picker URI remaining available after import.
- Never modify or delete the user's original source document.
- Store managed relative paths where practical.
- Validate file existence before opening a publication.
- Represent missing files as a recoverable state; do not crash or claim that the publication is available.
- Avoid reading an entire large publication into memory just to import or copy it.
- Clean up temporary files after success, cancellation, and failure.

### Multi-step operations

Import, deletion, backup, and restore affect both files and database records. Treat them as recoverable workflows.

- Define operation states and failure handling.
- Do not leave database records pointing to incomplete or nonexistent files.
- Use staging/temporary locations where appropriate.
- Commit database changes only when the corresponding file operation has reached the required safe point.
- Make cleanup and recovery idempotent where possible.
- Never delete unrelated files.

### Preferences

- Use SharedPreferences only for small global settings.
- Use Drift for relational and per-book state.
- Define defaults and migration behaviour for changed settings.
- Avoid maintaining duplicate sources of truth.

## 6. Reading progress and annotations

- Persist the reader engine's serialized locator in the app-owned, versioned locator envelope described in the reader and database specifications.
- Store useful fallback fields, such as progression or PDF page position, where defined by the data model.
- Do not use a percentage alone as the source of truth.
- Treat plugin locator payloads as opaque at the domain boundary.
- Validate locator data before attempting restoration.
- Handle malformed, outdated, missing, or unresolvable locators gracefully.
- Preserve the last valid saved position if a later progress write fails.
- Avoid excessive database writes during continuous scrolling; follow the specified save/debounce and lifecycle strategy.
- Do not assume EPUB and PDF location semantics are identical.
- Verify bookmarks and annotations resolve to the correct publication and location.
- Do not expose annotation capabilities for a format unless the reader engine and app implementation actually support them.

## 7. Offline and privacy requirements

- Core reading and library workflows must work with network connectivity disabled.
- Do not introduce account, analytics, telemetry, remote logging, or cloud dependencies without explicit approval.
- Do not make network calls for local reading, progress, annotations, or library search.
- Use the system document picker rather than requesting broad filesystem access when possible.
- Keep imported files and user reading data in app-private storage.
- Do not log publication contents, selected text, or personal notes.
- Do not commit secrets, credentials, tokens, private user documents, or production data.
- Explain any new permission and why it is necessary.

## 8. Backup and restore rules

Follow `BACKUP_FORMAT.md`.

- Use the documented `.readerbackup` archive format.
- Keep the backup schema version independent from the SQLite schema version.
- Full backups include the supported library data and publication files.
- Library-only backups exclude publication file bytes and must restore missing-file states correctly.
- Include and verify checksums as specified.
- Validate the manifest and every archive entry before extraction.
- Reject path traversal, absolute paths, duplicate unsafe entries, invalid checksums, unsupported versions, and archives exceeding documented safety limits.
- Never extract archive entries directly to arbitrary paths.
- Define conflict behaviour explicitly.
- Support safe cancellation and recovery from interrupted operations.
- Do not blindly copy a live SQLite database file as the backup strategy.
- Do not report success until the restore has been committed and verified.

## 9. Implementation workflow

Work in small, reviewable increments. Do not attempt to generate the entire application in one pass.

For each task:

1. Inspect the current repository structure and relevant code.
2. Read the applicable specification and ADRs.
3. Identify the smallest coherent implementation scope.
4. State a brief implementation plan before making broad or multi-file changes.
5. Reuse existing patterns and dependencies where appropriate.
6. Implement the change without unrelated refactoring.
7. Add or update tests at the appropriate level.
8. Run formatting, analysis, and relevant tests.
9. Inspect the final diff for accidental changes.
10. Report what changed, what was tested, and any remaining limitations.

### Task boundaries

- Do not rewrite unrelated modules to satisfy a narrow task.
- Do not change public interfaces without checking their callers and tests.
- Do not introduce placeholder implementations that appear complete.
- Do not leave dead code, unused dependencies, or commented-out alternative implementations.
- If a task reveals a specification gap, explain the gap and propose the smallest necessary clarification.
- Ask before making a product-level trade-off that changes scope or user-visible behaviour.

## 10. Testing requirements

Follow `TESTING_STRATEGY.md`.

Before considering a task complete, run the checks relevant to the changed code.

Common commands:

```bash
# Format check
dart format --output=none --set-exit-if-changed .

# Static analysis
flutter analyze

# All Flutter tests
flutter test

# Android debug build
flutter build apk --debug

# iOS simulator debug build (requires macOS and Xcode)
flutter build ios --simulator --debug
```

Add tests for:

- Domain logic and serialization.
- Repository and database behaviour.
- Database migrations.
- File import and recovery.
- Reader adapter mapping and lifecycle.
- Progress restoration.
- Bookmark and annotation persistence.
- Backup validation and restore recovery.
- UI loading, empty, error, and success states.

Do not claim a test passed unless you actually ran it and observed a successful result. If a command cannot run because the environment or platform tooling is unavailable, state that explicitly.

### Platform testing

- Android is the first release target.
- Keep the iOS target buildable throughout development.
- Test native reader behaviour on both platforms.
- Do not mark a shared feature complete based only on Android validation.
- Use physical devices for final checks involving document pickers, lifecycle, rendering, and performance.

## 11. Reader-engine technical spike

The first major implementation gate is a small end-to-end reader-engine spike.

Before substantial reader UI work, verify the exact pinned `flutter_readium` release on Android and iOS.

The spike should prove:

- Project builds with the package's documented native setup.
- A local EPUB opens and renders.
- A local PDF opens and renders.
- Table of contents can be read and navigated where supported.
- Navigation and locator updates work.
- A saved locator can be restored.
- Required reader preferences can be applied and restored.
- Search works if it is part of the MVP for the format.
- Required annotation capabilities work for EPUB.
- Reader sessions close and dispose cleanly.
- Background/foreground transitions do not leave the reader in a broken state.

Inspect the installed package source, API docs, examples, and changelog. Do not invent class names, constructors, callbacks, or method signatures. If a required capability is unsupported or behaves differently by platform, document the limitation before building UI around it.

## 12. Code conventions

- Follow the repository's existing naming and formatting conventions.
- Prefer clear, descriptive names over abbreviations.
- Keep functions and classes focused.
- Prefer immutable state and explicit state transitions.
- Handle errors at appropriate boundaries; do not silently swallow exceptions.
- Use typed models rather than unstructured maps for application data, except where opaque serialized payloads are explicitly required.
- Keep asynchronous operations cancellable or safely disposable where practical.
- Avoid unnecessary global state and service locators.
- Add comments to explain non-obvious decisions, not to narrate obvious code.
- Keep user-facing strings centralised if the project has an established localisation/string convention.
- Do not add dependencies solely to avoid writing a small amount of straightforward code.

## 13. UI and interaction requirements

Follow the product and UI/UX specifications.

- Design for a focused reading experience.
- Keep library management and reader controls predictable.
- Provide clear empty, loading, error, unavailable-file, and import-progress states.
- Confirm destructive actions such as deleting a book or replacing data during restore.
- Do not show controls for unsupported functionality.
- Ensure important controls have accessible labels and semantic meaning.
- Support system text scaling where practical.
- Do not sacrifice reading content area for unnecessary persistent controls.
- Keep platform conventions in mind while maintaining a consistent product experience.

Follow `UI_UX_SPECIFICATION.md` for design tokens, reusable components, screen content, and UI states. Do not extend it into a larger design system than it describes, and ask for clarification when a major interaction or visual decision is unspecified.

## 14. Definition of done

A task is done only when:

- The implementation matches the relevant product and architecture specifications.
- No unrelated changes have been introduced.
- Appropriate tests have been added or updated.
- Formatting and static analysis pass.
- Relevant tests pass.
- Platform limitations are identified rather than hidden.
- Errors, cancellation, and recovery states are handled where relevant.
- Documentation is updated if architecture, data format, setup, or user-visible behaviour changed.
- The final response summarises:
  - What was implemented.
  - Important files changed.
  - Commands and tests actually run.
  - Known limitations or follow-up work.

## 15. Things Claude Code must not do

- Do not replace Flutter with another framework without explicit approval.
- Do not introduce a backend, accounts, or cloud sync.
- Do not store publication files in SQLite.
- Do not couple domain models to Drift or reader-plugin classes.
- Do not call reader-plugin APIs directly from arbitrary feature widgets.
- Do not invent `flutter_readium` APIs.
- Do not upgrade critical dependencies casually.
- Do not silently change database or backup formats.
- Do not perform destructive file or database operations without a defined recovery strategy.
- Do not claim cross-platform support without validating both platforms.
- Do not mark incomplete or mocked functionality as production-ready.
- Do not expand the MVP without the user's approval.

When uncertain, inspect the repository and specifications, identify the uncertainty, and ask one focused question before making a consequential assumption.
