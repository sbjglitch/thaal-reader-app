import 'dart:convert';

import 'enums.dart';

/// App-owned, versioned wrapper around an opaque reader-engine locator
/// (READER_ENGINE_SPECIFICATION.md §9.2, DATABASE_SCHEMA.md §9).
///
/// [locator] holds the engine's serialized locator verbatim. The domain does
/// not interpret it beyond the minimal shape check in [tryDecode]; unknown
/// fields are preserved on round trips.
final class LocatorEnvelope {
  const LocatorEnvelope({
    required this.format,
    required this.locator,
    this.engine = readiumEngine,
    this.engineLocatorVersion,
  });

  /// Version of this envelope shape. Independent of the database schema
  /// version and the backup format version.
  static const int currentSchemaVersion = 1;
  static const String readiumEngine = 'readium';

  final PublicationFormat format;
  final String engine;
  final String? engineLocatorVersion;
  final Map<String, Object?> locator;

  Map<String, Object?> toJson() => {
    'schemaVersion': currentSchemaVersion,
    'engine': engine,
    'engineLocatorVersion': engineLocatorVersion,
    'format': format.wireName,
    'locator': locator,
  };

  String encode() => jsonEncode(toJson());

  /// Decodes [raw], returning null for anything that cannot be trusted:
  /// malformed JSON, an unknown envelope version or engine, a format other
  /// than [expectedFormat], or a locator without a non-empty `href`.
  ///
  /// Callers keep the stored value when this returns null, so a newer app
  /// version can still migrate it (DATABASE_SCHEMA.md §9).
  static LocatorEnvelope? tryDecode(
    String? raw, {
    required PublicationFormat expectedFormat,
  }) {
    if (raw == null || raw.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    if (decoded['schemaVersion'] != currentSchemaVersion) return null;
    if (decoded['engine'] != readiumEngine) return null;
    if (decoded['format'] != expectedFormat.wireName) return null;
    final locator = decoded['locator'];
    if (locator is! Map<String, Object?>) return null;
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

/// A persisted locator, kept as the exact JSON text that was stored.
///
/// Entities carry this rather than a decoded [LocatorEnvelope] so a value
/// that this app version cannot decode (for example, one written by a newer
/// version) is still preserved instead of being dropped.
final class SerializedLocator {
  /// Wraps text read back from storage without validating it.
  const SerializedLocator.stored(this.json);

  SerializedLocator.fromEnvelope(LocatorEnvelope envelope)
    : json = envelope.encode();

  final String json;

  /// The decoded envelope, or null when it cannot be trusted.
  LocatorEnvelope? decode(PublicationFormat expectedFormat) =>
      LocatorEnvelope.tryDecode(json, expectedFormat: expectedFormat);

  @override
  bool operator ==(Object other) =>
      other is SerializedLocator && other.json == json;

  @override
  int get hashCode => json.hashCode;
}
