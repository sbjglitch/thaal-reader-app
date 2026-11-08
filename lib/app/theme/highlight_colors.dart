import 'package:flutter/painting.dart';

import '../../domain/entities/enums.dart';

/// Display colour and name of each app-owned highlight colour. The same
/// tints are drawn under the text in the reader and shown in pickers and
/// lists. Readium blends them with the page, so they stay light enough for
/// dark text. Not part of the theme: stored highlights keep their colour in
/// every theme (DATABASE_SCHEMA.md §5.4).
extension HighlightColorDisplay on HighlightColor {
  Color get tint => switch (this) {
    HighlightColor.yellow => const Color(0xFFFFE066),
    HighlightColor.green => const Color(0xFFA8E6A1),
    HighlightColor.blue => const Color(0xFFA6D4FF),
    HighlightColor.pink => const Color(0xFFFFB3D1),
  };

  /// Spoken and shown name, so colour is never the only cue.
  String get label => switch (this) {
    HighlightColor.yellow => 'Yellow',
    HighlightColor.green => 'Green',
    HighlightColor.blue => 'Blue',
    HighlightColor.pink => 'Pink',
  };
}
