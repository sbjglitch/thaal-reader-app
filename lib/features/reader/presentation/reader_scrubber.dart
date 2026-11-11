import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing_tokens.dart';
import '../../../domain/entities/enums.dart';
import '../../../services/reader/publication_reader.dart';
import '../application/reader_controller.dart';

/// Slider across the whole publication (UI/UX §7.3 "progress navigation
/// control"). While dragging it shows where the book will open, "Page 120"
/// for PDF or "45%" for EPUB, and jumps only when released, so the engine
/// is not asked to render every step.
class ReaderScrubber extends StatefulWidget {
  const ReaderScrubber({super.key, required this.state, required this.onJump});

  final ReaderOpen state;

  /// Called once, on release, with the chosen whole-book progression;
  /// completes with false when the jump failed.
  final Future<bool> Function(double progression) onJump;

  /// The thumb position for [state]'s current location, or null before the
  /// first position arrives.
  static double? currentValue(ReaderOpen state) {
    final position = state.position;
    if (position == null) return null;
    final pages = state.pageCount;
    final page = position.pageNumber;
    if (state.book.format == PublicationFormat.pdf &&
        pages != null &&
        page != null) {
      return pdfProgressionForPage(page, pages);
    }
    return position.progression?.clamp(0.0, 1.0);
  }

  /// What [value] would open, for the label and screen readers.
  static String labelFor(ReaderOpen state, double value) {
    final pages = state.pageCount;
    if (state.book.format == PublicationFormat.pdf && pages != null) {
      return 'Page ${pdfPageForProgression(value, pages)} of $pages';
    }
    return '${(value * 100).round()}%';
  }

  @override
  State<ReaderScrubber> createState() => _ReaderScrubberState();
}

class _ReaderScrubberState extends State<ReaderScrubber> {
  double? _dragging;

  /// Where a released jump is going, held until the next position arrives
  /// so the thumb does not spring back meanwhile.
  double? _pending;

  @override
  void didUpdateWidget(ReaderScrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.position != oldWidget.state.position) _pending = null;
  }

  @override
  Widget build(BuildContext context) {
    final value =
        _dragging ?? _pending ?? ReaderScrubber.currentValue(widget.state);
    if (value == null) return const SizedBox.shrink();
    // Inset from the screen edges so dragging the thumb at either end is
    // not taken for Android's back gesture.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space24),
      child: SliderTheme(
        data: SliderTheme.of(context)
            .copyWith(showValueIndicator: ShowValueIndicator.onDrag),
        child: Slider(
          value: value,
          label: ReaderScrubber.labelFor(widget.state, value),
          semanticFormatterCallback: (value) =>
              'Position in book, ${ReaderScrubber.labelFor(widget.state, value)}',
          onChanged: (value) => setState(() => _dragging = value),
          onChangeEnd: (value) async {
            setState(() {
              _dragging = null;
              _pending = value;
            });
            final jumped = await widget.onJump(value);
            if (!jumped && mounted) setState(() => _pending = null);
          },
        ),
      ),
    );
  }
}
