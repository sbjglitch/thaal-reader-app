import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/logging/app_logger.dart';
import '../core/widgets/app_error_state.dart';
import '../data/database/app_database.dart';
import '../services/storage/library_storage.dart';
import 'app.dart';
import 'providers.dart';
import 'theme/app_theme.dart';

/// Starts the app: installs global error handlers, opens app-private storage
/// and the database, then runs [ThaalApp] inside the Riverpod scope.
/// Nothing here touches the network.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final logger = AppLogger();
  installErrorHandlers(logger);
  logger.info('bootstrap.started');

  final AppDatabase database;
  final LibraryStorage storage;
  try {
    final supportDirectory = await getApplicationSupportDirectory();
    storage = await LibraryStorage.open(
      Directory(p.join(supportDirectory.path, 'library')),
    );
    final cleanup = await storage.cleanUpStaging(now: DateTime.now());
    logger.info(
      'storage.staging_cleanup',
      fields: {
        'removed': cleanup.removed,
        'kept': cleanup.kept,
        'failed': cleanup.failed,
      },
    );
    database = AppDatabase.open(
      File(p.join(supportDirectory.path, databaseFileName)),
    );
    // Drift opens lazily; run a query now so creation and migrations happen
    // here, where a failure can be reported, rather than in the first screen.
    await database.customSelect('SELECT 1').get();
  } catch (error, stackTrace) {
    logger.error('bootstrap.failed', error, stackTrace: stackTrace);
    runApp(const _StartupFailureApp());
    return;
  }

  runApp(
    ProviderScope(
      overrides: [
        appLoggerProvider.overrideWithValue(logger),
        appDatabaseProvider.overrideWithValue(database),
        libraryStorageProvider.overrideWithValue(storage),
      ],
      child: const ThaalApp(),
    ),
  );
}

/// SQLite file name inside the application support directory.
const String databaseFileName = 'thaal.sqlite';

/// Shown when local storage cannot be opened. No data is modified.
class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const Scaffold(
        body: SafeArea(
          child: AppErrorState(
            title: 'Thaal could not start',
            message:
                'Local storage could not be opened. Close the app and try '
                'again. If this keeps happening, check that your device has '
                'free storage space.',
          ),
        ),
      ),
    );
  }
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
