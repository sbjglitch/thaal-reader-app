import 'package:flutter_readium/flutter_readium.dart';

/// App-wide plugin configuration, applied once at startup.
///
/// The plugin's native log level defaults to INFO, and its debug level logs
/// publication text (READER_ENGINE_SPIKE.md). Keep native logging to
/// warnings and errors.
Future<void> configureReadium(FlutterReadium readium) =>
    readium.setLogLevel(LogLevel.warn);
