import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/core/errors/app_errors.dart';
import 'package:thaal/core/logging/app_logger.dart';
import 'package:thaal/domain/entities/enums.dart';
import 'package:thaal/domain/entities/locator_envelope.dart';
import 'package:thaal/domain/entities/reading_data.dart';
import 'package:thaal/domain/repositories/reading_progress_repository.dart';
import 'package:thaal/features/reader/application/progress_saver.dart';
import 'package:thaal/services/reader/publication_reader.dart';

import '../../support/fixtures.dart';

class RecordingProgressRepository implements ReadingProgressRepository {
  final saved = <ReadingProgress>[];
  int failuresLeft = 0;

  @override
  Future<void> saveProgress(ReadingProgress progress) async {
    if (failuresLeft > 0) {
      failuresLeft--;
      throw const DatabaseError(DatabaseErrorKind.failure, 'fake');
    }
    saved.add(progress);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ReaderPosition position(String href, {double? progression, int? page}) =>
    ReaderPosition(
      locator: LocatorEnvelope(
        format: PublicationFormat.epub,
        locator: {'href': href, 'type': 'application/xhtml+xml'},
      ),
      progression: progression,
      pageNumber: page,
    );

void main() {
  late RecordingProgressRepository repository;
  late ProgressSaver saver;

  setUp(() {
    repository = RecordingProgressRepository();
    saver = ProgressSaver(
      bookId: 'book-1',
      repository: repository,
      logger: AppLogger(sink: (_) {}),
      clock: () => fixedTime,
      debounce: const Duration(milliseconds: 20),
    );
  });
  tearDown(() => saver.dispose());

  String href(ReadingProgress progress) =>
      progress.locator!.decode(PublicationFormat.epub)!.locator['href']!
          as String;

  test('debounces bursts and writes only the latest position', () async {
    saver
      ..update(position('a'))
      ..update(position('b'))
      ..update(position('c', progression: 0.4, page: 3));
    expect(repository.saved, isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(repository.saved, hasLength(1));
    final saved = repository.saved.single;
    expect(href(saved), 'c');
    expect(saved.progression, 0.4);
    expect(saved.pageNumber, 3);
    expect(saved.updatedAt, fixedTime);
  });

  test('flush writes immediately and is a no-op without changes', () async {
    saver.update(position('a'));
    await saver.flush();
    await saver.flush();
    expect(repository.saved.map(href), ['a']);
    expect(saver.hasPending, isFalse);
  });

  test('a failed write is retried on the next flush', () async {
    repository.failuresLeft = 1;
    saver.update(position('a'));
    await saver.flush();
    expect(repository.saved, isEmpty);
    expect(saver.hasPending, isTrue);

    await saver.flush();
    expect(repository.saved.map(href), ['a']);
  });

  test('a newer position wins over a failed older one', () async {
    repository.failuresLeft = 1;
    saver.update(position('old'));
    final failing = saver.flush();
    saver.update(position('new'));
    await failing;
    await saver.flush();
    expect(repository.saved.map(href), ['new']);
  });
}
