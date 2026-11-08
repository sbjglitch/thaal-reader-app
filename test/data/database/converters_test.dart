import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/data/database/converters.dart';
import 'package:thaal/domain/entities/enums.dart';

void main() {
  const authors = AuthorsConverter();

  test('authors round-trip as a JSON string array', () {
    final sql = authors.toSql(['Ada', 'Grace "Amazing" Hopper']);
    expect(authors.fromSql(sql), ['Ada', 'Grace "Amazing" Hopper']);
    expect(authors.fromSql('[]'), isEmpty);
  });

  test('authors reject non-array or non-string JSON', () {
    expect(() => authors.fromSql('{"a":1}'), throwsFormatException);
    expect(() => authors.fromSql('[1]'), throwsFormatException);
  });

  test('enum converters use stable wire names', () {
    expect(publicationFormatConverter.toSql(PublicationFormat.pdf), 'pdf');
    expect(readingStatusConverter.fromSql('reading'), ReadingStatus.reading);
    expect(highlightColorConverter.toSql(HighlightColor.pink), 'pink');
    expect(
      () => readingStatusConverter.fromSql('READING'),
      throwsFormatException,
    );
  });
}
