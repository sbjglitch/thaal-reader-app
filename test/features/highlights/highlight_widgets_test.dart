import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/app/providers.dart';
import 'package:thaal/app/theme/app_theme.dart';
import 'package:thaal/core/errors/app_errors.dart';
import 'package:thaal/domain/entities/enums.dart';
import 'package:thaal/domain/entities/locator_envelope.dart';
import 'package:thaal/domain/entities/reading_data.dart';
import 'package:thaal/features/highlights/application/highlights.dart';
import 'package:thaal/features/highlights/presentation/highlight_widgets.dart';

import '../../support/fixtures.dart';
import '../bookmarks/fake_bookmarks.dart' show HrefLocatorInterpreter;
import 'fake_highlights.dart';

Highlight sampleHighlight(
  String id, {
  String? text = 'It is a truth universally acknowledged',
  String? note,
  HighlightColor color = HighlightColor.yellow,
  int minute = 0,
  String href = 'c1',
}) => Highlight(
  id: id,
  bookId: 'book-1',
  locator: SerializedLocator.fromEnvelope(
    LocatorEnvelope(
      format: PublicationFormat.epub,
      locator: {'href': href, 'progression': 0.25, 'title': 'Chapter 1'},
    ),
  ),
  selectedText: text,
  color: color,
  note: note,
  createdAt: fixedTime.add(Duration(minutes: minute)),
  updatedAt: fixedTime.add(Duration(minutes: minute)),
);

void main() {
  late MemoryHighlightRepository repository;
  HighlightEntry? opened;

  setUp(() {
    repository = MemoryHighlightRepository();
    opened = null;
  });

  Future<void> pump(
    WidgetTester tester,
    Future<void> Function(BuildContext context) onOpen,
  ) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          highlightRepositoryProvider.overrideWithValue(repository),
          bookHighlightsProvider.overrideWith(
            (ref, bookId) => highlightEntriesOf(
              repository.watchHighlights(bookId),
              const HrefLocatorInterpreter(),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => onOpen(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openEditor(WidgetTester tester, String id) async {
    await pump(
      tester,
      (context) =>
          showHighlightEditor(context, bookId: 'book-1', highlightId: id),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('editor', () {
    testWidgets('shows the passage and saves colour and note', (tester) async {
      repository.items.add(sampleHighlight('hl-1'));
      await openEditor(tester, 'hl-1');

      expect(
        find.text('It is a truth universally acknowledged'),
        findsOneWidget,
      );
      expect(find.text('Chapter 1 · 25%'), findsOneWidget);
      // The current colour is marked by more than colour.
      expect(find.bySemanticsLabel('Yellow'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);

      await tester.tap(find.byTooltip('Blue'));
      await tester.enterText(find.byType(TextField), 'Opening line');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = repository.items.single;
      expect(saved.color, HighlightColor.blue);
      expect(saved.note, 'Opening line');
      expect(find.text('Save'), findsNothing); // Sheet closed.
    });

    testWidgets('a failed save keeps the sheet open and says so', (
      tester,
    ) async {
      repository.items.add(sampleHighlight('hl-1'));
      await openEditor(tester, 'hl-1');
      repository.failWrites = const DatabaseError(
        DatabaseErrorKind.failure,
        'test',
      );
      await tester.enterText(find.byType(TextField), 'Lost?');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        find.text('Your changes could not be saved. Try again.'),
        findsOneWidget,
      );
      expect(find.text('Save'), findsOneWidget);
      expect(repository.items.single.note, isNull);
    });

    testWidgets('delete removes the highlight and note, with undo', (
      tester,
    ) async {
      repository.items.add(sampleHighlight('hl-1', note: 'Mine'));
      await openEditor(tester, 'hl-1');

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(repository.items, isEmpty);
      expect(find.text('Highlight and note deleted.'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(repository.items.single.note, 'Mine');
    });

    testWidgets('copies the saved text', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      repository.items.add(sampleHighlight('hl-1'));
      await openEditor(tester, 'hl-1');

      await tester.tap(find.text('Copy text'));
      await tester.pumpAndSettle();
      expect(copied, 'It is a truth universally acknowledged');
      expect(find.text('Copied'), findsOneWidget);
    });

    testWidgets('without saved text there is nothing to copy', (tester) async {
      repository.items.add(sampleHighlight('hl-1', text: null));
      await openEditor(tester, 'hl-1');
      expect(
        find.text('No text was saved with this highlight.'),
        findsOneWidget,
      );
      expect(find.text('Copy text'), findsNothing);
    });

    testWidgets('explains a highlight that no longer exists', (tester) async {
      await openEditor(tester, 'gone');
      expect(find.text('This highlight no longer exists'), findsOneWidget);
    });
  });

  group('list', () {
    Future<void> openList(WidgetTester tester) async {
      await pump(tester, (context) async {
        opened = await showModalBottomSheet<HighlightEntry>(
          context: context,
          isScrollControlled: true,
          builder: (_) => const HighlightsSheet(bookId: 'book-1'),
        );
      });
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('explains how to highlight when there are none', (
      tester,
    ) async {
      await openList(tester);
      expect(find.text('No highlights in this book'), findsOneWidget);
    });

    testWidgets('lists passages with notes and returns the chosen one', (
      tester,
    ) async {
      repository.items.addAll([
        sampleHighlight('a', text: 'First passage', minute: 1),
        sampleHighlight(
          'b',
          text: 'Second passage',
          note: 'Why?',
          color: HighlightColor.green,
          minute: 2,
        ),
      ]);
      await openList(tester);

      final titles = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((tile) => (tile.title! as Text).data)
          .toList();
      expect(titles, ['First passage', 'Second passage']);
      expect(find.text('Note: Why? · Chapter 1 · 25%'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Green highlight')), findsOneWidget);

      await tester.tap(find.text('Second passage'));
      await tester.pumpAndSettle();
      expect(opened?.highlight.id, 'b');
    });

    testWidgets('delete from the list offers undo', (tester) async {
      repository.items.add(sampleHighlight('a'));
      await openList(tester);
      await tester.tap(find.byTooltip('More actions for this highlight'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(repository.items, isEmpty);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(repository.items, hasLength(1));
    });
  });
}
