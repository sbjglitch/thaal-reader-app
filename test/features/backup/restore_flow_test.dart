import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaal/app/providers.dart';
import 'package:thaal/app/theme/app_theme.dart';
import 'package:thaal/domain/entities/library_snapshot.dart';
import 'package:thaal/features/settings/presentation/settings_screen.dart';
import 'package:thaal/services/backup/backup_contents.dart';
import 'package:thaal/services/backup/backup_format.dart';
import 'package:thaal/services/backup/backup_restore_service.dart';
import 'package:thaal/services/backup/restore_plan.dart';
import 'package:thaal/services/import/document_picker.dart';

import '../../support/fixtures.dart';
import 'backup_section_test.dart' show TestSaver;

class _Picker implements DocumentPicker {
  ImportSource? next = const ImportSource(name: 'b.readerbackup', path: '/b');
  int releases = 0;

  @override
  Future<ImportSource?> pickBackup() async => next;

  @override
  Future<List<ImportSource>> pickPublications() async => const [];

  @override
  Future<void> releaseTemporaryFiles() async => releases++;
}

class _Restorer implements BackupRestoreService {
  RestoreInspection inspection = const RestoreRejected(
    RestoreRejection.damaged,
  );
  RestoreOutcome? outcome;
  final List<bool> restores = [];

  @override
  Future<RestoreInspection> inspect(String archivePath) async => inspection;

  @override
  Future<RestoreOutcome> restore(
    RestoreReady ready, {
    required bool applySettings,
  }) async {
    restores.add(applySettings);
    return outcome ?? RestoreCompleted(ready.plan, settingsApplied: 0);
  }

  @override
  Future<void> recoverInterrupted() async {}
}

RestoreReady ready({
  BackupType type = BackupType.libraryOnly,
  LibrarySnapshot local = const LibrarySnapshot(
    books: [],
    progress: [],
    bookmarks: [],
    highlights: [],
    collections: [],
    memberships: [],
  ),
  bool withSettings = true,
}) {
  final books = [
    sampleBook(id: 'a', title: 'Alpha'),
    sampleBook(id: 'b', title: 'Beta'),
  ];
  final contents = BackupContents(
    manifest: BackupManifest(
      createdAt: DateTime.utc(2026, 11, 8, 9, 30),
      type: type,
      app: const BackupAppInfo(name: 'Thaal', version: '1', buildNumber: '1'),
      locatorEnvelopeVersion: 1,
      counts: const {},
      entries: const [],
      preferencesIncluded: withSettings,
    ),
    books: [for (final book in books) BackupBookRecord(book: book)],
    records: LibrarySnapshot(
      books: books,
      progress: const [],
      bookmarks: const [],
      highlights: const [],
      collections: const [],
      memberships: const [],
    ),
    preferences: withSettings ? const {'app.theme': 'dark'} : null,
  );
  return RestoreReady(
    archivePath: '/b',
    contents: contents,
    plan: planRestore(contents, local),
  );
}

void main() {
  late SharedPreferences prefs;
  late _Picker picker;
  late _Restorer restorer;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    picker = _Picker();
    restorer = _Restorer();
  });

  Future<void> pumpAndRestore(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          backupSaverProvider.overrideWithValue(TestSaver()),
          documentPickerProvider.overrideWithValue(picker),
          backupRestoreServiceProvider.overrideWithValue(restorer),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const SettingsScreen()),
      ),
    );
    await tester.tap(find.text('Restore backup'));
    await tester.pumpAndSettle();
  }

  testWidgets('a cancelled picker does nothing', (tester) async {
    picker.next = null;
    await pumpAndRestore(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(picker.releases, 1);
  });

  testWidgets('explains why a file is rejected', (tester) async {
    await pumpAndRestore(tester);
    expect(find.text('This backup can’t be restored'), findsOneWidget);
    expect(find.textContaining('damaged'), findsOneWidget);
    expect(find.textContaining('Your library was not changed'), findsOneWidget);
  });

  testWidgets('previews a library-only restore, then reports it', (
    tester,
  ) async {
    restorer.inspection = ready();
    await pumpAndRestore(tester);

    expect(find.text('Restore backup?'), findsOneWidget);
    expect(
      find.textContaining('Library-only backup from 8 Nov 2026'),
      findsOneWidget,
    );
    expect(find.text('• 2 books'), findsOneWidget);
    expect(find.textContaining('“File missing”'), findsOneWidget);
    expect(
      find.text('Nothing in your library is changed or removed.'),
      findsOneWidget,
    );
    final checkbox = tester.widget<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect(checkbox.value, isFalse);

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(restorer.restores, [false]);
    expect(find.text('Restore complete'), findsOneWidget);
    expect(find.textContaining('Import the same files again'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(picker.releases, 1);
  });

  testWidgets('can apply settings from the backup', (tester) async {
    restorer.inspection = ready();
    await pumpAndRestore(tester);
    await tester.tap(find.text('Apply settings from the backup'));
    await tester.pump();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(restorer.restores, [true]);
  });

  testWidgets('lists conflicts and says when nothing is new', (tester) async {
    restorer.inspection = ready(
      local: LibrarySnapshot(
        books: [sampleBook(id: 'a', title: 'Alpha')],
        progress: const [],
        bookmarks: const [],
        highlights: const [],
        collections: const [],
        memberships: const [],
      ),
    );
    // Both incoming books share sampleChecksum: "a" is the same book, "b"
    // is a duplicate of it.
    await pumpAndRestore(tester);
    expect(find.text('Nothing to restore'), findsOneWidget);
    expect(
      find.textContaining('Beta (already in your library)'),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(restorer.restores, isEmpty);
  });

  testWidgets('reports a failed restore', (tester) async {
    restorer
      ..inspection = ready(withSettings: false)
      ..outcome = const RestoreFailed(RestoreFailure.insufficientStorage);
    await pumpAndRestore(tester);
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.text('Restore failed'), findsOneWidget);
    expect(find.textContaining('not enough storage'), findsOneWidget);
  });
}
