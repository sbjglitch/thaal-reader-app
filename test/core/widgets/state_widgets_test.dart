import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thaal/app/theme/app_theme.dart';
import 'package:thaal/core/widgets/app_empty_state.dart';
import 'package:thaal/core/widgets/app_error_state.dart';
import 'package:thaal/core/widgets/app_loading_indicator.dart';

import '../../support/pump_app.dart';

void main() {
  group('AppEmptyState', () {
    testWidgets('shows title and message without an action by default', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        const AppEmptyState(
          icon: Icons.book,
          title: 'Nothing here',
          message: 'Explanation',
        ),
      );

      expect(find.text('Nothing here'), findsOneWidget);
      expect(find.text('Explanation'), findsOneWidget);
      expect(find.byType(ButtonStyleButton), findsNothing);
    });

    testWidgets('shows the single next action when given', (tester) async {
      await pumpThemed(
        tester,
        AppEmptyState(
          icon: Icons.book,
          title: 'Nothing here',
          message: 'Explanation',
          action: FilledButton(onPressed: () {}, child: const Text('Do it')),
        ),
      );

      expect(find.widgetWithText(FilledButton, 'Do it'), findsOneWidget);
    });

    testWidgets('renders in the dark theme', (tester) async {
      await pumpThemed(
        tester,
        const AppEmptyState(icon: Icons.book, title: 'T', message: 'M'),
        theme: AppTheme.dark,
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('AppErrorState', () {
    testWidgets('hides retry without a callback', (tester) async {
      await pumpThemed(
        tester,
        const AppErrorState(title: 'Failed', message: 'Try later'),
      );

      expect(find.text('Failed'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('invokes retry', (tester) async {
      var retries = 0;
      await pumpThemed(
        tester,
        AppErrorState(
          title: 'Failed',
          message: 'Try later',
          onRetry: () => retries++,
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));

      expect(retries, 1);
    });
  });

  testWidgets('AppLoadingIndicator exposes an accessible label', (
    tester,
  ) async {
    await pumpThemed(tester, const AppLoadingIndicator());

    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
  });
}
