/// Throwaway JSON-file persistence for the spike.
///
/// The real app uses Drift (DATABASE_SCHEMA.md). This store only exists so the
/// spike can prove that positions, bookmarks and highlights survive closing
/// the reader and killing the process.
library;

import 'dart:convert';
import 'dart:io';

class SpikeStore {
  SpikeStore(this._file);

  final File _file;
  Map<String, dynamic> _data = {};

  static Future<SpikeStore> open(Directory root) async {
    final store = SpikeStore(File('${root.path}/spike_store.json'));
    await store._load();
    return store;
  }

  Future<void> _load() async {
    if (!await _file.exists()) return;
    try {
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is Map<String, dynamic>) _data = decoded;
    } on FormatException {
      // A corrupt spike store is discarded; the spike reports it in the log.
      _data = {};
    }
  }

  Map<String, dynamic> _book(String bookId) =>
      (_data[bookId] as Map<String, dynamic>?) ??
      (_data[bookId] = <String, dynamic>{});

  String? position(String bookId) => _book(bookId)['position'] as String?;

  List<String> bookmarks(String bookId) =>
      List<String>.from(_book(bookId)['bookmarks'] as List? ?? const []);

  List<Map<String, dynamic>> highlights(String bookId) =>
      List<Map<String, dynamic>>.from(
        _book(bookId)['highlights'] as List? ?? const [],
      );

  Future<void> savePosition(String bookId, String envelope) {
    _book(bookId)['position'] = envelope;
    return _flush();
  }

  Future<void> addBookmark(String bookId, String envelope) {
    _book(bookId)['bookmarks'] = [...bookmarks(bookId), envelope];
    return _flush();
  }

  Future<void> addHighlight(String bookId, Map<String, dynamic> decoration) {
    _book(bookId)['highlights'] = [...highlights(bookId), decoration];
    return _flush();
  }

  Future<void> clear(String bookId) {
    _data.remove(bookId);
    return _flush();
  }

  /// Write to a temporary file then rename, so a crash mid-write keeps the
  /// previous valid store.
  Future<void> _flush() async {
    final temp = File('${_file.path}.tmp');
    await temp.writeAsString(jsonEncode(_data), flush: true);
    await temp.rename(_file.path);
  }
}
