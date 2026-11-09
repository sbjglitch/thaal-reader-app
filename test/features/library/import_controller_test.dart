import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/app/providers.dart';
import 'package:thaal/features/library/application/import_controller.dart';
import 'package:thaal/services/import/document_picker.dart';
import 'package:thaal/services/import/import_service.dart';

import '../../support/fixtures.dart';

class FakePicker implements DocumentPicker {
  List<ImportSource> next = const [];
  Completer<void>? gate;

  /// Thrown by the next pick instead of returning [next], when set.
  Object? error;
  int picks = 0;
  int releases = 0;

  @override
  Future<List<ImportSource>> pickPublications() async {
    picks++;
    await gate?.future;
    if (error case final error?) throw error;
    return next;
  }

  @override
  Future<ImportSource?> pickBackup() async => null;

  @override
  Future<void> releaseTemporaryFiles() async => releases++;
}

class FakeImportService implements ImportService {
  final calls = <(String, bool)>[];
  Completer<void>? gate;
  ImportResult Function(ImportSource source, bool allowDuplicate)? respond;

  @override
  Future<ImportResult> importFile(
    ImportSource source, {
    bool allowDuplicate = false,
  }) async {
    calls.add((source.name, allowDuplicate));
    await gate?.future;
    return respond?.call(source, allowDuplicate) ??
        ImportSucceeded(source, sampleBook(id: source.name));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakePicker picker;
  late FakeImportService service;
  late ProviderContainer container;

  ImportController controller() =>
      container.read(importControllerProvider.notifier);
  ImportState state() => container.read(importControllerProvider);

  setUp(() {
    picker = FakePicker();
    service = FakeImportService();
    container = ProviderContainer.test(
      overrides: [
        documentPickerProvider.overrideWithValue(picker),
        importServiceProvider.overrideWithValue(service),
      ],
    );
  });

  test('cancelling the picker returns to idle', () async {
    await controller().pickAndImport();
    expect(state(), isA<ImportIdle>());
    expect(service.calls, isEmpty);
  });

  test('imports each picked file in order and reports results', () async {
    picker.next = const [
      ImportSource(name: 'a.epub', path: '/a'),
      ImportSource(name: 'b.pdf', path: '/b'),
    ];
    final seen = <ImportState>[];
    container.listen(importControllerProvider, (_, next) => seen.add(next));

    await controller().pickAndImport();

    expect(service.calls, [('a.epub', false), ('b.pdf', false)]);
    expect(seen.whereType<ImportRunning>().map((s) => (s.current, s.total)), [
      (1, 2),
      (2, 2),
    ]);
    final finished = state() as ImportFinished;
    expect(finished.imported, hasLength(2));
  });

  test('a second tap while busy does not start another import', () async {
    picker.gate = Completer();
    picker.next = const [ImportSource(name: 'a.epub', path: '/a')];

    final first = controller().pickAndImport();
    await controller().pickAndImport();
    picker.gate!.complete();
    await first;

    expect(picker.picks, 1);
    expect(service.calls, hasLength(1));
  });

  test(
    'duplicates can be imported anyway, then temp files are released',
    () async {
      picker.next = const [
        ImportSource(name: 'dup.epub', path: '/d'),
        ImportSource(name: 'new.epub', path: '/n'),
      ];
      service.respond = (source, allowDuplicate) =>
          source.name == 'dup.epub' && !allowDuplicate
          ? ImportDuplicate(source, [sampleBook()])
          : ImportSucceeded(source, sampleBook(id: source.name));

      await controller().pickAndImport();
      expect((state() as ImportFinished).duplicates, hasLength(1));

      await controller().importDuplicatesAnyway();
      expect(service.calls.last, ('dup.epub', true));
      expect((state() as ImportFinished).imported, hasLength(1));

      await controller().dismiss();
      expect(state(), isA<ImportIdle>());
      expect(picker.releases, 1);
    },
  );

  test('a picker failure is reported, not thrown', () async {
    picker.error = StateError('no activity');
    await controller().pickAndImport();
    final finished = state() as ImportFinished;
    expect(finished.pickerFailure, ImportPickerFailure.unavailable);
    expect(service.calls, isEmpty);
  });

  test('chosen files that could not be copied are reported apart', () async {
    picker.error = const PickedFilesUnreadable();
    await controller().pickAndImport();
    final finished = state() as ImportFinished;
    expect(finished.pickerFailure, ImportPickerFailure.filesUnreadable);
    expect(service.calls, isEmpty);

    await controller().dismiss();
    expect(picker.releases, 1);
  });
}
