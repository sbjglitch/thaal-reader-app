# Architecture Decisions

**Project:** Offline-first EPUB and PDF reader  
**Platforms:** Android first, iOS second  
**Status:** Accepted decisions for the MVP, subject to the validation gates noted below  
**Last updated:** 7 November 2026

---

## 1. Purpose

This document records the major architecture and technology decisions for the reader app, including the context, rationale, consequences, and constraints of each decision.

These records are intended to:

- Keep implementation aligned as the project grows.
- Prevent previously evaluated choices from being repeatedly reopened without new evidence.
- Make trade-offs visible to future contributors and AI coding agents.
- Identify decisions that depend on technical validation.

A decision marked **Accepted** is the current direction. It is not permission to ignore new evidence. Revisit a decision through a documented change when requirements, platform support, or test results materially change.

## 2. Decision summary

| ID | Decision | Current choice | Status |
|---|---|---|---|
| ADR-001 | Cross-platform framework | Flutter + Dart | Accepted |
| ADR-002 | Platform release order | Android first, iOS second | Accepted |
| ADR-003 | EPUB/PDF rendering engine | `flutter_readium` | Accepted, validation required |
| ADR-004 | Application architecture | Feature-oriented MVVM + Repository | Accepted |
| ADR-005 | State management | Riverpod | Accepted |
| ADR-006 | Navigation | go_router | Accepted |
| ADR-007 | Local relational database | Drift + SQLite | Accepted |
| ADR-008 | Publication file storage | App-private filesystem storage | Accepted |
| ADR-009 | Offline-first and privacy model | Local-only; no account or backend | Accepted |
| ADR-010 | Backup format | Versioned ZIP archive with JSON manifest and checksums | Accepted |
| ADR-011 | Progress persistence | Reader locator plus fallback position data | Accepted |
| ADR-012 | Platform-specific implementation boundary | Native reader integration behind a Flutter adapter | Accepted |
| ADR-013 | Dependency management | Exact versions for critical dependencies | Accepted |
| ADR-014 | MVP publication formats | EPUB and PDF only | Accepted |
| ADR-015 | User preferences storage | SharedPreferences for small global settings; Drift for relational/per-book state | Accepted |

---

## ADR-001 — Use Flutter and Dart for the cross-platform application

**Status:** Accepted

### Context

The application targets Android and iOS. The product needs a shared interface and shared application logic, while the EPUB/PDF rendering layer requires native platform integration.

Options considered included:

- Native Android and iOS applications.
- Kotlin Multiplatform with Compose Multiplatform.
- Flutter with Dart.

### Decision

Use **Flutter and Dart** for the shared application UI and application logic.

### Rationale

- A single UI codebase supports the Android-first release and subsequent iOS release.
- Flutter provides a mature widget system and tooling for a custom reading interface.
- Dart supports a clear separation between domain logic, data access, state management, and presentation.
- Platform-specific functionality can be isolated behind adapters and plugins.

### Consequences

- The team maintains one primary UI codebase.
- Native plugin compatibility remains a critical project risk.
- Android and iOS must both be built and tested even while Android is the first release target.
- Platform-specific behaviour must not leak throughout feature code.

---

## ADR-002 — Release Android before iOS

**Status:** Accepted

### Context

The app targets both mobile platforms, but development and release should be staged to reduce initial delivery risk.

### Decision

Ship the first MVP on **Android**, then complete and release the iOS version.

### Rationale

- A staged release narrows the initial release and validation scope.
- The Android release can validate core product workflows before the iOS release.
- The architecture still benefits from keeping the iOS target buildable throughout development.

### Consequences

- Android is the primary platform for early feature validation.
- Shared code must not depend on Android-only APIs.
- iOS build failures must be treated as architecture or integration risks, not deferred indefinitely.
- Cross-platform features are not considered complete until tested on both platforms.

---

## ADR-003 — Use `flutter_readium` as the publication rendering integration

**Status:** Accepted, with mandatory technical validation

### Context

The app needs a reading engine for EPUB and PDF. Building a complete publication renderer is outside the intended MVP scope.

The selected integration is `flutter_readium`, which provides Flutter access to Readium-based native reading functionality.

### Decision

Use **`flutter_readium`** behind an app-owned reader adapter for EPUB and PDF rendering and navigation.

Pin the exact package version used by the project. The version reviewed for this architecture is **0.9.0**, published in November 2026. Confirm the installed package version and compatibility requirements at implementation time.

### Rationale

- Readium is purpose-built for digital publication reading.
- A reader engine avoids implementing EPUB parsing, pagination, publication navigation, and rendering from scratch.
- The integration provides a path to native Android and iOS reading functionality.
- An adapter boundary limits the impact of package API changes.

### Consequences

- The package is a critical native dependency.
- Its recent release history and platform setup requirements require careful validation.
- The app must not assume that all features behave identically across Android and iOS.
- LCP-protected publications are outside the current MVP because the selected integration does not support them.
- Plugin classes and APIs must not appear in domain entities or unrelated feature modules.

### Mandatory validation gate

Before implementing the complete reader UI:

1. Pin the exact package version.
2. Read the installed package API, examples, changelog, and platform setup instructions.
3. Build a minimal EPUB reader on Android and iOS.
4. Build a minimal PDF reader on Android and iOS.
5. Validate open/close lifecycle, TOC, navigation, locator restore, preferences, search, and required annotation capabilities.
6. Confirm all Android and iOS deployment/toolchain requirements.
7. Record unsupported or platform-specific behaviour.

Do not invent plugin method names or infer APIs from old examples. The installed package is the source of truth.

---

## ADR-004 — Use feature-oriented MVVM with Repository boundaries

**Status:** Accepted

### Context

The app has distinct functional areas: library, reader, annotations, collections, backup, and settings. The codebase needs clear boundaries without introducing unnecessary enterprise-scale abstraction.

### Decision

Use a **feature-oriented architecture** with MVVM-style presentation, repositories for data access, and domain logic separated from framework-specific implementations.

### Rationale

- Features can evolve independently.
- UI state and business rules are easier to test separately.
- Database and reader-engine changes can be isolated behind interfaces.
- The structure is understandable for a small project and AI-assisted development.

### Consequences

- Feature modules own their presentation and feature-specific application logic.
- Repositories coordinate data sources and persistence.
- Domain entities must not depend on Flutter widgets, Drift-generated rows, or Readium plugin classes.
- Avoid creating abstractions that have no meaningful boundary or testability benefit.

### Suggested dependency direction

```text
Presentation
    ↓
Application / Use cases
    ↓
Domain contracts
    ↑
Data and platform implementations
```

Dependencies should point inward toward stable application/domain contracts. Infrastructure implements those contracts.

---

## ADR-005 — Use Riverpod for application state management

**Status:** Accepted

### Context

The app needs reactive state for library data, reader sessions, import operations, preferences, and backup workflows.

### Decision

Use **Riverpod** for dependency injection and application state management.

### Rationale

- It supports testable providers and dependency overrides.
- It can represent asynchronous repository operations and UI states.
- It separates feature state from widget-local presentation state.
- It supports a modular feature-oriented codebase.

### Consequences

- Providers should expose application-facing state and actions, not raw widget implementation details.
- Repository dependencies should be injected through providers.
- Provider lifetimes must be considered carefully for the active reader session and long-running import/backup operations.
- Do not use global mutable singletons as an alternative state system.

---

## ADR-006 — Use go_router for application navigation

**Status:** Accepted

### Context

The app needs navigation between the library, reader, collections, bookmarks, settings, and backup flows.

### Decision

Use **go_router** for declarative application navigation.

### Rationale

- It centralises route definitions.
- It supports parameterised routes and nested navigation.
- It provides a consistent routing model as the app grows.

### Consequences

- Route names and paths should be defined centrally.
- Pass stable identifiers, such as a book ID, rather than large model objects through route parameters.
- Reader-session creation and disposal must be handled explicitly; navigation alone must not leave native reader sessions active.
- Avoid storing essential application state only in route extras.

---

## ADR-007 — Use Drift with SQLite for structured local data

**Status:** Accepted

### Context

The app needs persistent local records for books, reading progress, bookmarks, highlights, collections, and their relationships.

### Decision

Use **Drift with SQLite** for structured relational data.

### Rationale

- SQLite is well suited to local relational data.
- Drift provides typed queries, migrations, and reactive query support.
- Relational constraints help preserve consistency between books, progress, and annotations.
- The app does not require a remote database for its MVP.

### Consequences

- Schema changes must use explicit migrations.
- Database access must be routed through repositories or data-layer services.
- Foreign-key and transaction behaviour must be tested.
- Publication file bytes must not be stored as database BLOBs.
- The database is not the only source of truth for publication file availability; file existence must be verified where necessary.

---

## ADR-008 — Store publication files in app-private filesystem storage

**Status:** Accepted

### Context

EPUB and PDF files can be large. The app needs reliable offline access without inflating the relational database.

### Decision

Copy imported publications into **app-private storage** and store their managed relative paths and metadata in SQLite.

### Rationale

- Files remain available offline after import.
- The app can manage file lifecycle independently of database records.
- SQLite remains focused on structured metadata and relationships.
- App-private storage reduces accidental exposure of imported files.

### Consequences

- Import must copy the selected source file; it must not rely on a temporary document-picker URI remaining valid indefinitely.
- Store relative managed paths rather than arbitrary absolute paths where practical.
- Do not assume a database record guarantees the file exists.
- File and database changes require recoverable multi-step operations.
- Deleting a book must not delete the user's original source document.

---

## ADR-009 — Make the MVP offline-first and local-only

**Status:** Accepted

### Context

The product is intended to be a personal reader. Core reading should not depend on an account, network connection, or cloud service.

### Decision

The MVP will be **offline-first and local-only**.

It will not include:

- User accounts.
- A backend service.
- Cloud synchronisation.
- Remote library storage.
- Social or discovery features requiring a server.

### Rationale

- Reading and library management should work without internet access.
- A local-only design reduces infrastructure and operational complexity.
- It minimises the amount of personal reading data transmitted externally.
- It keeps the MVP focused on the reading experience.

### Consequences

- Backup and restore are manual.
- No cross-device sync is available in the MVP.
- Core workflows must be tested in airplane mode.
- Future cloud features would require a separate architecture decision and a privacy/data-sync design.

---

## ADR-010 — Use a versioned ZIP-based backup format

**Status:** Accepted

### Context

Users need a way to preserve and move their library and reading data without relying on cloud sync.

### Decision

Use a versioned **`.readerbackup` ZIP archive** containing a JSON manifest, structured JSON datasets, publication files for full backups, and checksums.

Support two modes:

1. **Full backup:** Includes supported library data and imported publication files.
2. **Library-only backup:** Includes supported library data but excludes publication file bytes.

### Rationale

- ZIP is widely supported and suitable for bundling multiple files.
- JSON is inspectable and can be migrated between schema versions.
- Checksums help detect corrupted or incomplete archive entries.
- One portable format can be used across Android and iOS.

### Consequences

- The backup schema must be versioned independently from the app database schema.
- Restore must validate the manifest, paths, file counts, sizes, and checksums before committing data.
- Restore must define conflict behaviour and recover safely from interruption.
- Do not copy a live SQLite database file as the backup strategy.
- Library-only restore must represent publications whose files are absent as unavailable, not as readable books.

---

## ADR-011 — Persist reader locators, not only percentages

**Status:** Accepted

### Context

A percentage alone may not reliably identify a location in a reflowable EPUB or a page in a PDF. The app needs to reopen publications close to the user's last reading position.

### Decision

Persist the reader engine's **serialized locator** inside an app-owned, versioned locator envelope. Store additional fallback fields such as progression or page position where appropriate.

### Rationale

- A locator can carry more location context than a percentage.
- It supports restoration across changes in viewport size and text preferences better than a raw scroll offset.
- A versioned envelope allows the app to adapt stored data if the reader integration changes.

### Consequences

- Treat the serialized locator as opaque engine data at the domain boundary.
- Store an app-owned schema/version wrapper around it.
- Validate locator data before attempting restoration.
- Handle missing, malformed, or unresolvable locators gracefully.
- Preserve the last valid saved locator if a new progress write fails.
- Do not assume EPUB and PDF use identical location semantics.

---

## ADR-012 — Isolate native reader integration behind an adapter

**Status:** Accepted

### Context

The selected reading engine uses native platform implementations. Directly coupling feature code to plugin APIs would make upgrades and testing difficult.

### Decision

Create an app-owned **reader service/adapter** that translates between application contracts and the exact `flutter_readium` API.

### Rationale

- Keeps plugin-specific types out of domain and feature code.
- Enables fake reader implementations for unit and widget tests.
- Centralises lifecycle, error mapping, and platform-specific behaviour.
- Reduces the scope of changes when the plugin API evolves.

### Consequences

- The adapter must be the only application boundary that directly imports the reader plugin, except for unavoidable UI embedding points explicitly documented in the implementation.
- Adapter interfaces must reflect actual required app behaviour, not blindly mirror every plugin method.
- Native integration tests must still exercise the real plugin.
- Do not claim that a fake adapter proves native rendering works.

---

## ADR-013 — Pin exact versions of critical dependencies

**Status:** Accepted

### Context

Native plugins and platform build tooling can introduce breaking changes. Reproducible builds are important, especially for a project developed with AI coding assistance.

### Decision

Pin exact versions for critical dependencies, particularly `flutter_readium`, and commit the lockfile.

### Rationale

- Prevents unexpected API or native build changes during development.
- Makes technical spike results reproducible.
- Allows upgrades to be evaluated as explicit changes.

### Consequences

- Review changelogs before upgrades.
- Run the reader compatibility suite on Android and iOS after an upgrade.
- Update Flutter/Dart and native build tooling deliberately.
- Avoid automatic dependency upgrades for critical native packages.

---

## ADR-014 — Limit the MVP to EPUB and PDF

**Status:** Accepted

### Context

The product is a personal ebook/document reader. Supporting many formats would increase parsing, rendering, testing, and UX complexity.

### Decision

Support **EPUB and PDF only** in the MVP.

### Deferred formats and capabilities

- MOBI and AZW.
- CBZ/CBR.
- DJVU.
- DOC/DOCX.
- HTML as an imported publication format.
- Audiobooks and text-to-speech.
- OCR and advanced PDF editing.
- DRM/LCP-protected publications.

### Rationale

- EPUB and PDF cover the core reading use cases.
- Narrow format support makes compatibility testing manageable.
- The app can focus on a dependable reading and library experience.

### Consequences

- Unsupported formats must be rejected with clear messaging.
- Do not imply that renaming a file extension makes it supported.
- New formats require a separate evaluation of engine support, UX, storage, and test coverage.

---

## ADR-015 — Separate global preferences from relational reading data

**Status:** Accepted

### Context

The app has small global settings as well as structured, per-book state such as reading progress and annotations.

### Decision

Use:

- **SharedPreferences** for small global preferences and simple app settings.
- **Drift/SQLite** for relational records and per-book state.

Examples of global preferences include theme selection and default reader options. Per-book reading preferences should be stored in the database if the product supports them.

### Rationale

- Simple settings do not need relational queries.
- Structured reading data benefits from schema validation and transactions.
- The division keeps each storage mechanism focused.

### Consequences

- Do not store book records, annotations, or progress as loosely structured preference keys.
- Define defaults and migration behaviour for changed settings.
- Avoid duplicating the same source of truth in both stores.

---

## 3. Cross-cutting architecture rules

The following rules apply across all features:

1. **Local-first:** Core library and reading features must not require network access.
2. **File/database separation:** Publication bytes live in app-private storage; structured metadata lives in SQLite.
3. **Domain isolation:** Domain models do not depend on Flutter widgets, Drift rows, or reader-plugin classes.
4. **Reader boundary:** Plugin-specific integration stays behind the reader adapter.
5. **Recoverable file operations:** Import, delete, and restore must define failure and recovery behaviour.
6. **Versioned data:** Database schema, backup format, and locator envelope have independent versioning.
7. **No fabricated APIs:** Inspect installed package source, documentation, and examples before implementing integrations.
8. **Cross-platform discipline:** Android-first does not mean Android-only architecture.
9. **Explicit limitations:** Unsupported formats and engine capabilities must be represented honestly in the UI.
10. **Test critical paths:** Data integrity, progress restoration, and backup/restore require automated coverage.

## 4. Revisit criteria

Reopen an architecture decision only when at least one of these conditions is true:

- A required feature cannot be implemented reliably with the current choice.
- A critical dependency loses platform support or becomes incompatible.
- Technical spike or integration tests reveal a blocking limitation.
- A new requirement materially changes product scope.
- A measurable performance, reliability, privacy, or maintenance issue cannot be addressed within the current architecture.
- A replacement offers a clear, evidence-backed improvement that justifies migration cost.

Before changing a decision:

1. Identify the affected ADR.
2. Describe the new evidence or requirement.
3. List realistic alternatives.
4. Explain migration and compatibility costs.
5. Update the decision summary and affected technical documents.
6. Add or update tests that protect the new architecture.

## 5. Related project documents

Keep these documents aligned with the decisions above:

- `01_PRODUCT_REQUIREMENTS.md` — product scope and requirements.
- `02_TECHNICAL_ARCHITECTURE.md` — system structure and implementation boundaries.
- `03_DATABASE_SCHEMA.md` — Drift/SQLite entities, constraints, and migrations.
- `04_BACKUP_FORMAT.md` — archive format and restore behaviour.
- `05_IMPLEMENTATION_PLAN.md` — milestones and delivery sequence.
- `06_UI_UX_SPECIFICATION.md` — screens and interaction behaviour.
- `07_READER_ENGINE_SPECIFICATION.md` — reader adapter and engine integration.
- `08_TESTING_STRATEGY.md` — test layers, coverage, and release gates.
- `CLAUDE.md` — coding-agent instructions and repository workflow.

When a decision changes, update every affected document rather than allowing contradictory specifications to accumulate.
