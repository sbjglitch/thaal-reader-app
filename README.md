# Thaal

An offline-first EPUB and PDF reader for Android and iOS, built with Flutter.
No accounts, no backend, no network: publications and reading data stay on
the device.

> **Status:** Milestone 6 (backup and restore). Import, the library,
> reading EPUB and PDF books with a table of contents, saved reading
> position, reading settings, bookmarks, EPUB highlights and notes, the
> app theme setting, and creating full and library-only backups work.
> Restoring a backup is not built yet. Android is the first target;
> **iOS work is on hold**.

Product scope, architecture and milestones live in [`docs/`](docs/README.md).
Rules for AI-assisted development are in [`CLAUDE.md`](CLAUDE.md).

## Prerequisites

Versions this project is built and tested with:

| Tool | Version |
|---|---|
| Flutter | 3.47.9 (stable) |
| Dart | 3.13.7 (bundled with Flutter) |
| JDK | 21 (`flutter config --jdk-dir <path>`); `flutter_readium` needs JVM 18+ |
| Android SDK | compileSdk 37 |
| Android Gradle Plugin / Gradle / Kotlin | 9.1.1 / 9.3.1 / 2.4.0 |

iOS (Xcode, CocoaPods) is needed only when iOS work resumes.

Check the toolchain:

```bash
flutter --version
flutter doctor -v
```

## Setup

```bash
git clone https://github.com/sbjglitch/thaal-reader-app.git
cd thaal-reader-app
flutter pub get
```

Application ID / bundle ID: `com.sbjglitch.thaal`. Display name: Thaal.

### Generated code

Drift generates `lib/data/database/app_database.g.dart`, which is committed.
Regenerate it after changing tables or the database class:

```bash
dart run build_runner build
```

Before raising the database schema version, export the new schema snapshot
(see `docs/DATABASE_SCHEMA.md` §10):

```bash
dart run drift_dev schema dump lib/data/database/app_database.dart drift_schemas/
```

### SQLite at build time

`package:sqlite3` bundles its own SQLite. During a build it downloads the
prebuilt library from the package's GitHub release and verifies it against
SHA-256 hashes pinned in the package. This happens only on the build
machine; the app makes no network calls.

### Gradle wrapper download times out

On some networks one of GitHub's release-asset addresses is unreachable and
Java does not fall back to another address, so the Gradle wrapper download
fails with `ConnectException: Operation timed out`. The workaround is to
download the distribution with `curl`, verify its SHA-256 and place it in the
wrapper cache. See
[`docs/READER_ENGINE_SPIKE.md` §5](docs/READER_ENGINE_SPIKE.md) for details.

## Run

Connect an Android device with USB debugging enabled:

```bash
flutter devices
flutter run -d <device-id>
```

Importing uses the system document picker (`file_picker`), so the app needs
no storage permission. The picker's temporary copies are deleted after each
import; the user's original files are never modified. Backups are saved
through the system Save dialog, which needs no permission either.

## Checks

`tool/check.sh` runs formatting, static analysis and tests. Add `--build` to
also build the Android debug APK:

```bash
./tool/check.sh --build
```

## Project layout

```text
lib/
├── main.dart              # Entry point → app/bootstrap.dart
├── app/                   # Bootstrap, root widget, router, shell, providers
│   └── theme/             # Design tokens and ThemeData (UI/UX spec §3–5, §9)
├── core/
│   ├── errors/            # Typed AppError hierarchy
│   ├── logging/           # Privacy-safe local logger
│   ├── utils/             # UUID generation
│   └── widgets/           # Shared empty / error / loading states
├── domain/
│   ├── entities/          # Books, reading data, ManagedPath, locator envelope
│   ├── repositories/      # Repository contracts
│   └── services/          # Service contracts (publication inspector)
├── data/
│   ├── database/          # Drift tables, converters, AppDatabase (+ .g.dart)
│   ├── repositories/      # Drift-backed repository implementations
│   └── preferences/       # SharedPreferences-backed settings
├── services/
│   ├── storage/           # App-private library files and staging
│   ├── library/           # Book removal workflow
│   ├── import/            # Document picker and import pipeline
│   ├── backup/            # Backup format, archive writer/verifier, export
│   └── reader/            # Reader contract + flutter_readium adapters
│                          # (the only code that imports the plugin)
└── features/<feature>/{application,presentation}/
test/                      # Mirrors lib/; shared helpers in test/support/
drift_schemas/             # Exported database schema per version
spike/reader_engine_spike/ # Milestone 0 throwaway spike (not part of the app)
docs/                      # Specifications
```

At startup the app creates `<app support>/library/{books,staging}` and
`<app support>/thaal.sqlite`, and removes staging leftovers older than an
hour.

## License

Not yet specified.
