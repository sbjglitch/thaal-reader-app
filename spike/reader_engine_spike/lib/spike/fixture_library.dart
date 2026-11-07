import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'locator_envelope.dart';

class Fixture {
  const Fixture({
    required this.id,
    required this.label,
    required this.asset,
    required this.format,
  });

  final String id;
  final String label;
  final String asset;
  final EnvelopeFormat format;

  String get fileName => asset.split('/').last;
}

const fixtures = [
  Fixture(
    id: 'epub2',
    label: 'EPUB 2 sample',
    asset: 'assets/fixtures/spike_epub2.epub',
    format: EnvelopeFormat.epub,
  ),
  Fixture(
    id: 'epub3',
    label: 'EPUB 3 sample (nested TOC, links)',
    asset: 'assets/fixtures/spike_epub3.epub',
    format: EnvelopeFormat.epub,
  ),
  Fixture(
    id: 'pdf',
    label: 'PDF sample (mixed page sizes)',
    asset: 'assets/fixtures/spike_pdf.pdf',
    format: EnvelopeFormat.pdf,
  ),
  Fixture(
    id: 'corrupt',
    label: 'Corrupt EPUB (error handling)',
    asset: 'assets/fixtures/corrupt.epub',
    format: EnvelopeFormat.epub,
  ),
];

/// Copies bundled fixtures into app-private storage, standing in for the
/// import pipeline so the reader always opens an app-owned local copy.
class FixtureLibrary {
  FixtureLibrary(this.root);

  final Directory root;

  static Future<FixtureLibrary> prepare() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory('${support.path}/spike_library');
    await root.create(recursive: true);
    final library = FixtureLibrary(root);
    for (final fixture in fixtures) {
      final target = library.fileFor(fixture);
      if (await target.exists()) continue;
      // Fixtures are a few KB, so loading them whole is fine here; the real
      // import pipeline must stream large files instead.
      final bytes = await rootBundle.load(fixture.asset);
      final temp = File('${target.path}.part');
      await temp.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await temp.rename(target.path);
    }
    return library;
  }

  File fileFor(Fixture fixture) => File('${root.path}/${fixture.fileName}');
}
