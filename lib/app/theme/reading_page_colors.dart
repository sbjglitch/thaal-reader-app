import 'package:flutter/painting.dart';

/// Page and text colours for the reading themes that have no app-theme
/// equivalent (UI/UX §3.4). Light and dark use the app's colour tokens.
/// Both pairs keep text contrast above 7:1.
abstract final class ReadingPageColors {
  /// Warm paper with brown text (7.5:1).
  static const sepiaBackground = Color(0xFFF4ECD8);
  static const sepiaText = Color(0xFF5B4636);

  /// Dim blue-grey with warm grey text, softer than dark (8.4:1).
  static const twilightBackground = Color(0xFF2A2D36);
  static const twilightText = Color(0xFFCFCAC0);

  /// Underline under the search match being shown. Orange reads on every
  /// reading theme and is not one of the highlight colours, so a search
  /// mark is not mistaken for a saved highlight.
  static const searchMatch = Color(0xFFE8710A);
}
