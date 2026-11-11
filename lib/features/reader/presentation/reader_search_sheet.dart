import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_spacing_tokens.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_error_state.dart';
import '../../../services/reader/publication_reader.dart';
import '../application/reader_controller.dart';

/// Searches the open book and returns the chosen result
/// (READER_ENGINE_SPECIFICATION.md §12). The search runs when the query is
/// submitted, not on every keystroke, because the engine searches the whole
/// book each time. The last search is kept with the reader session.
Future<ReaderSearchResult?> showReaderSearchSheet(
  BuildContext context, {
  required ReaderRequest request,
}) => showModalBottomSheet<ReaderSearchResult>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => ReaderSearchSheet(request: request),
);

class ReaderSearchSheet extends ConsumerStatefulWidget {
  const ReaderSearchSheet({super.key, required this.request});

  final ReaderRequest request;

  @override
  ConsumerState<ReaderSearchSheet> createState() => _ReaderSearchSheetState();
}

class _ReaderSearchSheetState extends ConsumerState<ReaderSearchSheet> {
  late final TextEditingController _query;

  ReaderSearch _searchOf(ReaderState state) =>
      state is ReaderOpen ? state.search : const ReaderSearchIdle();

  @override
  void initState() {
    super.initState();
    final previous = _searchOf(
      ref.read(readerControllerProvider(widget.request)),
    );
    _query = TextEditingController(
      text: switch (previous) {
        ReaderSearchIdle() => '',
        ReaderSearchRunning(:final query) ||
        ReaderSearchDone(:final query) ||
        ReaderSearchFailed(:final query) => query,
      },
    );
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  ReaderController get _controller =>
      ref.read(readerControllerProvider(widget.request).notifier);

  void _submit() => _controller.search(_query.text);

  void _clear() {
    _query.clear();
    _controller.search('');
  }

  @override
  Widget build(BuildContext context) {
    final search = _searchOf(
      ref.watch(readerControllerProvider(widget.request)),
    );
    final text = Theme.of(context).textTheme;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: FractionallySizedBox(
        heightFactor: 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenEdge,
                0,
                AppSpacing.screenEdge,
                AppSpacing.space8,
              ),
              child: Text('Search in book', style: text.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenEdge,
              ),
              child: ListenableBuilder(
                listenable: _query,
                builder: (context, _) => TextField(
                  controller: _query,
                  autofocus: search is ReaderSearchIdle,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: 'Find words in this book',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close),
                            onPressed: _clear,
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.space8),
            if (search is ReaderSearchRunning)
              const LinearProgressIndicator(semanticsLabel: 'Searching')
            else
              const SizedBox(height: 4),
            Expanded(
              child: _Results(search: search, onRetry: _submit),
            ),
          ],
        ),
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.search, required this.onRetry});

  final ReaderSearch search;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // States sit in a list so they scroll rather than overflow when the
    // keyboard leaves little room.
    Widget state(Widget child) => ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space16),
      children: [child],
    );
    return switch (search) {
      ReaderSearchIdle() => const SizedBox.shrink(),
      // The previous results are not kept while a new search runs, so a
      // tap cannot open a result of the old query.
      ReaderSearchRunning() => const SizedBox.shrink(),
      ReaderSearchFailed() => state(
        AppErrorState(
          title: 'Search did not work',
          message: 'The book has not been changed. Try again.',
          onRetry: onRetry,
        ),
      ),
      ReaderSearchDone(:final query, :final results) when results.isEmpty =>
        state(
          AppEmptyState(
            icon: Icons.search_off,
            title: 'No matches',
            message: 'Nothing in this book matches “$query”.',
          ),
        ),
      ReaderSearchDone(:final results) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenEdge,
              AppSpacing.space8,
              AppSpacing.screenEdge,
              AppSpacing.space4,
            ),
            child: Semantics(
              liveRegion: true,
              child: Text(
                results.length == 1 ? '1 match' : '${results.length} matches',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, index) =>
                  SearchResultTile(result: results[index]),
            ),
          ),
        ],
      ),
    };
  }
}

/// One match: the surrounding text with the match in bold, and the
/// chapter it is in.
class SearchResultTile extends StatelessWidget {
  const SearchResultTile({super.key, required this.result});

  final ReaderSearchResult result;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final chapter = result.chapterTitle;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenEdge,
      ),
      title: Text.rich(
        TextSpan(
          children: [
            if (leadingContext(result.before) case final before
                when before.isNotEmpty)
              TextSpan(text: '…$before'),
            TextSpan(
              text: result.match,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (result.after.isNotEmpty) TextSpan(text: '${result.after}…'),
          ],
        ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: text.bodyMedium,
      ),
      subtitle: chapter == null
          ? null
          : Text(chapter, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => Navigator.of(context).pop(result),
    );
  }
}

/// The end of [before], cut at a word boundary to about [maxLength]
/// characters, so the match itself stays within the tile's lines.
String leadingContext(String before, {int maxLength = 40}) {
  if (before.length <= maxLength) return before;
  final start = before.length - maxLength;
  final tail = before.substring(start);
  // Already at a word start: nothing to trim.
  if (before[start - 1] == ' ') return tail;
  final space = tail.indexOf(' ');
  return space < 0 || space == tail.length - 1
      ? tail
      : tail.substring(space + 1);
}
