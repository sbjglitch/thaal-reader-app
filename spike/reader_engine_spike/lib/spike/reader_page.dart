import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_readium/flutter_readium.dart';

import 'fixture_library.dart';
import 'locator_envelope.dart';
import 'spike_log.dart';
import 'spike_store.dart';

/// Spike reader: deliberately plain UI that exercises each engine capability
/// from READER_ENGINE_SPECIFICATION.md §18 and logs what happens.
///
/// The plugin is called directly here because this is a throwaway spike; the
/// real app must go through an app-owned reader adapter (ADR-012).
class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.fixture,
    required this.library,
    required this.store,
  });

  final Fixture fixture;
  final FixtureLibrary library;
  final SpikeStore store;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> with WidgetsBindingObserver {
  static const _highlightGroup = 'spike_highlights';
  static const _highlightAction = SelectionAction(
    id: 'spike_highlight',
    title: 'Highlight',
  );

  /// Incremented per open so late events from a previous session are ignored.
  static int _generation = 0;

  final _readium = FlutterReadium();
  final _log = SpikeLog.instance;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  late final int _sessionGeneration;
  Publication? _publication;
  Locator? _initialLocator;
  Locator? _currentLocator;
  String? _error;
  Timer? _saveDebounce;
  bool _closing = false;

  double _fontSize = 1.0;
  bool _darkTheme = false;
  bool _epubScroll = false;
  PDFLayout _pdfLayout = PDFLayout.paginated;
  PDFFit _pdfFit = PDFFit.page;

  bool get _isPdf => widget.fixture.format == EnvelopeFormat.pdf;
  String get _bookId => widget.fixture.id;

  @override
  void initState() {
    super.initState();
    _sessionGeneration = ++_generation;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_open());
  }

  Future<void> _open() async {
    final file = widget.library.fileFor(widget.fixture);
    if (!await file.exists() || await file.length() == 0) {
      _fail('missing_file', 'Publication file is missing or empty.');
      return;
    }

    final saved = LocatorEnvelope.tryDecode(
      widget.store.position(_bookId),
      expectedFormat: widget.fixture.format,
    );
    _initialLocator = saved == null ? null : Locator.fromJson(saved.locator);
    _log.add(
      '[$_bookId] open requested; saved locator ${_initialLocator == null ? 'none/invalid' : _describe(_initialLocator!)}',
    );

    if (_isPdf) {
      _readium.setDefaultPDFPreferences(_pdfPreferences());
    } else {
      _readium.setDefaultPreferences(_epubPreferences());
    }

    final stopwatch = Stopwatch()..start();
    try {
      final publication = await _readium.openPublication(file.path);
      if (!mounted || _closing) {
        await _readium.closePublication();
        return;
      }
      _log.add(
        '[$_bookId] opened in ${stopwatch.elapsedMilliseconds} ms: "${publication.metadata.title}", '
        'toc=${publication.tocFlattened.length}, readingOrder=${publication.readingOrder.length}',
      );
      _listen();
      setState(() => _publication = publication);
    } on ReadiumException catch (error) {
      _fail(error.code ?? error.codeEnum.name, error.message);
    } on Exception catch (error) {
      _fail('unexpected', error.runtimeType.toString());
    }
  }

  void _listen() {
    bool current() => _sessionGeneration == _generation && !_closing;

    _subscriptions.add(
      _readium.onReaderStatusChanged.listen((status) {
        if (!current()) return;
        _log.add('[$_bookId] status=${status.name}');
        if (status == ReadiumReaderStatus.ready) unawaited(_applyHighlights());
      }),
    );
    _subscriptions.add(
      _readium.onTextLocatorChanged.listen((locator) {
        if (!current()) return;
        _currentLocator = locator;
        _log.add('[$_bookId] locator ${_describe(locator)}');
        if (mounted) setState(() {});
        _saveDebounce?.cancel();
        _saveDebounce = Timer(const Duration(milliseconds: 750), _savePosition);
      }),
    );
    _subscriptions.add(
      _readium.onErrorEvent.listen((error) {
        if (!current()) return;
        _log.add(
          '[$_bookId] reader error code=${error.code} fatal=${error.isFatal}',
        );
      }),
    );
  }

  Future<void> _savePosition() async {
    final locator = _currentLocator;
    if (locator == null) return;
    final envelope = LocatorEnvelope(
      format: widget.fixture.format,
      locator: locator.toJson(),
    );
    try {
      await widget.store.savePosition(_bookId, envelope.encode());
      _log.add('[$_bookId] position saved');
    } on FileSystemException catch (error) {
      // The previous saved position stays on disk because writes are atomic.
      _log.add('[$_bookId] position save failed: ${error.osError?.errorCode}');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _log.add('[$_bookId] app lifecycle=${state.name}');
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _saveDebounce?.cancel();
      unawaited(_savePosition());
    }
  }

  Future<void> _applyHighlights() async {
    if (_isPdf) return;
    final decorations = <ReaderDecoration>[];
    for (final stored in widget.store.highlights(_bookId)) {
      final locator = Locator.fromJson(
        stored['locator'] as Map<String, dynamic>?,
      );
      final id = stored['id'];
      final tint = stored['tint'];
      if (locator == null || id is! String || tint is! int) {
        _log.add('[$_bookId] skipped unreadable stored highlight');
        continue;
      }
      decorations.add(
        ReaderDecoration(
          id: id,
          locator: locator,
          style: ReaderDecorationStyle(
            style: DecorationStyle.highlight,
            tint: Color(tint),
          ),
        ),
      );
    }
    await _readium.applyDecorations(_highlightGroup, decorations);
    _log.add('[$_bookId] applied ${decorations.length} highlight(s)');
  }

  Future<void> _onSelectionAction(SelectionActionEvent event) async {
    if (event.actionId != _highlightAction.id) return;
    // Stored in an app-owned shape rather than ReaderDecoration.toJson():
    // in flutter_readium 0.9.0 ReaderDecorationStyle.toJson writes `tint` as
    // a CSS string but fromJson casts it to int, so the plugin's own JSON
    // does not round-trip.
    await widget.store.addHighlight(_bookId, {
      'id': 'hl-${DateTime.now().microsecondsSinceEpoch}',
      'locator': event.locator.toJson(),
      'tint': 0xFFFFE066,
    });
    _log.add('[$_bookId] highlight created at ${_describe(event.locator)}');
    await _applyHighlights();
  }

  EPUBPreferences _epubPreferences() => EPUBPreferences(
    fontSize: _fontSize,
    scroll: _epubScroll,
    backgroundColor: _darkTheme
        ? const Color(0xFF17191C)
        : const Color(0xFFFFFFFF),
    textColor: _darkTheme ? const Color(0xFFF3F4F4) : const Color(0xFF17191C),
  );

  PDFPreferences _pdfPreferences() =>
      PDFPreferences(layout: _pdfLayout, fit: _pdfFit);

  Future<void> _pushPreferences() async {
    try {
      if (_isPdf) {
        await _readium.setPDFPreferences(_pdfPreferences());
        _log.add(
          '[$_bookId] pdf prefs layout=${_pdfLayout.name} fit=${_pdfFit.name}',
        );
      } else {
        await _readium.setEPUBPreferences(_epubPreferences());
        _log.add(
          '[$_bookId] epub prefs fontSize=$_fontSize dark=$_darkTheme scroll=$_epubScroll',
        );
      }
    } on ReadiumException catch (error) {
      _log.add('[$_bookId] preferences failed code=${error.code}');
    }
    if (mounted) setState(() {});
  }

  Future<void> _addBookmark() async {
    final locator = _currentLocator;
    if (locator == null) {
      _snack('No position reported yet.');
      return;
    }
    final envelope = LocatorEnvelope(
      format: widget.fixture.format,
      locator: locator.toJson(),
    );
    await widget.store.addBookmark(_bookId, envelope.encode());
    _log.add('[$_bookId] bookmark added at ${_describe(locator)}');
    _snack('Bookmark added');
  }

  Future<void> _goTo(Locator locator, String source) async {
    final ok = await _readium.goToLocator(locator);
    _log.add('[$_bookId] goToLocator from $source -> $ok');
  }

  void _fail(String code, String message) {
    _log.add('[$_bookId] open failed code=$code');
    if (mounted) setState(() => _error = '$message\n(code: $code)');
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  static String _describe(Locator locator) {
    final locations = locator.locations;
    return 'href=${locator.href} progression=${locations?.progression?.toStringAsFixed(3)} '
        'total=${locations?.totalProgression?.toStringAsFixed(3)} position=${locations?.position}';
  }

  @override
  void dispose() {
    _closing = true;
    WidgetsBinding.instance.removeObserver(this);
    _saveDebounce?.cancel();
    unawaited(_savePosition());
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    if (_publication != null) unawaited(_readium.closePublication());
    _log.add('[$_bookId] reader disposed');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final publication = _publication;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          publication?.metadata.title ?? widget.fixture.label,
          overflow: TextOverflow.ellipsis,
        ),
        actions: publication == null
            ? null
            : [
                IconButton(
                  tooltip: 'Contents',
                  icon: const Icon(Icons.list),
                  onPressed: () => _showToc(publication),
                ),
                IconButton(
                  tooltip: 'Add bookmark',
                  icon: const Icon(Icons.bookmark_add_outlined),
                  onPressed: _addBookmark,
                ),
                IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.search),
                  onPressed: _showSearch,
                ),
                PopupMenuButton<String>(
                  onSelected: (value) => switch (value) {
                    'bookmarks' => _showBookmarks(),
                    'settings' => _showSettings(),
                    'forward' => _readium.goForward(),
                    'backward' => _readium.goBackward(),
                    _ => null,
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'bookmarks', child: Text('Bookmarks')),
                    PopupMenuItem(
                      value: 'settings',
                      child: Text('Reader settings'),
                    ),
                    PopupMenuItem(
                      value: 'backward',
                      child: Text('Go backward'),
                    ),
                    PopupMenuItem(value: 'forward', child: Text('Go forward')),
                  ],
                ),
              ],
      ),
      body: _buildBody(publication),
      bottomNavigationBar: publication == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  _currentLocator == null
                      ? 'Waiting for position…'
                      : 'Total progression: ${((_currentLocator!.locations?.totalProgression ?? 0) * 100).toStringAsFixed(1)}%',
                ),
              ),
            ),
    );
  }

  Widget _buildBody(Publication? publication) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (publication == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ReadiumReaderWidget(
      publication: publication,
      initialLocator: _initialLocator,
      loadingWidget: const Center(child: CircularProgressIndicator()),
      selectionActions: _isPdf ? const [] : const [_highlightAction],
      onSelectionAction: _onSelectionAction,
      onTextSelected: (event) =>
          _log.add('[$_bookId] text selected at ${_describe(event.locator)}'),
      onDecorationInteraction: (_) => _log.add('[$_bookId] decoration tapped'),
      onInternalLinkActivated: (_) =>
          _log.add('[$_bookId] internal link activated'),
      onExternalLinkActivated: (_) =>
          _log.add('[$_bookId] external link activated (ignored, offline app)'),
    );
  }

  void _showToc(Publication publication) {
    final rows = <Widget>[];
    void addLinks(List<Link> links, int depth) {
      for (final link in links) {
        rows.add(
          ListTile(
            contentPadding: EdgeInsets.only(left: 16.0 + depth * 20, right: 16),
            title: Text(link.title ?? link.href),
            onTap: () async {
              Navigator.pop(context);
              final ok = await _readium.goByLink(link, publication);
              _log.add('[$_bookId] TOC goByLink ${link.href} -> $ok');
            },
          ),
        );
        addLinks(link.children, depth + 1);
      }
    }

    addLinks(publication.toc, 0);
    _showSheet(
      rows.isEmpty
          ? const [
              ListTile(
                title: Text('This publication has no table of contents.'),
              ),
            ]
          : rows,
    );
  }

  void _showBookmarks() {
    final rows = <Widget>[];
    for (final raw in widget.store.bookmarks(_bookId)) {
      final envelope = LocatorEnvelope.tryDecode(
        raw,
        expectedFormat: widget.fixture.format,
      );
      final locator = envelope == null
          ? null
          : Locator.fromJson(envelope.locator);
      if (locator == null) continue;
      rows.add(
        ListTile(
          title: Text(locator.title ?? locator.href),
          subtitle: Text(_describe(locator)),
          onTap: () {
            Navigator.pop(context);
            unawaited(_goTo(locator, 'bookmark'));
          },
        ),
      );
    }
    _showSheet(
      rows.isEmpty ? const [ListTile(title: Text('No bookmarks yet.'))] : rows,
    );
  }

  Future<void> _showSearch() async {
    final query = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Search'),
          content: TextField(controller: controller, autofocus: true),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Search'),
            ),
          ],
        );
      },
    );
    if (query == null || query.trim().isEmpty) return;
    final stopwatch = Stopwatch()..start();
    try {
      final results = await _readium.searchInPublication(query.trim());
      _log.add(
        '[$_bookId] search returned ${results.length} result(s) in ${stopwatch.elapsedMilliseconds} ms',
      );
      _showSheet(
        results.isEmpty
            ? const [ListTile(title: Text('No results.'))]
            : [
                for (final result in results)
                  ListTile(
                    title: Text(result.chapterTitle ?? result.locator.href),
                    subtitle: Text(
                      result.locator.text?.highlight ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      unawaited(_goTo(result.locator, 'search'));
                    },
                  ),
              ],
      );
    } on ReadiumException catch (error) {
      _log.add('[$_bookId] search failed code=${error.code}');
      _snack('Search is not available for this publication.');
    }
  }

  void _showSettings() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          void update(VoidCallback change) {
            change();
            setSheetState(() {});
            unawaited(_pushPreferences());
          }

          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: _isPdf
                  ? [
                      SwitchListTile(
                        title: const Text('Vertical scroll layout'),
                        value: _pdfLayout == PDFLayout.scrollVertical,
                        onChanged: (on) => update(
                          () => _pdfLayout = on
                              ? PDFLayout.scrollVertical
                              : PDFLayout.paginated,
                        ),
                      ),
                      SwitchListTile(
                        title: const Text('Fit width (off = fit page)'),
                        value: _pdfFit == PDFFit.width,
                        onChanged: (on) => update(
                          () => _pdfFit = on ? PDFFit.width : PDFFit.page,
                        ),
                      ),
                    ]
                  : [
                      ListTile(
                        title: Text('Font size ${(_fontSize * 100).round()}%'),
                        subtitle: Slider(
                          min: 0.8,
                          max: 2.0,
                          divisions: 12,
                          value: _fontSize,
                          onChanged: (value) =>
                              setSheetState(() => _fontSize = value),
                          onChangeEnd: (_) => update(() {}),
                        ),
                      ),
                      SwitchListTile(
                        title: const Text('Dark reading theme'),
                        value: _darkTheme,
                        onChanged: (on) => update(() => _darkTheme = on),
                      ),
                      SwitchListTile(
                        title: const Text('Scroll instead of paginate'),
                        value: _epubScroll,
                        onChanged: (on) => update(() => _epubScroll = on),
                      ),
                    ],
            ),
          );
        },
      ),
    );
  }

  void _showSheet(List<Widget> children) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: ListView(shrinkWrap: true, children: children),
        ),
      ),
    );
  }
}
