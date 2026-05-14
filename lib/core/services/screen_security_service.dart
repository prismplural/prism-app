import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform-level capture protection. Android: `FLAG_SECURE` (also blocks
/// active screenshots). iOS: black `PrivacyOverlay` during capture or
/// background — does NOT block active screenshots; iOS has no API for that.
///
/// [setGlobalEnabled] backs the always-on Settings toggle; [enable] /
/// [disable] are per-screen `SecureScope` ref-counted requests. The flag
/// stays on whenever either path is requesting it; transitions guarded by
/// `_platformStateOn` so redundant calls don't hammer the channel.
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
  ///
  /// Always calls [_reconcile] even when the boolean hasn't changed,
  /// so a previously-failed platform call (e.g. the pre-`runApp` call
  /// in main.dart racing with FlutterEngine channel registration) gets
  /// retried on the next attempt. [_reconcile] short-circuits when the
  /// already-applied platform state matches.
  static Future<void> setGlobalEnabled(bool value) async {
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
    final applied = await _setSecureDisplay(desired);
    if (applied) {
      _platformStateOn = desired;
    }
    // On failure, _platformStateOn stays at its previous value so the
    // next caller's _reconcile detects the mismatch and retries — this
    // covers the cold-boot race where main.dart calls setGlobalEnabled
    // before the platform-side MethodChannel handler is registered.
  }

  static Future<bool> _setSecureDisplay(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setSecureDisplay', {
        'enabled': enabled,
      });
      return true;
    } on PlatformException {
      // Platform may not implement the channel (macOS, Linux, Windows,
      // web). Treat as "not applied" so the next attempt retries.
      return false;
    } on MissingPluginException {
      // Same — no platform-side handler registered yet, or never.
      return false;
    }
  }

  @visibleForTesting
  static void debugResetForTests() {
    _scopeRefCount = 0;
    _globalEnabled = false;
    _platformStateOn = false;
  }
}
