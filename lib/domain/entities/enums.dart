/// Enums with stable serialized values. The [wireName] values are persisted
/// in SQLite and backups, so they must never change; renaming a Dart
/// identifier is safe as long as its wire name stays the same.
library;

/// Implemented by enums persisted by a stable string value.
abstract interface class WireEnum {
  String get wireName;
}

/// Looks up the value of [values] whose [WireEnum.wireName] is [wireName].
/// Throws [FormatException] for unknown input.
T parseWireEnum<T extends WireEnum>(List<T> values, String wireName) {
  for (final value in values) {
    if (value.wireName == wireName) return value;
  }
  throw FormatException('Unknown $T value', wireName);
}

enum PublicationFormat implements WireEnum {
  epub('epub'),
  pdf('pdf');

  const PublicationFormat(this.wireName);

  @override
  final String wireName;
}

enum ReadingStatus implements WireEnum {
  unread('unread'),
  reading('reading'),
  finished('finished');

  const ReadingStatus(this.wireName);

  @override
  final String wireName;
}

/// App-owned highlight colours, independent of any theme palette
/// (DATABASE_SCHEMA.md §5.4).
enum HighlightColor implements WireEnum {
  yellow('yellow'),
  green('green'),
  blue('blue'),
  pink('pink');

  const HighlightColor(this.wireName);

  @override
  final String wireName;
}
