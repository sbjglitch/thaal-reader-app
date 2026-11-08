import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/entities/enums.dart';

/// Persists a [WireEnum] by its stable wire name. Unknown stored values throw
/// [FormatException]; the matching CHECK constraints keep them out of the
/// database in the first place.
class WireEnumConverter<T extends WireEnum> extends TypeConverter<T, String> {
  const WireEnumConverter(this.values);

  final List<T> values;

  @override
  T fromSql(String fromDb) => parseWireEnum(values, fromDb);

  @override
  String toSql(T value) => value.wireName;
}

const publicationFormatConverter = WireEnumConverter(PublicationFormat.values);
const readingStatusConverter = WireEnumConverter(ReadingStatus.values);
const highlightColorConverter = WireEnumConverter(HighlightColor.values);

/// `authors_json`: a JSON array of strings (DATABASE_SCHEMA.md §5.1).
class AuthorsConverter extends TypeConverter<List<String>, String> {
  const AuthorsConverter();

  @override
  List<String> fromSql(String fromDb) {
    final decoded = jsonDecode(fromDb);
    if (decoded is! List<Object?> || decoded.any((a) => a is! String)) {
      throw const FormatException('authors_json must be a JSON string array');
    }
    return List.unmodifiable(decoded.cast<String>());
  }

  @override
  String toSql(List<String> value) => jsonEncode(value);
}
