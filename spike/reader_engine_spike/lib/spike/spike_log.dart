import 'package:flutter/foundation.dart';

/// In-memory event log shown in the spike UI and mirrored to the console with
/// a `SPIKE` tag so it can be captured with `adb logcat`.
///
/// Only structural data is logged (hrefs, progression, status, error codes) —
/// never publication text, selected text or notes.
class SpikeLog extends ChangeNotifier {
  SpikeLog._();

  static final SpikeLog instance = SpikeLog._();

  final List<String> entries = [];

  void add(String message) {
    final time = DateTime.now().toIso8601String().substring(11, 23);
    final line = '$time $message';
    entries.insert(0, line);
    if (entries.length > 300) entries.removeLast();
    debugPrint('SPIKE $line');
    notifyListeners();
  }
}
