import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_spacing_tokens.dart';
import '../../../domain/entities/enums.dart';
import '../../../domain/entities/reader_preferences.dart';
import '../application/reader_controller.dart';
import '../application/reader_preferences_controller.dart';

/// Reading settings for the open book's format (UI/UX §7.6). Only options
/// the engine supports for that format are shown; changes apply at once and
/// apply to every book.
Future<void> showReaderSettingsSheet(
  BuildContext context, {
  required ReaderRequest request,
  required PublicationFormat format,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => ReaderSettingsSheet(request: request, format: format),
  );
}

class ReaderSettingsSheet extends ConsumerStatefulWidget {
  const ReaderSettingsSheet({
    super.key,
    required this.request,
    required this.format,
  });

  final ReaderRequest request;
  final PublicationFormat format;

  @override
  ConsumerState<ReaderSettingsSheet> createState() =>
      _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends ConsumerState<ReaderSettingsSheet> {
  /// Slider position while dragging; applied when the drag ends so the book
  /// is not reflowed on every step.
  double? _draggingScale;

  Future<void> _update(ReaderPreferences preferences) async {
    final applied = await ref
        .read(readerControllerProvider(widget.request).notifier)
        .updatePreferences(preferences);
    if (!applied && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That setting could not be applied.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(readerPreferencesProvider);
    final text = Theme.of(context).textTheme;
    final isEpub = widget.format == PublicationFormat.epub;
    final pageFit = ref.read(publicationReaderProvider).supportsPdfPageFit;

    Widget heading(String label) => Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.space16,
        bottom: AppSpacing.space8,
      ),
      child: Text(label, style: text.titleSmall),
    );

    Widget choice<T>(
      List<(T, String)> options,
      T selected,
      ValueChanged<T> onSelected,
    ) {
      return SizedBox(
        width: double.infinity,
        child: SegmentedButton<T>(
          showSelectedIcon: false,
          segments: [
            for (final (value, label) in options)
              ButtonSegment(value: value, label: Text(label)),
          ],
          selected: {selected},
          onSelectionChanged: (values) => onSelected(values.single),
        ),
      );
    }

    final scale = _draggingScale ?? preferences.fontScale;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenEdge,
          0,
          AppSpacing.screenEdge,
          AppSpacing.space24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reading settings', style: text.titleMedium),
            if (isEpub) ...[
              heading('Theme'),
              choice<ReadingTheme>(
                const [
                  (ReadingTheme.system, 'System'),
                  (ReadingTheme.light, 'Light'),
                  (ReadingTheme.dark, 'Dark'),
                ],
                preferences.theme,
                (theme) => _update(preferences.copyWith(theme: theme)),
              ),
              heading('Text size'),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      min: ReaderPreferences.minFontScale,
                      max: ReaderPreferences.maxFontScale,
                      divisions: 12,
                      value: scale,
                      label: '${(scale * 100).round()}%',
                      semanticFormatterCallback: (value) =>
                          'Text size ${(value * 100).round()} percent',
                      onChanged: (value) =>
                          setState(() => _draggingScale = value),
                      onChangeEnd: (value) async {
                        await _update(preferences.copyWith(fontScale: value));
                        if (mounted) setState(() => _draggingScale = null);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: ExcludeSemantics(
                      child: Text(
                        '${(scale * 100).round()}%',
                        textAlign: TextAlign.end,
                        style: text.labelLarge,
                      ),
                    ),
                  ),
                ],
              ),
              heading('Page turning'),
              choice<PageLayout>(
                const [
                  (PageLayout.paginated, 'Pages'),
                  (PageLayout.scroll, 'Scroll'),
                ],
                preferences.epubLayout,
                (layout) => _update(preferences.copyWith(epubLayout: layout)),
              ),
            ] else ...[
              heading('Page turning'),
              choice<PageLayout>(
                const [
                  (PageLayout.paginated, 'Pages'),
                  (PageLayout.scroll, 'Scroll'),
                ],
                preferences.pdfLayout,
                (layout) => _update(preferences.copyWith(pdfLayout: layout)),
              ),
              if (pageFit) ...[
                heading('Page fit'),
                choice<PdfPageFit>(
                  const [
                    (PdfPageFit.width, 'Fit width'),
                    (PdfPageFit.page, 'Whole page'),
                  ],
                  preferences.pdfFit,
                  (fit) => _update(preferences.copyWith(pdfFit: fit)),
                ),
              ],
            ],
            const SizedBox(height: AppSpacing.space24),
            TextButton.icon(
              onPressed: () => _update(_reset(preferences)),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset to defaults'),
            ),
          ],
        ),
      ),
    );
  }

  /// Resets only the settings shown for this format.
  ReaderPreferences _reset(ReaderPreferences current) {
    const defaults = ReaderPreferences();
    return widget.format == PublicationFormat.epub
        ? current.copyWith(
            theme: defaults.theme,
            fontScale: defaults.fontScale,
            epubLayout: defaults.epubLayout,
          )
        : current.copyWith(
            pdfLayout: defaults.pdfLayout,
            pdfFit: defaults.pdfFit,
          );
  }
}
