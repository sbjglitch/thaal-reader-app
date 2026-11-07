import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/app_error_state.dart';
import '../features/bookmarks/presentation/bookmarks_screen.dart';
import '../features/collections/presentation/collections_screen.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import 'app_shell.dart';

/// Central route names and paths (ADR-006). Routes that need data take stable
/// identifiers such as a book ID, never domain objects.
abstract final class AppRoutes {
  static const library = (name: 'library', path: '/library');
  static const collections = (name: 'collections', path: '/collections');
  static const bookmarks = (name: 'bookmarks', path: '/bookmarks');
  static const settings = (name: 'settings', path: '/settings');

  static const initialLocation = '/library';
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.initialLocation,
    routes: [
      // The reader will be a full-screen route outside this shell: it is
      // opened from a book, not a bottom-navigation destination (UI/UX §6.1).
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          _branch(AppRoutes.library, (_) => const LibraryScreen()),
          _branch(AppRoutes.collections, (_) => const CollectionsScreen()),
          _branch(AppRoutes.bookmarks, (_) => const BookmarksScreen()),
          _branch(AppRoutes.settings, (_) => const SettingsScreen()),
        ],
      ),
    ],
    errorBuilder: (context, state) => const _RouteNotFoundScreen(),
  );
  ref.onDispose(router.dispose);
  return router;
});

StatefulShellBranch _branch(
  ({String name, String path}) route,
  WidgetBuilder screen,
) {
  return StatefulShellBranch(
    routes: [
      GoRoute(
        name: route.name,
        path: route.path,
        builder: (context, state) => screen(context),
      ),
    ],
  );
}

class _RouteNotFoundScreen extends StatelessWidget {
  const _RouteNotFoundScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: AppErrorState(
        title: 'Page not found',
        message: 'This screen does not exist.',
        retryLabel: 'Go to library',
        onRetry: () => context.go(AppRoutes.library.path),
      ),
    );
  }
}
