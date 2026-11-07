/// Descriptive metadata read from a publication file during import.
final class PublicationDetails {
  const PublicationDetails({
    this.title,
    this.authors = const [],
    this.description,
    this.language,
    this.identifier,
    this.publisher,
    this.publishedAt,
    this.coverFilePath,
  });

  /// Null or blank when the publication does not declare a title.
  final String? title;
  final List<String> authors;
  final String? description;
  final String? language;
  final String? identifier;
  final String? publisher;
  final String? publishedAt;

  /// Absolute path of the extracted cover image, when one was extracted.
  final String? coverFilePath;
}

/// Reads metadata (and, where supported, the cover) from a publication file.
/// Implemented by the reader-engine adapter; the domain never sees plugin
/// types.
abstract interface class PublicationInspector {
  /// Inspects the publication at [publicationPath]. A cover, if extracted,
  /// is written inside [coverDirectory].
  ///
  /// Throws `PublicationError` when the file is not a readable publication.
  /// Failing to extract a cover is not an error.
  Future<PublicationDetails> inspect(
    String publicationPath, {
    required String coverDirectory,
  });
}
