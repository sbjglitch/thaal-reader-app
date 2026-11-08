import 'package:flutter/widgets.dart';

/// Corner radius scale from docs/UI_UX_SPECIFICATION.md §5.
abstract final class AppRadius {
  /// Compact controls.
  static const double small = 6;

  /// Inputs and buttons.
  static const double medium = 10;

  /// Sheets and larger surfaces.
  static const double large = 14;

  /// Pills and circular controls.
  static const double full = 999;

  static const BorderRadius smallAll = BorderRadius.all(Radius.circular(small));
  static const BorderRadius mediumAll = BorderRadius.all(
    Radius.circular(medium),
  );
  static const BorderRadius largeAll = BorderRadius.all(Radius.circular(large));
}
