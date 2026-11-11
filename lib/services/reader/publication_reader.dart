import 'package:flutter/widgets.dart';

import '../../domain/entities/enums.dart';
import '../../domain/entities/locator_envelope.dart';
import '../../domain/entities/reader_preferences.dart';

// App-owned reader contract (READER_ENGINE_SPECIFICATION.md §4). Nothing in
// this file refers to the reader plugin, so features depend only on these
// types. The single implementation is `ReadiumPublicationReader`.

/// Why a publication could not be opened or kept open. Mapped to wording in
/// the UI; never carries engine messages or file paths.
enum ReaderFailureKind {
  /// The engine could not parse or decode the file.
  unreadable,

  /// The engine does not support this publication (e.g. DRM-protected).
  unsupported,

  /// Anything else the engine reported.
  engine,
}

final class ReaderFailure implements Exception {
  const ReaderFailure(this.kind, {required this.code});

  final ReaderFailureKind kind;

  /// The engine's error code, safe to log.
  final String code;

  @override
  String toString() => 'ReaderFailure(${kind.name}, $code)';
}

/// The reader's current location, ready to persist.
final class ReaderPosition {
  const ReaderPosition({
    required this.locator,
    this.progression,
    this.pageNumber,
    this.chapterTitle,
  });

  /// The engine locator wrapped in the app envelope; opaque to the app.
  final LocatorEnvelope locator;

  /// Approximate position in the whole publication, 0.0–1.0, if known.
  final double? progression;

  /// One-based page number. Set for PDF only: EPUB "pages" depend on font
  /// size and screen, so they are not stored.
  final int? pageNumber;

  /// Title of the current chapter, when the engine reports one.
  final String? chapterTitle;
}

/// One table-of-contents entry, flattened with its nesting [depth].
final class TocEntry {
  const TocEntry({
    required this.index,
    required this.title,
    required this.depth,
  });

  /// Position in the flattened table of contents of the open publication.
  /// Only meaningful for the session that produced it.
  final int index;
  final String title;
  final int depth;
}

/// What the app learns when a publication opens.
final class OpenedPublication {
  const OpenedPublication({required this.title, required this.toc});

  /// The title declared by the publication, if any.
  final String? title;
  final List<TocEntry> toc;
}

/// Preferences plus the colours the reading theme resolved to. The engine
/// uses the parts that apply to the open format.
final class ReaderAppearance {
  const ReaderAppearance({
    required this.preferences,
    required this.background,
    required this.foreground,
  });

  final ReaderPreferences preferences;

  /// EPUB page and text colours.
  final Color background;
  final Color foreground;

  @override
  bool operator ==(Object other) =>
      other is ReaderAppearance &&
      other.preferences == preferences &&
      other.background == background &&
      other.foreground == foreground;

  @override
  int get hashCode => Object.hash(preferences, background, foreground);
}

sealed class ReaderEvent {
  const ReaderEvent();
}

/// The navigator has rendered and accepts commands.
final class ReaderReady extends ReaderEvent {
  const ReaderReady();
}

final class ReaderPositionChanged extends ReaderEvent {
  const ReaderPositionChanged(this.position);

  final ReaderPosition position;
}

/// The reader reached the end of the publication.
final class ReaderReachedEnd extends ReaderEvent {
  const ReaderReachedEnd();
}

/// Actions the reader offers on selected text where highlights are
/// supported (EPUB only; spec §11).
enum ReaderTextAction { highlight, note }

/// The user chose a [ReaderTextAction] on selected text. [locator] anchors
/// the selection; [selectedText] is user content and must never be logged.
final class ReaderTextActionEvent extends ReaderEvent {
  const ReaderTextActionEvent({
    required this.action,
    required this.locator,
    this.selectedText,
  });

  final ReaderTextAction action;
  final LocatorEnvelope locator;
  final String? selectedText;
}

/// The user tapped a highlight shown with [PublicationReader.showHighlights].
final class ReaderHighlightTapped extends ReaderEvent {
  const ReaderHighlightTapped(this.highlightId);

  final String highlightId;
}

/// A saved highlight to draw over the publication.
final class ReaderHighlight {
  const ReaderHighlight({
    required this.id,
    required this.locator,
    required this.color,
  });

  final String id;
  final LocatorEnvelope locator;
  final HighlightColor color;
}

/// One match of a text search in the open publication. The text fields are
/// publication content and must never be logged.
final class ReaderSearchResult {
  const ReaderSearchResult({
    required this.locator,
    required this.match,
    this.before = '',
    this.after = '',
    this.chapterTitle,
  });

  /// Where the match is; pass it to [PublicationReader.goToLocator].
  final LocatorEnvelope locator;

  /// The matched text and a little of the text around it, with runs of
  /// whitespace collapsed.
  final String before;
  final String match;
  final String after;
  final String? chapterTitle;
}

/// An error reported while reading. [fatal] errors leave the reader unusable.
final class ReaderErrorEvent extends ReaderEvent {
  const ReaderErrorEvent(this.failure, {required this.fatal});

  final ReaderFailure failure;
  final bool fatal;
}

/// The one-based PDF page for a whole-document [progression] of [pages]
/// pages, rounded as the Android PDF navigator rounds it, so a page shown
/// while dragging is the page a jump opens.
int pdfPageForProgression(double progression, int pages) {
  final clamped = progression.isNaN ? 0.0 : progression.clamp(0.0, 1.0);
  return ((clamped * (pages - 1)).round() + 1).clamp(1, pages);
}

/// The whole-document progression of one-based [page] of [pages]; the
/// inverse of [pdfPageForProgression].
double pdfProgressionForPage(int page, int pages) =>
    pages <= 1 ? 0 : ((page - 1) / (pages - 1)).clamp(0.0, 1.0);

/// Reads display details out of stored locators without an open
/// publication, so lists of saved locations can show a chapter or page.
abstract interface class LocatorInterpreter {
  /// Chapter, page and progression stored in [locator].
  ReaderPosition describe(LocatorEnvelope locator);

  /// Whether [a] and [b] point at the same place, tolerating the small
  /// differences the engine reports for one location.
  bool isSameLocation(LocatorEnvelope a, LocatorEnvelope b);
}

/// Opens, renders and navigates one publication at a time
/// (READER_ENGINE_SPECIFICATION.md §5.3).
abstract interface class PublicationReader {
  /// Events of the current session only; events from a closed session are
  /// never delivered.
  Stream<ReaderEvent> get events;

  /// Whether a publication is open. Import inspection must not run then,
  /// because the engine holds a single global publication.
  bool get isOpen;

  /// Opens the local file at [filePath]. Closes any previous session first.
  /// Throws [ReaderFailure] when the file cannot be opened.
  Future<OpenedPublication> open({
    required String filePath,
    required PublicationFormat format,
    required ReaderAppearance appearance,
  });

  /// Applies [appearance] to the open publication. Returns false when the
  /// engine rejected it; the previous appearance then stays in effect.
  Future<bool> applyAppearance(ReaderAppearance appearance);

  /// The engine view for the open publication, starting at [initialLocator]
  /// when given. [controlsVisible] is toggled by a tap in the middle of the
  /// page.
  Widget buildView({
    LocatorEnvelope? initialLocator,
    required ValueNotifier<bool> controlsVisible,
    required Widget loading,
  });

  Future<void> goForward();

  Future<void> goBackward();

  /// Returns false when the entry cannot be resolved to a location.
  Future<bool> goToTocEntry(TocEntry entry);

  /// Returns false when the location cannot be found.
  Future<bool> goToLocator(LocatorEnvelope locator);

  /// Whether [goToProgression] can jump anywhere in the open publication.
  /// False when nothing is open or the engine cannot place a whole-book
  /// position; callers hide the scrubber then.
  bool get supportsProgressionJump;

  /// Number of pages of the open PDF; null for EPUB or when unknown.
  int? get pageCount;

  /// Moves to [progression] (0.0–1.0) of the whole publication: a page for
  /// PDF, a chapter and a point within it for EPUB. Returns false when it
  /// cannot be resolved.
  Future<bool> goToProgression(double progression);

  /// Whether the open publication supports text highlights. False for PDF
  /// and when nothing is open; callers hide highlight controls then.
  bool get supportsHighlights;

  /// Whether the "whole page" PDF fit is applied. Callers hide the page
  /// fit choice when it is not.
  bool get supportsPdfPageFit;

  /// Whether text search works for the open publication. False for PDF,
  /// which the Android engine cannot search, and when nothing is open;
  /// callers hide search then.
  bool get supportsSearch;

  /// Every match of [query] in the open publication, in reading order.
  /// Throws [ReaderFailure] when the engine search fails. The engine cannot
  /// cancel a search, so a caller that no longer wants the results ignores
  /// them.
  Future<List<ReaderSearchResult>> search(String query);

  /// Marks the search match at [locator] over the text, replacing any
  /// earlier mark; null removes it. Returns false when it could not be
  /// drawn.
  Future<bool> showSearchMatch(LocatorEnvelope? locator);

  /// Replaces every highlight drawn over the open publication. Highlights
  /// whose locator the engine cannot read are skipped, not deleted.
  /// Returns false when they could not be applied.
  Future<bool> showHighlights(List<ReaderHighlight> highlights);

  /// Releases the publication. Safe to call when nothing is open.
  Future<void> close();
}
