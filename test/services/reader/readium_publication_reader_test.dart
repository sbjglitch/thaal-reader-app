import 'package:flutter/material.dart' show Color, Colors, TextAlign;
import 'package:flutter_readium/flutter_readium.dart' hide PublicationFormat;
import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/app/theme/highlight_colors.dart';
import 'package:thaal/domain/entities/enums.dart';
import 'package:thaal/domain/entities/locator_envelope.dart';
import 'package:thaal/domain/entities/reader_preferences.dart';
import 'package:thaal/services/reader/publication_reader.dart';
import 'package:thaal/services/reader/readium_publication_reader.dart';

void main() {
  group('positionFrom', () {
    test('wraps the EPUB locator verbatim and keeps no page number', () {
      const locator = Locator(
        href: 'chapter2.xhtml',
        type: 'application/xhtml+xml',
        title: 'Chapter 2',
        locations: Locations(
          position: 7,
          progression: 0.5,
          totalProgression: 0.42,
          cssSelector: '#p3',
        ),
      );

      final position = ReadiumPublicationReader.positionFrom(
        locator,
        PublicationFormat.epub,
      );

      expect(position.progression, 0.42);
      expect(position.pageNumber, isNull);
      expect(position.chapterTitle, 'Chapter 2');
      expect(position.locator.format, PublicationFormat.epub);
      expect(position.locator.locator, locator.toJson());

      // Round trip through the stored envelope and back to the engine type.
      final decoded = LocatorEnvelope.tryDecode(
        position.locator.encode(),
        expectedFormat: PublicationFormat.epub,
      )!;
      expect(Locator.fromJson(decoded.locator)!.toJson(), locator.toJson());
    });

    test('PDF position is the page number', () {
      const locator = Locator(
        href: 'publication.pdf',
        type: 'application/pdf',
        locations: Locations(position: 12, totalProgression: 0.25),
      );
      final position = ReadiumPublicationReader.positionFrom(
        locator,
        PublicationFormat.pdf,
      );
      expect(position.pageNumber, 12);
      expect(position.progression, 0.25);
    });

    test('falls back to chapter progression and tolerates none', () {
      expect(
        ReadiumPublicationReader.positionFrom(
          const Locator(
            href: 'a.xhtml',
            type: 'application/xhtml+xml',
            locations: Locations(progression: 0.3),
          ),
          PublicationFormat.epub,
        ).progression,
        0.3,
      );
      final bare = ReadiumPublicationReader.positionFrom(
        const Locator(href: 'a.xhtml', type: 'application/xhtml+xml'),
        PublicationFormat.epub,
      );
      expect(bare.progression, isNull);
      expect(bare.pageNumber, isNull);
    });
  });

  test('maps engine errors to app failures by code only', () {
    ReaderFailure map(String? code) => ReadiumPublicationReader.mapReadiumError(
      ReadiumError('/data/user/0/secret/path failed', code: code),
    );

    expect(map('readingError').kind, ReaderFailureKind.unreadable);
    expect(map('formatNotSupported').kind, ReaderFailureKind.unsupported);
    expect(map('forbidden').kind, ReaderFailureKind.unsupported);
    expect(map('somethingNew').kind, ReaderFailureKind.engine);
    expect(map(null).kind, ReaderFailureKind.engine);
    expect(map('readingError').toString(), isNot(contains('secret')));
  });

  test('flattens the table of contents in plugin order with depth', () {
    const toc = [
      Link(
        href: 'part1.xhtml',
        title: 'Part 1',
        children: [
          Link(href: 'c1.xhtml', title: 'Chapter 1'),
          Link(href: 'c2.xhtml', title: '  '),
        ],
      ),
      Link(href: 'part2.xhtml', title: 'Part 2'),
    ];

    final entries = ReadiumPublicationReader.tocEntriesFrom(toc);

    expect(
      [for (final e in entries) (e.index, e.title, e.depth)],
      [
        (0, 'Part 1', 0),
        (1, 'Chapter 1', 1),
        (2, 'Untitled section', 1),
        (3, 'Part 2', 0),
      ],
    );
    // Indexes must line up with the plugin's own flattening, which
    // goToTocEntry uses to find the link.
    final flattened = toc.flatten();
    expect(
      [for (final link in flattened) link.href],
      ['part1.xhtml', 'c1.xhtml', 'c2.xhtml', 'part2.xhtml'],
    );
  });

  group('preference mapping', () {
    ReaderAppearance appearance(ReaderPreferences preferences) =>
        ReaderAppearance(
          preferences: preferences,
          background: const Color(0xFF121416),
          foreground: Colors.white,
        );

    test('EPUB uses a font-size ratio, scroll flag and theme colours', () {
      final epub = ReadiumPublicationReader.epubPreferencesFrom(
        appearance(
          const ReaderPreferences(
            fontScale: 1.3,
            epubLayout: PageLayout.scroll,
          ),
        ),
      );
      expect(epub.fontSize, 1.3);
      expect(epub.scroll, isTrue);
      expect(epub.backgroundColor, const Color(0xFF121416));
      expect(epub.textColor, Colors.white);
    });

    test('EPUB margins pass through; alignment toggles publisher styles', () {
      EPUBPreferences epub(TextAlignment alignment) =>
          ReadiumPublicationReader.epubPreferencesFrom(
            appearance(
              ReaderPreferences(pageMargins: 1.5, textAlignment: alignment),
            ),
          );

      expect(epub(TextAlignment.original).pageMargins, 1.5);
      // Readium applies textAlign only with publisher styles off, so
      // "original" turns them back on.
      expect(epub(TextAlignment.original).publisherStyles, isTrue);
      expect(epub(TextAlignment.original).textAlign, isNull);
      expect(epub(TextAlignment.start).publisherStyles, isFalse);
      expect(epub(TextAlignment.start).textAlign, TextAlign.start);
      expect(epub(TextAlignment.justify).publisherStyles, isFalse);
      expect(epub(TextAlignment.justify).textAlign, TextAlign.justify);
    });

    test('EPUB fonts map to generic families; original sends none', () {
      String? family(FontFace face) =>
          ReadiumPublicationReader.epubPreferencesFrom(
            appearance(ReaderPreferences(fontFace: face)),
          ).fontFamily;

      // Each call replaces the engine's preferences, so null restores the
      // publication's own fonts.
      expect(family(FontFace.original), isNull);
      expect(family(FontFace.serif), 'serif');
      expect(family(FontFace.sansSerif), 'sans-serif');
    });

    test('PDF always sends the full set of layout and fit', () {
      final pdf = ReadiumPublicationReader.pdfPreferencesFrom(
        appearance(
          const ReaderPreferences(
            pdfLayout: PageLayout.scroll,
            pdfFit: PdfPageFit.page,
          ),
        ),
      );
      expect(pdf.layout, PDFLayout.scrollVertical);
      expect(pdf.fit, PDFFit.page);

      final defaults = ReadiumPublicationReader.pdfPreferencesFrom(
        appearance(const ReaderPreferences()),
      );
      expect(defaults.layout, PDFLayout.paginated);
      expect(defaults.fit, PDFFit.width);
    });
  });

  group('ReadiumLocatorInterpreter', () {
    const interpreter = ReadiumLocatorInterpreter();

    LocatorEnvelope epub(String href, double? progression) => LocatorEnvelope(
      format: PublicationFormat.epub,
      locator: Locator(
        href: href,
        type: 'application/xhtml+xml',
        title: 'Chapter',
        locations: Locations(progression: progression),
      ).toJson(),
    );

    LocatorEnvelope pdf(int page) => LocatorEnvelope(
      format: PublicationFormat.pdf,
      locator: Locator(
        href: 'publication.pdf',
        type: 'application/pdf',
        locations: Locations(position: page, progression: page / 100),
      ).toJson(),
    );

    test('describes a stored locator like a live position', () {
      final described = interpreter.describe(pdf(12));
      expect(described.pageNumber, 12);
      expect(interpreter.describe(epub('c1', 0.3)).chapterTitle, 'Chapter');
    });

    test('EPUB locations match by chapter and nearby progression', () {
      expect(
        interpreter.isSameLocation(epub('c1', 0.3), epub('c1', 0.3005)),
        isTrue,
      );
      expect(
        interpreter.isSameLocation(epub('c1', 0.3), epub('c1', 0.35)),
        isFalse,
      );
      expect(
        interpreter.isSameLocation(epub('c1', 0.3), epub('c2', 0.3)),
        isFalse,
      );
      expect(
        interpreter.isSameLocation(epub('c1', null), epub('c1', null)),
        isTrue,
      );
    });

    test('PDF locations match by page', () {
      expect(interpreter.isSameLocation(pdf(4), pdf(4)), isTrue);
      expect(interpreter.isSameLocation(pdf(4), pdf(5)), isFalse);
      expect(
        interpreter.isSameLocation(pdf(4), epub('publication.pdf', 0.04)),
        isFalse,
      );
    });

    test('an undecodable locator never matches', () {
      const broken = LocatorEnvelope(
        format: PublicationFormat.epub,
        locator: {'nothing': true},
      );
      expect(interpreter.isSameLocation(broken, broken), isFalse);
    });
  });

  group('search results', () {
    TextSearchResult result({
      String? before,
      String? highlight,
      String? after,
      String? chapterTitle,
      String? title,
    }) => TextSearchResult(
      chapterTitle: chapterTitle,
      locator: Locator(
        href: 'c2.xhtml',
        type: 'application/xhtml+xml',
        title: title,
        text: LocatorText(before: before, highlight: highlight, after: after),
      ),
    );

    test('carry the locator, the match and tidied context', () {
      final mapped = ReadiumPublicationReader.searchResultFrom(
        result(
          before: '  end of\n\n  one ',
          highlight: 'the  word',
          after: ' and\tmore  ',
          chapterTitle: ' Chapter 2 ',
        ),
      )!;
      expect(mapped.locator.format, PublicationFormat.epub);
      expect(mapped.locator.locator['href'], 'c2.xhtml');
      expect(mapped.before, 'end of one ');
      expect(mapped.match, 'the word');
      expect(mapped.after, ' and more');
      expect(mapped.chapterTitle, 'Chapter 2');
    });

    test("fall back to the locator's title", () {
      final mapped = ReadiumPublicationReader.searchResultFrom(
        result(highlight: 'word', title: 'Part one'),
      )!;
      expect(mapped.chapterTitle, 'Part one');
      expect(mapped.before, '');
      expect(mapped.after, '');
      expect(
        ReadiumPublicationReader.searchResultFrom(
          result(highlight: 'word', chapterTitle: '  '),
        )!.chapterTitle,
        isNull,
      );
    });

    test('without matched text are dropped', () {
      expect(ReadiumPublicationReader.searchResultFrom(result()), isNull);
      expect(
        ReadiumPublicationReader.searchResultFrom(result(highlight: ' \n ')),
        isNull,
      );
    });
  });

  group('highlights', () {
    test('maps selection actions by id', () {
      expect(
        ReadiumPublicationReader.textActionFor('thaal_highlight'),
        ReaderTextAction.highlight,
      );
      expect(
        ReadiumPublicationReader.textActionFor('thaal_note'),
        ReaderTextAction.note,
      );
      expect(ReadiumPublicationReader.textActionFor('copy'), isNull);
    });

    test('builds decorations from app records and skips unreadable ones', () {
      const locator = Locator(
        href: 'c1.xhtml',
        type: 'application/xhtml+xml',
        locations: Locations(progression: 0.2),
        text: LocatorText(highlight: 'word'),
      );
      final decorations = ReadiumPublicationReader.decorationsFrom([
        ReaderHighlight(
          id: 'hl-1',
          locator: LocatorEnvelope(
            format: PublicationFormat.epub,
            locator: locator.toJson(),
          ),
          color: HighlightColor.green,
        ),
        const ReaderHighlight(
          id: 'broken',
          locator: LocatorEnvelope(
            format: PublicationFormat.epub,
            locator: {'nothing': true},
          ),
          color: HighlightColor.yellow,
        ),
      ]);

      final decoration = decorations.single;
      expect(decoration.id, 'hl-1');
      expect(decoration.locator.toJson(), locator.toJson());
      expect(decoration.style.style, DecorationStyle.highlight);
      expect(decoration.style.tint, HighlightColor.green.tint);
    });

    test('every app colour has a distinct tint and a name', () {
      final tints = {for (final c in HighlightColor.values) c.tint};
      expect(tints, hasLength(HighlightColor.values.length));
      for (final color in HighlightColor.values) {
        expect(color.label, isNotEmpty);
      }
    });
  });
}
