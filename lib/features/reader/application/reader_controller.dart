import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_errors.dart';
import '../../../core/logging/app_logger.dart';
import '../../../domain/entities/book.dart';
import '../../../domain/entities/enums.dart';
import '../../../domain/entities/locator_envelope.dart';
import '../../../domain/entities/reader_preferences.dart';
import '../../../domain/entities/reading_data.dart';
import '../../../services/reader/publication_reader.dart';
import '../../highlights/application/highlights.dart';
import 'progress_saver.dart';
import 'reader_preferences_controller.dart';

/// What to open: a book, optionally at a bookmark instead of the saved
/// reading position.
final class ReaderRequest {
  const ReaderRequest(this.bookId, {this.bookmarkId});

  final String bookId;
  final String? bookmarkId;

  @override
  bool operator ==(Object other) =>
      other is ReaderRequest &&
      other.bookId == bookId &&
      other.bookmarkId == bookmarkId;

  @override
  int get hashCode => Object.hash(bookId, bookmarkId);
}

/// Why the reader cannot show a book.
enum ReaderProblem {
  bookNotFound,
  missingFile,
  unreadable,
  unsupported,
  failed,
}

/// Reader screen state (READER_ENGINE_SPECIFICATION.md §5.4).
sealed class ReaderState {
  const ReaderState();
}

final class ReaderOpening extends ReaderState {
  const ReaderOpening();
}

final class ReaderUnavailable extends ReaderState {
  const ReaderUnavailable(this.problem);

  final ReaderProblem problem;
}

final class ReaderOpen extends ReaderState {
  const ReaderOpen({
    required this.book,
    required this.toc,
    this.initialLocator,
    this.ready = false,
    this.position,
    this.restoreFailed = false,
    this.supportsHighlights = false,
  });

  final Book book;
  final List<TocEntry> toc;

  /// Where the engine view starts; null opens at the beginning.
  final LocatorEnvelope? initialLocator;

  /// The engine has rendered its first page.
  final bool ready;
  final ReaderPosition? position;

  /// A saved position existed but could not be used, so the book opened at
  /// the beginning. The saved row is kept until the reader moves on.
  final bool restoreFailed;

  /// Text highlights are offered for this publication (EPUB only).
  final bool supportsHighlights;

  ReaderOpen copyWith({bool? ready, ReaderPosition? position}) => ReaderOpen(
    book: book,
    toc: toc,
    initialLocator: initialLocator,
    ready: ready ?? this.ready,
    position: position ?? this.position,
    restoreFailed: restoreFailed,
    supportsHighlights: supportsHighlights,
  );
}

/// One-off things the reader screen should show.
sealed class ReaderNotice {
  const ReaderNotice();
}

/// Open the editor for a highlight (it was tapped, or created with a note).
final class EditHighlightNotice extends ReaderNotice {
  const EditHighlightNotice(this.highlightId);

  final String highlightId;
}

/// A highlight could not be saved; nothing was added.
final class HighlightSaveFailedNotice extends ReaderNotice {
  const HighlightSaveFailedNotice();
}

/// Owns one reader session: opens the book, restores and saves the
/// position, records the open, and releases the engine when the screen goes
/// away (spec §5.1–5.2, §14).
class ReaderController extends Notifier<ReaderState> {
  ReaderController(this.request);

  final ReaderRequest request;

  String get bookId => request.bookId;

  late PublicationReader _reader;
  late AppLogger _logger;
  ProgressSaver? _saver;
  StreamSubscription<ReaderEvent>? _events;
  StreamSubscription<List<Highlight>>? _highlightSubscription;
  List<Highlight> _highlights = const [];
  final _notices = StreamController<ReaderNotice>.broadcast();
  AppLifecycleListener? _lifecycle;
  bool _disposed = false;
  bool _recordedOpen = false;
  Brightness _brightness =
      WidgetsBinding.instance.platformDispatcher.platformBrightness;
  ReaderAppearance? _appearance;

  /// After a failed restore the engine reports the start of the book; that
  /// position must not overwrite the saved one until the reader moves.
  bool _skipNextPosition = false;

  /// Notices for the screen; see [ReaderNotice].
  Stream<ReaderNotice> get notices => _notices.stream;

  @override
  ReaderState build() {
    _reader = ref.watch(publicationReaderProvider);
    _logger = ref.watch(appLoggerProvider);
    ref.onDispose(_dispose);
    unawaited(Future.microtask(_openSafely));
    return const ReaderOpening();
  }

  /// Never leaves the screen stuck on "opening".
  Future<void> _openSafely() async {
    try {
      await _open();
    } on Object catch (error, stackTrace) {
      _logger.error('reader.unexpected_error', error, stackTrace: stackTrace);
      _fail(ReaderProblem.failed);
    }
  }

  Future<void> _open() async {
    final books = ref.read(bookRepositoryProvider);
    final storage = ref.read(libraryStorageProvider);
    final Book? book;
    try {
      book = await books.getBook(bookId);
    } on AppError {
      return _fail(ReaderProblem.failed);
    }
    if (book == null) return _fail(ReaderProblem.bookNotFound);
    final size = await storage.fileSize(book.filePath);
    if (size == null || size == 0) return _fail(ReaderProblem.missingFile);

    LocatorEnvelope? initial = await _bookmarkLocator(book.format);
    var restoreFailed = false;
    if (initial == null) {
      try {
        final saved = await ref
            .read(readingProgressRepositoryProvider)
            .getProgress(bookId);
        final stored = saved?.locator;
        if (stored != null) {
          initial = stored.decode(book.format);
          restoreFailed = initial == null;
        }
      } on AppError {
        restoreFailed = true;
      }
    }
    if (_disposed) return;

    final appearance = _appearance = resolveAppearance(
      ref.read(readerPreferencesProvider),
      _brightness,
    );
    final OpenedPublication opened;
    try {
      opened = await _reader.open(
        filePath: storage.file(book.filePath).path,
        format: book.format,
        appearance: appearance,
      );
    } on ReaderFailure catch (failure) {
      _logger.warning(
        'reader.open_failed',
        fields: {'code': failure.code, 'format': book.format},
      );
      return _fail(switch (failure.kind) {
        ReaderFailureKind.unreadable => ReaderProblem.unreadable,
        ReaderFailureKind.unsupported => ReaderProblem.unsupported,
        ReaderFailureKind.engine => ReaderProblem.failed,
      });
    }
    if (_disposed) {
      await _reader.close();
      return;
    }

    _saver = ProgressSaver(
      bookId: bookId,
      repository: ref.read(readingProgressRepositoryProvider),
      logger: _logger,
    );
    _skipNextPosition = restoreFailed;
    _events = _reader.events.listen(_onEvent);
    _lifecycle = AppLifecycleListener(
      onHide: _flush,
      onPause: _flush,
      onDetach: _flush,
    );
    if (restoreFailed) _logger.warning('reader.restore_failed');
    final supportsHighlights = _reader.supportsHighlights;
    state = ReaderOpen(
      book: book,
      toc: opened.toc,
      initialLocator: initial,
      restoreFailed: restoreFailed,
      supportsHighlights: supportsHighlights,
    );
    if (supportsHighlights) {
      _highlightSubscription = ref
          .read(highlightRepositoryProvider)
          .watchHighlights(bookId)
          .listen(
            (list) {
              _highlights = list;
              unawaited(_showHighlights());
            },
            onError: (Object error) =>
                _logger.warning('reader.highlights_load_failed', error: error),
          );
    }
  }

  /// Draws the saved highlights once the engine is ready (spec §11.4).
  /// Ones whose locator cannot be read are skipped and kept.
  Future<void> _showHighlights() async {
    final current = state;
    if (current is! ReaderOpen ||
        !current.supportsHighlights ||
        !current.ready ||
        _disposed) {
      return;
    }
    final shown = <ReaderHighlight>[
      for (final highlight in _highlights)
        if (highlight.locator.decode(PublicationFormat.epub) case final env?)
          ReaderHighlight(
            id: highlight.id,
            locator: env,
            color: highlight.color,
          ),
    ];
    if (!await _reader.showHighlights(shown)) {
      _logger.warning('reader.highlights_apply_failed');
    }
  }

  Future<void> _createHighlight(ReaderTextActionEvent event) async {
    try {
      final highlight = await ref
          .read(highlightActionsProvider)
          .add(bookId, event.locator, selectedText: event.selectedText);
      if (event.action == ReaderTextAction.note && !_disposed) {
        _notices.add(EditHighlightNotice(highlight.id));
      }
    } on AppError catch (error) {
      _logger.warning('reader.highlight_save_failed', error: error);
      if (!_disposed) _notices.add(const HighlightSaveFailedNotice());
    }
  }

  /// The requested bookmark's location, or null to use the saved reading
  /// position (no bookmark requested, or it no longer exists or cannot be
  /// read; the bookmark itself is kept).
  Future<LocatorEnvelope?> _bookmarkLocator(PublicationFormat format) async {
    final bookmarkId = request.bookmarkId;
    if (bookmarkId == null) return null;
    try {
      final bookmarks = await ref
          .read(bookmarkRepositoryProvider)
          .watchBookmarks(bookId)
          .first;
      for (final bookmark in bookmarks) {
        if (bookmark.id == bookmarkId) return bookmark.locator.decode(format);
      }
    } on AppError catch (error) {
      _logger.warning('reader.bookmark_load_failed', error: error);
    }
    return null;
  }

  void _onEvent(ReaderEvent event) {
    final current = state;
    if (current is! ReaderOpen) return;
    switch (event) {
      case ReaderReady():
        state = current.copyWith(ready: true);
        unawaited(_showHighlights());
        if (!_recordedOpen) {
          _recordedOpen = true;
          unawaited(_recordOpened());
        }
      case ReaderPositionChanged(:final position):
        state = current.copyWith(position: position);
        if (_skipNextPosition) {
          _skipNextPosition = false;
          return;
        }
        _saver?.update(position);
      case ReaderReachedEnd():
        unawaited(_markFinished());
      case ReaderTextActionEvent():
        if (current.supportsHighlights) unawaited(_createHighlight(event));
      case ReaderHighlightTapped(:final highlightId):
        _notices.add(EditHighlightNotice(highlightId));
      case ReaderErrorEvent(:final failure, :final fatal):
        _logger.warning(
          'reader.error',
          fields: {'code': failure.code, 'fatal': fatal},
        );
        if (fatal) {
          _flush();
          state = const ReaderUnavailable(ReaderProblem.failed);
        }
    }
  }

  Future<void> _recordOpened() async {
    try {
      await ref
          .read(bookRepositoryProvider)
          .recordOpened(bookId, DateTime.now());
    } on AppError catch (error) {
      _logger.warning('reader.record_open_failed', error: error);
    }
  }

  Future<void> _markFinished() async {
    try {
      await ref
          .read(bookRepositoryProvider)
          .updateReadingStatus(bookId, ReadingStatus.finished);
    } on AppError catch (error) {
      _logger.warning('reader.mark_finished_failed', error: error);
    }
  }

  void _flush() => unawaited(_saver?.flush());

  /// Applies [preferences] to the open book, then saves them. Returns false
  /// when the engine rejected them; nothing is saved then (spec §15:
  /// "keep prior preference and show no false success").
  Future<bool> updatePreferences(ReaderPreferences preferences) async {
    final current = state;
    final applied = current is ReaderOpen
        ? await _apply(resolveAppearance(preferences, _brightness))
        : true;
    if (!applied) return false;
    await ref.read(readerPreferencesProvider.notifier).save(preferences);
    return true;
  }

  /// Follows the system light/dark setting for the "system" reading theme.
  Future<void> setPlatformBrightness(Brightness brightness) async {
    if (brightness == _brightness) return;
    _brightness = brightness;
    if (state is ReaderOpen) {
      await _apply(
        resolveAppearance(ref.read(readerPreferencesProvider), brightness),
      );
    }
  }

  Future<bool> _apply(ReaderAppearance appearance) async {
    final previous = _appearance;
    if (appearance == previous) return true;
    if (!await _reader.applyAppearance(appearance)) {
      _logger.warning('reader.preferences_rejected');
      return false;
    }
    _appearance = appearance;
    // Reflowing EPUB text does not report a new position (spike finding
    // 10), so return to the last known one to keep the reader's place.
    final current = state;
    if (current is ReaderOpen &&
        current.book.format == PublicationFormat.epub &&
        _reflows(previous?.preferences, appearance.preferences)) {
      final position = current.position;
      if (position != null) await _reader.goToLocator(position.locator);
    }
    return true;
  }

  static bool _reflows(ReaderPreferences? before, ReaderPreferences after) =>
      before == null ||
      before.fontScale != after.fontScale ||
      before.epubLayout != after.epubLayout;

  void _fail(ReaderProblem problem) {
    if (!_disposed) state = ReaderUnavailable(problem);
  }

  /// Moves to a saved location. Returns false when it cannot be found; the
  /// caller keeps the bookmark and explains (spec §10.2).
  Future<bool> goToLocator(LocatorEnvelope locator) async {
    if (state is! ReaderOpen) return false;
    _skipNextPosition = false;
    await _saver?.flush();
    return _reader.goToLocator(locator);
  }

  Future<void> goForward() => _navigate(_reader.goForward);

  Future<void> goBackward() => _navigate(_reader.goBackward);

  /// Returns false when the entry could not be resolved.
  Future<bool> goToTocEntry(TocEntry entry) async {
    _skipNextPosition = false;
    await _saver?.flush();
    return _reader.goToTocEntry(entry);
  }

  Future<void> _navigate(Future<void> Function() command) async {
    if (state is! ReaderOpen) return;
    _skipNextPosition = false;
    await command();
  }

  void _dispose() {
    _disposed = true;
    _lifecycle?.dispose();
    unawaited(_events?.cancel());
    unawaited(_highlightSubscription?.cancel());
    unawaited(_notices.close());
    final saver = _saver;
    // Flush before releasing the engine; the write does not need the engine.
    unawaited(saver?.flush().whenComplete(saver.dispose));
    unawaited(_reader.close());
  }
}

final readerControllerProvider = NotifierProvider.autoDispose
    .family<ReaderController, ReaderState, ReaderRequest>(ReaderController.new);
