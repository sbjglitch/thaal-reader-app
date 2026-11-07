import 'package:drift/native.dart';
import 'package:thaal/data/database/app_database.dart';
import 'package:thaal/domain/entities/book.dart';
import 'package:thaal/domain/entities/enums.dart';
import 'package:thaal/domain/entities/locator_envelope.dart';
import 'package:thaal/domain/entities/managed_path.dart';

/// A fresh in-memory database. Callers close it in tearDown.
AppDatabase openTestDatabase() => AppDatabase(NativeDatabase.memory());

final DateTime fixedTime = DateTime.utc(2026, 11, 7, 12);

const String sampleChecksum =
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

Book sampleBook({
  String id = 'book-1',
  String title = 'Sample Book',
  PublicationFormat format = PublicationFormat.epub,
  DateTime? addedAt,
}) {
  return Book(
    id: id,
    title: title,
    authors: const ['A. Author', 'B. Author'],
    format: format,
    filePath: ManagedPath.join(['books', id, 'publication.${format.wireName}']),
    fileSizeBytes: 1024,
    fileChecksum: sampleChecksum,
    addedAt: addedAt ?? fixedTime,
    updatedAt: addedAt ?? fixedTime,
  );
}

SerializedLocator sampleLocator({String href = 'chapter1.xhtml'}) {
  return SerializedLocator.fromEnvelope(
    LocatorEnvelope(
      format: PublicationFormat.epub,
      locator: {
        'href': href,
        'type': 'application/xhtml+xml',
        'locations': {'progression': 0.25},
      },
    ),
  );
}
