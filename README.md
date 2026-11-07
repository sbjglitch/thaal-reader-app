# Thaal

An offline-first EPUB and PDF reader for Android and iOS, built with Flutter.
No accounts, no backend, no network: publications and reading data stay on
the device.

> **Status:** Milestone 1 (project foundation). The app shell, theme and
> navigation are in place. Library, reader and backup features are not built
> yet. Android is the first target; **iOS work is on hold**.

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
│   ├── logging/           # Privacy-safe local logger
│   └── widgets/           # Shared empty / error / loading states
└── features/<feature>/presentation/
test/                      # Mirrors lib/; shared helpers in test/support/
spike/reader_engine_spike/ # Milestone 0 throwaway spike (not part of the app)
docs/                      # Specifications
```

`domain/`, `data/` and `services/` are added with Milestone 2, when they first
contain code.

## License

Not yet specified.
