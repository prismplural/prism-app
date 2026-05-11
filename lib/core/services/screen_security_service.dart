import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Controls platform-level secure display (FLAG_SECURE on Android when
/// requested, secure text field overlay on iOS) to prevent screen recording
/// and app-switcher screenshots of sensitive content.
///
/// Two ways to request protection:
/// - [setGlobalEnabled] for the user-facing "Screen Privacy" setting that
///   keeps the platform flag on for the whole app session.
/// - [enable] / [disable] for per-screen `SecureScope` widgets that wrap
///   one-off sensitive flows.
///
/// The platform flag stays on whenever the global mode is on OR any
/// per-platform ref-count is above zero. Transitions are detected against
/// `_platformStateOn`, so redundant calls don't hammer the channel.
class ScreenSecurityService {
  static const _channel = MethodChannel(
    'com.prism.prism_plurality/secure_display',
  );

  static int _scopeRefCount = 0;
  static bool _globalEnabled = false;

  // Tracks the last bool actually pushed to the platform side, so we only
  // call setSecureDisplay when the desired state transitions.
  static bool _platformStateOn = false;

  /// Toggle the always-on global mode. Backs the Settings → Privacy &
  /// Security "Screen Privacy" toggle. Independent of per-screen
  /// [enable] / [disable] requests.
  static Future<void> setGlobalEnabled(bool value) async {
    if (_globalEnabled == value) return;
    _globalEnabled = value;
    await _reconcile();
  }

  /// Request secure display. Call [disable] when the sensitive content
  /// is no longer visible.
  ///
  /// On Android, callers may pass `blockAndroidScreenCapture: false` to
  /// opt out of the ref-bump for screens that intentionally allow
  /// screenshots (backup keys, mnemonic display). The flag has no effect
  /// on iOS — the secure text field trick is applied unconditionally
  /// when any scope is active there.
  static Future<void> enable({bool blockAndroidScreenCapture = true}) async {
    if (Platform.isAndroid && !blockAndroidScreenCapture) return;
    _scopeRefCount++;
    await _reconcile();
  }

  /// Release a secure display request. The flag is cleared only when all
  /// requesters and the global mode are off.
  static Future<void> disable({bool blockAndroidScreenCapture = true}) async {
    if (Platform.isAndroid && !blockAndroidScreenCapture) return;
    if (_scopeRefCount > 0) _scopeRefCount--;
    await _reconcile();
  }

  static Future<void> _reconcile() async {
    final desired = _globalEnabled || _scopeRefCount > 0;
    if (desired == _platformStateOn) return;
    _platformStateOn = desired;
    await _setSecureDisplay(desired);
  }

  static Future<void> _setSecureDisplay(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setSecureDisplay', {
        'enabled': enabled,
      });
    } on PlatformException {
      // Platform may not implement the channel (macOS, Linux, Windows,
      // web). Silently no-op.
    } on MissingPluginException {
      // Same — no platform-side handler registered.
    }
  }

  @visibleForTesting
  static void debugResetForTests() {
    _scopeRefCount = 0;
    _globalEnabled = false;
    _platformStateOn = false;
  }
}
