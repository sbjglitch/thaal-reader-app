import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thaal/domain/entities/enums.dart';
import 'package:thaal/domain/entities/locator_envelope.dart';

void main() {
  final locator = <String, Object?>{
    'href': 'chapter2.xhtml',
    'type': 'application/xhtml+xml',
    'locations': {'progression': 0.5, 'position': 12},
    'text': {'highlight': 'x'},
    'futureField': [1, 2, 3],
  };

  test('round-trips and preserves unknown locator fields', () {
    final encoded = LocatorEnvelope(
      format: PublicationFormat.epub,
      locator: locator,
      engineLocatorVersion: '3.4.0',
    ).encode();

    final decoded = LocatorEnvelope.tryDecode(
      encoded,
      expectedFormat: PublicationFormat.epub,
    )!;

    expect(decoded.locator, locator);
    expect(decoded.engineLocatorVersion, '3.4.0');
    expect(jsonDecode(encoded), containsPair('schemaVersion', 1));
    expect(jsonDecode(encoded), containsPair('engine', 'readium'));
  });

  test('rejects untrusted input', () {
    String envelope(Map<String, Object?> changes) => jsonEncode({
      'schemaVersion': 1,
      'engine': 'readium',
      'format': 'epub',
      'locator': locator,
      ...changes,
    });

    for (final raw in [
      null,
      '',
      'not json',
      '[]',
      envelope({'schemaVersion': 2}),
      envelope({'engine': 'other'}),
      envelope({'format': 'pdf'}),
      envelope({'locator': 'x'}),
      envelope({
        'locator': {'href': ''},
      }),
    ]) {
      expect(
        LocatorEnvelope.tryDecode(raw, expectedFormat: PublicationFormat.epub),
        isNull,
        reason: '$raw',
      );
    }
  });

  test('SerializedLocator keeps undecodable text intact', () {
    const stored = SerializedLocator.stored('{"schemaVersion":99}');
    expect(stored.json, '{"schemaVersion":99}');
    expect(stored.decode(PublicationFormat.epub), isNull);
  });
}
