import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thaal/app/theme/app_theme.dart';

/// Pumps [child] inside a [MaterialApp] using the app theme.
Future<void> pumpThemed(WidgetTester tester, Widget child, {ThemeData? theme}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Scaffold(body: child),
    ),
  );
}
