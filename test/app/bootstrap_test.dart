import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thaal/app/bootstrap.dart';
import 'package:thaal/core/logging/app_logger.dart';

void main() {
  late List<LogRecord> records;
  late FlutterExceptionHandler? onError;

  setUp(() {
    final originalOnError = FlutterError.onError;
    final originalPresent = FlutterError.presentError;
    final originalPlatformOnError = PlatformDispatcher.instance.onError;
    addTearDown(() {
      FlutterError.onError = originalOnError;
      FlutterError.presentError = originalPresent;
      PlatformDispatcher.instance.onError = originalPlatformOnError;
    });
    // Keep the deliberate test errors out of the console.
    FlutterError.presentError = (_) {};

    records = [];
    installErrorHandlers(AppLogger(sink: records.add));
    onError = FlutterError.onError;
  });

  test('framework errors are logged by type only', () {
    onError!(FlutterErrorDetails(exception: StateError('secret note text')));

    final record = records.single;
    expect(record.event, 'flutter.framework_error');
    expect(record.errorType, 'StateError');
    expect(record.toString(), isNot(contains('secret')));
  });

  test('uncaught platform errors are logged and marked handled', () {
    final handled = PlatformDispatcher.instance.onError!(
      ArgumentError('/private/path.epub'),
      StackTrace.empty,
    );

    expect(handled, isTrue);
    expect(records.single.event, 'platform.uncaught_error');
    expect(records.single.toString(), isNot(contains('/private')));
  });
}
