import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/core/errors/app_errors.dart';
import 'package:thaal/domain/entities/enums.dart';
import 'package:thaal/domain/entities/managed_path.dart';
import 'package:thaal/services/storage/library_storage.dart';

Matcher throwsStorageError(StorageErrorKind kind) =>
    throwsA(isA<StorageError>().having((e) => e.kind, 'kind', kind));

void main() {
  late Directory temp;
  late Directory root;
  late LibraryStorage storage;
  late File source;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('thaal_storage');
    root = Directory('${temp.path}/library');
    storage = await LibraryStorage.open(root);
    source = File('${temp.path}/user-book.epub');
    await source.writeAsString('abc');
  });
  tearDown(() => temp.delete(recursive: true));

  test('creates the books and staging directories', () async {
    expect(await Directory('${root.path}/books').exists(), isTrue);
    expect(await Directory('${root.path}/staging').exists(), isTrue);
  });

  test('stages, hashes and promotes without touching the source', () async {
    final area = await storage.createStagingArea();
    final staged = await storage.copyIntoStaging(source, area, 'upload.epub');

    expect(
      await storage.sha256Hex(staged),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(await storage.fileSize(staged), 3);

    final target = storage.publicationPath('book-1', PublicationFormat.epub);
    expect(target.value, 'books/book-1/publication.epub');
    await storage.promote(staged, target);
    await storage.discardStagingArea(area);

    expect(await storage.exists(target), isTrue);
    expect(await storage.exists(staged), isFalse);
    expect(await source.readAsString(), 'abc');
    expect(await Directory('${root.path}/${area.value}').exists(), isFalse);
  });

  test('promote refuses to overwrite an existing publication', () async {
    final target = storage.publicationPath('book-1', PublicationFormat.pdf);
    for (var i = 0; i < 2; i++) {
      final area = await storage.createStagingArea();
      final staged = await storage.copyIntoStaging(source, area, 'f.pdf');
      if (i == 0) {
        await storage.promote(staged, target);
      } else {
        expect(
          storage.promote(staged, target),
          throwsStorageError(StorageErrorKind.ioFailure),
        );
      }
    }
  });

  test('a failed copy leaves no staged file', () async {
    final area = await storage.createStagingArea();
    await expectLater(
      storage.copyIntoStaging(
        File('${temp.path}/missing.epub'),
        area,
        'x.epub',
      ),
      throwsStorageError(StorageErrorKind.ioFailure),
    );
    expect(
      await Directory('${root.path}/${area.value}').list().toList(),
      isEmpty,
    );
  });

  test('rejects operations outside their designated directories', () async {
    final area = await storage.createStagingArea();
    final staged = await storage.copyIntoStaging(source, area, 'a.epub');
    expect(
      storage.promote(staged, ManagedPath.parse('staging/elsewhere.epub')),
      throwsStorageError(StorageErrorKind.unsafePath),
    );
    expect(
      storage.copyIntoStaging(source, ManagedPath.parse('books'), 'a.epub'),
      throwsStorageError(StorageErrorKind.unsafePath),
    );
    expect(
      storage.discardStagingArea(LibraryStorage.stagingDir),
      throwsStorageError(StorageErrorKind.unsafePath),
    );
    expect(
      () => storage.copyIntoStaging(source, area, '../escape.epub'),
      throwsFormatException,
    );
  });

  test('missing files are reported, not thrown', () async {
    final path = storage.publicationPath('gone', PublicationFormat.epub);
    expect(await storage.exists(path), isFalse);
    expect(await storage.fileSize(path), isNull);
  });

  test('deleteBookFiles removes only that book and is idempotent', () async {
    for (final id in ['keep', 'drop']) {
      final area = await storage.createStagingArea();
      final staged = await storage.copyIntoStaging(source, area, 'f.epub');
      await storage.promote(
        staged,
        storage.publicationPath(id, PublicationFormat.epub),
      );
    }

    await storage.deleteBookFiles('drop');
    await storage.deleteBookFiles('drop');

    expect(
      await storage.exists(
        storage.publicationPath('keep', PublicationFormat.epub),
      ),
      isTrue,
    );
    expect(await Directory('${root.path}/books/drop').exists(), isFalse);
  });

  test('startup cleanup removes every staging entry', () async {
    final area = await storage.createStagingArea();
    await storage.copyIntoStaging(source, area, 'partial.epub');
    await storage.createStagingArea();

    final cleanup = await storage.clearStaging();
    expect((cleanup.removed, cleanup.failed), (2, 0));
    expect(await Directory('${root.path}/staging').list().toList(), isEmpty);
    expect(await Directory('${root.path}/books').exists(), isTrue);
  });
}
