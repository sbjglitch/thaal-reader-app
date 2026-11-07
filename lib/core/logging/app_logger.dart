import 'package:flutter/foundation.dart';

/// Severity of a [LogRecord].
enum LogLevel { debug, info, warning, error }

/// A sanitised, structured log entry.
@immutable
class LogRecord {
  const LogRecord({
    required this.level,
    required this.event,
    required this.fields,
    this.errorType,
    this.stackTrace,
  });

  final LogLevel level;

  /// A fixed, code-defined event name such as `bootstrap.started`.
  final String event;

  /// Sanitised diagnostic fields; see [AppLogger] for the rules.
  final Map<String, Object?> fields;

  /// The runtime type of a reported error. The error's message is never
  /// recorded because exception text can carry file paths or content.
  final String? errorType;

  final StackTrace? stackTrace;

  @override
  String toString() {
    final buffer = StringBuffer('THAAL ${level.name} $event');
    if (errorType != null) buffer.write(' error=$errorType');
    fields.forEach((key, value) => buffer.write(' $key=$value'));
    return buffer.toString();
  }
}

/// Receives records that pass the logger's level filter.
typedef LogSink = void Function(LogRecord record);

/// Local-only diagnostic logger.
///
/// Privacy rules (CLAUDE.md §7, TECHNICAL_ARCHITECTURE.md §9): logs must not
/// contain publication contents, selected text, notes or full local paths.
/// The logger enforces what it can mechanically:
///
/// - Errors are recorded by type only, never by message.
/// - Field strings that look like paths or URIs are replaced with
///   `<redacted-path>`.
/// - Field strings longer than [maxFieldLength] are replaced with
///   `<redacted-text>` so prose cannot slip through.
/// - Only primitives, enums and durations are kept; other objects are
///   recorded by type.
///
/// Callers must still choose fields deliberately: identifiers, counts,
/// formats and states — not user content. Nothing is sent off the device.
class AppLogger {
  AppLogger({LogSink? sink, LogLevel? minimumLevel})
    : _sink = sink ?? _debugPrintSink,
      minimumLevel =
          minimumLevel ?? (kDebugMode ? LogLevel.debug : LogLevel.warning);

  static const int maxFieldLength = 64;
  static final RegExp _pathLike = RegExp(r'[/\\]|^[a-zA-Z][\w+.-]*:');

  final LogSink _sink;
  final LogLevel minimumLevel;

  void debug(String event, {Map<String, Object?> fields = const {}}) =>
      _log(LogLevel.debug, event, fields);

  void info(String event, {Map<String, Object?> fields = const {}}) =>
      _log(LogLevel.info, event, fields);

  void warning(
    String event, {
    Object? error,
    Map<String, Object?> fields = const {},
  }) => _log(LogLevel.warning, event, fields, error: error);

  void error(
    String event,
    Object error, {
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) =>
      _log(LogLevel.error, event, fields, error: error, stackTrace: stackTrace);

  void _log(
    LogLevel level,
    String event,
    Map<String, Object?> fields, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.index < minimumLevel.index) return;
    _sink(
      LogRecord(
        level: level,
        event: event,
        fields: {
          for (final MapEntry(:key, :value) in fields.entries)
            key: sanitize(value),
        },
        errorType: error?.runtimeType.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  /// Reduces [value] to something safe to log. Visible for testing.
  @visibleForTesting
  static Object? sanitize(Object? value) {
    return switch (value) {
      null || num() || bool() => value,
      Enum() => value.name,
      Duration() => '${value.inMilliseconds}ms',
      String() when _pathLike.hasMatch(value) => '<redacted-path>',
      String() when value.length > maxFieldLength => '<redacted-text>',
      String() => value,
      _ => '<${value.runtimeType}>',
    };
  }

  static void _debugPrintSink(LogRecord record) {
    debugPrint(record.toString());
    if (kDebugMode && record.stackTrace != null) {
      debugPrint(record.stackTrace.toString());
    }
  }
}
