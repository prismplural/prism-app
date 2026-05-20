import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Centralized FlutterSecureStorage instance with correct platform options.
///
/// Uses `first_unlock_this_device` on iOS so that:
/// - Keys are available for background sync (workmanager) while device is locked
/// - Keys are device-bound (not included in iCloud backups or device migration)
/// - Keys are available after the user's first unlock since boot
///
/// On Android, both options are stated explicitly (no defaults relied upon):
///
/// - `resetOnError: false` — fail closed instead of letting
///   flutter_secure_storage delete all entries after a Keystore/storage
///   mismatch. Losing the DB key while `prism.db` remains on disk makes the
///   local database unrecoverable. (fss 10.0.0 flipped this default to
///   `true`; we explicitly opt back out.)
///
/// - `migrateOnAlgorithmChange: true` — keep fss' explicit migration path
///   enabled. FSS 10.2 treats missing algorithm markers as a legacy install;
///   with migration disabled and `resetOnError: false`, a markerless fresh
///   store can fail during initialization instead of writing current markers.
///
/// - `migrateWithBackup: true` — added in fss 10.1.0. When fss migrates
///   data between cipher algorithms (e.g. the deprecated
///   `AES_CBC_PKCS7Padding` → default `AES_GCM_NoPadding` path in 10.2.0),
///   backup copies of encrypted entries are written before the migration
///   starts so a mid-migration crash or interrupted write leaves the
///   pre-migration data intact rather than corrupted. This is the exact
///   class of failure that produced the original 0.9.1 BAD_DECRYPT bug.
const secureStorage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
  aOptions: AndroidOptions(
    resetOnError: false,
    migrateOnAlgorithmChange: true,
    migrateWithBackup: true,
    keyCipherAlgorithm:
        KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
    storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
  ),
);

const _nativeSecureStorageChannel = MethodChannel(
  'com.prism.prism_plurality/runtime_dek_wrap',
);

// ---------------------------------------------------------------------------
// Classified secure-storage wrappers (Prism 0.9.2 secure storage remediation §1)
// ---------------------------------------------------------------------------
//
// Every secure-storage read/write/delete in this codebase should funnel
// through these wrappers so PlatformException leaks cannot surface to the UI.
// See docs/0.9.2-secure-storage-remediation.md for the full plan.

/// Classification of a failed secure-storage operation.
///
/// - [cipher]: Keystore-backed AES-GCM (or related) cipher failure. The stored
///   blob cannot be decrypted with the current key — almost always permanent
///   for that slot; never auto-retry.
/// - [transient]: temporary platform-side condition (e.g. user not
///   authenticated yet, backend busy). Safe to retry with bounded backoff.
/// - [unknown]: everything else. Treat as failure but don't retry blindly.
enum SecureStorageFailure { cipher, transient, unknown }

/// Operations supported by the test-only secure-storage fault injector.
///
/// The injector only throws synthetic wrapper exceptions. It never mutates
/// secure storage, and app builds leave it disabled.
enum SecureStorageFaultOperation { read, readAll, write, delete, deleteAll }

class SecureStorageInjectedFault {
  const SecureStorageInjectedFault({
    required this.operation,
    required this.failure,
    this.key,
  });

  final SecureStorageFaultOperation operation;
  final SecureStorageFailure failure;
  final String? key;

  String get label {
    final keySuffix = key == null ? '' : '($key)';
    return '${operation.name}$keySuffix → ${failure.name}';
  }
}

class SecureStorageFaultInjector {
  SecureStorageFaultInjector._();

  static final List<SecureStorageInjectedFault> _pending =
      <SecureStorageInjectedFault>[];
  static bool _enabledForTesting = false;

  static bool get enabled => !kReleaseMode && _enabledForTesting;

  static List<SecureStorageInjectedFault> get pending =>
      List.unmodifiable(_pending);

  @visibleForTesting
  static void enableForTesting() {
    if (!kReleaseMode) _enabledForTesting = true;
  }

  @visibleForTesting
  static void disableForTesting() {
    _enabledForTesting = false;
    _pending.clear();
  }

  static void queueNext({
    required SecureStorageFaultOperation operation,
    SecureStorageFailure failure = SecureStorageFailure.cipher,
    String? key,
  }) {
    if (!enabled) return;
    _pending.add(
      SecureStorageInjectedFault(
        operation: operation,
        failure: failure,
        key: key,
      ),
    );
  }

  static void clear() {
    _pending.clear();
  }

  static PlatformException? take(
    SecureStorageFaultOperation operation, {
    String? key,
  }) {
    if (!enabled || _pending.isEmpty) return null;
    final index = _pending.indexWhere((fault) {
      if (fault.operation != operation) return false;
      return fault.key == null || fault.key == key;
    });
    if (index < 0) return null;
    final fault = _pending.removeAt(index);
    return _exceptionFor(fault.failure);
  }

  static PlatformException _exceptionFor(SecureStorageFailure failure) {
    switch (failure) {
      case SecureStorageFailure.cipher:
        return PlatformException(
          code: 'Exception encountered',
          message:
              'error:1e000065:Cipher functions:OPENSSL_internal:BAD_DECRYPT',
          details:
              'javax.crypto.AEADBadTagException: Error while decrypting '
              '(injected by Prism debug fault injector)',
        );
      case SecureStorageFailure.transient:
        return PlatformException(
          code: 'UserNotAuthenticated',
          message:
              'UserNotAuthenticated: injected by Prism debug fault injector',
        );
      case SecureStorageFailure.unknown:
        return PlatformException(
          code: 'PrismInjectedSecureStorageFault',
          message: 'Injected secure-storage failure',
        );
    }
  }
}

/// Substring fragments that indicate a cipher-level failure.
///
/// Matched case-insensitively against [PlatformException.code], `details`,
/// and `message` in that order. See fss 10.0.0 plugin source —
/// `FlutterSecureStoragePlugin.java#handleException` — which forwards the
/// underlying Java exception's `getMessage()` (and a full stack trace in
/// `details`) for things like `javax.crypto.AEADBadTagException`,
/// `BadPaddingException`, `InvalidKeyException`, `IllegalBlockSizeException`,
/// `UnrecoverableKeyException`, `NoSuchAlgorithmException`, and
/// `KeyPermanentlyInvalidatedException`. Once fss initialization fails, later
/// operations can also surface null-cipher `NullPointerException`s.
const _kCipherSubstrings = <String>[
  'aeadbadtag',
  'badpadding',
  'bad_decrypt',
  'invalidkey',
  'failed to unwrap key',
  'illegalblocksize',
  'migration failed after algorithm change',
  'nosuchalgorithm',
  'nullpointerexception',
  'required cryptographic algorithm not supported',
  'storagecipher',
  'unrecoverablekey',
  'keypermanentlyinvalidated',
];

/// Substring fragments that indicate a transient platform-side failure.
const _kTransientSubstrings = <String>['usernotauthenticated', 'backendbusy'];

/// Classify a [PlatformException] raised by `flutter_secure_storage`.
///
/// Checks fields in priority order: `code`, then `details`, then `message`.
/// Returns the first matching kind, or [SecureStorageFailure.unknown] when
/// nothing matches.
SecureStorageFailure classifySecureStorageError(PlatformException e) {
  // Priority 1: code
  final codeMatch = _classifyText(e.code);
  if (codeMatch != null) return codeMatch;

  // Priority 2: details (may be String, may be other)
  final details = e.details;
  if (details is String) {
    final detailsMatch = _classifyText(details);
    if (detailsMatch != null) return detailsMatch;
  }

  // Priority 3: message
  final message = e.message;
  if (message != null) {
    final messageMatch = _classifyText(message);
    if (messageMatch != null) return messageMatch;
  }

  return SecureStorageFailure.unknown;
}

/// Returns the matching failure kind for [text], or null if no substring
/// fragment is present. Matching is case-insensitive.
SecureStorageFailure? _classifyText(String text) {
  if (text.isEmpty) return null;
  final lower = text.toLowerCase();
  for (final fragment in _kCipherSubstrings) {
    if (lower.contains(fragment)) return SecureStorageFailure.cipher;
  }
  for (final fragment in _kTransientSubstrings) {
    if (lower.contains(fragment)) return SecureStorageFailure.transient;
  }
  return null;
}

/// Result of a single-key secure-storage read.
///
/// - When the operation succeeded the [failure] is null and [value] is the
///   stored string (or null when the key was absent).
/// - When the operation failed [failure] is set and [value] is null; the
///   raw platform [code] and [message] are preserved for diagnostics.
class SecureReadResult {
  const SecureReadResult({this.value, this.failure, this.code, this.message});

  /// Stored value, or null when the key was absent or the read failed.
  final String? value;

  /// Failure classification. Null when the read succeeded.
  final SecureStorageFailure? failure;

  /// Raw `PlatformException.code` when [failure] is non-null.
  final String? code;

  /// Raw `PlatformException.message` when [failure] is non-null.
  final String? message;

  bool get ok => failure == null;
}

/// Result of a `readAll`-style secure-storage read.
///
/// On success [entries] contains every key/value pair the plugin returned and
/// [failure] is null. On failure [entries] may be partially populated (when
/// the wrapper fell back to per-key probes) or empty.
class SecureReadAllResult {
  const SecureReadAllResult({
    this.entries = const <String, String>{},
    this.failure,
    this.code,
    this.message,
  });

  /// Stored entries, possibly partial when [failure] is non-null.
  final Map<String, String> entries;

  /// Failure classification. Null when the read succeeded.
  final SecureStorageFailure? failure;

  /// Raw `PlatformException.code` when [failure] is non-null.
  final String? code;

  /// Raw `PlatformException.message` when [failure] is non-null.
  final String? message;

  bool get ok => failure == null;
}

/// Result of a secure-storage write.
class SecureWriteResult {
  const SecureWriteResult({this.failure, this.code, this.message});

  /// Failure classification. Null when the write succeeded.
  final SecureStorageFailure? failure;

  /// Raw `PlatformException.code` when [failure] is non-null.
  final String? code;

  /// Raw `PlatformException.message` when [failure] is non-null.
  final String? message;

  bool get ok => failure == null;
}

/// Result of a secure-storage delete (single key or `deleteAll`).
class SecureDeleteResult {
  const SecureDeleteResult({this.failure, this.code, this.message});

  /// Failure classification. Null when the delete succeeded.
  final SecureStorageFailure? failure;

  /// Raw `PlatformException.code` when [failure] is non-null.
  final String? code;

  /// Raw `PlatformException.message` when [failure] is non-null.
  final String? message;

  bool get ok => failure == null;
}

/// Read [key] from secure storage, classifying any [PlatformException] into a
/// [SecureReadResult]. Callers must decide what to do with [SecureReadResult.failure].
///
/// When [storage] is omitted the canonical [secureStorage] singleton is used;
/// injection exists for testing.
Future<SecureReadResult> safeSecureRead(
  String key, {
  FlutterSecureStorage storage = secureStorage,
}) async {
  try {
    final injected = SecureStorageFaultInjector.take(
      SecureStorageFaultOperation.read,
      key: key,
    );
    if (injected != null) throw injected;
    final value = await storage.read(key: key);
    return SecureReadResult(value: value);
  } on PlatformException catch (e) {
    return SecureReadResult(
      failure: classifySecureStorageError(e),
      code: e.code,
      message: e.message,
    );
  }
}

/// Read every entry from secure storage, classifying any [PlatformException]
/// into a [SecureReadAllResult].
Future<SecureReadAllResult> safeSecureReadAll({
  FlutterSecureStorage storage = secureStorage,
}) async {
  try {
    final injected = SecureStorageFaultInjector.take(
      SecureStorageFaultOperation.readAll,
    );
    if (injected != null) throw injected;
    final all = await storage.readAll();
    return SecureReadAllResult(entries: Map<String, String>.from(all));
  } on PlatformException catch (e) {
    return SecureReadAllResult(
      failure: classifySecureStorageError(e),
      code: e.code,
      message: e.message,
    );
  }
}

/// Read every entry from secure storage; if the top-level `readAll` fails with
/// a cipher error, fall back to probing each of [knownKeys] individually so
/// diagnostic capture isn't empty.
///
/// The returned [SecureReadAllResult.failure] reflects the original `readAll`
/// failure; `entries` may contain whatever individual keys did succeed.
Future<SecureReadAllResult> safeSecureReadAllWithSlotProbe(
  List<String> knownKeys, {
  FlutterSecureStorage storage = secureStorage,
}) async {
  final initial = await safeSecureReadAll(storage: storage);
  if (initial.ok || initial.failure != SecureStorageFailure.cipher) {
    return initial;
  }

  final salvaged = <String, String>{};
  for (final key in knownKeys) {
    final probe = await safeSecureRead(key, storage: storage);
    if (probe.ok && probe.value != null) {
      salvaged[key] = probe.value!;
    }
  }
  return SecureReadAllResult(
    entries: salvaged,
    failure: initial.failure,
    code: initial.code,
    message: initial.message,
  );
}

/// Write [value] under [key], classifying any [PlatformException] into a
/// [SecureWriteResult].
Future<SecureWriteResult> safeSecureWrite(
  String key,
  String value, {
  FlutterSecureStorage storage = secureStorage,
}) async {
  try {
    final injected = SecureStorageFaultInjector.take(
      SecureStorageFaultOperation.write,
      key: key,
    );
    if (injected != null) throw injected;
    await storage.write(key: key, value: value);
    final commitFailure = await _commitAndroidSecureStoragePrefs();
    if (commitFailure != null) return commitFailure;
    return const SecureWriteResult();
  } on PlatformException catch (e) {
    return SecureWriteResult(
      failure: classifySecureStorageError(e),
      code: e.code,
      message: e.message,
    );
  }
}

/// Write [value] and immediately verify the stored value can be read back.
///
/// This is used for DB encryption keys, where a write that only reaches
/// Android's in-memory `SharedPreferences` cache can create an unrecoverable
/// orphaned encrypted database if the process dies before the XML flush.
Future<SecureWriteResult> safeSecureWriteVerified(
  String key,
  String value, {
  FlutterSecureStorage storage = secureStorage,
}) async {
  final write = await safeSecureWrite(key, value, storage: storage);
  if (!write.ok) return write;

  final verify = await safeSecureRead(key, storage: storage);
  if (!verify.ok) {
    return SecureWriteResult(
      failure: verify.failure,
      code: verify.code,
      message: verify.message,
    );
  }
  if (verify.value != value) {
    return const SecureWriteResult(
      failure: SecureStorageFailure.unknown,
      code: 'PrismSecureStorageVerifyMismatch',
      message: 'Secure-storage write verification read back a different value',
    );
  }
  return const SecureWriteResult();
}

Future<SecureWriteResult?> _commitAndroidSecureStoragePrefs() async {
  if (kIsWeb || !Platform.isAndroid) return null;
  try {
    await _nativeSecureStorageChannel.invokeMethod<void>(
      'commitFlutterSecureStorage',
    );
    return null;
  } on PlatformException catch (e) {
    return SecureWriteResult(
      failure: classifySecureStorageError(e),
      code: e.code,
      message: e.message,
    );
  } on MissingPluginException catch (e) {
    return SecureWriteResult(
      failure: SecureStorageFailure.unknown,
      code: 'MissingPluginException',
      message: e.message,
    );
  }
}

/// Collect native secure-storage backend state for user-shareable diagnostics.
///
/// On Android this includes FlutterSecureStorage SharedPreferences namespace
/// presence plus relevant Android Keystore aliases. On Apple platforms it
/// reports the existing native reset-key presence map. Unsupported platforms
/// return null so diagnostic JSON can distinguish "not available" from
/// "probe failed".
Future<Map<String, dynamic>?> collectNativeSecureStorageDiagnostics() async {
  if (kIsWeb) return null;
  final supported = Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  if (!supported) return null;

  try {
    final raw = await _nativeSecureStorageChannel
        .invokeMapMethod<String, dynamic>('hasPrismResetKeys');
    return raw == null ? null : Map<String, dynamic>.from(raw);
  } on MissingPluginException {
    return null;
  } on PlatformException catch (e) {
    return <String, dynamic>{'error_code': e.code, 'error_message': e.message};
  } catch (e) {
    return <String, dynamic>{'error': e.toString()};
  }
}

/// Delete [key] from secure storage, classifying any [PlatformException] into
/// a [SecureDeleteResult].
Future<SecureDeleteResult> safeSecureDelete(
  String key, {
  FlutterSecureStorage storage = secureStorage,
}) async {
  try {
    final injected = SecureStorageFaultInjector.take(
      SecureStorageFaultOperation.delete,
      key: key,
    );
    if (injected != null) throw injected;
    await storage.delete(key: key);
    return const SecureDeleteResult();
  } on PlatformException catch (e) {
    return SecureDeleteResult(
      failure: classifySecureStorageError(e),
      code: e.code,
      message: e.message,
    );
  }
}

/// Delete every entry from secure storage, classifying any [PlatformException]
/// into a [SecureDeleteResult].
Future<SecureDeleteResult> safeSecureDeleteAll({
  FlutterSecureStorage storage = secureStorage,
}) async {
  try {
    final injected = SecureStorageFaultInjector.take(
      SecureStorageFaultOperation.deleteAll,
    );
    if (injected != null) throw injected;
    await storage.deleteAll();
    return const SecureDeleteResult();
  } on PlatformException catch (e) {
    return SecureDeleteResult(
      failure: classifySecureStorageError(e),
      code: e.code,
      message: e.message,
    );
  }
}

/// One-time migration: rewrite relay URL from old domain to new one.
/// Safe to remove once all devices have launched with this build.
///
/// Wrapped via [safeSecureRead] / [safeSecureWrite] so a cipher failure on
/// the relay-URL slot cannot crash boot. The relay URL is reconstructable
/// (users can re-pair); skip the migration on any read/write failure.
Future<void> migrateRelayUrl() async {
  const key = 'prism_sync.relay_url';
  final read = await safeSecureRead(key);
  if (!read.ok) {
    // Cipher / transient / unknown — skip the migration. Relay URL is
    // reconstructable on the next successful pair.
    return;
  }
  final stored = read.value;
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
    // Write failure is non-fatal — the migration will be retried next boot.
    await safeSecureWrite(key, base64Encode(utf8.encode(newUrl)));
  }
}

/// Read every keychain entry whose key starts with [prefix].
///
/// Used by sync setup/reset paths that need to operate on the entire
/// `prism_sync.*` namespace without hardcoding the key list (which silently
/// goes stale when new transient pairing keys are added).
Future<Map<String, String>> readPrefixed(String prefix) async {
  final result = await safeSecureReadAll();
  if (!result.ok) {
    throw StateError(
      'secure storage readAll failed '
      '(failure=${result.failure?.name ?? 'unknown'}, code=${result.code}, '
      'message=${result.message})',
    );
  }
  return Map.fromEntries(
    result.entries.entries.where((e) => e.key.startsWith(prefix)),
  );
}
