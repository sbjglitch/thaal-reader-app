/// A validated relative path inside the app-private library root, such as
/// `books/<book-id>/publication.epub`.
///
/// Stored in the database instead of absolute paths, which change between
/// installs and restores (ADR-008). Every segment must be non-empty, must not
/// be `.` or `..`, and may only contain ASCII letters, digits, `.`, `_` and
/// `-`; separators are always `/`. This rules out absolute paths, path
/// traversal, drive letters and backslashes by construction.
final class ManagedPath {
  ManagedPath._(this.segments);

  /// Parses [value], throwing [FormatException] when it is not a safe
  /// relative path.
  factory ManagedPath.parse(String value) {
    final segments = value.split('/');
    for (final segment in segments) {
      if (!_isSafeSegment(segment)) {
        throw FormatException('Unsafe managed path', value);
      }
    }
    return ManagedPath._(List.unmodifiable(segments));
  }

  /// Returns the parsed path, or null when [value] is not safe.
  static ManagedPath? tryParse(String value) {
    try {
      return ManagedPath.parse(value);
    } on FormatException {
      return null;
    }
  }

  /// Builds a path from [segments], validating each one.
  factory ManagedPath.join(List<String> segments) =>
      ManagedPath.parse(segments.join('/'));

  static final RegExp _segmentPattern = RegExp(r'^[A-Za-z0-9._-]+$');

  static bool _isSafeSegment(String segment) =>
      segment != '.' && segment != '..' && _segmentPattern.hasMatch(segment);

  final List<String> segments;

  String get value => segments.join('/');

  /// Whether this path is [other] or lies inside it.
  bool isWithin(ManagedPath other) {
    if (segments.length < other.segments.length) return false;
    for (var i = 0; i < other.segments.length; i++) {
      if (segments[i] != other.segments[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is ManagedPath && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
