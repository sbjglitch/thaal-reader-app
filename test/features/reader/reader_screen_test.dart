import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/app/providers.dart';
import 'package:thaal/app/theme/app_theme.dart';
import 'package:thaal/domain/entities/enums.dart';
import 'package:thaal/features/reader/application/reader_controller.dart';
import 'package:thaal/features/reader/presentation/reader_screen.dart';
import 'package:thaal/services/reader/publication_reader.dart';

import '../../support/fixtures.dart';
import 'fake_publication_reader.dart';
import 'progress_saver_test.dart' show position;

/// Controller double that exposes a fixed state.
class _StaticController extends ReaderController {
  _StaticController(super.bookId, this._state);

  final ReaderState _state;
  final calls = <String>[];

  @override
  ReaderState build() => _state;

  @override
  Future<void> goForward() async => calls.add('forward');

  @override
  Future<bool> goToTocEntry(TocEntry entry) async {
    calls.add('toc:${entry.title}');
    return false;
  }
}

void main() {
  late FakePublicationReader reader;
  _StaticController? controller;

  Future<void> pump(WidgetTester tester, ReaderState state) async {
    reader = FakePublicationReader();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          publicationReaderProvider.overrideWithValue(reader),
          readerControllerProvider.overrideWith2(
            (bookId) => controller = _StaticController(bookId, state),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const ReaderScreen(bookId: 'book-1'),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows a loading state while opening', (tester) async {
    await pump(tester, const ReaderOpening());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('explains a missing file', (tester) async {
    await pump(tester, const ReaderUnavailable(ReaderProblem.missingFile));
    expect(find.text('The book file is missing'), findsOneWidget);
    expect(find.text('Back to library'), findsOneWidget);
  });

  testWidgets('a damaged file is explained without engine details', (
    tester,
  ) async {
    await pump(tester, const ReaderUnavailable(ReaderProblem.unreadable));
    expect(find.text('This book could not be opened'), findsOneWidget);
  });

  testWidgets('renders the engine view with title, contents and progress', (
    tester,
  ) async {
    await pump(
      tester,
      ReaderOpen(
        book: sampleBook(title: 'Middlemarch'),
        toc: const [TocEntry(index: 0, title: 'Prelude', depth: 0)],
        ready: true,
        position: position('c1', progression: 0.345),
      ),
    );

    expect(find.byKey(const Key('engine-view')), findsOneWidget);
    expect(find.text('Middlemarch'), findsOneWidget);
    expect(find.text('35%'), findsOneWidget);

    await tester.tap(find.byTooltip('Next page'));
    expect(controller!.calls, ['forward']);

    await tester.tap(find.byTooltip('Contents'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prelude'));
    await tester.pumpAndSettle();
    expect(controller!.calls.last, 'toc:Prelude');
    expect(find.text('That section could not be opened.'), findsOneWidget);
  });

  testWidgets('hides contents when the publication has none', (tester) async {
    await pump(tester, ReaderOpen(book: sampleBook(), toc: const []));
    expect(find.byTooltip('Contents'), findsNothing);
  });

  testWidgets('PDF shows the page number', (tester) async {
    await pump(
      tester,
      ReaderOpen(
        book: sampleBook(format: PublicationFormat.pdf),
        toc: const [],
        position: position('p', progression: 0.1, page: 4),
      ),
    );
    expect(find.text('Page 4'), findsOneWidget);
  });
}
