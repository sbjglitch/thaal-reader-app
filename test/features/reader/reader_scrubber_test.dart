import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/app/theme/app_theme.dart';
import 'package:thaal/domain/entities/enums.dart';
import 'package:thaal/features/reader/application/reader_controller.dart';
import 'package:thaal/features/reader/presentation/reader_scrubber.dart';

import '../../support/fixtures.dart';
import 'progress_saver_test.dart' show position;

void main() {
  ReaderOpen epubAt(double progression) => ReaderOpen(
    book: sampleBook(),
    toc: const [],
    ready: true,
    supportsProgressionJump: true,
    position: position('c1', progression: progression),
  );

  ReaderOpen pdfAt(int page, {int? pages = 200}) => ReaderOpen(
    book: sampleBook(format: PublicationFormat.pdf),
    toc: const [],
    ready: true,
    supportsProgressionJump: true,
    pageCount: pages,
    position: position('p', progression: 0, page: page),
  );

  Future<void> pump(
    WidgetTester tester,
    ReaderOpen state,
    Future<bool> Function(double) onJump,
  ) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: ReaderScrubber(state: state, onJump: onJump),
        ),
      ),
    ),
  );

  test('the thumb follows the current location', () {
    expect(ReaderScrubber.currentValue(epubAt(0.25)), 0.25);
    expect(ReaderScrubber.currentValue(pdfAt(1)), 0);
    expect(ReaderScrubber.currentValue(pdfAt(200)), 1);
    // PDF without a page count falls back to the engine's progression.
    expect(ReaderScrubber.currentValue(pdfAt(5, pages: null)), 0);
  });

  test('labels say where a value would open', () {
    expect(ReaderScrubber.labelFor(epubAt(0), 0.456), '46%');
    expect(ReaderScrubber.labelFor(pdfAt(1), 0.5), 'Page 101 of 200');
    expect(ReaderScrubber.labelFor(pdfAt(1, pages: null), 0.5), '50%');
  });

  testWidgets('nothing is shown before the first position', (tester) async {
    await pump(
      tester,
      ReaderOpen(book: sampleBook(), toc: const [], ready: true),
      (_) async => true,
    );
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('a drag jumps once, on release, and is announced', (
    tester,
  ) async {
    final jumps = <double>[];
    await pump(tester, pdfAt(1), (value) async {
      jumps.add(value);
      return true;
    });

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(
      slider.semanticFormatterCallback!(slider.value),
      'Position in book, Page 1 of 200',
    );
    await tester.drag(find.byType(Slider), const Offset(2000, 0));
    await tester.pump();
    expect(jumps, [1.0]);
    // Held at the target until the engine reports the new position.
    expect(tester.widget<Slider>(find.byType(Slider)).value, 1.0);
  });

  testWidgets('a failed jump puts the thumb back', (tester) async {
    final result = Completer<bool>();
    await pump(tester, epubAt(0.2), (_) => result.future);

    await tester.drag(find.byType(Slider), const Offset(2000, 0));
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 1.0);

    result.complete(false);
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0.2);
  });

  testWidgets('a new position releases the held target', (tester) async {
    await pump(tester, epubAt(0.2), (_) async => true);
    await tester.drag(find.byType(Slider), const Offset(2000, 0));
    await tester.pump();

    await pump(tester, epubAt(0.8), (_) async => true);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0.8);
  });
}
