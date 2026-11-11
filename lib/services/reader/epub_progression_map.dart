import 'dart:math' as math;

import 'package:archive/archive_io.dart';

/// Maps a whole-book progression (0.0–1.0) to a chapter and a progression
/// within it, so the reader can jump anywhere in an EPUB.
///
/// flutter_readium 0.9.0 can only jump within the current chapter on Android
/// (`goToProgression` scrolls the open resource) and does not expose
/// Readium's positions list. Readium computes whole-book progression from
/// that list: one position per [bytesPerPosition] bytes of each reading-order
/// resource, at least one per resource, counting the compressed size of a
/// compressed ZIP entry. This map rebuilds the same weights from the EPUB's
/// ZIP directory, so the chapter a jump opens is the one the reported
/// progression points to. Within a chapter the jump is continuous, while
/// Readium reports whole positions, so the progress shown afterwards can be
/// up to one position lower than the jump target.
final class EpubProgressionMap {
  EpubProgressionMap(List<int> resourceBytes)
    : _positions = [
        for (final bytes in resourceBytes)
          math.max(1, (bytes / bytesPerPosition).ceil()),
      ] {
    _total = _positions.fold(0, (sum, count) => sum + count);
  }

  /// Readium's reflowable position length.
  static const bytesPerPosition = 1024;

  final List<int> _positions;
  late final int _total;

  /// Builds the map for the reading-order [hrefs] of the EPUB at [path],
  /// or returns null when the file cannot be read or a resource is not in
  /// it. Only the ZIP directory is read; nothing is decompressed.
  static EpubProgressionMap? fromFile(String path, List<String> hrefs) {
    if (hrefs.isEmpty) return null;
    InputFileStream? input;
    try {
      input = InputFileStream(path);
      final decoder = ZipDecoder()..decodeStream(input, throwOnError: true);
      // Readium's rule: the stored length, which for a compressed entry is
      // its compressed size.
      final sizes = {
        for (final header in decoder.directory.fileHeaders)
          header.filename: header.compressionMethod == 0
              ? header.uncompressedSize
              : header.compressedSize,
      };
      final bytes = <int>[];
      for (final href in hrefs) {
        final size = sizes[zipPathFor(href)];
        if (size == null) return null;
        bytes.add(size);
      }
      return EpubProgressionMap(bytes);
    } on Object {
      return null;
    } finally {
      input?.closeSync();
    }
  }

  /// The ZIP entry name for a reading-order [href]: relative to the
  /// container root, without a fragment, percent-decoded. Visible for tests.
  static String zipPathFor(String href) {
    final withoutFragment = href.split('#').first;
    final relative = withoutFragment.startsWith('/')
        ? withoutFragment.substring(1)
        : withoutFragment;
    try {
      return Uri.decodeComponent(relative);
    } on ArgumentError {
      return relative;
    }
  }

  int get resourceCount => _positions.length;

  /// The resource index and the progression within that resource for a
  /// whole-book [progression]: each resource covers a share of the book in
  /// proportion to its positions, and the point within it is continuous, so
  /// 1.0 is the end of the last resource.
  ({int index, double progression}) resolve(double progression) {
    final clamped = progression.isNaN ? 0.0 : progression.clamp(0.0, 1.0);
    final target = clamped * _total;
    var before = 0;
    for (var index = 0; index < _positions.length; index++) {
      final count = _positions[index];
      final isLast = index == _positions.length - 1;
      if (target < before + count || isLast) {
        final within = ((target - before) / count).clamp(0.0, 1.0);
        return (index: index, progression: within);
      }
      before += count;
    }
    throw StateError('unreachable: the map has at least one resource');
  }
}
