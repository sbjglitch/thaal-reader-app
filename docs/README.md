# Reader App

An offline-first EPUB and PDF reader for Android and iOS, built with Flutter.

The app is designed for a focused personal reading experience: import publications into a local library, read without an internet connection, save reading progress, organise books, create bookmarks and EPUB annotations, and back up or restore the library manually.

> **Project status:** Milestone 0 (reader-engine spike) validated on Android; Milestone 1 (project foundation) in place. iOS work is on hold. See the repository root `README.md` for setup and the pinned toolchain.

## Product goals

- Provide a dependable EPUB and PDF reading experience.
- Keep the library and reading data available offline.
- Restore a reader to its last saved location.
- Support bookmarks and EPUB highlights/notes where the reader engine permits.
- Let users export and restore their data without an account or cloud service.
- Maintain one shared Flutter application for Android and iOS.

## MVP scope

- Local book library and metadata.
- EPUB reader.
- PDF reader.
- Reading progress and status.
- Bookmarks.
- EPUB highlights and notes, subject to validated engine support.
- Manual full backup and library-only backup.
- Backup restore.
- Reader and application preferences.

### Not included in the MVP

- Accounts, backend, and cloud sync.
- Social, discovery, and marketplace features.
- AI reading assistant.
- Audiobooks and text-to-speech.
- DRM/LCP-protected publications.
- OCR and advanced PDF editing.
- Additional formats beyond EPUB and PDF.
- Web or desktop applications.

## Technology stack

| Area | Technology |
|---|---|
| Framework | Flutter |
| Language | Dart |
| State management | Riverpod |
| Navigation | go_router |
| Local database | Drift + SQLite |
| EPUB/PDF integration | `flutter_readium` |
| Simple global preferences | SharedPreferences |
| Publication files | App-private filesystem storage |
| Backup archive | ZIP with JSON manifest and checksums |

Critical dependencies should be pinned to exact versions and upgraded deliberately. The reviewed `flutter_readium` version for the current architecture is `0.9.0`; verify the installed package version, API, and native setup requirements before implementation.

## Getting started

### Prerequisites

Install and configure:

- Flutter SDK compatible with the project.
- Dart SDK bundled with the selected Flutter SDK.
- Android Studio and Android SDK for Android development.
- Xcode and CocoaPods for iOS development on macOS.
- Git.

Confirm the local toolchain:

```bash
flutter --version
dart --version
flutter doctor -v
```

Resolve the issues reported by `flutter doctor` for the platforms you intend to build.

### Set up the project

Clone the repository, then run:

```bash
git clone https://github.com/sbjglitch/thaal-reader-app.git
cd thaal-reader-app

flutter pub get
```

The application ID and iOS bundle identifier are `com.sbjglitch.thaal`. Do not overwrite existing platform configuration.

### Run on Android

Start an Android emulator or connect a device with USB debugging enabled:

```bash
flutter devices
flutter run -d <android-device-id>
```

### Run on iOS

On macOS with Xcode and CocoaPods configured, start an iOS simulator or connect a device:

```bash
flutter devices
flutter run -d <ios-device-id>
```

The exact commands may change as the repository and platform configuration are established. Follow the committed Flutter and native build configuration.

## Project structure

The intended architecture is feature-oriented MVVM with Repository boundaries. Adapt this outline to the actual implementation as it develops.

```text
reader_app/
├── CLAUDE.md
├── README.md
├── pubspec.yaml
├── pubspec.lock
├── lib/
│   ├── app/
│   │   ├── router/
│   │   └── theme/
│   ├── core/
│   │   ├── errors/
│   │   ├── files/
│   │   └── utils/
│   ├── data/
│   │   ├── database/
│   │   ├── repositories/
│   │   └── backup/
│   ├── domain/
│   │   ├── entities/
│   │   ├── repositories/
│   │   └── use_cases/
│   └── features/
│       ├── library/
│       ├── reader/
│       ├── bookmarks/
│       ├── annotations/
│       ├── collections/
│       ├── backup/
│       └── settings/
├── test/
├── integration_test/
├── docs/
└── assets/
```

### Architecture boundaries

- Domain models must not depend on Flutter widgets, Drift-generated rows, or reader-plugin classes.
- Repositories isolate database and filesystem access.
- `flutter_readium` is accessed through an app-owned reader adapter/service.
- Publication files are stored in app-private storage, not as SQLite BLOBs.
- Drift/SQLite stores structured library and reading data.
- SharedPreferences is reserved for small global settings.
- Keep Android and iOS build targets viable throughout development.

## Documentation

Read the relevant specifications before implementing a feature.

| Document | Purpose |
|---|---|
| `reader_app_prd.md` | Product requirements and MVP scope |
| `TECHNICAL_ARCHITECTURE.md` | System architecture and implementation boundaries |
| `DATABASE_SCHEMA.md` | Local data model, constraints, and migrations |
| `BACKUP_FORMAT.md` | Backup archive structure and restore rules |
| `IMPLEMENTATION_PLAN.md` | Development milestones and acceptance criteria |
| `READER_ENGINE_SPECIFICATION.md` | Reader adapter and engine integration |
| `TESTING_STRATEGY.md` | Test coverage, platform matrix, and release gates |
| `RELEASE.md` | Android signing, release builds, store listing and privacy drafts |
| `ARCHITECTURE_DECISIONS.md` | Accepted architecture decisions |
| `UI_UX_SPECIFICATION.md` | Visual direction, design tokens, screens, and UI states |
| `CLAUDE.md` | Claude Code instructions and development workflow |

Keep these documents in the repository root or move them into `docs/` consistently. If you move them, update references in `CLAUDE.md` and other project documents.

## Development workflow

Work in small, testable milestones rather than generating the entire application at once.

Recommended order:

1. **Reader-engine spike:** Validate EPUB and PDF rendering with the pinned `flutter_readium` version on Android and iOS.
2. **Foundation:** Establish Flutter project structure, routing, Riverpod, themes, and CI checks.
3. **Database and storage:** Implement Drift schema, migrations, private file storage, and recoverable import operations.
4. **Library:** Implement import, metadata, search, sorting, and collections.
5. **Reader:** Implement reader sessions, navigation, preferences, and progress restoration.
6. **Annotations:** Add bookmarks, EPUB highlights, and notes.
7. **Backup and restore:** Implement and test full and library-only backup workflows.
8. **Hardening:** Complete platform, accessibility, privacy, performance, and release checks.

Android is the first release target, but shared features should be designed for both platforms and validated on iOS before the iOS release.

## Testing and quality checks

Run these commands from the repository root:

```bash
# Check formatting
dart format --output=none --set-exit-if-changed .

# Static analysis
flutter analyze

# Run tests
flutter test

# Build Android debug APK
flutter build apk --debug

# Build iOS simulator app (macOS with Xcode required)
flutter build ios --simulator --debug
```

Add tests for domain logic, database migrations, file import/recovery, reader adapter behaviour, progress restoration, annotations, and backup/restore.

Before release, validate:

- EPUB and PDF reading on the target platform.
- Import, app restart, and publication reopening.
- Reading-progress restoration.
- Bookmark and annotation persistence.
- Full and library-only backup/restore.
- Core workflows in airplane mode.
- Invalid backup rejection and interrupted-operation recovery.
- Accessibility and physical-device lifecycle behaviour.

Do not report a check as passing unless it has actually been run successfully. See `TESTING_STRATEGY.md` for the complete strategy.

## Offline operation and data handling

The MVP is local-only:

- No user account is required.
- No backend or cloud sync is used.
- Imported files are copied into app-private storage.
- Structured metadata and reading state are stored locally in SQLite.
- Backups are initiated and managed by the user.

The original file selected during import must not be modified or deleted. Backup restore must validate archive paths and contents before writing files.

## Known constraints

- The app supports EPUB and PDF only in the MVP.
- LCP-protected publications are not supported by the selected reader integration at the time of the current architecture review.
- Reader-engine capabilities and setup requirements must be checked against the exact installed `flutter_readium` release.
- Some reader features may differ between Android and iOS and must be validated independently.
- Cloud sync and automatic cross-device transfer are not part of the MVP.

## Contributing and AI-assisted development

Before changing code:

1. Inspect the existing repository and read relevant documentation.
2. Identify the smallest coherent task.
3. Follow `CLAUDE.md` and the accepted architecture decisions.
4. Add or update tests.
5. Run formatting, static analysis, and relevant tests.
6. Review the diff and update documentation when behaviour or architecture changes.

Do not invent reader-plugin APIs, silently change database or backup formats, introduce unapproved backend services, or expand MVP scope without approval.

## License

License not yet specified. Add the project's chosen licence before public distribution.
