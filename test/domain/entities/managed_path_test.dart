import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/domain/entities/managed_path.dart';

void main() {
  test('accepts simple relative paths', () {
    final path = ManagedPath.parse('books/abc-123/publication.epub');
    expect(path.segments, ['books', 'abc-123', 'publication.epub']);
    expect(path.value, 'books/abc-123/publication.epub');
  });

  for (final unsafe in [
    '',
    '/books/a.epub',
    'books//a.epub',
    'books/../secret',
    '../a',
    'books/./a',
    r'books\a.epub',
    'C:/a.epub',
    'books/a b.epub',
    'books/a.epub/',
    'books/\u0000',
  ]) {
    test('rejects unsafe path "$unsafe"', () {
      expect(() => ManagedPath.parse(unsafe), throwsFormatException);
      expect(ManagedPath.tryParse(unsafe), isNull);
    });
  }

  test('isWithin compares whole segments', () {
    final books = ManagedPath.parse('books');
    expect(ManagedPath.parse('books/x/y').isWithin(books), isTrue);
    expect(books.isWithin(books), isTrue);
    expect(ManagedPath.parse('booksx/y').isWithin(books), isFalse);
    expect(ManagedPath.parse('staging/books').isWithin(books), isFalse);
  });

  test('equality is by value', () {
    expect(ManagedPath.parse('a/b'), ManagedPath.join(['a', 'b']));
  });
}
