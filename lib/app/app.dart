import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/application/app_theme_controller.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class ThaalApp extends ConsumerWidget {
  const ThaalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Thaal',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeModeFor(ref.watch(appThemeProvider)),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
