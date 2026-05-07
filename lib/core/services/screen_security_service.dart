import 'dart:io';

import 'package:flutter/services.dart';

/// Controls platform-level secure display (FLAG_SECURE on Android when
/// requested, secure text field overlay on iOS) to prevent screen recording
/// and app-switcher screenshots of sensitive content.
///
/// Uses ref-counting so multiple screens can request secure display
/// simultaneously without stepping on each other.
class ScreenSecurityService {
  static const _channel = MethodChannel(
    'com.prism.prism_plurality/secure_display',
  );

  static int _androidBlockRefCount = 0;
  static int _iosRefCount = 0;

  /// Request secure display. Call [disable] when the sensitive content
  /// is no longer visible.
  static Future<void> enable({bool blockAndroidScreenCapture = true}) async {
    if (Platform.isAndroid) {
      if (!blockAndroidScreenCapture) return;
      _androidBlockRefCount++;
      if (_androidBlockRefCount == 1) {
        await _setSecureDisplay(true);
      }
      return;
    }

    if (Platform.isIOS) {
      _iosRefCount++;
      if (_iosRefCount == 1) {
        await _setSecureDisplay(true);
      }
    }
  }

  /// Release a secure display request. The flag is cleared only when all
  /// requesters for this platform mode have called disable.
  static Future<void> disable({bool blockAndroidScreenCapture = true}) async {
    if (Platform.isAndroid) {
      if (!blockAndroidScreenCapture) return;
      if (_androidBlockRefCount > 0) _androidBlockRefCount--;
      if (_androidBlockRefCount == 0) {
        await _setSecureDisplay(false);
      }
      return;
    }

    if (Platform.isIOS) {
      if (_iosRefCount > 0) _iosRefCount--;
      if (_iosRefCount == 0) {
        await _setSecureDisplay(false);
      }
    }
  }

  static Future<void> _setSecureDisplay(bool enabled) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('setSecureDisplay', {
        'enabled': enabled,
      });
    } on PlatformException {
      // Silently ignore — platform may not support this.
    }
  }
}
