import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_logger.dart';

/// App-wide logger. Bootstrap overrides this with the instance it uses for
/// global error handlers, so there is a single logger per app run.
final appLoggerProvider = Provider<AppLogger>((ref) => AppLogger());
