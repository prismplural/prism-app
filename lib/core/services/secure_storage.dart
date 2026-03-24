import 'dart:convert';

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
    await secureStorage.write(key: key, value: base64Encode(utf8.encode(newUrl)));
  }
}

/// Clears stale keychain data on fresh iOS installs.
///
/// iOS Keychain persists across app uninstall/reinstall (unlike Android).
/// Without this check, a reinstalled app could find orphaned sync credentials
/// from a previous install, causing silent failures or security issues.
///
/// Uses SharedPreferences (which IS deleted on uninstall) to detect
/// whether this is a fresh install.
Future<void> clearKeychainIfFreshInstall() async {
  final prefs = await SharedPreferences.getInstance();
  const key = 'has_launched_before';
  if (prefs.getBool(key) != true) {
    await secureStorage.deleteAll();
    await prefs.setBool(key, true);
  }
}
