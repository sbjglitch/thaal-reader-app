import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thaal/app/app.dart';
import 'package:thaal/app/providers.dart';
import 'package:thaal/app/router.dart';
import 'package:thaal/features/library/application/library_items.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryItemsProvider.overrideWith((ref) => Stream.value(const [])),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
      child: const ThaalApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _title(String text) =>
    find.descendant(of: find.byType(AppBar), matching: find.text(text));

Finder _tab(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

void main() {
  testWidgets('starts on the library with four destinations', (tester) async {
    await _pumpApp(tester);

    expect(_title('Library'), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    for (final label in ['Library', 'Collections', 'Bookmarks', 'Settings']) {
      expect(_tab(label), findsOneWidget);
    }
  });

  testWidgets('switches between tabs', (tester) async {
    await _pumpApp(tester);

    for (final label in ['Collections', 'Bookmarks', 'Settings', 'Library']) {
      await tester.tap(_tab(label));
      await tester.pumpAndSettle();
      expect(_title(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('placeholder tabs offer no actions', (tester) async {
    await _pumpApp(tester);

    for (final label in ['Collections', 'Bookmarks', 'Settings']) {
      await tester.tap(_tab(label));
      await tester.pumpAndSettle();
      expect(find.byType(ButtonStyleButton), findsNothing, reason: label);
    }
  });

  testWidgets('unknown routes show a recoverable error', (tester) async {
    await _pumpApp(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ThaalApp)),
    );

    container.read(routerProvider).go('/does-not-exist');
    await tester.pumpAndSettle();
    expect(find.text('Page not found'), findsOneWidget);

    await tester.tap(find.text('Go to library'));
    await tester.pumpAndSettle();
    expect(_title('Library'), findsOneWidget);
  });
}
