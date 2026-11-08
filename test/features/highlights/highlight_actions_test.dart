import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/domain/entities/enums.dart';
import 'package:thaal/domain/entities/locator_envelope.dart';
import 'package:thaal/features/highlights/application/highlights.dart';

import '../../support/fixtures.dart';
import 'fake_highlights.dart';

void main() {
  late MemoryHighlightRepository repository;
  late HighlightActions actions;
  var now = fixedTime;

  const locator = LocatorEnvelope(
    format: PublicationFormat.epub,
    locator: {'href': 'c1.xhtml'},
  );

  setUp(() {
    repository = MemoryHighlightRepository();
    now = fixedTime;
    actions = HighlightActions(
      repository,
      clock: () => now,
      newId: () => 'hl-${repository.items.length + 1}',
    );
  });

  test('adds a yellow highlight with the trimmed selected text', () async {
    final highlight = await actions.add(
      'book-1',
      locator,
      selectedText: '  a passage \n',
    );
    expect(repository.items.single.id, 'hl-1');
    expect(highlight.selectedText, 'a passage');
    expect(highlight.color, HighlightColor.yellow);
    expect(highlight.note, isNull);
    expect(
      highlight.locator.decode(PublicationFormat.epub)?.locator['href'],
      'c1.xhtml',
    );
  });

  test('blank selected text is stored as none', () async {
    final highlight = await actions.add('book-1', locator, selectedText: ' ');
    expect(highlight.selectedText, isNull);
  });

  test(
    'update saves colour and note, keeping text and creation time',
    () async {
      final highlight = await actions.add('book-1', locator, selectedText: 'x');
      now = fixedTime.add(const Duration(minutes: 3));

      await actions.update(
        highlight,
        color: HighlightColor.blue,
        note: '  Remember this.  ',
      );
      final stored = repository.items.single;
      expect(stored.color, HighlightColor.blue);
      expect(stored.note, 'Remember this.');
      expect(stored.selectedText, 'x');
      expect(stored.createdAt, fixedTime);
      expect(stored.updatedAt, now);

      await actions.update(
        stored,
        color: HighlightColor.blue,
        note: 'n' * 6000,
      );
      expect(repository.items.single.note, hasLength(5000));

      await actions.update(stored, color: HighlightColor.pink, note: '   ');
      expect(repository.items.single.note, isNull);
    },
  );

  test('a deleted highlight can be restored with its note', () async {
    final added = await actions.add('book-1', locator);
    final withNote = await actions.update(
      added,
      color: HighlightColor.green,
      note: 'Keep',
    );
    await actions.delete(withNote);
    expect(repository.items, isEmpty);
    await actions.restore(withNote);
    expect(repository.items.single.note, 'Keep');
    expect(repository.items.single.id, added.id);
  });
}
