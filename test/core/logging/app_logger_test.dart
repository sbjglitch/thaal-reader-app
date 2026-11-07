import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:thaal/core/logging/app_logger.dart';

enum _Format { epub }

void main() {
  late List<LogRecord> records;
  late AppLogger logger;

  setUp(() {
    records = [];
    logger = AppLogger(sink: records.add, minimumLevel: LogLevel.debug);
  });

  group('sanitize', () {
    test('keeps primitives, enums and durations', () {
      expect(AppLogger.sanitize(3), 3);
      expect(AppLogger.sanitize(true), true);
      expect(AppLogger.sanitize(null), isNull);
      expect(AppLogger.sanitize(_Format.epub), 'epub');
      expect(AppLogger.sanitize(const Duration(seconds: 2)), '2000ms');
      expect(AppLogger.sanitize('book-42'), 'book-42');
    });

    test('redacts paths and URIs', () {
      expect(
        AppLogger.sanitize('/data/user/0/app/books/a.epub'),
        '<redacted-path>',
      );
      expect(AppLogger.sanitize(r'C:\Users\me\a.pdf'), '<redacted-path>');
      expect(AppLogger.sanitize('content://media/doc/12'), '<redacted-path>');
      expect(AppLogger.sanitize('file:a.epub'), '<redacted-path>');
    });

    test('redacts long text', () {
      final prose = 'word ' * 20;
      expect(AppLogger.sanitize(prose), '<redacted-text>');
    });

    test('records other objects by type only', () {
      expect(AppLogger.sanitize(<String>['secret']), isNot(contains('secret')));
      expect(AppLogger.sanitize(Object()), '<Object>');
    });
  });

  test('records errors by type, never by message', () {
    logger.error(
      'import.failed',
      const FileSystemException('cannot open', '/private/book.epub'),
      fields: {'bookId': 'b1', 'path': '/private/book.epub'},
    );

    final record = records.single;
    expect(record.level, LogLevel.error);
    expect(record.errorType, 'FileSystemException');
    expect(record.fields, {'bookId': 'b1', 'path': '<redacted-path>'});
    expect(record.toString(), isNot(contains('/private')));
    expect(record.toString(), isNot(contains('cannot open')));
  });

  test('drops records below the minimum level', () {
    final quiet = AppLogger(sink: records.add, minimumLevel: LogLevel.warning);

    quiet.debug('a');
    quiet.info('b');
    quiet.warning('c');

    expect(records.map((r) => r.event), ['c']);
  });
}
