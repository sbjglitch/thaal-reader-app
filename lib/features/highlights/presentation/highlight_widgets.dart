import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_color_tokens.dart';
import '../../../app/theme/app_spacing_tokens.dart';
import '../../../app/theme/highlight_colors.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_error_state.dart';
import '../../../core/widgets/app_loading_indicator.dart';
import '../../../core/widgets/sheet_messenger.dart';
import '../../../domain/entities/enums.dart';
import '../../../domain/entities/reading_data.dart';
import '../application/highlights.dart';

/// "Chapter 3 · 42%": where a highlight is, or empty when unknown.
String highlightLocationText(HighlightEntry entry) {
  final location = entry.location;
  if (location == null) return 'Location unavailable';
  return [
    if (location.chapterTitle case final chapter?
        when chapter.trim().isNotEmpty)
      chapter.trim(),
    if (location.progression case final progression?)
      '${(progression * 100).round()}%',
  ].join(' · ');
}

/// Opens the editor for [highlightId] in [bookId]. Messages about the
/// outcome go to [messenger], which outlives the sheet.
Future<void> showHighlightEditor(
  BuildContext context, {
  required String bookId,
  required String highlightId,
}) {
  final messenger = ScaffoldMessenger.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => HighlightEditorSheet(
      bookId: bookId,
      highlightId: highlightId,
      messenger: messenger,
    ),
  );
}

/// Deletes [highlight] (and its note) and offers undo.
Future<void> deleteHighlightWithUndo(
  ScaffoldMessengerState messenger,
  HighlightActions actions,
  Highlight highlight,
) async {
  try {
    await actions.delete(highlight);
  } on Object {
    messenger.showSnackBar(
      const SnackBar(content: Text('The highlight could not be deleted.')),
    );
    return;
  }
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        highlight.note == null
            ? 'Highlight deleted.'
            : 'Highlight and note deleted.',
      ),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          try {
            await actions.restore(highlight);
          } on Object {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('The highlight could not be restored.'),
              ),
            );
          }
        },
      ),
    ),
  );
}

/// Colour, note, copy and delete for one highlight (spec §11.2, §11.5).
class HighlightEditorSheet extends ConsumerWidget {
  const HighlightEditorSheet({
    super.key,
    required this.bookId,
    required this.highlightId,
    required this.messenger,
  });

  final String bookId;
  final String highlightId;
  final ScaffoldMessengerState messenger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final highlights = ref.watch(bookHighlightsProvider(bookId));
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: highlights.when(
        loading: () =>
            const SizedBox(height: 160, child: AppLoadingIndicator()),
        error: (_, _) => const SizedBox(
          height: 240,
          child: AppErrorState(
            title: 'This highlight could not be loaded',
            message: 'Your highlights have not been changed.',
          ),
        ),
        data: (list) {
          final entry = list
              .where((e) => e.highlight.id == highlightId)
              .firstOrNull;
          if (entry == null) {
            return const SizedBox(
              height: 200,
              child: AppEmptyState(
                icon: Icons.format_color_text,
                title: 'This highlight no longer exists',
                message: 'It may have been deleted.',
              ),
            );
          }
          return _Editor(
            key: ValueKey(entry.highlight.id),
            entry: entry,
            messenger: messenger,
          );
        },
      ),
    );
  }
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({super.key, required this.entry, required this.messenger});

  final HighlightEntry entry;
  final ScaffoldMessengerState messenger;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  late HighlightColor _color = widget.entry.highlight.color;
  late final _note = TextEditingController(
    text: widget.entry.highlight.note ?? '',
  );
  bool _saving = false;
  bool _saveFailed = false;
  bool _copied = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Highlight get _highlight => widget.entry.highlight;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      await ref
          .read(highlightActionsProvider)
          .update(_highlight, color: _color, note: _note.text);
    } on Object {
      // Shown in the sheet: a snack bar would sit behind it.
      if (mounted) {
        setState(() {
          _saving = false;
          _saveFailed = true;
        });
      }
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final actions = ref.read(highlightActionsProvider);
    Navigator.of(context).pop();
    await deleteHighlightWithUndo(widget.messenger, actions, _highlight);
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colorTokens;
    final selected = _highlight.selectedText;
    final location = highlightLocationText(widget.entry);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenEdge,
        0,
        AppSpacing.screenEdge,
        AppSpacing.space16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Highlight', style: text.titleMedium),
          if (location.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.space4),
            Text(
              location,
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.space12),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: _color.tint, width: 4)),
            ),
            child: Padding(
              padding: const EdgeInsets.only(left: AppSpacing.space12),
              child: Text(
                selected ?? 'No text was saved with this highlight.',
                style: selected == null
                    ? text.bodyMedium?.copyWith(color: colors.textSecondary)
                    : text.bodyMedium,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.space16),
          Text('Colour', style: text.labelLarge),
          const SizedBox(height: AppSpacing.space8),
          Wrap(
            spacing: AppSpacing.space12,
            children: [
              for (final color in HighlightColor.values)
                _ColorChoice(
                  color: color,
                  selected: color == _color,
                  onSelected: () => setState(() => _color = color),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.space16),
          TextField(
            controller: _note,
            minLines: 3,
            maxLines: 6,
            maxLength: HighlightActions.maxNoteLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Note',
              hintText: 'Add a note',
              counterText: '',
            ),
          ),
          if (_saveFailed) ...[
            const SizedBox(height: AppSpacing.space8),
            Text(
              'Your changes could not be saved. Try again.',
              style: text.bodySmall?.copyWith(color: colors.danger),
            ),
          ],
          const SizedBox(height: AppSpacing.space12),
          Row(
            children: [
              TextButton.icon(
                onPressed: _saving ? null : _delete,
                icon: Icon(Icons.delete_outline, color: colors.danger),
                label: Text('Delete', style: TextStyle(color: colors.danger)),
              ),
              if (selected != null)
                TextButton.icon(
                  onPressed: () => _copy(selected),
                  icon: Icon(_copied ? Icons.check : Icons.copy),
                  label: Text(_copied ? 'Copied' : 'Copy text'),
                ),
              const Spacer(),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ColorChoice extends StatelessWidget {
  const _ColorChoice({
    required this.color,
    required this.selected,
    required this.onSelected,
  });

  final HighlightColor color;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTokens;
    return Semantics(
      label: color.label,
      selected: selected,
      button: true,
      excludeSemantics: true,
      child: Tooltip(
        message: color.label,
        child: InkResponse(
          onTap: onSelected,
          radius: 24,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.tint,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? colors.textPrimary : colors.border,
                width: selected ? 2 : 1,
              ),
            ),
            // A check, not only the border, marks the choice.
            child: selected
                ? const Icon(Icons.check, size: 20, color: Color(0xFF17191C))
                : null,
          ),
        ),
      ),
    );
  }
}

/// The open book's highlights; returns the one to go to.
class HighlightsSheet extends ConsumerWidget {
  const HighlightsSheet({super.key, required this.bookId});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final highlights = ref.watch(bookHighlightsProvider(bookId));
    final text = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scrollController) => SheetMessenger(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenEdge,
                0,
                AppSpacing.screenEdge,
                AppSpacing.space8,
              ),
              child: Text('Highlights', style: text.titleMedium),
            ),
            Expanded(
              child: highlights.when(
                loading: () => const AppLoadingIndicator(),
                error: (_, _) => const AppErrorState(
                  title: 'Highlights could not be loaded',
                  message: 'Your highlights have not been changed.',
                ),
                data: (list) => list.isEmpty
                    ? const AppEmptyState(
                        icon: Icons.format_color_text,
                        title: 'No highlights in this book',
                        message: 'Select text, then choose Highlight or Note.',
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: list.length,
                        itemBuilder: (context, index) {
                          final entry = list[index];
                          return HighlightTile(
                            key: ValueKey(entry.highlight.id),
                            entry: entry,
                            onOpen: () => Navigator.of(context).pop(entry),
                            onEdit: () => showHighlightEditor(
                              context,
                              bookId: bookId,
                              highlightId: entry.highlight.id,
                            ),
                            onDelete: () => deleteHighlightWithUndo(
                              ScaffoldMessenger.of(context),
                              ref.read(highlightActionsProvider),
                              entry.highlight,
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One highlight row: colour, excerpt, note preview and place.
class HighlightTile extends StatelessWidget {
  const HighlightTile({
    super.key,
    required this.entry,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final HighlightEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final highlight = entry.highlight;
    final location = highlightLocationText(entry);
    final details = [
      if (highlight.note case final note?) 'Note: $note',
      if (location.isNotEmpty) location,
    ].join(' · ');
    return ListTile(
      contentPadding: const EdgeInsets.only(
        left: AppSpacing.screenEdge,
        right: AppSpacing.space4,
      ),
      leading: Semantics(
        label: '${highlight.color.label} highlight',
        child: Container(
          width: 12,
          height: 40,
          decoration: BoxDecoration(
            color: highlight.color.tint,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
      title: Text(
        highlight.selectedText ?? 'Highlight',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: details.isEmpty
          ? null
          : Text(
              details,
              style: text.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
      onTap: onOpen,
      trailing: PopupMenuButton<bool>(
        tooltip: 'More actions for this highlight',
        onSelected: (edit) => edit ? onEdit() : onDelete(),
        itemBuilder: (_) => const [
          PopupMenuItem(value: true, child: Text('Edit')),
          PopupMenuItem(value: false, child: Text('Delete')),
        ],
      ),
    );
  }
}
