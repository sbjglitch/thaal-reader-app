import 'dart:async';

import '../../../core/errors/app_errors.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/utils/clock.dart';
import '../../../domain/entities/locator_envelope.dart';
import '../../../domain/entities/reading_data.dart';
import '../../../domain/repositories/reading_progress_repository.dart';
import '../../../services/reader/publication_reader.dart';

/// Debounces reading-position writes (READER_ENGINE_SPECIFICATION.md §9.3).
///
/// Positions arrive often while paging or scrolling; only the latest is kept
/// and written after [debounce] of quiet, or at once on [flush] (navigation,
/// backgrounding, close). Writes run one at a time in arrival order. A
/// failed write keeps the previous saved row (the repository upserts in one
/// statement) and the position stays pending for the next flush.
class ProgressSaver {
  ProgressSaver({
    required this.bookId,
    required this._repository,
    required this._logger,
    this._clock = DateTime.now,
    this.debounce = const Duration(milliseconds: 750),
  });

  final String bookId;
  final Duration debounce;
  final ReadingProgressRepository _repository;
  final AppLogger _logger;
  final Clock _clock;

  ReaderPosition? _pending;
  Timer? _timer;
  Future<void> _writes = Future.value();

  bool get hasPending => _pending != null;

  void update(ReaderPosition position) {
    _pending = position;
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(flush()));
  }

  /// Writes the pending position, if any. Completes after the write.
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    final position = _pending;
    if (position == null) return _writes;
    _pending = null;
    return _writes = _writes.then((_) => _write(position));
  }

  Future<void> _write(ReaderPosition position) async {
    try {
      await _repository.saveProgress(
        ReadingProgress(
          bookId: bookId,
          locator: SerializedLocator.fromEnvelope(position.locator),
          pageNumber: position.pageNumber,
          progression: position.progression,
          updatedAt: _clock(),
        ),
      );
    } on AppError catch (error) {
      _logger.warning('reader.progress_save_failed', error: error);
      // Retry with the next flush unless a newer position has arrived.
      _pending ??= position;
    }
  }

  /// Stops the timer. Call [flush] first to keep the latest position.
  void dispose() => _timer?.cancel();
}
