# UI/UX Specification

**Project:** Offline-first EPUB and PDF reader  
**Platforms:** Android first, iOS second  
**Framework:** Flutter  
**Visual direction:** Clean, minimal, modern  
**Themes:** Light and dark  
**Status:** MVP design specification  
**Design principle:** Build a usable, restrained first version that is easy to redesign without changing business logic.

---

## 1. Design vision

Create a calm reading application that puts the user's books and reading content first.

The interface should feel:

- **Minimal:** Show only the information and controls needed for the current task.
- **Modern:** Use clear typography, consistent spacing, subtle surfaces, and restrained iconography.
- **Quiet:** Avoid unnecessary decoration, gradients, excessive borders, and persistent visual noise.
- **Readable:** Prioritise comfortable reading, strong hierarchy, and accessible contrast.
- **Adaptable:** Use reusable components and semantic design tokens so the visual system can be changed later without rewriting feature logic.

The app should feel like a personal reading space rather than a content marketplace or social platform.

## 2. Design principles

### 2.1 Content first

- Book covers and titles should be the primary elements in the library.
- Reading content should occupy most of the reader screen.
- Keep controls hidden or compact when they are not needed.
- Avoid unnecessary cards around every item.

### 2.2 Progressive disclosure

- Show essential actions first.
- Put secondary actions in overflow menus, bottom sheets, or contextual toolbars.
- Avoid presenting every reader setting at once.
- Use clear labels for important actions; do not rely on unfamiliar icons alone.

### 2.3 Consistency over decoration

- Use a small set of spacing, typography, radius, and colour tokens.
- Reuse common buttons, list rows, dialogs, and empty states.
- Avoid one-off styling values in individual screens.
- Keep interaction patterns consistent across light and dark themes.

### 2.4 Redesign-friendly implementation

The first UI is a foundation, not a permanent visual identity.

- Keep design tokens separate from feature logic.
- Keep reusable UI components separate from screens.
- Keep domain models and repository code independent of widgets.
- Avoid hardcoding colours, dimensions, and text styles throughout the app.
- Prefer simple layouts that can be rearranged without changing data flows.
- Do not build a large custom design system before the product needs one.

## 3. Visual direction

<text color="secondary" size="sm">Reference direction: editorial, understated, spacious, and functional. Avoid highly decorative dashboard patterns.</text>

### 3.1 Light theme

<box border radius="lg" padding={3} gap={3} theme="light">
  <row align="center" justify="between">
    **Light theme direction**
    <badge color="secondary">Light</badge>
  </row>
  <box background="#FFFFFF" border={{size:1,color:"#E5E7EB"}} radius="md" padding={3} gap={2}>
    <row align="center" justify="between">
      <text color="#111827" weight="semibold">Library</text>
      <row gap={2}>
        <icon name="search" color="#4B5563"/>
        <icon name="plus" color="#4B5563"/>
      </row>
    </row>
    <text color="#6B7280" size="xs">Continue reading</text>
    <row gap={3}>
      <box background="#E8E3D8" radius="sm" width="48px" height="68px" align="center" justify="center">
        <icon name="book-open" color="#514B42" size="lg"/>
      </box>
      <box flex="1" gap={1} justify="center">
        <text color="#111827" weight="semibold">The Design of Everyday Things</text>
        <text color="#6B7280" size="xs">Don Norman</text>
        <box background="#E5E7EB" height="4px" radius="full">
          <box background="#30343B" width="42%" height="4px" radius="full"/>
        </box>
        <text color="#6B7280" size="xs">42% read</text>
      </box>
    </row>
    <divider color="#E5E7EB"/>
    <text color="#6B7280" size="xs">YOUR LIBRARY</text>
    <row gap={3}>
      <box background="#DCE6E2" radius="sm" width="48px" height="68px" align="center" justify="center">
        <icon name="book-open" color="#405B50"/>
      </box>
      <box flex="1" gap={1} justify="center">
        <text color="#111827" weight="medium">A Sample Publication</text>
        <text color="#6B7280" size="xs">EPUB · Author name</text>
      </box>
      <icon name="more-horizontal" color="#6B7280"/>
    </row>
  </box>
  <caption color="secondary">White canvas, near-black text, soft neutral dividers, and muted secondary text.</caption>
</box>

### 3.2 Dark theme

<box border radius="lg" padding={3} gap={3} theme="dark">
  <row align="center" justify="between">
    **Dark theme direction**
    <badge color="secondary">Dark</badge>
  </row>
  <box background="#17191C" border={{size:1,color:"#30343A"}} radius="md" padding={3} gap={2}>
    <row align="center" justify="between">
      <text color="#F4F4F5" weight="semibold">Library</text>
      <row gap={2}>
        <icon name="search" color="#A1A1AA"/>
        <icon name="plus" color="#A1A1AA"/>
      </row>
    </row>
    <text color="#A1A1AA" size="xs">Continue reading</text>
    <row gap={3}>
      <box background="#514B42" radius="sm" width="48px" height="68px" align="center" justify="center">
        <icon name="book-open" color="#F1EDE5" size="lg"/>
      </box>
      <box flex="1" gap={1} justify="center">
        <text color="#F4F4F5" weight="semibold">The Design of Everyday Things</text>
        <text color="#A1A1AA" size="xs">Don Norman</text>
        <box background="#3B3F45" height="4px" radius="full">
          <box background="#D4D4D8" width="42%" height="4px" radius="full"/>
        </box>
        <text color="#A1A1AA" size="xs">42% read</text>
      </box>
    </row>
    <divider color="#30343A"/>
    <text color="#A1A1AA" size="xs">YOUR LIBRARY</text>
    <row gap={3}>
      <box background="#405B50" radius="sm" width="48px" height="68px" align="center" justify="center">
        <icon name="book-open" color="#E4EEE8"/>
      </box>
      <box flex="1" gap={1} justify="center">
        <text color="#F4F4F5" weight="medium">A Sample Publication</text>
        <text color="#A1A1AA" size="xs">EPUB · Author name</text>
      </box>
      <icon name="more-horizontal" color="#A1A1AA"/>
    </row>
  </box>
  <caption color="secondary">Deep charcoal surfaces rather than pure black, soft white text, and subtle separators.</caption>
</box>

### 3.3 Colour tokens

Use semantic tokens rather than assigning raw colours directly inside feature widgets. The values below are starting points and should be checked for contrast in the implemented UI.

| Token | Light theme | Dark theme | Usage |
|---|---|---|---|
| `background` | `#FFFFFF` | `#121416` | Main app background |
| `surface` | `#F7F7F5` | `#1B1E21` | Secondary surfaces |
| `surfaceElevated` | `#FFFFFF` | `#24282C` | Sheets, menus, dialogs |
| `textPrimary` | `#17191C` | `#F3F4F4` | Main text |
| `textSecondary` | `#666C72` | `#A4A9AE` | Metadata and supporting text |
| `textTertiary` | `#858B91` | `#7F878E` | Hints and low-emphasis labels |
| `border` | `#E7E9EB` | `#30353A` | Dividers and outlines |
| `accent` | `#303943` | `#D9E0E5` | Primary action and selected states |
| `onAccent` | `#FFFFFF` | `#17191C` | Text/icons on accent |
| `success` | `#287A52` | `#75C69A` | Successful operations |
| `warning` | `#98651A` | `#E8B967` | Warnings |
| `danger` | `#B33B3B` | `#F08B8B` | Destructive/error states |

The accent is intentionally neutral. A stronger brand colour can be introduced later by changing the token values, not individual components.

### 3.4 Reader page colours

The reader content surface may use a separate reading theme from the application theme.

Initial reader themes:

- **Light:** warm or neutral paper background with dark text.
- **Dark:** dark charcoal background with soft light text.
- **System:** follows the application/system theme where supported.
- **Sepia:** warm paper background (`#F4ECD8`) with brown text (`#5B4636`).
- **Twilight:** dim blue-grey background (`#2A2D36`) with warm grey text (`#CFCAC0`), softer than dark for low light.

Light and dark use the app's `background` and `textPrimary` tokens; sepia and twilight have fixed colours that do not change with the app theme. Every reading theme keeps text contrast of at least 7:1. Reading themes apply to EPUB only; the PDF engine draws pages as they are.

In reader settings, themes are shown as chips with a small swatch of the page and text colours, and a text label so colour is never the only cue.

Do not assume the app's dark theme must force every publication into dark reading mode. Provide a reader-specific theme preference if supported by the engine.

## 4. Typography

Use a restrained type scale with clear hierarchy.

Recommended starting point:

| Style | Size | Weight | Usage |
|---|---:|---|---|
| Display | 28 | Semibold | Rare large screen title |
| Heading 1 | 24 | Semibold | Screen title |
| Heading 2 | 20 | Semibold | Section title |
| Heading 3 | 16 | Semibold | Book title / dialog title |
| Body | 14–16 | Regular | Main UI content |
| Body small | 13 | Regular | Metadata and descriptions |
| Label | 12 | Medium | Small section labels |
| Caption | 11–12 | Regular | Supporting information |

Guidelines:

- Prefer the platform's familiar system font initially.
- Avoid adding custom fonts until there is a clear product reason.
- Use a dedicated typography token file.
- Support system text scaling in app UI.
- Keep metadata visibly secondary without making it too faint.
- Reader typography controls should be independent of application UI typography.

## 5. Spacing, shape, and elevation

### Spacing scale

Use a 4-point base spacing system.

| Token | Value |
|---|---:|
| `space2` | 2 |
| `space4` | 4 |
| `space8` | 8 |
| `space12` | 12 |
| `space16` | 16 |
| `space20` | 20 |
| `space24` | 24 |
| `space32` | 32 |
| `space40` | 40 |
| `space48` | 48 |

Use 16–24 px as the usual screen-edge spacing, adjusted for platform safe areas and device width.

### Radius scale

| Token | Value | Usage |
|---|---:|---|
| `radiusSmall` | 6 | Compact controls |
| `radiusMedium` | 10 | Inputs and buttons |
| `radiusLarge` | 14 | Sheets and larger surfaces |
| `radiusFull` | 999 | Pills and circular controls |

Keep shadows minimal. Prefer surface contrast and subtle borders over floating cards and heavy elevation.

## 6. Layout and navigation

### 6.1 Primary navigation

Use a simple bottom navigation structure for the MVP:

1. **Library** — all imported publications and reading activity.
2. **Collections** — user-created groups of books.
3. **Bookmarks** — saved reading locations.
4. **Settings** — theme, reader defaults, backup, and app information.

The reader is opened from a book and is not a permanent bottom-navigation destination.

If early usability testing shows that four destinations feel excessive, simplify the navigation rather than preserving it for symmetry. Backup can live under Settings.

### 6.2 Navigation behaviour

- Preserve the user's library context when opening and closing a book.
- Use standard platform back behaviour.
- Keep destructive actions behind confirmation.
- Use bottom sheets for contextual actions that do not need a full screen.
- Use dialogs only for short decisions or confirmations.
- Avoid deeply nested navigation for simple tasks.

### 6.3 Responsive behaviour

- Support compact phones first.
- Use flexible layouts and safe-area insets.
- Avoid fixed widths for text-heavy regions.
- Keep primary actions reachable on larger phones.
- On tablets, allow more library columns and wider content margins without introducing a separate tablet design system for the MVP.

## 7. Core screens

The screen definitions below describe required content and behaviour, not pixel-perfect layouts. Keep the first implementation simple and use the design tokens and reusable components.

### 7.1 Library screen

**Purpose:** Let users find, resume, and manage imported publications.

**Primary content:**

- Screen title: Library.
- Search action/input.
- Import action.
- Continue reading section, shown only when there is a relevant in-progress book.
- Library list or grid.
- Sort and filter controls.
- Empty state when no books have been imported.

**Book item content:**

- Cover thumbnail, with a neutral fallback when unavailable.
- Title.
- Author, when available.
- Format label: EPUB or PDF.
- Reading status or progress, when available.
- Overflow action.

**Interactions:**

- Tap a book to open it.
- Tap Import to invoke the system document picker.
- Search by title and author.
- Sort by supported fields.
- Filter by reading status.
- Overflow menu: edit metadata if supported, add to collection, remove from library.

**Keep minimal:**

- Do not show every metadata field in the library.
- Avoid a dashboard full of statistics.
- Do not show progress bars for books that have no meaningful progress value.

### 7.2 Import flow

**Purpose:** Add a publication to the local library.

**Flow:**

1. User taps Import.
2. System document picker opens.
3. User selects an EPUB or PDF.
4. App validates the file and copies it to app-private storage.
5. App extracts available metadata and cover.
6. App creates the library record.
7. Library updates and the new book becomes available.

**States:**

- Selecting.
- Importing.
- Processing metadata.
- Completed.
- Unsupported format.
- Invalid or corrupt file.
- Insufficient storage.
- Cancelled.
- Failed, with retry where appropriate.

**UX requirements:**

- Show progress for operations that take noticeable time.
- Prevent duplicate taps from starting overlapping imports of the same file.
- Do not block the whole app unnecessarily.
- Explain failures in plain language.
- Never delete or modify the original source file.

### 7.3 Reader screen — EPUB

**Purpose:** Provide a distraction-free reading experience.

**Default layout:**

- Publication content occupies the majority of the screen.
- A compact top bar appears when controls are visible.
- A compact bottom control area contains progress/navigation access.
- Controls can be shown or hidden with a tap, according to the reader engine's interaction model.

**Top controls:**

- Back.
- Book title, truncated when necessary.
- Table of contents.
- More/options menu.

**Bottom controls:**

- Current location or progress, where meaningful.
- Progress navigation control if supported: a slider across the whole
  publication that shows where it will open while dragging ("Page N of
  M" for PDF, a percentage for EPUB) and jumps once on release. It is
  hidden when the publication cannot be mapped.
- Access to bookmarks and reader settings.
- Search within the publication, where supported (EPUB): a sheet with a
  search field. The search runs on submit and lists the matches with
  the surrounding text (the match in bold) and the chapter, a match
  count, and "No matches" or a retryable error. Opening a match
  underlines it on the page.

**Secondary actions:**

- Add/remove bookmark.
- Search within publication.
- Reader appearance settings.
- Navigate to chapter.
- View publication details where needed.

**Text selection:**

- Use the reader engine's native selection behaviour.
- Offer highlight and note actions only when supported.
- Keep selection actions contextual rather than permanently visible.

**Reader controls should not:**

- Permanently occupy large portions of the reading area.
- Add decorative cards around publication content.
- Recreate text rendering outside the reader engine.
- Assume every EPUB has identical layout or pagination.

### 7.4 Reader screen — PDF

Use the same overall reader shell as EPUB where possible, but adapt controls to PDF behaviour.

**Controls may include:**

- Back.
- Document title.
- Page position.
- Page navigation.
- Search, if supported.
- Zoom or fit controls, if supported.
- Bookmark.
- More/options menu.

Do not show EPUB-only controls such as chapter typography settings on PDF unless the engine supports an equivalent behaviour.

### 7.5 Table of contents

**Purpose:** Navigate within a publication.

- Present a clear hierarchical list where the publication provides nested sections.
- Highlight the current section when the engine provides reliable location data.
- Tapping a section navigates to that location and closes the TOC surface.
- Handle publications with no usable TOC with a clear empty state.

Use a bottom sheet or side panel depending on platform space and reader-engine integration. Do not build a complex custom navigation tree for the MVP.

### 7.6 Reader settings

**Purpose:** Adjust the reading experience without cluttering the reader.

For EPUB, show only options supported by the engine, such as:

- Reader theme.
- Font size.
- Font family, if supported.
- Line spacing.
- Margins.
- Text alignment, if supported.

For both formats, where the platform allows it (Android; iOS deferred):

- Brightness: a slider for the screen brightness while reading and a
  "Match system brightness" switch, on by default. The slider changes
  the screen as it is dragged and turns the switch off. The level
  applies only while a book is open; elsewhere the system decides. It
  is remembered on this device and not backed up.

For PDF, show only supported viewing options, such as:

- Page fit mode.
- Zoom controls.
- Page layout options, if supported.

**UX requirements:**

- Group related settings.
- Use sliders for continuous values and clear selectable rows for discrete options.
- Apply changes promptly where supported.
- Persist settings according to the product rule: global defaults and per-book preferences must have an explicit source of truth.
- Include a reset-to-default action.

### 7.7 Bookmarks screen

**Purpose:** Find and revisit saved locations.

Each bookmark row should show:

- Book title.
- Chapter/title or page information where available.
- Optional user label or short excerpt, if supported and privacy-appropriate.
- Date created, only if useful.

Interactions:

- Tap to open the book at the saved location.
- Delete through an overflow action or swipe action with undo where feasible.
- Group by book or sort by recently added.

Empty state should explain how to create a bookmark while reading.

### 7.8 Collections screen

**Purpose:** Organise publications into user-created groups.

- Show collection name and book count.
- Provide a clear create action.
- Allow rename and delete.
- Allow adding/removing books.
- Deleting a collection must not delete its books.
- An empty collection should have a simple empty state.

Do not introduce complex nested folders or tags in the MVP.

### 7.9 Annotations screen

**Purpose:** Review highlights and notes created in EPUB publications.

Each annotation item may show:

- Book title.
- Selected text or short excerpt, if available.
- Note preview, if one exists.
- Highlight colour/style indicator.
- Location/chapter information where available.

Interactions:

- Tap to navigate to the annotation.
- Edit or delete a note where supported.
- Filter by book if useful.

Do not imply that annotations are supported for PDF unless the implemented reader engine explicitly supports the required behaviour.

### 7.10 Settings screen

Keep the settings screen short and grouped.

Suggested sections:

**Appearance**
- Theme: System / Light / Dark.

**Reading**
- Default reader theme.
- Default reading preferences.
- Progress or reading behaviour options, if exposed.

**Library**
- Default sort order.
- Default library layout, if the app offers more than one.

**Data**
- Create full backup.
- Create library-only backup.
- Restore backup.
- Storage usage, if reliable.

**About**
- App version.
- Open-source licences or acknowledgements where applicable.

Do not add account, cloud sync, subscription, or notification settings to the MVP.

### 7.11 Backup and restore screens

**Purpose:** Let users protect and recover local library data.

**Backup flow:**

1. Choose Full backup or Library-only backup.
2. Explain what each option includes.
3. Create the archive.
4. Let the user save/share it through the system destination picker.
5. Confirm completion and show the archive location/name when available.

**Restore flow:**

1. Select a `.readerbackup` file.
2. Validate the archive.
3. Show a concise summary of what will be restored.
4. Explain conflicts or replacement behaviour before proceeding.
5. Ask for confirmation before destructive replacement.
6. Restore with progress feedback.
7. Show completed, partial, or failed status with recovery guidance.

Never imply that a library-only backup contains the publication files.

## 8. Reusable UI components

Build only the reusable components needed by the first screens. Keep them generic and style them through tokens.

Suggested initial components:

| Component | Responsibility |
|---|---|
| `AppScaffold` | Shared safe-area and page layout |
| `AppTopBar` | Consistent screen title and actions |
| `PrimaryButton` | Main action |
| `IconButton` | Standard icon action with accessible label |
| `SearchField` | Library and in-publication search entry |
| `BookListItem` | Compact book row |
| `BookCover` | Cover image with fallback |
| `SectionHeader` | Section title and optional action |
| `EmptyState` | Empty library/collection/bookmark states |
| `ErrorState` | Recoverable error presentation |
| `LoadingIndicator` | Consistent loading feedback |
| `AppBottomSheet` | Standard contextual sheet |
| `AppDialog` | Short confirmation and decision dialogs |
| `ProgressIndicator` | Reading/import/backup progress where relevant |

Avoid building a generic component for every small layout. Extract components when they are reused or have a meaningful interaction contract.

## 9. Design system implementation in Flutter

Keep design values centralised and semantic.

Suggested structure:

```text
lib/
├── app/
│   └── theme/
│       ├── app_theme.dart
│       ├── app_color_tokens.dart
│       ├── app_text_tokens.dart
│       ├── app_spacing_tokens.dart
│       ├── app_radius_tokens.dart
│       └── app_component_themes.dart
│
└── core/
    └── widgets/
        ├── app_scaffold.dart
        ├── app_top_bar.dart
        ├── app_button.dart
        ├── app_icon_button.dart
        ├── app_empty_state.dart
        └── app_error_state.dart
```

Implementation rules:

- Use Flutter `ThemeData` and `ColorScheme` for app-wide theming.
- Define semantic colour names such as `background`, `surface`, `textPrimary`, and `border`.
- Use theme-aware text styles rather than hardcoded colours.
- Use spacing and radius constants for repeated values.
- Prefer theme extensions only where Flutter's standard theme properties are insufficient.
- Avoid a separate styling framework unless a real need emerges.
- Ensure all shared components render correctly in both themes.
- Keep publication rendering/theme configuration separate from app chrome styling.

A future redesign should mostly require changes to tokens, component themes, and presentation widgets—not repositories, domain entities, or database code.

## 10. Interaction and feedback

### General interaction

- Use standard tap targets and platform gestures.
- Provide visible feedback after important actions.
- Use undo for reversible destructive list actions where practical.
- Use confirmation for irreversible deletion or restore replacement.
- Preserve scroll position when navigating back to the library.
- Avoid unnecessary animations.

### Motion

Keep motion subtle and functional:

- Short fades for lightweight state transitions.
- Standard platform navigation transitions.
- Small progress transitions where they improve comprehension.
- No decorative animated backgrounds or elaborate page transitions in the MVP.
- Respect system reduced-motion preferences where applicable.

### Haptics

Use haptic feedback sparingly for meaningful actions only. Do not make haptics required for understanding an interaction.

## 11. UI states and error handling

Every data-driven screen should account for relevant states:

| State | Expected behaviour |
|---|---|
| Loading | Show a restrained progress indicator or skeleton only when useful |
| Empty | Explain what is missing and provide one clear next action |
| Success | Show the content and a subtle confirmation for completed actions |
| Error | Explain what failed and offer a recovery action where possible |
| Unavailable file | Identify the missing publication and offer remove/relink if supported |
| Offline | Core local functionality remains available; avoid irrelevant network error messaging |
| Processing | Show progress and prevent unsafe duplicate actions |
| Cancelled | Return to a stable state without leaving partial data |

Error messages should be specific and actionable. Avoid displaying raw exceptions, stack traces, or plugin error text to users.

## 12. Accessibility

- Support TalkBack and VoiceOver for core navigation and actions.
- Give icon-only buttons meaningful semantic labels.
- Maintain logical focus order.
- Support system text scaling.
- Maintain sufficient contrast in both themes.
- Do not use colour alone to communicate reading status or errors.
- Ensure controls have comfortable touch targets.
- Announce import, backup, and restore progress/status changes accessibly.
- Test reader controls with assistive technology in addition to app chrome.

## 13. Platform behaviour

Use shared UI where possible, but respect native platform behaviour.

- Use the system document picker for importing and selecting backup files.
- Respect Android and iOS safe areas, status bars, and system navigation.
- Use platform-appropriate back behaviour.
- Validate bottom-sheet, dialog, and keyboard behaviour on both platforms.
- Do not assume Android document URI behaviour matches iOS file-provider behaviour.
- Avoid platform-specific visual divergence unless it improves usability or is required by the native reader engine.

## 14. MVP design priorities

Implement in this order:

| Priority | Screen/area | Why |
|---|---|---|
| P0 | Library | Main entry point and book discovery |
| P0 | Import flow | Required to populate the app |
| P0 | EPUB reader shell | Core product experience |
| P0 | PDF reader shell | Core supported format |
| P0 | Reader controls and progress | Reading continuity |
| P1 | Reader settings | Reading comfort |
| P1 | Bookmarks | Core reading utility |
| P1 | Collections | Library organisation |
| P1 | Backup/restore | Data protection |
| P2 | Annotations list | Easier review of highlights and notes |
| P2 | Additional library layouts | Only if user testing demonstrates value |

The reader-engine technical spike must precede full reader UI implementation. This specification does not override native engine limitations.

## 15. What not to design yet

To keep the UI easy to redo, avoid premature design commitments:

- No elaborate branding system.
- No custom illustration system.
- No complex animation language.
- No highly customised navigation patterns.
- No extensive component library before reuse is proven.
- No advanced dashboard or reading analytics.
- No decorative cards around every section.
- No fixed visual dependence on a single accent colour.
- No custom EPUB/PDF rendering UI that duplicates engine responsibilities.

Use neutral defaults and refine the visual identity after the core reading experience is validated.

## 16. Usability validation

Before polishing, test the basic information architecture and flows with a small set of representative users.

Ask users to complete these tasks without guidance:

1. Import an EPUB.
2. Find a book in the library.
3. Open it and hide/show reader controls.
4. Find a chapter using the table of contents.
5. Change the reading theme or text size.
6. Add a bookmark and return to it.
7. Import and open a PDF.
8. Create a backup and identify what it contains.
9. Find the restore action in Settings.

Observe task completion, hesitation, errors, and whether labels match user expectations. Prioritise issues that block reading or data protection over cosmetic preferences.

## 17. Definition of done

A screen or interaction is ready when:

- It fulfils the relevant product requirement.
- It uses shared semantic design tokens.
- It works in light and dark themes.
- Loading, empty, error, and success states are handled where relevant.
- Important actions have accessible labels and feedback.
- It behaves correctly on Android.
- iOS behaviour is validated or tracked as remaining work.
- It does not introduce business logic into presentation widgets.
- It can be visually revised without changing domain or data-layer code.
- Widget or integration tests cover important behaviour.

---

## Appendix A — Initial visual checklist

Use this as a lightweight review checklist during implementation:

- [ ] White theme uses a clean white/near-white canvas.
- [ ] Dark theme uses deep charcoal rather than harsh pure black everywhere.
- [ ] Text hierarchy is clear and restrained.
- [ ] Primary actions are visually obvious without being oversized.
- [ ] Secondary actions are quiet and discoverable.
- [ ] Book covers are consistent in size and have fallbacks.
- [ ] Library is easy to scan.
- [ ] Reader content receives the majority of screen space.
- [ ] Borders and shadows are subtle.
- [ ] No unnecessary gradients or decorative cards.
- [ ] Both themes maintain readable contrast.
- [ ] UI values are tokenised and not scattered through feature code.

## Appendix B — Design direction in one sentence

**A quiet, modern reading space with a simple library, an unobtrusive reader, neutral light and dark themes, and a presentation layer that can be redesigned without disturbing the app's underlying architecture.**
