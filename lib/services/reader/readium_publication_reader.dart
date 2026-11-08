import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_readium/flutter_readium.dart' hide PublicationFormat;

import '../../app/theme/highlight_colors.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/locator_envelope.dart';
import '../../domain/entities/reader_preferences.dart';
import 'publication_reader.dart';

/// [PublicationReader] backed by `flutter_readium` 0.9.0. The only place,
/// with `ReadiumPublicationInspector`, that touches plugin types.
///
/// `FlutterReadium` is a singleton with one global publication, so this
/// class enforces a single session and tags every subscription with a
/// generation number: events that arrive after [close] or after a newer
/// [open] are dropped.
class ReadiumPublicationReader implements PublicationReader {
  ReadiumPublicationReader(this._readium);

  final FlutterReadium _readium;
  final _events = StreamController<ReaderEvent>.broadcast();
  final List<StreamSubscription<Object?>> _subscriptions = [];

  int _generation = 0;

  /// Serialises open/close so a close from a disposed screen can never run
  /// in the middle of the next open.
  Future<void> _lastOperation = Future.value();
  Publication? _publication;
  PublicationFormat? _format;
  List<Link> _toc = const [];

  @override
  Stream<ReaderEvent> get events => _events.stream;

  @override
  bool get isOpen => _publication != null;

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _lastOperation.then((_) => operation());
    _lastOperation = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<OpenedPublication> open({
    required String filePath,
    required PublicationFormat format,
    required ReaderAppearance appearance,
  }) => _serial(() => _open(filePath, format, appearance));

  Future<OpenedPublication> _open(
    String filePath,
    PublicationFormat format,
    ReaderAppearance appearance,
  ) async {
    await _close();
    final generation = ++_generation;
    // Defaults are what the navigator starts with, so the first page renders
    // with the user's preferences instead of reflowing after load.
    switch (format) {
      case PublicationFormat.epub:
        _readium.setDefaultPreferences(epubPreferencesFrom(appearance));
      case PublicationFormat.pdf:
        _readium.setDefaultPDFPreferences(pdfPreferencesFrom(appearance));
    }

    final Publication publication;
    try {
      publication = await _readium.openPublication(
        Uri.file(filePath).toString(),
      );
    } on ReadiumException catch (error) {
      throw mapReadiumError(error.error);
    } on Exception {
      throw const ReaderFailure(ReaderFailureKind.engine, code: 'open_failed');
    }
    if (generation != _generation) {
      // close() ran while opening; do not leave the publication open.
      await _closeQuietly();
      throw const ReaderFailure(ReaderFailureKind.engine, code: 'cancelled');
    }

    _publication = publication;
    _format = format;
    _toc = publication.tocFlattened;
    _listen(generation);
    return OpenedPublication(
      title: publication.metadata.title,
      toc: tocEntriesFrom(publication.tableOfContents),
    );
  }

  /// Flattens [links] in the same order as `Publication.tocFlattened`
  /// (depth-first, parent before children) so [TocEntry.index] matches.
  /// Visible for tests.
  static List<TocEntry> tocEntriesFrom(List<Link> links) {
    final entries = <TocEntry>[];
    void visit(List<Link> level, int depth) {
      for (final link in level) {
        final title = link.title?.trim();
        entries.add(
          TocEntry(
            index: entries.length,
            title: title == null || title.isEmpty ? 'Untitled section' : title,
            depth: depth,
          ),
        );
        visit(link.children, depth + 1);
      }
    }

    visit(links, 0);
    return entries;
  }

  void _listen(int generation) {
    bool current() => generation == _generation;

    _subscriptions
      ..add(
        _readium.onReaderStatusChanged.listen((status) {
          if (!current()) return;
          switch (status) {
            case ReadiumReaderStatus.ready:
              _events.add(const ReaderReady());
            case ReadiumReaderStatus.reachedEndOfPublication:
              _events.add(const ReaderReachedEnd());
            case ReadiumReaderStatus.loading:
            case ReadiumReaderStatus.closed:
            case ReadiumReaderStatus.error:
              break;
          }
        }),
      )
      ..add(
        _readium.onTextLocatorChanged.listen((locator) {
          final format = _format;
          if (!current() || format == null) return;
          _events.add(ReaderPositionChanged(positionFrom(locator, format)));
        }),
      )
      ..add(
        _readium.onErrorEvent.listen((error) {
          if (!current()) return;
          _events.add(
            ReaderErrorEvent(mapReadiumError(error), fatal: error.isFatal),
          );
        }),
      );
  }

  @override
  Widget buildView({
    LocatorEnvelope? initialLocator,
    required ValueNotifier<bool> controlsVisible,
    required Widget loading,
  }) {
    final publication = _publication;
    if (publication == null) {
      throw StateError('buildView called without an open publication');
    }
    final generation = _generation;
    bool current() => generation == _generation;
    final highlights = supportsHighlights;
    return ReadiumReaderWidget(
      publication: publication,
      selectionActions: highlights ? _textActions : const [],
      onSelectionAction: highlights
          ? (event) {
              final action = textActionFor(event.actionId);
              if (!current() || action == null) return;
              _events.add(
                ReaderTextActionEvent(
                  action: action,
                  locator: LocatorEnvelope(
                    format: PublicationFormat.epub,
                    locator: event.locator.toJson(),
                  ),
                  selectedText:
                      event.selectedText ?? event.locator.text?.highlight,
                ),
              );
            }
          : null,
      onDecorationInteraction: highlights
          ? (event) {
              if (!current() || event.group != _highlightGroup) return;
              if (event.type != DecorationInteractionType.tap) return;
              _events.add(ReaderHighlightTapped(event.decorationId));
            }
          : null,
      initialLocator: initialLocator == null
          ? null
          : Locator.fromJson(initialLocator.locator),
      shouldShowControls: controlsVisible,
      loadingWidget: loading,
      goBackwardSemanticLabel: 'Previous page',
      goForwardSemanticLabel: 'Next page',
      toggleShowControlsSemanticLabel: 'Show or hide reader controls',
      // Offline app: external links are not followed (spec §7.5). A
      // confirm-and-open policy can be added later.
      onExternalLinkActivated: (_) {},
    );
  }

  @override
  Future<void> goForward() => _ifOpen(_readium.goForward);

  @override
  Future<void> goBackward() => _ifOpen(_readium.goBackward);

  @override
  Future<bool> goToTocEntry(TocEntry entry) async {
    final publication = _publication;
    if (publication == null || entry.index >= _toc.length) return false;
    try {
      return await _readium.goByLink(_toc[entry.index], publication);
    } on ReadiumException {
      return false;
    }
  }

  @override
  Future<bool> applyAppearance(ReaderAppearance appearance) async {
    final format = _format;
    if (format == null) return false;
    try {
      switch (format) {
        case PublicationFormat.epub:
          final preferences = epubPreferencesFrom(appearance);
          await _readium.setEPUBPreferences(preferences);
          // Also the default, so a reload keeps it.
          _readium.setDefaultPreferences(preferences);
        case PublicationFormat.pdf:
          // setPDFPreferences replaces the whole set (spike finding 4); the
          // mapping always sends every field.
          final preferences = pdfPreferencesFrom(appearance);
          await _readium.setPDFPreferences(preferences);
          _readium.setDefaultPDFPreferences(preferences);
      }
      return true;
    } on ReadiumException {
      return false;
    }
  }

  @override
  Future<bool> goToLocator(LocatorEnvelope locator) async {
    final target = Locator.fromJson(locator.locator);
    if (_publication == null || target == null) return false;
    try {
      return await _readium.goToLocator(target);
    } on ReadiumException {
      return false;
    }
  }

  static const _highlightGroup = 'thaal_highlights';
  static const _textActions = [
    SelectionAction(id: 'thaal_highlight', title: 'Highlight'),
    SelectionAction(id: 'thaal_note', title: 'Note'),
  ];

  /// Visible for tests.
  static ReaderTextAction? textActionFor(String actionId) => switch (actionId) {
    'thaal_highlight' => ReaderTextAction.highlight,
    'thaal_note' => ReaderTextAction.note,
    _ => null,
  };

  @override
  bool get supportsHighlights =>
      _publication != null && _format == PublicationFormat.epub;

  @override
  Future<bool> showHighlights(List<ReaderHighlight> highlights) async {
    if (!supportsHighlights) return false;
    try {
      await _readium.applyDecorations(
        _highlightGroup,
        decorationsFrom(highlights),
      );
      return true;
    } on Exception {
      return false;
    }
  }

  /// Rebuilt from app records each time: the plugin's decoration JSON does
  /// not round-trip in 0.9.0 (spike finding 12). Visible for tests.
  static List<ReaderDecoration> decorationsFrom(
    List<ReaderHighlight> highlights,
  ) => [
    for (final highlight in highlights)
      if (Locator.fromJson(highlight.locator.locator) case final locator?)
        ReaderDecoration(
          id: highlight.id,
          locator: locator,
          style: ReaderDecorationStyle(
            style: DecorationStyle.highlight,
            tint: highlight.color.tint,
          ),
        ),
  ];

  /// Visible for tests. `fontSize` is a ratio in 0.9.0 (spike finding 5).
  static EPUBPreferences epubPreferencesFrom(ReaderAppearance appearance) {
    final preferences = appearance.preferences;
    return EPUBPreferences(
      fontSize: preferences.fontScale,
      scroll: preferences.epubLayout == PageLayout.scroll,
      backgroundColor: appearance.background,
      textColor: appearance.foreground,
    );
  }

  /// Visible for tests.
  static PDFPreferences pdfPreferencesFrom(ReaderAppearance appearance) {
    final preferences = appearance.preferences;
    return PDFPreferences(
      layout: switch (preferences.pdfLayout) {
        PageLayout.paginated => PDFLayout.paginated,
        PageLayout.scroll => PDFLayout.scrollVertical,
      },
      fit: switch (preferences.pdfFit) {
        PdfPageFit.width => PDFFit.width,
        PdfPageFit.page => PDFFit.page,
      },
    );
  }

  @override
  Future<void> close() => _serial(_close);

  Future<void> _close() async {
    _generation++;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    if (_publication == null) return;
    _publication = null;
    _format = null;
    _toc = const [];
    await _closeQuietly();
  }

  Future<void> _closeQuietly() async {
    try {
      await _readium.closePublication();
    } on Object {
      // The next open replaces the engine's publication anyway.
    }
  }

  Future<void> _ifOpen(Future<void> Function() command) async {
    if (_publication == null) return;
    try {
      await command();
    } on ReadiumException {
      // A failed page turn leaves the reader where it was.
    }
  }

  /// Maps an engine locator to an app position. Visible for tests.
  static ReaderPosition positionFrom(
    Locator locator,
    PublicationFormat format,
  ) {
    final locations = locator.locations;
    final total = locations?.totalProgression ?? locations?.progression;
    final page = locations?.position;
    return ReaderPosition(
      locator: LocatorEnvelope(format: format, locator: locator.toJson()),
      progression: total == null || total.isNaN ? null : total.clamp(0.0, 1.0),
      // In PDF locators `position` is the page number (spike finding).
      pageNumber: format == PublicationFormat.pdf && page != null && page > 0
          ? page
          : null,
      chapterTitle: locator.title,
    );
  }

  /// Maps engine errors to app failures without their messages, which can
  /// be technical or contain paths. Visible for tests.
  static ReaderFailure mapReadiumError(ReadiumError error) {
    final code = error.codeEnum;
    final kind = switch (code) {
      ReadiumErrorCode.readingError ||
      ReadiumErrorCode.resourceReadError ||
      ReadiumErrorCode.notFound => ReaderFailureKind.unreadable,
      ReadiumErrorCode.formatNotSupported ||
      ReadiumErrorCode.unsupportedScheme ||
      ReadiumErrorCode.forbidden ||
      ReadiumErrorCode.incorrectCredentials => ReaderFailureKind.unsupported,
      _ => ReaderFailureKind.engine,
    };
    return ReaderFailure(kind, code: code.name);
  }
}

/// [LocatorInterpreter] for Readium locators.
class ReadiumLocatorInterpreter implements LocatorInterpreter {
  const ReadiumLocatorInterpreter();

  /// EPUB progression within a resource is a float; positions this close
  /// are treated as the same page.
  static const double _sameProgressionTolerance = 0.001;

  @override
  ReaderPosition describe(LocatorEnvelope locator) {
    final parsed = Locator.fromJson(locator.locator);
    if (parsed == null) return ReaderPosition(locator: locator);
    return ReadiumPublicationReader.positionFrom(parsed, locator.format);
  }

  @override
  bool isSameLocation(LocatorEnvelope a, LocatorEnvelope b) {
    if (a.format != b.format) return false;
    final first = Locator.fromJson(a.locator);
    final second = Locator.fromJson(b.locator);
    if (first == null || second == null || first.href != second.href) {
      return false;
    }
    final locationsA = first.locations;
    final locationsB = second.locations;
    if (a.format == PublicationFormat.pdf) {
      return locationsA?.position == locationsB?.position;
    }
    final progressionA = locationsA?.progression;
    final progressionB = locationsB?.progression;
    if (progressionA == null || progressionB == null) {
      return progressionA == progressionB;
    }
    return (progressionA - progressionB).abs() <= _sameProgressionTolerance;
  }
}
