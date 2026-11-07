import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/domain/entities/book.dart';
import 'package:thaal/domain/entities/enums.dart';
import 'package:thaal/domain/entities/managed_path.dart';
import 'package:thaal/domain/entities/reading_data.dart';

import '../../support/fixtures.dart';

void main() {
  Book book({
    String title = 'T',
    int size = 1,
    String checksum = sampleChecksum,
  }) => Book(
    id: 'b',
    title: title,
    format: PublicationFormat.pdf,
    filePath: ManagedPath.parse('books/b/publication.pdf'),
    fileSizeBytes: size,
    fileChecksum: checksum,
    addedAt: fixedTime,
    updatedAt: fixedTime,
  );

  test('book title is trimmed and must not be empty', () {
    expect(book(title: '  Title  ').title, 'Title');
    expect(() => book(title: '   '), throwsArgumentError);
  });

  test('book requires a positive size and a lowercase SHA-256 digest', () {
    expect(() => book(size: 0), throwsArgumentError);
    expect(() => book(checksum: 'abc'), throwsArgumentError);
    expect(
      () => book(checksum: sampleChecksum.toUpperCase()),
      throwsArgumentError,
    );
  });

  test('progress validates progression and page number', () {
    ReadingProgress progress({double? progression, int? page}) =>
        ReadingProgress(
          bookId: 'b',
          progression: progression,
          pageNumber: page,
          updatedAt: fixedTime,
        );

    expect(progress(progression: 0).progression, 0);
    expect(progress(progression: 1).progression, 1);
    expect(() => progress(progression: -0.01), throwsArgumentError);
    expect(() => progress(progression: 1.01), throwsArgumentError);
    expect(() => progress(progression: double.nan), throwsArgumentError);
    expect(() => progress(page: 0), throwsArgumentError);
  });

  test('collection name is trimmed and must not be empty', () {
    Collection collection(String name) => Collection(
      id: 'c',
      name: name,
      createdAt: fixedTime,
      updatedAt: fixedTime,
    );
    expect(collection(' Favourites ').name, 'Favourites');
    expect(() => collection(''), throwsArgumentError);
  });

  test('wire enums parse their stable names and reject unknown ones', () {
    expect(
      parseWireEnum(ReadingStatus.values, 'finished'),
      ReadingStatus.finished,
    );
    expect(
      () => parseWireEnum(PublicationFormat.values, 'mobi'),
      throwsFormatException,
    );
  });
}
