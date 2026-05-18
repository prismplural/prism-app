import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
