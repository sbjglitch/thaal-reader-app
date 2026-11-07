import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_color_tokens.dart';
import '../../../app/theme/app_spacing_tokens.dart';
import '../../../core/widgets/app_error_state.dart';
import '../../../core/widgets/app_loading_indicator.dart';
import '../../../domain/entities/enums.dart';
import '../../../services/reader/publication_reader.dart';
import '../application/reader_controller.dart';
import 'reader_settings_sheet.dart';
import 'toc_sheet.dart';

/// Full-screen reader (UI/UX §7.3–7.4, READER_ENGINE_SPECIFICATION.md §13).
/// The engine view fills the screen; a tap in the middle of the page shows
/// or hides the top and bottom controls.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final _controlsVisible = ValueNotifier<bool>(true);
  Widget? _view;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The "system" reading theme follows the device's light/dark setting.
    final brightness = MediaQuery.platformBrightnessOf(context);
    final controller = ref.read(
      readerControllerProvider(widget.bookId).notifier,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.setPlatformBrightness(brightness);
    });
  }

  @override
  void dispose() {
    _controlsVisible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = readerControllerProvider(widget.bookId);
    final state = ref.watch(provider);
    ref.listen(provider, (previous, next) {
      if (next is ReaderOpen && next.restoreFailed && previous is! ReaderOpen) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your place could not be restored, so the book opened at the '
              'beginning.',
            ),
          ),
        );
      }
    });

    return Scaffold(
      body: switch (state) {
        ReaderOpening() => const _PlainFrame(child: AppLoadingIndicator()),
        ReaderUnavailable(:final problem) => _PlainFrame(
          child: _ProblemView(
            problem: problem,
            onRetry: () => ref.invalidate(provider),
          ),
        ),
        ReaderOpen() => _buildOpen(state),
      },
    );
  }

  Widget _buildOpen(ReaderOpen state) {
    // The engine view is created once per session; rebuilding it would
    // reload the publication.
    final view = _view ??= ref
        .read(publicationReaderProvider)
        .buildView(
          initialLocator: state.initialLocator,
          controlsVisible: _controlsVisible,
          loading: const AppLoadingIndicator(),
        );
    final controller = ref.read(
      readerControllerProvider(widget.bookId).notifier,
    );

    return ValueListenableBuilder<bool>(
      valueListenable: _controlsVisible,
      builder: (context, visible, child) => Stack(
        children: [
          Positioned.fill(child: SafeArea(child: child!)),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _Chrome(
              visible: visible,
              slideFrom: const Offset(0, -1),
              child: _TopBar(
                state: state,
                onContents: state.toc.isEmpty
                    ? null
                    : () => _showToc(state.toc, controller),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _Chrome(
              visible: visible,
              slideFrom: const Offset(0, 1),
              child: _BottomBar(
                state: state,
                onPrevious: controller.goBackward,
                onNext: controller.goForward,
                onSettings: () => showReaderSettingsSheet(
                  context,
                  bookId: widget.bookId,
                  format: state.book.format,
                ),
              ),
            ),
          ),
        ],
      ),
      child: view,
    );
  }

  Future<void> _showToc(List<TocEntry> toc, ReaderController controller) async {
    final entry = await showTocSheet(context, toc);
    if (entry == null || !mounted) return;
    final found = await controller.goToTocEntry(entry);
    if (!found && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That section could not be opened.')),
      );
    }
  }
}

/// Scaffold body for states without the engine view.
class _PlainFrame extends StatelessWidget {
  const _PlainFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppBar(),
        Expanded(child: child),
      ],
    );
  }
}

/// Slides and fades reader controls. Hidden controls ignore input and are
/// removed from the accessibility tree.
class _Chrome extends StatelessWidget {
  const _Chrome({
    required this.visible,
    required this.slideFrom,
    required this.child,
  });

  final bool visible;
  final Offset slideFrom;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const duration = Duration(milliseconds: 180);
    return IgnorePointer(
      ignoring: !visible,
      child: ExcludeSemantics(
        excluding: !visible,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : slideFrom,
          duration: duration,
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: duration,
            child: Material(
              color: context.colorTokens.surfaceElevated,
              elevation: 1,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.state, required this.onContents});

  final ReaderOpen state;
  final VoidCallback? onContents;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final chapter = state.position?.chapterTitle;
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            const BackButton(),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.book.title,
                    style: text.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (chapter != null && chapter.trim().isNotEmpty)
                    Text(
                      chapter,
                      style: text.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // Shown only when the publication has a table of contents.
            if (onContents != null)
              IconButton(
                tooltip: 'Contents',
                icon: const Icon(Icons.toc),
                onPressed: onContents,
              ),
            const SizedBox(width: AppSpacing.space4),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.state,
    required this.onPrevious,
    required this.onNext,
    required this.onSettings,
  });

  final ReaderOpen state;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final label = readerProgressLabel(state);
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Previous page',
              icon: const Icon(Icons.chevron_left),
              onPressed: state.ready ? onPrevious : null,
            ),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Next page',
              icon: const Icon(Icons.chevron_right),
              onPressed: state.ready ? onNext : null,
            ),
            IconButton(
              tooltip: 'Reading settings',
              icon: const Icon(Icons.text_fields),
              onPressed: state.ready ? onSettings : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// "Page 3" for PDF, "34%" for EPUB, empty until the first position.
/// EPUB page counts depend on font and screen, so only progression is shown
/// (spec §9.5: approximate display value).
String readerProgressLabel(ReaderOpen state) {
  final position = state.position;
  if (position == null) return '';
  if (state.book.format == PublicationFormat.pdf) {
    final page = position.pageNumber;
    if (page != null) return 'Page $page';
  }
  final progression = position.progression;
  if (progression == null) return '';
  return '${(progression * 100).round()}%';
}

class _ProblemView extends StatelessWidget {
  const _ProblemView({required this.problem, required this.onRetry});

  final ReaderProblem problem;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    void back() => Navigator.of(context).maybePop();
    final (title, message) = switch (problem) {
      ReaderProblem.bookNotFound => (
        'Book not found',
        'This book is no longer in your library.',
      ),
      ReaderProblem.missingFile => (
        'The book file is missing',
        'Its file is no longer in the app. You can remove the book and import '
            'the file again.',
      ),
      ReaderProblem.unreadable => (
        'This book could not be opened',
        'The file may be damaged. Your library and reading data have not been '
            'changed.',
      ),
      ReaderProblem.unsupported => (
        'This book is not supported',
        'Thaal can open EPUB and PDF files without DRM protection.',
      ),
      ReaderProblem.failed => (
        'Something went wrong',
        'The book could not be shown. Your reading position has been kept.',
      ),
    };
    final canRetry = problem == ReaderProblem.failed;
    return AppErrorState(
      title: title,
      message: message,
      retryLabel: canRetry ? 'Try again' : 'Back to library',
      onRetry: canRetry ? onRetry : back,
    );
  }
}
