# Android Release Guide

How to build, sign and publish Thaal for Android, with draft store and
privacy text. iOS release steps belong to Milestone 8.

## 1. One-time setup: the upload key

Google Play signs the app that users install (Play App Signing). You sign
uploads with your own **upload key**. If the upload key is lost it can be
reset through Play Console support, but keep it backed up anyway.

1.  Create the keystore outside the repository, choosing your own
    password when asked:

    ```bash
    keytool -genkeypair -v -keystore ~/keys/thaal-upload.jks -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 -alias upload
    ```

    `keytool` ships with Java (the build uses
    `/opt/homebrew/opt/openjdk@21`).

2.  Create `android/key.properties` (git-ignored):

    ```properties
    storeFile=/Users/<you>/keys/thaal-upload.jks
    storePassword=<your password>
    keyAlias=upload
    keyPassword=<your password>
    ```

3.  Back up the keystore and the password somewhere safe (a password
    manager). Never commit either.

Without `android/key.properties`, release builds are signed with the
debug key and the build prints a warning. That is fine for testing on a
phone; Google Play rejects such uploads.

## 2. Each release

1.  Set the version in `pubspec.yaml`: `version: <name>+<code>`, for
    example `1.0.0+1`. The code must increase with every upload.
2.  Run the checks: `./tool/check.sh`.
3.  Build the bundle:

    ```bash
    flutter build appbundle --release
    ```

    Output: `build/app/outputs/bundle/release/app-release.aab`.
4.  Smoke-test a release build on a phone (install
    `flutter build apk --release`): import, open an EPUB and a PDF, turn
    pages, add a bookmark, back up, restore.
5.  Confirm the release APK still requests no permissions:

    ```bash
    "$(ls -d ~/Library/Android/sdk/build-tools/*/ | tail -1)aapt2" dump permissions build/app/outputs/flutter-apk/app-release.apk
    ```

    Only `com.sbjglitch.thaal.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`
    (an internal AndroidX permission) should be listed. Re-check after
    upgrading `flutter_readium`: its manifest declares network and media
    permissions that `android/app/src/main/AndroidManifest.xml` removes.
6.  Upload to the **internal testing** track first, then closed testing,
    before production.

## 3. Release configuration (current)

| Item | Value |
|---|---|
| Application ID | `com.sbjglitch.thaal` |
| App name | Thaal |
| Version | from `pubspec.yaml` |
| minSdk / compileSdk | 24 / 37 |
| targetSdk | Flutter default |
| Permissions | none |
| Android backup | off (`allowBackup="false"`, data extraction rules exclude everything) |
| Code shrinking | R8, Flutter defaults |
| Launch screen | app background colour (`#FFFFFF` light, `#121416` dark), launcher icon on Android 12+ |
| App icon | Flutter default; replace before release (§5) |

## 4. Store listing draft

**Short description (80 characters max):**

> Read your EPUB and PDF books offline. No account, no ads, no tracking.

**Full description:**

> Thaal is a calm, private reader for the EPUB and PDF books you already
> have.
>
> - Import EPUB and PDF files from your phone.
> - Read offline with your choice of theme, text size and layout.
> - Pick up where you left off: your reading position is saved.
> - Add bookmarks, and highlight passages and write notes in EPUB books.
> - Organise your library with search, sorting, filters and collections.
> - Back up your library to a file and restore it on this or another
>   phone.
>
> Your books and reading data stay on your device. Thaal has no account,
> no ads and no analytics, and it does not use the internet at all.
>
> Thaal does not open DRM-protected books.

Assets still needed: app icon (512×512), feature graphic (1024×500), at
least two phone screenshots.

## 5. Privacy

**Data safety form (draft answers):**

-   Does the app collect or share any of the required user data types?
    **No.**
-   Thaal has no network permission, so nothing can leave the device
    through the app. Backups are files the user saves and shares
    themselves.

**Privacy policy (draft text; Google Play requires a public URL):**

> Thaal works entirely on your device. It has no account and no
> internet access, and it does not collect, store on any server, or
> share any personal data.
>
> Books you import and your reading data (progress, bookmarks,
> highlights, notes, collections and settings) are stored only in the
> app's private storage on your device. They are not included in
> Android's cloud backup or device-to-device transfer.
>
> If you create a backup, Thaal writes a file to the location you
> choose. The file is not encrypted; you control where it goes and who
> can read it.
>
> Uninstalling Thaal deletes its data from your device.

Before publishing, add a contact email and the date, and host the text
at a public URL (for example a GitHub Pages page).

## 6. Before the first public release

-   Replace the launcher icon with the final design (adaptive icon with
    a monochrome layer for Android 13 themed icons).
-   Complete the Milestone 7 reliability checks in
    `IMPLEMENTATION_PLAN.md`.
-   Run the internal and closed testing tracks.
