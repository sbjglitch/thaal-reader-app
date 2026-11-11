import 'dart:io';

import 'package:flutter/services.dart';

/// Sets the brightness of the app's own window while reading. The device's
/// brightness setting is never changed.
abstract interface class ScreenBrightness {
  /// Whether this platform can set the window brightness. The brightness
  /// controls are hidden when it cannot.
  bool get isSupported;

  /// Sets the window to [level] (0.0–1.0), or hands brightness back to the
  /// system when [level] is null. Returns false when it could not be set.
  Future<bool> apply(double? level);
}

/// Android: `WindowManager.LayoutParams.screenBrightness` through a small
/// channel in MainActivity, which needs no permission. iOS support is
/// deferred with the rest of iOS work.
class PlatformScreenBrightness implements ScreenBrightness {
  const PlatformScreenBrightness();

  static const MethodChannel _channel = MethodChannel(
    'com.sbjglitch.thaal/brightness',
  );

  @override
  bool get isSupported => Platform.isAndroid;

  @override
  Future<bool> apply(double? level) async {
    if (!isSupported) return false;
    try {
      await _channel.invokeMethod<void>('setBrightness', level);
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
