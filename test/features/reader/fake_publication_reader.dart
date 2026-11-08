import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:thaal/domain/entities/enums.dart';
import 'package:thaal/domain/entities/locator_envelope.dart';
import 'package:thaal/services/reader/publication_reader.dart';

/// Scriptable [PublicationReader] for controller and widget tests.
class FakePublicationReader implements PublicationReader {
  final controller = StreamController<ReaderEvent>.broadcast();
  final calls = <String>[];

  ReaderFailure? openFailure;
  List<TocEntry> toc = const [];
  bool tocResolves = true;
  bool _open = false;
  LocatorEnvelope? builtWith;
  String? openedPath;
  ReaderAppearance? openedWith;
  final applied = <ReaderAppearance>[];
  final visited = <LocatorEnvelope>[];
  bool acceptAppearance = true;
  PublicationFormat? _format;

  /// Every set passed to [showHighlights], latest last.
  final shownHighlights = <List<ReaderHighlight>>[];

  void emit(ReaderEvent event) => controller.add(event);

  @override
  Stream<ReaderEvent> get events => controller.stream;

  @override
  bool get isOpen => _open;

  @override
  Future<OpenedPublication> open({
    required String filePath,
    required PublicationFormat format,
    required ReaderAppearance appearance,
  }) async {
    calls.add('open');
    _format = format;
    openedPath = filePath;
    openedWith = appearance;
    if (openFailure case final failure?) throw failure;
    _open = true;
    return OpenedPublication(title: 'Declared', toc: toc);
  }

  @override
  Widget buildView({
    LocatorEnvelope? initialLocator,
    required ValueNotifier<bool> controlsVisible,
    required Widget loading,
  }) {
    builtWith = initialLocator;
    return const SizedBox.expand(key: Key('engine-view'));
  }

  @override
  Future<void> goForward() async => calls.add('forward');

  @override
  Future<void> goBackward() async => calls.add('backward');

  @override
  Future<bool> goToTocEntry(TocEntry entry) async {
    calls.add('toc:${entry.index}');
    return tocResolves;
  }

  @override
  Future<bool> applyAppearance(ReaderAppearance appearance) async {
    calls.add('appearance');
    if (!acceptAppearance) return false;
    applied.add(appearance);
    return true;
  }

  @override
  Future<bool> goToLocator(LocatorEnvelope locator) async {
    calls.add('locator');
    visited.add(locator);
    return true;
  }

  @override
  Future<void> close() async {
    calls.add('close');
    _open = false;
  }

  @override
  bool get supportsHighlights => _open && _format == PublicationFormat.epub;

  @override
  Future<bool> showHighlights(List<ReaderHighlight> highlights) async {
    shownHighlights.add(highlights);
    return true;
  }
}
