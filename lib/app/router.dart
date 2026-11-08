import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/app_error_state.dart';
import '../features/bookmarks/presentation/bookmarks_screen.dart';
import '../features/collections/presentation/collections_screen.dart';
import '../features/library/presentation/book_details_screen.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/reader/application/reader_controller.dart';
import '../features/reader/presentation/reader_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import 'app_shell.dart';

/// Central route names and paths (ADR-006). Routes that need data take stable
/// identifiers such as a book ID, never domain objects.
abstract final class AppRoutes {
  static const library = (name: 'library', path: '/library');
  static const collections = (name: 'collections', path: '/collections');
  static const bookmarks = (name: 'bookmarks', path: '/bookmarks');
  static const settings = (name: 'settings', path: '/settings');

  /// Book details, nested under the library so back returns to it.
  static const bookDetails = (name: 'bookDetails', path: 'books/:bookId');

  /// Full-screen reader, outside the bottom-navigation shell (UI/UX §6.1).
  static const reader = (name: 'reader', path: '/reader/:bookId');

  /// Opens [bookId] at its saved position, or at [bookmarkId] when given.
  static String readerLocation(String bookId, {String? bookmarkId}) => Uri(
    path: '/reader/$bookId',
    queryParameters: bookmarkId == null ? null : {'bookmark': bookmarkId},
  ).toString();

  static String bookDetailsLocation(String bookId) =>
      '${library.path}/books/${Uri.encodeComponent(bookId)}';

  static const initialLocation = '/library';
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.initialLocation,
    routes: [
      GoRoute(
        name: AppRoutes.reader.name,
        path: AppRoutes.reader.path,
        builder: (context, state) => ReaderScreen(
          request: ReaderRequest(
            state.pathParameters['bookId']!,
            bookmarkId: state.uri.queryParameters['bookmark'],
          ),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          _branch(
            AppRoutes.library,
            (_) => const LibraryScreen(),
            routes: [
              GoRoute(
                name: AppRoutes.bookDetails.name,
                path: AppRoutes.bookDetails.path,
                builder: (context, state) =>
                    BookDetailsScreen(bookId: state.pathParameters['bookId']!),
              ),
            ],
          ),
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
  WidgetBuilder screen, {
  List<RouteBase> routes = const [],
}) {
  return StatefulShellBranch(
    routes: [
      GoRoute(
        name: route.name,
        path: route.path,
        builder: (context, state) => screen(context),
        routes: routes,
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
