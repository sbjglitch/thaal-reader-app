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

/// An error reported while reading. [fatal] errors leave the reader unusable.
final class ReaderErrorEvent extends ReaderEvent {
  const ReaderErrorEvent(this.failure, {required this.fatal});

  final ReaderFailure failure;
  final bool fatal;
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

  /// Releases the publication. Safe to call when nothing is open.
  Future<void> close();
}
