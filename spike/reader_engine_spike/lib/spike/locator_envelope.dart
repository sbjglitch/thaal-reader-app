/// App-owned, versioned wrapper around an opaque reader-engine locator.
///
/// Mirrors the envelope in READER_ENGINE_SPECIFICATION.md §9.2. The spike
/// uses it to prove that a plugin locator survives a JSON round trip and can
/// be rejected safely when malformed or written by an unknown version.
library;

import 'dart:convert';

enum EnvelopeFormat { epub, pdf }

class LocatorEnvelope {
  const LocatorEnvelope({
    required this.format,
    required this.locator,
    this.engineLocatorVersion,
  });

  static const int currentSchemaVersion = 1;
  static const String engineName = 'readium';

  final EnvelopeFormat format;

  /// The plugin's `Locator.toJson()` output, kept verbatim.
  final Map<String, dynamic> locator;
  final String? engineLocatorVersion;

  Map<String, dynamic> toJson() => {
    'schemaVersion': currentSchemaVersion,
    'engine': engineName,
    'engineLocatorVersion': engineLocatorVersion,
    'format': format.name,
    'locator': locator,
  };

  String encode() => jsonEncode(toJson());

  /// Returns null instead of throwing for any input that cannot be trusted,
  /// so callers fall back to opening at the start of the publication.
  static LocatorEnvelope? tryDecode(
    String? raw, {
    required EnvelopeFormat expectedFormat,
  }) {
    if (raw == null || raw.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['schemaVersion'] != currentSchemaVersion) return null;
    if (decoded['engine'] != engineName) return null;
    if (decoded['format'] != expectedFormat.name) return null;
    final locator = decoded['locator'];
    if (locator is! Map<String, dynamic>) return null;
    final href = locator['href'];
    if (href is! String || href.isEmpty) return null;
    final version = decoded['engineLocatorVersion'];
    return LocatorEnvelope(
      format: expectedFormat,
      locator: locator,
      engineLocatorVersion: version is String ? version : null,
    );
  }
}
