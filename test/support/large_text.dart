import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A long title that wraps badly: a very long word and many short ones.
const String longTitle =
    'Supercalifragilisticexpialidociousness: An Extraordinarily Long Title '
    'of a Book That Keeps Going Well Past Any Reasonable Length';

/// Renders at 320×568 logical pixels with system text at 200%, the
/// smallest supported phone at the largest common text size. Layout
/// overflows then fail the test.
void useSmallPhoneWithLargeText(WidgetTester tester) {
  tester.view.physicalSize = const Size(640, 1136);
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
}
