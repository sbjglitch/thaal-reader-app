import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_color_tokens.dart';
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
  /// Slider positions while dragging; applied when the drag ends so the book
  /// is not reflowed on every step.
  double? _draggingScale;
  double? _draggingMargins;

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

    /// A slider for a relative setting, shown and announced as a percentage.
    Widget percentSlider({
      required String name,
      required double min,
      required double max,
      required int divisions,
      required double value,
      required ValueChanged<double?> onDragging,
      required ReaderPreferences Function(double value) changed,
    }) {
      final percent = '${(value * 100).round()}%';
      return Row(
        children: [
          Expanded(
            child: Slider(
              min: min,
              max: max,
              divisions: divisions,
              value: value,
              label: percent,
              semanticFormatterCallback: (value) =>
                  '$name ${(value * 100).round()} percent',
              onChanged: (value) => setState(() => onDragging(value)),
              onChangeEnd: (value) async {
                await _update(changed(value));
                if (mounted) setState(() => onDragging(null));
              },
            ),
          ),
          SizedBox(
            width: 48,
            child: ExcludeSemantics(
              child: Text(
                percent,
                textAlign: TextAlign.end,
                style: text.labelLarge,
              ),
            ),
          ),
        ],
      );
    }

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
            if (ref.read(readerBrightnessProvider.notifier).isSupported) ...[
              heading('Brightness'),
              const _BrightnessControl(),
            ],
            if (isEpub) ...[
              heading('Theme'),
              _ThemeChoice(
                preferences: preferences,
                onSelected: (theme) =>
                    _update(preferences.copyWith(theme: theme)),
              ),
              heading('Font'),
              choice<FontFace>(
                const [
                  (FontFace.original, 'Original'),
                  (FontFace.serif, 'Serif'),
                  (FontFace.sansSerif, 'Sans-serif'),
                ],
                preferences.fontFace,
                (face) => _update(preferences.copyWith(fontFace: face)),
              ),
              heading('Text size'),
              percentSlider(
                name: 'Text size',
                min: ReaderPreferences.minFontScale,
                max: ReaderPreferences.maxFontScale,
                divisions: 12,
                value: _draggingScale ?? preferences.fontScale,
                onDragging: (value) => _draggingScale = value,
                changed: (value) => preferences.copyWith(fontScale: value),
              ),
              heading('Margins'),
              percentSlider(
                name: 'Margins',
                min: ReaderPreferences.minPageMargins,
                max: ReaderPreferences.maxPageMargins,
                divisions: 6,
                value: _draggingMargins ?? preferences.pageMargins,
                onDragging: (value) => _draggingMargins = value,
                changed: (value) => preferences.copyWith(pageMargins: value),
              ),
              heading('Text alignment'),
              choice<TextAlignment>(
                const [
                  (TextAlignment.original, 'Original'),
                  (TextAlignment.start, 'Left'),
                  (TextAlignment.justify, 'Justified'),
                ],
                preferences.textAlignment,
                (alignment) =>
                    _update(preferences.copyWith(textAlignment: alignment)),
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
            pageMargins: defaults.pageMargins,
            textAlignment: defaults.textAlignment,
            fontFace: defaults.fontFace,
          )
        : current.copyWith(
            pdfLayout: defaults.pdfLayout,
            pdfFit: defaults.pdfFit,
          );
  }
}

/// Window brightness for reading: a slider that changes the screen while
/// it is dragged, and a switch to let the system decide again. Dragging the
/// slider turns "Match system brightness" off.
class _BrightnessControl extends ConsumerStatefulWidget {
  const _BrightnessControl();

  @override
  ConsumerState<_BrightnessControl> createState() => _BrightnessControlState();
}

class _BrightnessControlState extends ConsumerState<_BrightnessControl> {
  double? _dragging;

  ReaderBrightnessController get _controller =>
      ref.read(readerBrightnessProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final brightness = ref.watch(readerBrightnessProvider);
    final level = _dragging ?? brightness.level;
    String percent(double value) => '${(value * 100).round()}%';
    return Column(
      children: [
        Row(
          children: [
            const ExcludeSemantics(child: Icon(Icons.brightness_low)),
            Expanded(
              child: Slider(
                min: ReaderBrightness.minLevel,
                max: ReaderBrightness.maxLevel,
                value: level,
                label: percent(level),
                semanticFormatterCallback: (value) =>
                    'Brightness ${percent(value)}',
                onChanged: (value) {
                  setState(() => _dragging = value);
                  _controller.preview(value);
                },
                onChangeEnd: (value) async {
                  await _controller.save(
                    ReaderBrightness(followsSystem: false, level: value),
                  );
                  if (mounted) setState(() => _dragging = null);
                },
              ),
            ),
            const ExcludeSemantics(child: Icon(Icons.brightness_high)),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Match system brightness'),
          value: brightness.followsSystem && _dragging == null,
          onChanged: (follows) => _controller.save(
            ReaderBrightness(followsSystem: follows, level: brightness.level),
          ),
        ),
      ],
    );
  }
}

/// Reading themes as chips, each with a swatch of its page and text colours
/// so the choice can be seen before it is made. The label names each theme,
/// so colour is never the only cue.
class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({required this.preferences, required this.onSelected});

  final ReaderPreferences preferences;
  final ValueChanged<ReadingTheme> onSelected;

  static const _labels = {
    ReadingTheme.system: 'System',
    ReadingTheme.light: 'Light',
    ReadingTheme.dark: 'Dark',
    ReadingTheme.sepia: 'Sepia',
    ReadingTheme.twilight: 'Twilight',
  };

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final border = context.colorTokens.border;
    return Wrap(
      spacing: AppSpacing.space8,
      runSpacing: AppSpacing.space8,
      children: [
        for (final theme in ReadingTheme.values)
          Builder(
            builder: (context) {
              final colors = resolveAppearance(
                preferences.copyWith(theme: theme),
                brightness,
              );
              return ChoiceChip(
                showCheckmark: false,
                selected: preferences.theme == theme,
                onSelected: (_) => onSelected(theme),
                avatar: ExcludeSemantics(
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.background,
                      shape: BoxShape.circle,
                      border: Border.all(color: border),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'A',
                      style: TextStyle(
                        color: colors.foreground,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                label: Text(_labels[theme]!),
              );
            },
          ),
      ],
    );
  }
}
