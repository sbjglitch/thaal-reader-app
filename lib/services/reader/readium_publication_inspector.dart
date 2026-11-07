import 'dart:io';

import 'package:flutter_readium/flutter_readium.dart';
import 'package:path/path.dart' as p;

import '../../core/errors/app_errors.dart';
import '../../domain/services/publication_inspector.dart';

/// [PublicationInspector] backed by `flutter_readium` 0.9.0.
///
/// Metadata comes from `loadPublication`, which does not open the
/// publication for reading. The plugin can only resolve a resource (the
/// cover) for the *open* publication, so cover extraction briefly opens and
/// then closes it. That would replace an open reader session's publication,
/// so the cover is skipped while [_readerIsOpen] reports a session.
class ReadiumPublicationInspector implements PublicationInspector {
  ReadiumPublicationInspector(this._readium, {required this._readerIsOpen});

  final FlutterReadium _readium;
  final bool Function() _readerIsOpen;

  static const Map<String, String> _coverExtensions = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
    'image/gif': 'gif',
  };

  @override
  Future<PublicationDetails> inspect(
    String publicationPath, {
    required String coverDirectory,
  }) async {
    final url = Uri.file(publicationPath).toString();
    final Publication publication;
    try {
      publication = await _readium.loadPublication(url);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        const PublicationError(
          PublicationErrorKind.unreadable,
          'loadPublication failed',
        ),
        stackTrace,
      );
    }

    final metadata = publication.metadata;
    return PublicationDetails(
      title: metadata.title,
      authors: [
        for (final author in metadata.authors)
          if (author.name?.trim() case final name? when name.isNotEmpty) name,
      ],
      description: _nonBlank(metadata.description),
      language: metadata.languages.isEmpty ? null : metadata.languages.first,
      identifier: _nonBlank(metadata.identifier),
      publisher: metadata.publishers.isEmpty
          ? null
          : _nonBlank(metadata.publishers.first.name),
      publishedAt: metadata.published?.toIso8601String().substring(0, 10),
      coverFilePath: await _extractCover(publication, url, coverDirectory),
    );
  }

  /// Best effort: any failure yields no cover rather than a failed import.
  Future<String?> _extractCover(
    Publication publication,
    String url,
    String coverDirectory,
  ) async {
    final link = publication.coverLink;
    final extension = _coverExtensions[link?.type];
    if (link == null || extension == null || _readerIsOpen()) return null;

    var opened = false;
    try {
      await _readium.openPublication(url);
      opened = true;
      final resourceUrl = Uri.parse(await _readium.getResourceUrl(link.href));
      if (resourceUrl.scheme != 'file') return null;
      final target = p.join(coverDirectory, 'cover.$extension');
      await File.fromUri(resourceUrl).copy(target);
      return target;
    } catch (_) {
      return null;
    } finally {
      if (opened) {
        try {
          await _readium.closePublication();
        } catch (_) {
          // Nothing else to release; the next open replaces the publication.
        }
      }
    }
  }

  static String? _nonBlank(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
