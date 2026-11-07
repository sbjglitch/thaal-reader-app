import 'package:flutter/material.dart' show Color, Colors;
import 'package:flutter_readium/flutter_readium.dart' hide PublicationFormat;
import 'package:flutter_test/flutter_test.dart';
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
}
