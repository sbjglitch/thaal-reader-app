import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaal/app/providers.dart';
import 'package:thaal/app/theme/app_theme.dart';
import 'package:thaal/features/settings/presentation/settings_screen.dart';
import 'package:thaal/services/backup/backup_export_service.dart';
import 'package:thaal/services/backup/backup_format.dart';
import 'package:thaal/services/backup/backup_saver.dart';

import '../../support/fixtures.dart';

/// A saver that reports support; saving itself is not exercised here.
class TestSaver implements BackupSaver {
  TestSaver({this.isSupported = true});

  @override
  final bool isSupported;

  @override
  Future<String?> save(File file, {required String suggestedName}) =>
      throw UnimplementedError();
}

/// Records calls and answers with the next queued result once [release]d.
class _FakeExport implements BackupExportService {
  final List<(BackupType, bool)> calls = [];
  final List<BackupExportResult> results = [];
  Completer<void>? gate;

  @override
  Future<BackupExportResult> export(
    BackupType type, {
    required bool includeSettings,
  }) async {
    calls.add((type, includeSettings));
    await gate?.future;
    return results.removeAt(0);
  }
}

void main() {
  late SharedPreferences prefs;
  late _FakeExport export;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    export = _FakeExport();
  });

  Future<void> pump(WidgetTester tester, {bool supported = true}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          backupSaverProvider.overrideWithValue(
            TestSaver(isSupported: supported),
          ),
          backupExportServiceProvider.overrideWithValue(export),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const SettingsScreen()),
      ),
    );
  }

  Future<void> createVia(WidgetTester tester, String tile) async {
    await tester.tap(find.text(tile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pump();
  }

  testWidgets('hides backup where saving is unsupported', (tester) async {
    await pump(tester, supported: false);
    expect(find.text('Data'), findsNothing);
    expect(find.text('Create full backup'), findsNothing);
  });

  testWidgets('offers both backup types under Data', (tester) async {
    await pump(tester);
    expect(find.text('Data'), findsOneWidget);
    expect(find.text('Create full backup'), findsOneWidget);
    expect(find.text('Create library-only backup'), findsOneWidget);
  });

  testWidgets('explains the backup, shows progress, then the saved name', (
    tester,
  ) async {
    await pump(tester);
    export
      ..gate = Completer<void>()
      ..results.add(const BackupExportSaved('my.readerbackup'));

    await tester.tap(find.text('Create full backup'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Includes your books'), findsOneWidget);
    expect(find.textContaining('not encrypted'), findsOneWidget);
    await tester.tap(find.text('Create'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Creating backup…'), findsOneWidget);
    expect(export.calls, [(BackupType.full, true)]);

    export.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Creating backup…'), findsNothing);
    expect(find.text('Backup saved as my.readerbackup.'), findsOneWidget);
  });

  testWidgets('says library-only backups have no book files and can skip '
      'settings', (tester) async {
    await pump(tester);
    export.results.add(const BackupExportCancelled());

    await tester.tap(find.text('Create library-only backup'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Book files are not included'), findsOneWidget);
    await tester.tap(find.text('Include settings'));
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(export.calls, [(BackupType.libraryOnly, false)]);
    expect(find.text('Backup not saved.'), findsOneWidget);
  });

  testWidgets('cancelling the explanation creates nothing', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Create full backup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(export.calls, isEmpty);
  });

  testWidgets('lists missing books and offers a library-only backup', (
    tester,
  ) async {
    await pump(tester);
    export.results.addAll([
      BackupExportIncomplete([
        for (var i = 1; i <= 7; i++) sampleBook(id: 'b$i', title: 'Book $i'),
      ]),
      const BackupExportSaved('lib.readerbackup'),
    ]);

    await createVia(tester, 'Create full backup');
    await tester.pumpAndSettle();

    expect(find.text('Some book files are missing'), findsOneWidget);
    expect(find.text('• Book 1'), findsOneWidget);
    expect(find.text('• Book 5'), findsOneWidget);
    expect(find.text('• Book 6'), findsNothing);
    expect(find.text('and 2 more'), findsOneWidget);

    await tester.tap(find.text('Create library-only backup').last);
    await tester.pumpAndSettle();
    expect(export.calls, [
      (BackupType.full, true),
      (BackupType.libraryOnly, true),
    ]);
    expect(find.text('Backup saved as lib.readerbackup.'), findsOneWidget);
  });

  testWidgets('reports failures', (tester) async {
    await pump(tester);
    export.results.addAll(const [
      BackupExportFailed(BackupExportFailure.insufficientStorage),
      BackupExportFailed(BackupExportFailure.failed),
    ]);

    await createVia(tester, 'Create full backup');
    await tester.pumpAndSettle();
    expect(find.textContaining('not enough storage'), findsOneWidget);

    ScaffoldMessenger.of(tester.element(find.byType(SettingsScreen)))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();
    await createVia(tester, 'Create full backup');
    await tester.pumpAndSettle();
    expect(
      find.text('The backup could not be created. Nothing was saved.'),
      findsOneWidget,
    );
  });
}
