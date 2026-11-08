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

/// A batch finished. The screen reports [results], then calls
/// [ImportController.importDuplicatesAnyway] or [ImportController.dismiss].
final class ImportFinished extends ImportState {
  const ImportFinished(this.results, {this.pickerFailed = false});

  final List<ImportResult> results;

  /// The document picker itself could not be opened.
  final bool pickerFailed;

  List<ImportSucceeded> get imported =>
      results.whereType<ImportSucceeded>().toList();
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
    } catch (error, stackTrace) {
      ref
          .read(appLoggerProvider)
          .error('import.picker_failed', error, stackTrace: stackTrace);
      state = const ImportFinished([], pickerFailed: true);
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
