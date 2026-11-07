import 'dart:convert';

import 'package:flutter_readium/flutter_readium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_engine_spike/spike/locator_envelope.dart';

void main() {
  final pluginLocator = Locator.fromJson({
    'href': 'OEBPS/chapter2.xhtml',
    'type': 'application/xhtml+xml',
    'title': 'Chapter 2',
    'locations': {'progression': 0.25, 'totalProgression': 0.4, 'position': 7},
  })!;

  LocatorEnvelope? decode(
    Object? raw, {
    EnvelopeFormat format = EnvelopeFormat.epub,
  }) => LocatorEnvelope.tryDecode(
    raw is String? ? raw : jsonEncode(raw),
    expectedFormat: format,
  );

  test('plugin locator survives an envelope round trip unchanged', () {
    final encoded = LocatorEnvelope(
      format: EnvelopeFormat.epub,
      locator: pluginLocator.toJson(),
    ).encode();

    final decoded = decode(encoded);

    expect(decoded, isNotNull);
    expect(Locator.fromJson(decoded!.locator), pluginLocator);
  });

  test('rejects malformed, mismatched and unknown-version envelopes', () {
    final valid = LocatorEnvelope(
      format: EnvelopeFormat.epub,
      locator: pluginLocator.toJson(),
    ).toJson();

    expect(decode(null), isNull);
    expect(decode('{not json'), isNull);
    expect(decode('[]'), isNull);
    expect(decode(valid, format: EnvelopeFormat.pdf), isNull);
    expect(decode({...valid, 'schemaVersion': 2}), isNull);
    expect(decode({...valid, 'engine': 'other'}), isNull);
    expect(
      decode({
        ...valid,
        'locator': {'type': 'application/xhtml+xml'},
      }),
      isNull,
    );
  });
}
