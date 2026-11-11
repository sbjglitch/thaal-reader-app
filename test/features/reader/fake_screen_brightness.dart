import 'package:thaal/services/platform/screen_brightness.dart';

/// Records the brightness the app asks for; [accept] decides the outcome.
class FakeScreenBrightness implements ScreenBrightness {
  FakeScreenBrightness({this.isSupported = true});

  @override
  final bool isSupported;
  bool accept = true;

  /// Every level applied, null meaning "back to the system".
  final applied = <double?>[];

  @override
  Future<bool> apply(double? level) async {
    applied.add(level);
    return accept;
  }
}
