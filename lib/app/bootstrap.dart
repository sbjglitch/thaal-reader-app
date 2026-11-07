import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_logger.dart';
import 'app.dart';
import 'providers.dart';

/// Starts the app: installs global error handlers, then runs [ThaalApp]
/// inside the Riverpod scope. Database and storage initialisation join this
/// sequence in Milestone 2; nothing here touches the network.
void bootstrap() {
  WidgetsFlutterBinding.ensureInitialized();
  final logger = AppLogger();
  installErrorHandlers(logger);
  logger.info('bootstrap.started');
  runApp(
    ProviderScope(
      overrides: [appLoggerProvider.overrideWithValue(logger)],
      child: const ThaalApp(),
    ),
  );
}

/// Routes uncaught framework and platform errors to [logger], which records
/// them by type only. Release builds replace Flutter's grey error box with a
/// neutral message that exposes no exception text.
@visibleForTesting
void installErrorHandlers(AppLogger logger) {
  FlutterError.onError = (details) {
    logger.error(
      'flutter.framework_error',
      details.exception,
      stackTrace: details.stack,
    );
    // Developer builds keep Flutter's full diagnostic output.
    if (kDebugMode) FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    logger.error('platform.uncaught_error', error, stackTrace: stackTrace);
    return true;
  };
  if (!kDebugMode) {
    ErrorWidget.builder = (_) => const _RenderFailurePlaceholder();
  }
}

class _RenderFailurePlaceholder extends StatelessWidget {
  const _RenderFailurePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Something went wrong showing this part of the screen.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
