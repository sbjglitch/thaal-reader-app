# Reader Engine Specification --- Offline-First Ebook Reader

**Document version:** 1.0\
**Date:** 7 November 2026\
**Status:** Proposed implementation specification\
**Platforms:** Android first, iOS second\
**Framework:** Flutter\
**Reader engine:** `flutter_readium` over native Readium toolkits

------------------------------------------------------------------------

## 1. Purpose

This document defines how the application integrates EPUB and PDF
reading into the Flutter app.

It is the implementation contract for: - Opening and closing local
publications. - Rendering EPUB and PDF content. - Navigation and table
of contents. - Reading-position tracking and restoration. - EPUB reading
preferences. - PDF display preferences. - Bookmarks. - EPUB highlights
and notes. - Search. - Reader lifecycle, error handling, and platform
compatibility.

The app must keep the reader engine behind an application-owned adapter.
UI widgets, domain entities, database tables, and backup serializers
must not depend directly on `flutter_readium` classes.

## 2. Reader engine decision

### 2.1 Selected integration

Use [`flutter_readium`](https://pub.dev/packages/flutter_readium) as the
initial cross-platform reader integration.

The package exposes a unified Dart API and delegates publication
rendering to the native Readium toolkits: - Android: Readium Kotlin
Toolkit. - iOS: Readium Swift Toolkit.

The package's published documentation currently describes EPUB 2/3
reading, PDF on Android and iOS, preferences, locators,
highlights/decorations, content search, and reader event streams.

### 2.2 Version and dependency caution

As of 7 November 2026, pub.dev lists `flutter_readium` **0.9.0**,
published on 4 November 2026. It is a very recent release. Pin the exact
version used by the technical spike and do not automatically upgrade it
during MVP development.

The current published requirements include: - Flutter 3.44.8 or later. -
Dart SDK 3.8.0 or later. - Android minimum SDK 24. - Android compile SDK
37 or later. - Kotlin Gradle Plugin 2.3 or later. - iOS deployment
target 15.0 or later. - Android `MainActivity` must extend
`FlutterFragmentActivity`. - Android core library desugaring must be
enabled. - iOS Readium CocoaPods versions must match the versions pinned
by the plugin.

These requirements can change between releases. The pinned package's
installation guide and example project are the source of truth during
implementation.

### 2.3 MVP supported formats

  -------------------------------------------------------------------------
  Format                       Android                  iOS MVP decision
  --------------- -------------------- -------------------- ---------------
  EPUB 2                           Yes                  Yes Include

  EPUB 3                           Yes                  Yes Include

  PDF                              Yes                  Yes Include

  LCP-protected          Not currently        Not currently Exclude
  EPUB/PDF            supported by the     supported by the 
                                plugin               plugin 

  WebPub            Documented support   Documented support Exclude

  Audiobook         Documented support   Documented support Exclude

  CBZ / DiViNa       Version-dependent    Version-dependent Exclude
  -------------------------------------------------------------------------

Do not advertise support for a format just because the underlying
Readium toolkit has some capability. Confirm the exact behavior in the
pinned Flutter plugin version.

## 3. Architectural boundary

### 3.1 Responsibilities

**Flutter application owns:** - Reader screen layout and surrounding
controls. - App navigation and reader session state. - Opening and
closing workflow. - Book metadata and library records. - Progress
persistence. - Bookmark and highlight records. - Reading preferences
persistence. - Error presentation and recovery actions. - Backup and
restore.

**Readium plugin owns:** - EPUB/PDF publication rendering. -
Format-aware navigation. - Publication parsing and reading order. -
Locator generation and navigation. - EPUB/PDF display preferences
supported by the plugin. - Text selection and annotation/decorator
rendering supported by the plugin. - Reader-specific events and errors.

**Reader adapter owns:** - Translating plugin types to app-owned
types. - Mapping app commands to plugin calls. - Mapping plugin streams
to app events. - Validating serialized locators. - Hiding
plugin-specific API details from the rest of the app. - Handling plugin
lifecycle and subscriptions.

### 3.2 Dependency flow

``` text
Reader Screen (Flutter UI)
        │
        ▼
Reader ViewModel / Controller
        │
        ▼
Reader Session Coordinator
        │
        ▼
PublicationReaderService (app-owned interface)
        │
        ▼
FlutterReadiumAdapter
        │
        ▼
flutter_readium
        │
        ├── Android Readium Kotlin
        └── iOS Readium Swift

Reader Session Coordinator
        │
        ├── BookRepository
        ├── ReadingProgressRepository
        ├── BookmarkRepository
        ├── HighlightRepository
        └── ReaderPreferencesRepository
```

No feature outside the adapter should import
`package:flutter_readium/flutter_readium.dart`.

## 4. Application-owned reader contract

The following is a proposed app-owned contract. It is not a copy of the
plugin API. Implementations must map it to the exact API of the pinned
`flutter_readium` version.

### 4.1 Domain models

``` dart
enum PublicationFormat {
  epub,
  pdf,
}

enum ReaderStatus {
  idle,
  opening,
  ready,
  closing,
  error,
}

class ReaderPosition {
  const ReaderPosition({
    required this.bookId,
    required this.format,
    required this.locatorJson,
    this.progression,
    this.pageNumber,
    this.href,
    this.title,
    required this.updatedAt,
  });

  final String bookId;
  final PublicationFormat format;
  final String locatorJson;
  final double? progression;
  final int? pageNumber;
  final String? href;
  final String? title;
  final DateTime updatedAt;
}

class ReaderFailure {
  const ReaderFailure({
    required this.code,
    required this.message,
    this.recoverable = true,
  });

  final String code;
  final String message;
  final bool recoverable;
}
```

### 4.2 Service interface

``` dart
abstract interface class PublicationReaderService {
  Stream<ReaderEvent> get events;

  Future<OpenedPublication> open({
    required String bookId,
    required String localFilePath,
    required PublicationFormat format,
    String? initialLocatorJson,
  });

  Future<void> close();

  Future<void> goForward();
  Future<void> goBackward();

  Future<void> goToLocator(String locatorJson);
  Future<void> goToProgression(double progression);

  Future<void> setEpubPreferences(ReaderEpubPreferences preferences);
  Future<void> setPdfPreferences(ReaderPdfPreferences preferences);

  Future<List<ReaderSearchResult>> search(String query);
}
```

Keep the contract focused on the MVP. Add commands only when a
user-facing feature requires them. Bookmark and highlight persistence
should remain in their repositories; the reader service exposes the
engine capability to navigate or apply decorations.

### 4.3 Reader events

Define app-owned events for: - Reader status changed. - Publication
ready. - Position changed. - Table of contents available. - Text
selected. - Highlight/decorator interaction. - External link
activated. - Internal link activated. - Reader error. - Publication
closed.

The adapter should map the plugin's actual streams and callbacks to
these events. Do not assume every event exists on every platform;
document platform gaps.

## 5. Reader session lifecycle

### 5.1 Opening a book

1.  User taps a book in the library.
2.  Load the book record from `BookRepository`.
3.  Confirm the local publication file exists.
4.  Retrieve saved progress from `ReadingProgressRepository`.
5.  Parse and validate the app locator envelope.
6.  Transition UI state to `opening`.
7.  Call the reader adapter to open the local file.
8.  Wait for publication open to succeed.
9.  Build and mount the reader widget using the opened publication.
10. Pass the saved locator as the initial position when valid.
11. Wait for the reader to report ready/first usable position.
12. Transition UI state to `ready`.
13. Update `last_opened_at` and reading status.
14. Start processing reader events.

If the book file is missing, do not invoke Readium. Show a missing-file
state and offer relink/re-import.

### 5.2 Closing a book

1.  Stop accepting new reader commands.
2.  Flush the latest pending reading-position write.
3.  Cancel event subscriptions.
4.  Remove/unmount the reader widget as required by the plugin
    lifecycle.
5.  Await `closePublication()`.
6.  Clear the active publication and session state.
7.  Return to the library or previous route.

Do not call `closePublication()` repeatedly from unrelated widgets. The
session coordinator owns the lifecycle.

### 5.3 One active publication

For the MVP, support one active reader session at a time.

-   Do not open a second publication while another is active.
-   Close the current publication before opening another.
-   Prevent duplicate open calls caused by repeated taps.
-   Use a session identifier or generation token to ignore late events
    from a previous session.
-   Ensure route disposal and app lifecycle events cannot leave the
    plugin session open.

If the package's API uses a shared/global active publication, this
single-session policy avoids cross-book state collisions.

### 5.4 Reader state machine

``` text
idle
  │ open requested
  ▼
opening
  ├── success ──► ready
  └── failure ──► error

ready
  ├── close requested ──► closing
  ├── runtime failure ──► error
  └── position event ──► ready (persist position)

closing
  └── close complete ──► idle

error
  ├── retry ──► opening
  └── close ──► closing
```

The UI must render appropriate loading, ready, error, and missing-file
states. Do not display a permanently blank reader while the native
navigator is initializing.

## 6. Local publication handling

### 6.1 File input

The reader must open the app-owned local copy, not a temporary URI from
the document picker.

Expected flow:

``` text
System document picker
       │
       ▼
Temporary source URI
       │
       ▼
Import validation and copy
       │
       ▼
App-private library file
       │
       ▼
Reader adapter
       │
       ▼
flutter_readium
```

The adapter must convert the stored local path to the URL/path
representation required by the pinned plugin version.

### 6.2 Supported local file conditions

Before opening: - Confirm the file exists. - Confirm it is readable. -
Confirm its extension/recorded format is supported. - Confirm file size
is greater than zero. - Confirm the file path is inside the app's
library storage root. - Do not accept arbitrary path input from UI or
imported backup metadata.

Do not require network access to open an imported book. The app should
not pass remote URLs to the reader in the MVP.

### 6.3 Publication metadata

Use the `Publication` object returned by Readium to obtain available
publication metadata, such as title, authors, reading order, and table
of contents. Map it to the app's `Book` domain model.

The library's persisted metadata remains app-owned. If metadata
extraction fails, the import workflow should still allow a valid file to
be stored with a fallback title derived from the original filename.

## 7. EPUB reading requirements

### 7.1 Rendering

The EPUB reader must support the plugin's verified EPUB 2/3 rendering
behavior on Android and iOS.

Required MVP behaviors: - Reflowable EPUB reading. - Page/pagination
navigation. - Vertical scrolling if supported and exposed by the pinned
version. - Internal chapter links. - Table of contents navigation. -
Reading-position restoration. - Font size and reading theme controls. -
Text selection. - EPUB bookmarks and highlights, subject to integration
validation.

Fixed-layout EPUB should be tested separately. If behavior is
inconsistent or unsuitable, document it as a limitation rather than
promising full support.

### 7.2 Table of contents

-   Read the publication's flattened TOC from the publication model
    where available.
-   Present a Flutter-owned TOC sheet/panel.
-   Display nested entries with hierarchy.
-   Convert a selected TOC link to a reader locator using the plugin's
    supported API.
-   Navigate to that locator.
-   Close the TOC panel after successful navigation.
-   Handle entries that cannot be resolved without crashing.

The TOC UI should be app-owned and visually consistent with the rest of
the product.

### 7.3 Navigation

Provide: - Next/previous page or progression commands. - TOC chapter
navigation. - Jump to a saved bookmark. - Jump to a saved highlight. -
Restore last reading position.

Use the plugin's navigation methods rather than implementing EPUB
navigation by changing WebView URLs or manipulating publication HTML.

### 7.4 EPUB preferences

Persist app-owned preferences and translate them to the plugin's
`EPUBPreferences`.

Initial preferences:

  ------------------------------------------------------------------------
  Preference                                     MVP Notes
  --------------------- ---------------------------- ---------------------
  Font size                                      Yes Relative scale;
                                                     verify API semantics

  Font family                                    Yes Only offer families
                                                     supported by the
                                                     plugin or bundled app
                                                     fonts

  Reading theme                                  Yes Light, dark, sepia;
                                                     map to supported
                                                     styling API

  Pagination /                                   Yes Paginated default;
  scrolling                                          scroll mode optional

  Line height                               Optional Include only if
                                                     stable on both
                                                     platforms

  Text alignment                            Optional Include if stable

  Margins                                      Later Avoid overloading
                                                     initial settings

  Columns                                      Later Not essential to MVP

  Custom CSS                                      No Avoid arbitrary CSS
                                                     in user settings for
                                                     MVP
  ------------------------------------------------------------------------

Use the plugin's preferences API. Do not inject custom JavaScript or CSS
to implement basic typography controls.

### 7.5 External and internal links

-   Internal EPUB links should remain within the publication.
-   If the plugin exposes an internal-link callback, use it for optional
    "return to previous position" behavior later.
-   External links should be handled by an explicit app policy.
-   MVP default: ask for confirmation or open external links through the
    system browser only after user action.
-   Do not automatically navigate the app's WebView to arbitrary
    external content.
-   Preserve reading position before leaving the publication for an
    external link.

## 8. PDF reading requirements

### 8.1 Rendering

Use the plugin's PDF navigator on Android and iOS.

MVP behaviors: - Render PDF pages. - Page navigation. - Current page
display where available. - Restore the last reading position. - Basic
page fit/layout preferences supported by the plugin. - PDF table of
contents navigation where the publication exposes usable navigation
data.

### 8.2 PDF preferences

The plugin documents a PDF preference model including layout, reading
progression, page spacing, and fit behavior.

Initial app preferences:

  Preference                                               MVP
  --------------------------- --------------------------------
  Layout: paginated                                        Yes
  Layout: vertical scroll       Yes, after platform validation
  Layout: horizontal scroll                              Later
  Fit: auto                                                Yes
  Fit: page                                           Optional
  Fit: width                                               Yes
  Page spacing                               Default initially
  Reading progression                        Default initially

The default layout must be tested on both platforms. The plugin
changelog documents a change to Android PDF's default layout in version
0.7.0, so set the desired app default explicitly rather than relying on
a package default.

### 8.3 PDF annotations

MVP includes PDF page position and page bookmarks only.

Do not assume EPUB text highlight behavior applies to PDF. PDF text
selection, highlight persistence, annotation geometry, and
re-application require separate validation and are deferred from the
MVP.

## 9. Reading position and locator persistence

### 9.1 Principle

A reading position is format-specific. Store the complete serialized
locator, not just a page number or percentage.

-   EPUB: locator generally identifies a resource and a position within
    it, potentially including CFI and text context.
-   PDF: locator identifies a PDF page/location according to the
    plugin's locator representation.
-   Progression: useful for UI display but not sufficient for reliable
    restoration.

### 9.2 Stored locator envelope

Store the plugin locator inside an app-owned versioned envelope:

``` json
{
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
}
```

This is a structural example only. Persist the actual JSON from
`Locator.toJson()` and preserve its fields. Do not create a locator
manually from the sample.

### 9.3 Save behavior

Listen to the plugin's text-locator/position event stream. The current
documentation names `onTextLocatorChanged` for position updates.

For each event: 1. Convert locator to JSON using the plugin's supported
serialization method. 2. Wrap it in the app-owned locator envelope. 3.
Extract progression and page information when available. 4. Update an
in-memory pending position. 5. Debounce writes to Drift. 6. Flush on
explicit page navigation, app backgrounding, reader close, and a short
idle interval.

Do not write to SQLite for every pixel of a scrolling event. Use a
configurable debounce interval and ensure the latest pending value is
flushed.

### 9.4 Restore behavior

1.  Read the saved locator JSON.
2.  Validate the app envelope version.
3.  Parse the plugin locator with the pinned version's supported parser,
    e.g. `Locator.fromJsonString()` where available.
4.  Pass it as the reader widget's initial locator using the supported
    API.
5.  Wait for the reader to become ready.
6.  Verify that the restored position is close to the saved location.
7.  If restoration fails, open at the beginning and show a
    non-destructive warning.
8.  Preserve the invalid locator record for diagnostics or future
    migration unless the user chooses to reset progress.

### 9.5 Progress display

Use `totalProgression` when available and meaningful. Treat it as an
approximate display value: - Do not assume EPUB progression is a
universal page percentage. - Do not use it as the only key for bookmarks
or restoration. - PDF page number should be stored separately when
available. - Some publications may not expose a reliable total
progression.

## 10. Bookmarks

### 10.1 Create bookmark

-   Capture the current locator.
-   Create an app-owned bookmark UUID.
-   Store the locator envelope in the `bookmarks` table.
-   Store optional user label and timestamps.
-   Show a success state only after persistence succeeds.

### 10.2 Navigate to bookmark

-   Retrieve the bookmark.
-   Validate its locator envelope.
-   Parse locator with the reader adapter.
-   Navigate using the plugin's supported `goToLocator` method.
-   If the target is unavailable, preserve the bookmark and show a
    recoverable message.

### 10.3 Bookmark UI

The Flutter app owns: - Bookmark list. - Add/remove actions. - Label
editing. - Chapter/page context display where available. - Empty state
and error handling.

Readium is responsible for navigating to the location, not for owning
the app's bookmark database.

## 11. EPUB highlights and notes

### 11.1 Scope

Highlights are an MVP feature only if the technical spike confirms
stable support for: - Text selection events. - Locator/selection
serialization. - Applying decorations/highlights. - Reapplying
decorations after reopening. - Android and iOS behavior.

### 11.2 Data flow

``` text
User selects text
       │
       ▼
Readium selection event
       │
       ▼
Flutter reader adapter
       │
       ├── selected text
       └── locator / selection location
       │
       ▼
Highlight editor UI
       │
       ├── color
       └── optional note
       │
       ▼
HighlightRepository (Drift)
       │
       ▼
Saved highlight
       │
       ▼
Readium decoration API on next open
```

### 11.3 Persistence

Store: - Stable highlight ID. - Book ID. - Serialized
locator/selection. - Selected text when available. - App-owned color
token. - Optional note. - Created and updated timestamps.

Do not store plugin decoration objects or native platform classes in
Drift.

### 11.4 Reapplying highlights

On opening an EPUB: 1. Load saved highlights for the book. 2. Parse
their locator/selection payloads. 3. Map them to the plugin's decoration
model. 4. Apply decorations after the publication navigator is ready. 5.
Reconcile user interactions or deleted decorations through supported
callbacks.

The exact decoration APIs and model types must be taken from the pinned
plugin version's Highlights & Annotations guide and API reference. Keep
this mapping entirely inside the adapter.

### 11.5 Unsupported or stale highlights

-   A stale locator must not delete the highlight record or note.
-   If a highlight cannot be rendered, retain it in the highlight list.
-   Allow the user to copy the saved selected text if available.
-   Do not promise that a highlight will remain anchored after the
    publication file itself is replaced with a different edition.
-   If a book's checksum changes, treat it as a different publication or
    explicitly warn that its locators may no longer match.

## 12. Search

If enabled in the pinned plugin version: - Search within the currently
open publication. - Return app-owned result models containing text and
locator. - Display results in a Flutter-owned search panel. - Navigate
to a selected result using the reader adapter. - Handle empty results
and search errors.

MVP search may be limited to the open publication. Do not implement a
cross-library full-text index in this reader module.

## 13. Reader UI specification

### 13.1 Reader screen regions

The Flutter-owned reader screen should provide:

**Top controls** - Back to library. - Book title or chapter title. -
Table of contents. - Search. - More/settings menu.

**Publication viewport** - `ReadiumReaderWidget`. - Loading overlay
while opening. - Error and missing-publication states. - Avoid placing
Flutter overlays over text selection controls unless tested.

**Bottom controls** - Current progression or page indicator. -
Previous/next navigation where appropriate. - Bookmark action. - Reading
settings.

Controls should be format-aware. Do not show EPUB typography settings on
PDF unless they have a meaningful PDF equivalent.

### 13.2 Reader chrome behavior

-   Support tap-to-toggle controls if compatible with the native
    navigator.
-   Ensure controls do not intercept publication gestures
    unintentionally.
-   Keep system back behavior predictable.
-   Do not force the status/navigation bars to hide until the immersive
    mode behavior is validated on both platforms.
-   Persist preferences and reading position independently of whether
    reader chrome is visible.

### 13.3 Accessibility

-   Provide semantic labels for controls.
-   Support system text scaling for Flutter-owned controls.
-   Maintain sufficient contrast for reader chrome in all themes.
-   Do not rely on color alone to distinguish bookmark/highlight state.
-   Verify TalkBack and VoiceOver behavior around the native reader
    view; document limitations of platform-view accessibility.

## 14. Reader lifecycle and app lifecycle

### 14.1 App backgrounding

When the app moves to background/inactive: - Flush pending reading
progress. - Preserve the active publication if the plugin supports safe
suspension. - Do not close the publication automatically unless required
by platform constraints. - Do not assume the process will receive a
final shutdown callback.

### 14.2 App resume

When the app resumes: - Verify that the reader session remains valid. -
Re-establish event subscriptions only if the adapter lifecycle requires
it. - Avoid opening the same publication twice. - Re-read the latest
saved state only if the active session was lost.

### 14.3 Memory and resource management

-   Close the publication when leaving the reader route.
-   Cancel all stream subscriptions.
-   Remove reader widgets/platform views as required by plugin guidance.
-   Avoid retaining publication objects in long-lived library
    ViewModels.
-   Test repeated open/close cycles and large PDFs.
-   Do not cache entire publication content in Dart memory.

## 15. Error handling

Map plugin exceptions and error codes to app-owned failures.

  -----------------------------------------------------------------------
  Failure                             App behavior
  ----------------------------------- -----------------------------------
  File missing                        Show missing-file state and
                                      relink/import action

  Unsupported format                  Explain supported formats

  Corrupt EPUB/PDF                    Show cannot-open error; preserve
                                      library record

  Permission/source URI failure       Re-import or copy file into
                                      app-private storage

  Reader initialization failure       Retry and provide diagnostic
                                      details

  Locator parse failure               Open at beginning; preserve saved
                                      locator

  Navigation target unavailable       Keep bookmark/highlight and explain
                                      location cannot be found

  Preference unsupported              Keep prior preference and show no
                                      false success

  Plugin platform exception           Log safe diagnostic code; show
                                      recoverable error

  App lifecycle/session failure       Reopen safely using saved locator
  -----------------------------------------------------------------------

Do not show raw stack traces or platform exception dumps to users. Avoid
logging publication contents, selected text, notes, or private file
paths.

## 16. Platform setup requirements

### 16.1 Android

Verify against the pinned plugin installation guide: - `minSdkVersion`
24 or higher. - `compileSdk` 37 or higher. - Kotlin Gradle Plugin 2.3 or
newer. - Core library desugaring enabled with the required desugar
library version. - `MainActivity` extends `FlutterFragmentActivity`. -
Required plugin Gradle configuration is applied. - Do not add audio/TTS
foreground-service permissions unless those features are later included.

Test: - Android 7/API 24 baseline if supported by the release target. -
Recent Android release. - Low-memory device. - Background/resume and
process death. - Rotation and multi-window where supported.

### 16.2 iOS

Verify against the pinned plugin installation guide: - iOS deployment
target 15.0 or higher. - Readium CocoaPods source and dependency
versions match the plugin's podspec. - CocoaPods setup follows the
plugin example. - Xcode and Swift toolchain versions meet plugin
requirements.

Test: - iPhone simulator. - Physical iPhone. - iPad layout. - App
background/resume. - Reader close/reopen and memory behavior. - Document
import and app-private file handling.

## 17. Testing strategy

### 17.1 Fixture library

Maintain a legally distributable local test fixture set: - Small EPUB
2. - Small EPUB 3. - EPUB with nested table of contents. - EPUB with
internal links and footnotes. - EPUB with images. - EPUB with complex
CSS. - Fixed-layout EPUB, if considered in scope. - Small PDF. - PDF
with different page dimensions. - Large PDF. - Corrupt EPUB. - Corrupt
PDF. - EPUB with no reliable progression metadata.

Do not commit copyrighted books to the repository. Use public-domain or
purpose-built test fixtures.

### 17.2 Adapter unit tests

-   Locator envelope serialization/deserialization.
-   Mapping from plugin locator to app position.
-   Mapping from app preferences to plugin preferences.
-   Error mapping.
-   Session generation token behavior.
-   Event stream cancellation and cleanup.

### 17.3 Widget tests

-   Reader loading state.
-   Reader error state.
-   Reader chrome visibility.
-   TOC panel.
-   Search panel.
-   Bookmark list.
-   Highlight list.
-   Settings controls.
-   Missing-file state.

### 17.4 Device integration tests

-   Open EPUB/PDF.
-   Navigate.
-   Save and restore progress.
-   Create and navigate to bookmark.
-   Create and reapply EPUB highlight.
-   Apply preferences.
-   Search within publication.
-   Close and reopen repeatedly.
-   Background and resume.
-   Process termination and recovery.
-   Airplane mode.
-   Large file and memory pressure.
-   Repeat on Android and iOS.

### 17.5 Release compatibility suite

Run the full reader compatibility suite whenever: - `flutter_readium`
version changes. - Flutter SDK changes materially. - Android
Gradle/Kotlin toolchain changes. - Xcode/iOS deployment target
changes. - Native Readium versions change.

Do not merge a reader plugin upgrade solely because the app compiles.

## 18. Technical spike checklist

Before implementing the complete reader, prove each of the following on
Android and iOS:

-   [ ] Open a local EPUB 2.
-   [ ] Open a local EPUB 3.
-   [ ] Open a local PDF.
-   [ ] Mount and dispose `ReadiumReaderWidget`.
-   [ ] Retrieve the publication metadata.
-   [ ] Read the table of contents.
-   [ ] Navigate forward and backward.
-   [ ] Navigate to a TOC entry.
-   [ ] Receive position-change events.
-   [ ] Serialize a locator.
-   [ ] Restore a locator after closing and reopening.
-   [ ] Apply EPUB font size and theme preferences.
-   [ ] Apply PDF layout/fit preferences.
-   [ ] Create and restore a bookmark.
-   [ ] Select text and create an EPUB highlight.
-   [ ] Reapply a highlight after reopening.
-   [ ] Search within a publication.
-   [ ] Close the reader without leaking subscriptions or native views.
-   [ ] Recover from malformed files and reader exceptions.
-   [ ] Verify all critical flows offline.

Record the exact package version, Flutter version, native toolkit
versions, device/OS versions, and any platform-specific limitations in
`READER_ENGINE_SPIKE.md`.

## 19. Implementation sequence

1.  Add and pin `flutter_readium`.
2.  Complete Android and iOS native setup.
3.  Build a minimal screen that opens one local EPUB.
4.  Add PDF opening.
5.  Implement the app-owned reader interface and adapter.
6.  Implement reader state machine and lifecycle coordinator.
7.  Add locator persistence and restoration.
8.  Add TOC and navigation.
9.  Add EPUB/PDF preferences.
10. Add bookmarks.
11. Validate and implement EPUB highlights.
12. Add search if the plugin behavior meets MVP requirements.
13. Complete error mapping and lifecycle tests.
14. Integrate with the library UI.
15. Run the Android/iOS compatibility suite.

## 20. Definition of done

The reader engine integration is complete for the MVP when: - EPUB 2/3
and PDF open from app-private local files on Android and iOS. - Core
reading and navigation work offline. - Reader lifecycle is controlled by
one session coordinator. - The app can persist and restore the
serialized reading locator. - EPUB and PDF preferences behave as
documented and tested. - Bookmarks can be saved and revisited. - EPUB
highlights and notes can be saved and restored, if confirmed by the
spike. - Errors are mapped to understandable app states. - Plugin types
do not leak outside the adapter. - Stream subscriptions and native
reader resources are cleaned up. - The compatibility suite passes on
Android and iOS.

------------------------------------------------------------------------

## 21. References

-   `flutter_readium` package: https://pub.dev/packages/flutter_readium
-   Dart API documentation:
    https://pub.dev/documentation/flutter_readium/latest/
-   Quick start:
    https://github.com/Notalib/flutter_readium/blob/main/docs/getting-started/quick-start.md
-   EPUB reading guide:
    https://github.com/Notalib/flutter_readium/blob/main/docs/guides/epub-reading.md
-   Project repository and example:
    https://github.com/Notalib/flutter_readium
-   Readium Kotlin Toolkit: https://github.com/readium/kotlin-toolkit
-   Readium Swift Toolkit: https://github.com/readium/swift-toolkit

------------------------------------------------------------------------

**Reader architecture decision summary:** Use `flutter_readium` behind
an app-owned `PublicationReaderService` adapter. Flutter owns the reader
shell, session state, progress persistence, bookmarks, highlights, and
preferences. Readium owns publication rendering and format-aware
navigation. Persist complete serialized locators in a versioned app
envelope. Validate all required reader features on Android and iOS
before full implementation.
