import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Centralized FlutterSecureStorage instance with correct platform options.
///
/// Uses `first_unlock_this_device` on iOS so that:
/// - Keys are available for background sync (workmanager) while device is locked
/// - Keys are device-bound (not included in iCloud backups or device migration)
/// - Keys are available after the user's first unlock since boot
///
/// On Android, uses defaults (Android Keystore with resetOnError: true).
const secureStorage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
  aOptions: AndroidOptions(),
);

const _runtimeDekWrapChannel = MethodChannel(
  'com.prism.prism_plurality/runtime_dek_wrap',
);
const _runtimeDekLinuxWrapKey = 'prism_sync.runtime_dek_linux_wrap_key_v1';

/// One-time migration: rewrite relay URL from old domain to new one.
/// Safe to remove once all devices have launched with this build.
Future<void> migrateRelayUrl() async {
  const key = 'prism_sync.relay_url';
  final stored = await secureStorage.read(key: key);
  if (stored == null) return;

  // The URL is stored base64-encoded. Decode, check, re-encode.
  const oldUrl = 'https://prismrelay.neatkit.xyz';
  const newUrl = 'https://sync.prismplural.com';

  String decoded;
  try {
    decoded = String.fromCharCodes(base64Decode(stored));
  } catch (_) {
    decoded = stored; // plain text fallback
  }

  if (decoded == oldUrl) {
    await secureStorage.write(
      key: key,
      value: base64Encode(utf8.encode(newUrl)),
    );
  }
}

/// Read every keychain entry whose key starts with [prefix].
///
/// Used by sync setup/reset paths that need to operate on the entire
/// `prism_sync.*` namespace without hardcoding the key list (which silently
/// goes stale when new transient pairing keys are added).
Future<Map<String, String>> readPrefixed(String prefix) async {
  final all = await secureStorage.readAll();
  return Map.fromEntries(all.entries.where((e) => e.key.startsWith(prefix)));
}

/// Clears stale keychain data on fresh iOS installs in release builds.
///
/// iOS Keychain persists across app uninstall/reinstall (unlike Android).
/// Without this check, a reinstalled app could find orphaned sync credentials
/// from a previous install, causing silent failures or security issues.
/// Also clears app-owned runtime-DEK wrapping keys that live outside
/// `flutter_secure_storage` on Apple desktop/mobile platforms.
///
/// Uses SharedPreferences (which IS deleted on uninstall) to detect
/// whether this is a fresh install.
///
/// Caller is responsible for gating this on `kReleaseMode` — debug/profile
/// reinstalls (Xcode `flutter run`) are not the threat model and would
/// otherwise wipe the developer's working sync credentials. See
/// `docs/plans/skip-fresh-install-guard-in-non-release-builds.md`.
Future<void> clearKeychainIfFreshInstall({
  Future<void> Function()? deleteRuntimeDekWrappingKey,
}) async {
  final prefs = await SharedPreferences.getInstance();
  const key = 'has_launched_before';
  if (prefs.getBool(key) != true) {
    await secureStorage.deleteAll();
    await (deleteRuntimeDekWrappingKey ??
        _deleteRuntimeDekWrappingKeyBestEffort)();
    await prefs.setBool(key, true);
  }
}

Future<void> _deleteRuntimeDekWrappingKeyBestEffort() async {
  try {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        await _runtimeDekWrapChannel.invokeMethod<void>(
          'deleteRuntimeDekWrappingKey',
        );
        return;
      case TargetPlatform.linux:
        await secureStorage.delete(key: _runtimeDekLinuxWrapKey);
        return;
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
        return;
    }
  } on MissingPluginException {
    return;
  } catch (_) {
    return;
  }
}
