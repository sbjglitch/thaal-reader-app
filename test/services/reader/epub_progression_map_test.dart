import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/services/reader/epub_progression_map.dart';
import 'package:thaal/services/reader/publication_reader.dart';

Matcher isAt(int index, double progression) =>
    isA<({int index, double progression})>()
        .having((r) => r.index, 'index', index)
        .having(
          (r) => r.progression,
          'progression',
          closeTo(progression, 1e-9),
        );

void main() {
  group('resolve', () {
    // Positions per resource: 1, 3 and 1 (Readium: ceil(bytes / 1024)).
    final map = EpubProgressionMap([10, 3000, 1024]);

    test('the start and end of the book', () {
      expect(map.resolve(0), (index: 0, progression: 0.0));
      expect(map.resolve(1), (index: 2, progression: 1.0));
    });

    test('each resource covers a share in proportion to its positions', () {
      // 5 positions in all: the first resource is 0–0.2, the second 0.2–0.8.
      expect(map.resolve(0.1), isAt(0, 0.5));
      expect(map.resolve(0.2), isAt(1, 0.0));
      expect(map.resolve(0.5), isAt(1, 0.5));
      expect(map.resolve(0.9), isAt(2, 0.5));
    });

    test('out-of-range and invalid values are clamped', () {
      expect(map.resolve(-1).index, 0);
      expect(map.resolve(7), (index: 2, progression: 1.0));
      expect(map.resolve(double.nan), (index: 0, progression: 0.0));
    });

    test('an empty resource still counts as one position', () {
      final single = EpubProgressionMap([0]);
      expect(single.resolve(0.5), (index: 0, progression: 0.5));
    });
  });

  test('hrefs map to ZIP entry names', () {
    expect(EpubProgressionMap.zipPathFor('OEBPS/c1.xhtml'), 'OEBPS/c1.xhtml');
    expect(EpubProgressionMap.zipPathFor('/OEBPS/c1.xhtml'), 'OEBPS/c1.xhtml');
    expect(
      EpubProgressionMap.zipPathFor('OEBPS/c1.xhtml#s2'),
      'OEBPS/c1.xhtml',
    );
    expect(
      EpubProgressionMap.zipPathFor('OEBPS/chapter%20one.xhtml'),
      'OEBPS/chapter one.xhtml',
    );
  });

  group('fromFile', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('thaal_progression_');
    });
    tearDown(() async => dir.delete(recursive: true));

    String writeEpub(Map<String, (String, bool)> entries) {
      final archive = Archive();
      for (final MapEntry(key: name, value: (text, compress))
          in entries.entries) {
        final file = ArchiveFile.bytes(name, utf8.encode(text))
          ..compression = compress
              ? CompressionType.deflate
              : CompressionType.none;
        archive.add(file);
      }
      final path = '${dir.path}/book.epub';
      File(path).writeAsBytesSync(ZipEncoder().encode(archive));
      return path;
    }

    test(
      'weights compressed entries by their stored size, as Readium does',
      () {
        // 8 KB of repeated text compresses to well under 1 KB: one position.
        final repeated = 'Synthetic text. ' * 512;
        final varied = List.generate(700, (i) => '${i * 7919 % 10007} ').join();
        final path = writeEpub({
          'mimetype': ('application/epub+zip', false),
          'OEBPS/a.xhtml': (repeated, true),
          'OEBPS/b.xhtml': (varied, false),
        });

        final map = EpubProgressionMap.fromFile(path, [
          'OEBPS/a.xhtml',
          'OEBPS/b.xhtml',
        ])!;
        expect(map.resourceCount, 2);
        // a: 1 position; b: stored, so its full length counts.
        final bPositions = (utf8.encode(varied).length / 1024).ceil();
        expect(map.resolve(1 / (1 + bPositions)), isAt(1, 0));
      },
    );

    test('a missing resource or unreadable file gives no map', () {
      final path = writeEpub({'OEBPS/a.xhtml': ('text', true)});
      expect(
        EpubProgressionMap.fromFile(path, ['OEBPS/missing.xhtml']),
        isNull,
      );
      expect(EpubProgressionMap.fromFile(path, const []), isNull);

      final notZip = File('${dir.path}/not.epub')..writeAsStringSync('nope');
      expect(EpubProgressionMap.fromFile(notZip.path, ['a']), isNull);
      expect(
        EpubProgressionMap.fromFile('${dir.path}/gone.epub', ['a']),
        isNull,
      );
    });
  });

  group('PDF pages', () {
    test('progression maps to pages with the navigator rounding', () {
      expect(pdfPageForProgression(0, 2000), 1);
      expect(pdfPageForProgression(1, 2000), 2000);
      expect(pdfPageForProgression(0.5, 2000), 1001);
      expect(pdfPageForProgression(0.5, 1), 1);
      expect(pdfPageForProgression(double.nan, 10), 1);
    });

    test('a page maps back to itself', () {
      for (final page in [1, 2, 999, 1387, 2000]) {
        expect(
          pdfPageForProgression(pdfProgressionForPage(page, 2000), 2000),
          page,
        );
      }
      expect(pdfProgressionForPage(1, 1), 0);
    });
  });
}
