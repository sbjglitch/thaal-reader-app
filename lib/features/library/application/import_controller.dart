import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../services/import/document_picker.dart';
import '../../../services/import/import_service.dart';

/// Import progress shown on the library screen (UI/UX spec §7.2).
sealed class ImportState {
  const ImportState();

  bool get isBusy => this is ImportPicking || this is ImportRunning;
}

final class ImportIdle extends ImportState {
  const ImportIdle();
}

/// The system document picker is open.
final class ImportPicking extends ImportState {
  const ImportPicking();
}

/// Importing file [current] of [total] (1-based).
final class ImportRunning extends ImportState {
  const ImportRunning(this.current, this.total);

  final int current;
  final int total;
}

enum ImportPickerFailure {
  /// The document picker could not be opened.
  unavailable,

  /// Files were chosen but could not be copied, usually for lack of space.
  filesUnreadable,
}

/// A batch finished. The screen reports [results], then calls
/// [ImportController.importDuplicatesAnyway] or [ImportController.dismiss].
final class ImportFinished extends ImportState {
  const ImportFinished(this.results, {this.pickerFailure});

  final List<ImportResult> results;

  /// Why the picker step failed, if it did; [results] is then empty.
  final ImportPickerFailure? pickerFailure;

  List<ImportSucceeded> get imported =>
      results.whereType<ImportSucceeded>().toList();
  List<ImportRelinked> get relinked =>
      results.whereType<ImportRelinked>().toList();
  List<ImportDuplicate> get duplicates =>
      results.whereType<ImportDuplicate>().toList();
  List<ImportFailed> get failures => results.whereType<ImportFailed>().toList();
}

class ImportController extends Notifier<ImportState> {
  @override
  ImportState build() => const ImportIdle();

  DocumentPicker get _picker => ref.read(documentPickerProvider);
  ImportService get _service => ref.read(importServiceProvider);

  /// Opens the picker and imports the chosen files one at a time. Ignored
  /// while another import is in progress, so repeated taps cannot start
  /// overlapping imports.
  Future<void> pickAndImport() async {
    if (state.isBusy) return;
    state = const ImportPicking();
    final List<ImportSource> sources;
    try {
      sources = await _picker.pickPublications();
    } on PickedFilesUnreadable {
      ref.read(appLoggerProvider).warning('import.picked_files_unreadable');
      state = const ImportFinished(
        [],
        pickerFailure: ImportPickerFailure.filesUnreadable,
      );
      return;
    } catch (error, stackTrace) {
      ref
          .read(appLoggerProvider)
          .error('import.picker_failed', error, stackTrace: stackTrace);
      state = const ImportFinished(
        [],
        pickerFailure: ImportPickerFailure.unavailable,
      );
      return;
    }
    if (sources.isEmpty) {
      state = const ImportIdle();
      return;
    }
    await _run(sources, allowDuplicate: false);
  }

  /// Imports the files reported as duplicates in the last batch.
  Future<void> importDuplicatesAnyway() async {
    final current = state;
    if (current is! ImportFinished) return;
    final sources = [for (final d in current.duplicates) d.source];
    if (sources.isEmpty) return dismiss();
    await _run(sources, allowDuplicate: true);
  }

  /// Ends the batch and releases the picker's temporary copies.
  Future<void> dismiss() async {
    state = const ImportIdle();
    try {
      await _picker.releaseTemporaryFiles();
    } catch (error) {
      // Temporary picker copies live in the app cache, which the OS may
      // also clear; failing to delete them now is not user-visible.
      ref
          .read(appLoggerProvider)
          .warning('import.release_failed', error: error);
    }
  }

  Future<void> _run(
    List<ImportSource> sources, {
    required bool allowDuplicate,
  }) async {
    final results = <ImportResult>[];
    for (var i = 0; i < sources.length; i++) {
      state = ImportRunning(i + 1, sources.length);
      results.add(
        await _service.importFile(sources[i], allowDuplicate: allowDuplicate),
      );
    }
    state = ImportFinished(results);
  }
}

final importControllerProvider =
    NotifierProvider<ImportController, ImportState>(ImportController.new);
