import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';
import 'package:prism_plurality/core/services/secure_storage_diagnostic.dart'
    show SlotOutcome;

// ---------------------------------------------------------------------------
// Secure storage keys
// ---------------------------------------------------------------------------

/// Hex-encoded 32-byte key for the Drift app database (`prism.db`).
const kDatabaseKeyStorageKey = 'prism_sync.database_key';

/// Hex-encoded 32-byte key for the Rust sync database (`prism_sync.db`).
///
/// Stored separately from [kDatabaseKeyStorageKey] so that crash-safe rotation
/// of the two databases can be staged independently. Both keys converge to the
/// same HKDF-derived local-storage key after `cacheRuntimeKeys` completes, but
/// are rotated one at a time (Drift first, then Rust) with their own staging
/// slots for crash recovery.
///
/// For existing installs that pre-date this slot, [ensureLocalSyncDatabaseKey]
/// seeds it from [kDatabaseKeyStorageKey] so `createPrismSync` keeps opening
/// the sync DB with the same key it was using before.
const kSyncDatabaseKeyStorageKey = 'prism_sync.sync_database_key';

// Internal cleanup-delete helper. Every delete in this file is a
// best-effort cleanup of a DB-key slot (staging cleanup, full reset, etc.).
// Cipher / unknown / transient failures during these deletes are not fatal —
// the slot is either re-written on the next boot's repair path or remains
// stale until then. We funnel everything through [safeSecureDelete] so a
// platform exception cannot escape and crash the call site.
Future<SecureDeleteResult> _safeDelete(String key) => safeSecureDelete(key);

// ---------------------------------------------------------------------------
// Keychain repair state (Prism 0.9.2 secure storage remediation §3)
// ---------------------------------------------------------------------------

/// SharedPreferences flag set while the boot probe has recovered the app DB
/// key via a non-primary slot (sync slot, sync-staging slot, etc.). Set by
/// the §4 boot probe; cleared by the guarded writer once the matching key has
/// been re-written into the primary slot.
///
/// While this flag is true, the guarded writers in this file refuse:
///   * any divergent value into the primary DB-key slots
///   * any write at all to the staging slots (no key rotation while keychain
///     is in a known-broken state)
///
/// See `docs/0.9.2-secure-storage-remediation.md` §3 for details.
const kKeychainRepairPendingKey = 'prism.keychain.repair_pending';

/// Riverpod provider exposing the DB key hex that the §4 boot probe verified
/// against the on-disk encrypted database.
///
/// **§3 contract:** the default override below throws. `main.dart` (§6) MUST
/// supply a real override via `ProviderScope.overrides`:
///
/// ```dart
/// ProviderScope(
///   overrides: [
///     verifiedStartupKeyProvider.overrideWithValue(probeResult.keyInMemory),
///   ],
///   child: PrismApp(),
/// );
/// ```
///
/// Tests override the provider directly via `ProviderContainer(overrides: ...)`.
///
/// The value is the 64-character lowercase hex form of the verified app DB
/// encryption key, or `null` if the probe could not recover one (in which case
/// guarded writes during repair-pending will refuse).
final verifiedStartupKeyProvider = Provider<String?>((ref) {
  throw UnimplementedError(
    'verifiedStartupKeyProvider must be overridden by main.dart with the '
    'boot probe result. See docs/0.9.2-secure-storage-remediation.md §3.',
  );
});

/// Read the SharedPref flag indicating an in-progress keychain repair.
Future<bool> isKeychainRepairPending() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(kKeychainRepairPendingKey) ?? false;
}

/// Write the SharedPref flag indicating an in-progress keychain repair.
Future<void> setKeychainRepairPending(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  if (value) {
    await prefs.setBool(kKeychainRepairPendingKey, true);
  } else {
    await prefs.remove(kKeychainRepairPendingKey);
  }
}

// ---------------------------------------------------------------------------
// Key validation
// ---------------------------------------------------------------------------

/// Whether [hex] is a valid 64-character lowercase hex string (32 bytes).
bool validateHexKey(String? hex) {
  if (hex == null || hex.length != 64) return false;
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(hex);
}

// ---------------------------------------------------------------------------
// Classified secure-storage reads with transient retry
// ---------------------------------------------------------------------------

/// Jittered exponential backoff for transient secure-storage failures.
///
/// Two retry attempts:
///   * attempt 1: 100ms ± 50ms
///   * attempt 2: 400ms ± 100ms
///
/// Cipher and unknown failures do NOT retry — they're treated as terminal.
/// Returns the recovered hex value, or null after all retries fail.
///
/// [slotLabel] is used in debug log lines so callers can tell which slot
/// failed without inspecting stack traces.
Future<String?> _readWithTransientRetry(
  String key, {
  required String slotLabel,
  Random? random,
}) async {
  final rng = random ?? Random();

  // Attempt 0: no delay.
  // Attempt 1: ~100ms ± 50ms.
  // Attempt 2: ~400ms ± 100ms.
  const baseDelaysMs = <int>[0, 100, 400];
  const jitterRangesMs = <int>[0, 50, 100];

  for (var attempt = 0; attempt < baseDelaysMs.length; attempt++) {
    if (attempt > 0) {
      final base = baseDelaysMs[attempt];
      final jitterRange = jitterRangesMs[attempt];
      // Symmetric jitter in [-jitterRange, +jitterRange].
      final jitter = jitterRange == 0
          ? 0
          : rng.nextInt(jitterRange * 2 + 1) - jitterRange;
      final delayMs = (base + jitter).clamp(0, base + jitterRange).toInt();
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }

    final result = await safeSecureRead(key);
    if (result.ok) {
      return result.value;
    }

    switch (result.failure) {
      case SecureStorageFailure.cipher:
        debugPrint(
          '[DB_ENCRYPT] Cipher failure reading $slotLabel — treating as missing '
          '(code=${result.code})',
        );
        return null;
      case SecureStorageFailure.unknown:
        debugPrint(
          '[DB_ENCRYPT] Unknown failure reading $slotLabel — treating as missing '
          '(code=${result.code}, message=${result.message})',
        );
        return null;
      case SecureStorageFailure.transient:
        // Loop continues; retry after backoff. Only log the final exhaustion.
        if (attempt == baseDelaysMs.length - 1) {
          debugPrint(
            '[DB_ENCRYPT] Transient failures exhausted for $slotLabel — '
            'treating as missing (code=${result.code})',
          );
          return null;
        }
        continue;
      case null:
        // Unreachable: result.ok would be true.
        return result.value;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Key management — reads
// ---------------------------------------------------------------------------

/// Read [key] and classify the outcome into a [SlotOutcome] alongside the
/// returned hex value.
///
/// Used by the boot probes (§4/§5) to populate per-slot diagnostic
/// outcomes. Mirrors [_readWithTransientRetry]'s policy (cipher/unknown
/// treated as terminal, transients retried twice) but returns the
/// classification rather than swallowing it.
///
/// Returns a record:
///   * `hex`     — the validated hex key, or null when missing /
///                 invalid / failed.
///   * `outcome` — one of [SlotOutcome.ok], [SlotOutcome.cipher],
///                 [SlotOutcome.transient], [SlotOutcome.unknown],
///                 [SlotOutcome.missing], [SlotOutcome.invalidHex].
///                 (`threw` is reserved for unclassified exceptions
///                 outside this read — the probe records those at the
///                 boundary.)
Future<({String? hex, SlotOutcome outcome})> readSlotForDiagnostic(
  String key, {
  required String slotLabel,
  Random? random,
}) async {
  final rng = random ?? Random();

  const baseDelaysMs = <int>[0, 100, 400];
  const jitterRangesMs = <int>[0, 50, 100];
  SecureStorageFailure? lastFailure;

  for (var attempt = 0; attempt < baseDelaysMs.length; attempt++) {
    if (attempt > 0) {
      final base = baseDelaysMs[attempt];
      final jitterRange = jitterRangesMs[attempt];
      final jitter = jitterRange == 0
          ? 0
          : rng.nextInt(jitterRange * 2 + 1) - jitterRange;
      final delayMs = (base + jitter).clamp(0, base + jitterRange).toInt();
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }

    final result = await safeSecureRead(key);
    if (result.ok) {
      final value = result.value;
      if (value == null) {
        return (hex: null, outcome: SlotOutcome.missing);
      }
      if (!validateHexKey(value)) {
        debugPrint(
          '[DB_ENCRYPT] $slotLabel returned an invalid hex value '
          '(${value.length} chars) — outcome=invalid_hex',
        );
        return (hex: null, outcome: SlotOutcome.invalidHex);
      }
      return (hex: value, outcome: SlotOutcome.ok);
    }

    lastFailure = result.failure;
    switch (result.failure) {
      case SecureStorageFailure.cipher:
        debugPrint(
          '[DB_ENCRYPT] Cipher failure reading $slotLabel (code=${result.code})',
        );
        return (hex: null, outcome: SlotOutcome.cipher);
      case SecureStorageFailure.unknown:
        debugPrint(
          '[DB_ENCRYPT] Unknown failure reading $slotLabel '
          '(code=${result.code}, message=${result.message})',
        );
        return (hex: null, outcome: SlotOutcome.unknown);
      case SecureStorageFailure.transient:
        if (attempt == baseDelaysMs.length - 1) {
          debugPrint(
            '[DB_ENCRYPT] Transient failures exhausted for $slotLabel '
            '(code=${result.code})',
          );
          return (hex: null, outcome: SlotOutcome.transient);
        }
        continue;
      case null:
        return (hex: result.value, outcome: SlotOutcome.ok);
    }
  }
  // Unreachable in practice (loop always returns) — fall through to a
  // best-guess based on the last observed failure.
  return (
    hex: null,
    outcome: switch (lastFailure) {
      SecureStorageFailure.cipher => SlotOutcome.cipher,
      SecureStorageFailure.transient => SlotOutcome.transient,
      SecureStorageFailure.unknown => SlotOutcome.unknown,
      null => SlotOutcome.missing,
    },
  );
}

/// Read the cached database encryption key from secure storage.
///
/// Returns the hex-encoded key string suitable for
/// `PRAGMA key = "x'<hex>'";`, or null if no key has been cached yet, the
/// stored value is malformed, or the read failed.
///
/// Failures are classified by [safeSecureRead]: cipher and unknown failures
/// resolve to null without retry; transient failures retry twice with jittered
/// exponential backoff before giving up.
Future<String?> readDatabaseKeyHex() async {
  final hex = await _readWithTransientRetry(
    kDatabaseKeyStorageKey,
    slotLabel: 'primary DB key',
  );
  if (hex == null) return null;
  if (!validateHexKey(hex)) {
    debugPrint(
      '[DB_ENCRYPT] Invalid key in keychain (${hex.length} chars) — treating as missing',
    );
    return null;
  }
  return hex;
}

/// Read the staging database encryption key from secure storage.
///
/// This slot is written by `rotateDatabaseToKey` before issuing PRAGMA rekey,
/// then deleted after the primary slot is updated. If it exists on startup, it
/// means the app crashed between the PRAGMA rekey and the primary slot write.
Future<String?> readStagingDatabaseKeyHex() async {
  final hex = await _readWithTransientRetry(
    '${kDatabaseKeyStorageKey}_staging',
    slotLabel: 'primary DB staging key',
  );
  if (hex == null) return null;
  if (!validateHexKey(hex)) {
    debugPrint(
      '[DB_ENCRYPT] Invalid staging key (${hex.length} chars) — ignoring',
    );
    return null;
  }
  return hex;
}

/// Read the Rust sync database key from secure storage.
Future<String?> readSyncDatabaseKeyHex() async {
  final hex = await _readWithTransientRetry(
    kSyncDatabaseKeyStorageKey,
    slotLabel: 'sync DB key',
  );
  if (hex == null) return null;
  if (!validateHexKey(hex)) {
    debugPrint(
      '[DB_ENCRYPT] Invalid sync DB key in keychain (${hex.length} chars) — treating as missing',
    );
    return null;
  }
  return hex;
}

/// Read the staging sync database key from secure storage.
Future<String?> readStagingSyncDatabaseKeyHex() async {
  final hex = await _readWithTransientRetry(
    '${kSyncDatabaseKeyStorageKey}_staging',
    slotLabel: 'sync DB staging key',
  );
  if (hex == null) return null;
  if (!validateHexKey(hex)) {
    debugPrint('[DB_ENCRYPT] Invalid sync DB staging key — ignoring');
    return null;
  }
  return hex;
}

// ---------------------------------------------------------------------------
// Key management — guarded writes
// ---------------------------------------------------------------------------
//
// Every DB-key write must go through one of the guarded writers below. While
// the SharedPref flag [kKeychainRepairPendingKey] is set:
//   * Primary slot writes refuse divergent values. The only allowed value is
//     [verifiedStartupKey]. A matching write succeeds and the caller is
//     responsible for clearing the flag.
//   * Staging slot writes are blocked entirely — no key rotation while the
//     keychain is in a known-broken state.
//
// Callers that have a Riverpod [Ref] in scope MUST pass
// `verifiedStartupKey: ref.read(verifiedStartupKeyProvider)`. Callers that do
// not have a Ref (legacy top-level helpers, FFI bridges) pass `null`; in that
// case the guard refuses any divergent write while pending. §4 wires up the
// provider on every primary write path.

/// Write [hex] into the primary Drift DB key slot, gated by the keychain
/// repair-pending flag.
///
/// While `keychain_repair_pending` is set:
///   * If [verifiedStartupKey] is null this throws [StateError] — repair
///     cannot be verified without the boot probe's key.
///   * If [hex] equals [verifiedStartupKey] the write proceeds (this is how
///     repair succeeds; callers clear the flag on a successful write).
///   * Any other value throws [StateError] — refusing to overwrite a verified
///     working key with a divergent value.
///
/// Returns the underlying [SecureWriteResult] so callers can decide how to
/// surface platform-level write failures.
Future<SecureWriteResult> writeDatabaseKeyHex(
  String hex, {
  String? verifiedStartupKey,
}) async {
  await _guardPrimaryWrite(
    slotLabel: 'primary DB key',
    hex: hex,
    verifiedStartupKey: verifiedStartupKey,
  );
  return safeSecureWriteVerified(kDatabaseKeyStorageKey, hex);
}

/// Write [hex] into the primary sync DB key slot, gated by the keychain
/// repair-pending flag. Behaves identically to [writeDatabaseKeyHex] for the
/// sync DB slot.
Future<SecureWriteResult> writeSyncDatabaseKeyHex(
  String hex, {
  String? verifiedStartupKey,
}) async {
  await _guardPrimaryWrite(
    slotLabel: 'primary sync DB key',
    hex: hex,
    verifiedStartupKey: verifiedStartupKey,
  );
  return safeSecureWriteVerified(kSyncDatabaseKeyStorageKey, hex);
}

/// Write [hex] into the staging Drift DB key slot. Refused entirely while
/// keychain repair is pending — we don't trust the keystore enough to rotate
/// keys when the user's primary slot is suspect.
Future<SecureWriteResult> writeStagingDatabaseKeyHex(String hex) async {
  await _guardStagingWrite('primary DB staging key');
  return safeSecureWriteVerified('${kDatabaseKeyStorageKey}_staging', hex);
}

/// Write [hex] into the staging sync DB key slot. See
/// [writeStagingDatabaseKeyHex].
Future<SecureWriteResult> writeStagingSyncDatabaseKeyHex(String hex) async {
  await _guardStagingWrite('sync DB staging key');
  return safeSecureWriteVerified('${kSyncDatabaseKeyStorageKey}_staging', hex);
}

void _requireSecureWriteOk(SecureWriteResult result, String operation) {
  if (result.ok) return;
  throw StateError(
    '$operation failed '
    '(failure=${result.failure?.name ?? 'unknown'}, code=${result.code}, '
    'message=${result.message})',
  );
}

Future<void> _guardPrimaryWrite({
  required String slotLabel,
  required String hex,
  required String? verifiedStartupKey,
}) async {
  if (!await isKeychainRepairPending()) return;

  if (verifiedStartupKey == null) {
    debugPrint(
      '[DB_ENCRYPT] Refusing $slotLabel write while keychain_repair_pending '
      'is set and no verifiedStartupKey was supplied',
    );
    throw StateError(
      'Cannot write DB key while repair pending without a verified startup key',
    );
  }

  if (hex != verifiedStartupKey) {
    debugPrint(
      '[DB_ENCRYPT] Refusing divergent $slotLabel write while '
      'keychain_repair_pending is set (incoming != verifiedStartupKey)',
    );
    throw StateError(
      'Cannot persist divergent DB key while keychain repair is pending',
    );
  }

  // Matching write — allow. Caller clears the flag after success.
}

Future<void> _guardStagingWrite(String slotLabel) async {
  if (!await isKeychainRepairPending()) return;
  debugPrint(
    '[DB_ENCRYPT] Refusing $slotLabel rotation while '
    'keychain_repair_pending is set',
  );
  throw StateError(
    'Cannot rotate keys while keychain repair is pending — restart the '
    'app to retry repair first',
  );
}

// ---------------------------------------------------------------------------
// Key management — high-level writers (use the guarded writers above)
// ---------------------------------------------------------------------------

/// Promote the staging key to the primary slot and clean up the staging slot.
///
/// Called during startup crash recovery when the staging key has been verified
/// to open the database (PRAGMA rekey completed before the crash).
///
/// Goes through [writeDatabaseKeyHex] so the repair-pending guard applies. The
/// recovery flow that calls this is responsible for matching the caller's
/// verified startup key.
Future<void> promoteStagingDatabaseKey(
  String stagingHexKey, {
  String? verifiedStartupKey,
}) async {
  final writeResult = await writeDatabaseKeyHex(
    stagingHexKey,
    verifiedStartupKey: verifiedStartupKey,
  );
  _requireSecureWriteOk(writeResult, 'Promote staging DB key to primary slot');
  await _safeDelete('${kDatabaseKeyStorageKey}_staging');
  debugPrint('[DB_ENCRYPT] Promoted staging key to primary slot');
}

/// Discard the staging key slot without promoting it.
///
/// Called during startup crash recovery when the staging key does NOT open the
/// database — meaning the crash happened before PRAGMA rekey, so the DB still
/// has the old primary key and the staging slot is stale.
Future<void> discardStagingDatabaseKey() async {
  await _safeDelete('${kDatabaseKeyStorageKey}_staging');
  debugPrint('[DB_ENCRYPT] Discarded stale staging key (crash before rekey)');
}

/// Cache the database encryption key in secure storage.
///
/// [keyBytes] should be the raw 32-byte key from `ffi.databaseKey()`.
/// Stored as a lowercase hex string for direct use with PRAGMA key.
///
/// Goes through [writeDatabaseKeyHex] so the repair-pending guard applies.
Future<void> cacheDatabaseKey(
  Uint8List keyBytes, {
  String? verifiedStartupKey,
}) async {
  final hex = keyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final writeResult = await writeDatabaseKeyHex(
    hex,
    verifiedStartupKey: verifiedStartupKey,
  );
  _requireSecureWriteOk(writeResult, 'Cache Drift database key');
}

/// Restore the Drift database key from a verified recovery candidate.
///
/// The caller must first prove [hexKey] opens `prism.db`; this helper only
/// validates the key shape and writes it back to the primary keychain slot.
///
/// Goes through [writeDatabaseKeyHex] so the repair-pending guard applies.
Future<void> restoreDatabaseKeyHexForRecovery(
  String hexKey, {
  String? verifiedStartupKey,
}) async {
  if (!validateHexKey(hexKey)) {
    throw ArgumentError.value(hexKey, 'hexKey', 'invalid database key');
  }
  final writeResult = await writeDatabaseKeyHex(
    hexKey,
    verifiedStartupKey: verifiedStartupKey,
  );
  _requireSecureWriteOk(writeResult, 'Restore Drift database key');
  await _safeDelete('${kDatabaseKeyStorageKey}_staging');
  debugPrint('[DB_ENCRYPT] Restored missing database key from recovery slot');
}

/// Ensure a database encryption key exists in the platform keychain.
///
/// If a valid key already exists, returns it. Otherwise generates a new
/// 32-byte key via the platform CSPRNG (`Random.secure()`), persists it,
/// and verifies the write succeeded before returning.
///
/// This is the Signal model: encryption is always on, the key is device-bound,
/// and the user never interacts with it.
///
/// The internal probe read goes through [safeSecureRead] with transient
/// retry — same classification policy as [readDatabaseKeyHex]. The persist
/// step goes through the guarded [writeDatabaseKeyHex]; if a §4 boot probe
/// has flagged the keychain as repair-pending, callers must supply
/// [verifiedStartupKey].
Future<String> ensureLocalDatabaseKey({String? verifiedStartupKey}) async {
  final existing = await readDatabaseKeyHex();
  if (existing != null) return existing;

  // Generate 32 random bytes via platform CSPRNG.
  final rng = Random.secure();
  final bytes = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    bytes[i] = rng.nextInt(256);
  }
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  // Persist via the guarded writer (repair-pending may refuse).
  final writeResult = await writeDatabaseKeyHex(
    hex,
    verifiedStartupKey: verifiedStartupKey,
  );
  if (!writeResult.ok) {
    throw StateError(
      'Failed to persist newly-generated database encryption key '
      '(failure=${writeResult.failure}, code=${writeResult.code}, '
      'message=${writeResult.message}).',
    );
  }

  // Verify the write actually landed via a classified read with retry.
  final readBack = await _readWithTransientRetry(
    kDatabaseKeyStorageKey,
    slotLabel: 'primary DB key (post-generate verify)',
  );
  if (readBack != hex) {
    throw StateError(
      'Failed to persist database encryption key to platform keychain. '
      'Read-back did not match written value.',
    );
  }

  debugPrint('[DB_ENCRYPT] Generated and cached new local database key');
  return hex;
}

/// Clear the database encryption key from secure storage.
///
/// Called during a full data reset. The caller must delete the DB files
/// BEFORE calling this — otherwise next launch has no key for an encrypted DB.
Future<void> clearDatabaseEncryptionState() async {
  await _safeDelete(kDatabaseKeyStorageKey);
  await _safeDelete('${kDatabaseKeyStorageKey}_staging');
  // Also clear the sync DB dedicated slot and its staging slot.
  await _safeDelete(kSyncDatabaseKeyStorageKey);
  await _safeDelete('${kSyncDatabaseKeyStorageKey}_staging');
}

// ---------------------------------------------------------------------------
// Rust sync database key management (prism_sync.db)
// ---------------------------------------------------------------------------
//
// The Rust sync database uses a DEDICATED keychain slot so its key can be
// rotated independently from the Drift app database. Both converge to the
// same HKDF-derived local-storage key after cacheRuntimeKeys completes, but
// they are rotated one at a time (Drift first, Rust second) so a crash between
// the two rotations is safely recoverable via each DB's own staging slot.

/// Promote the sync DB staging key to the primary slot.
///
/// Goes through [writeSyncDatabaseKeyHex] so the repair-pending guard applies.
Future<void> promoteStagingSyncDatabaseKey(
  String stagingHexKey, {
  String? verifiedStartupKey,
}) async {
  final writeResult = await writeSyncDatabaseKeyHex(
    stagingHexKey,
    verifiedStartupKey: verifiedStartupKey,
  );
  _requireSecureWriteOk(
    writeResult,
    'Promote staging sync DB key to primary slot',
  );
  await _safeDelete('${kSyncDatabaseKeyStorageKey}_staging');
  debugPrint('[DB_ENCRYPT] Promoted sync DB staging key to primary slot');
}

/// Discard the sync DB staging slot without promoting it.
Future<void> discardStagingSyncDatabaseKey() async {
  await _safeDelete('${kSyncDatabaseKeyStorageKey}_staging');
  debugPrint('[DB_ENCRYPT] Discarded stale sync DB staging key');
}

/// Ensure a Rust sync database key exists in the platform keychain.
///
/// For existing installs (before this slot was introduced), seeds the sync
/// slot from the Drift [kDatabaseKeyStorageKey] slot so that `createPrismSync`
/// continues to open the sync DB with the same key it was using before the
/// split. On fresh installs both slots are generated independently.
Future<String> ensureLocalSyncDatabaseKey({String? verifiedStartupKey}) async {
  final existing = await readSyncDatabaseKeyHex();
  if (existing != null) return existing;

  // Migration path: the sync DB was previously opened with the Drift key.
  // Copy it to the new dedicated slot so the DB remains openable.
  final driftKey = await readDatabaseKeyHex();
  if (driftKey != null) {
    final writeResult = await writeSyncDatabaseKeyHex(
      driftKey,
      verifiedStartupKey: verifiedStartupKey,
    );
    _requireSecureWriteOk(writeResult, 'Migrate sync DB key from Drift slot');
    debugPrint(
      '[DB_ENCRYPT] Migrated sync DB key from Drift slot to dedicated slot',
    );
    return driftKey;
  }

  // Neither slot exists — generate a fresh key.
  final rng = Random.secure();
  final bytes = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    bytes[i] = rng.nextInt(256);
  }
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final writeResult = await writeSyncDatabaseKeyHex(
    hex,
    verifiedStartupKey: verifiedStartupKey,
  );
  _requireSecureWriteOk(writeResult, 'Generate sync database key');
  debugPrint('[DB_ENCRYPT] Generated and cached new sync database key');
  return hex;
}

// ---------------------------------------------------------------------------
// Shared probe utility
// ---------------------------------------------------------------------------

/// Try to open an encrypted SQLite file at [path] with [hexKey].
/// Returns true if the file exists, opens, and responds to a query.
///
/// Returns false immediately if the file does not exist (SQLite would otherwise
/// create an empty file, making the probe meaningless for crash recovery).
///
/// Used by both the Drift crash-recovery path (database_provider.dart) and
/// the Rust sync DB staging-recovery path (prism_sync_providers.dart).
bool tryOpenEncryptedDb(String path, String hexKey) {
  if (!File(path).existsSync()) return false;
  try {
    final db = raw.sqlite3.open(path);
    try {
      db.execute("PRAGMA key = \"x'$hexKey'\";");
      db.select('SELECT count(*) FROM sqlite_master;');
      return true;
    } finally {
      db.close();
    }
  } catch (_) {
    return false;
  }
}

/// Rotate the DB encryption key using PRAGMA rekey on an open Drift connection.
///
/// Takes raw bytes — hex-encodes internally (prevents injection).
/// Uses a staging keychain slot for crash recovery: if we crash after
/// PRAGMA rekey but before the primary keychain slot is written, the next
/// startup will read the staging slot and use it.
///
/// [db] must be the open Drift [AppDatabase] instance.
/// [newKey] must be exactly 32 bytes.
///
/// Goes through [writeStagingDatabaseKeyHex] / [writeDatabaseKeyHex] so the
/// repair-pending guard applies — rotation is refused entirely while a repair
/// is pending.
Future<void> rotateDatabaseToKey({
  required AppDatabase db,
  required Uint8List newKey,
  String? verifiedStartupKey,
}) async {
  if (newKey.length != 32) {
    throw ArgumentError(
      'rotateDatabaseToKey: key must be exactly 32 bytes, got ${newKey.length}',
    );
  }
  final newHexKey = newKey
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  // Write staging slot first — crash recovery: if we crash after PRAGMA rekey
  // but before the primary keychain write, startup reads the staging slot.
  // (Both writes go through the guarded writers; staging writes are refused
  // entirely while keychain repair is pending.)
  final stagingWrite = await writeStagingDatabaseKeyHex(newHexKey);
  _requireSecureWriteOk(
    stagingWrite,
    'Write Drift DB staging key before rekey',
  );
  await db.customStatement("PRAGMA rekey = \"x'$newHexKey'\";");
  final primaryWrite = await writeDatabaseKeyHex(
    newHexKey,
    verifiedStartupKey: verifiedStartupKey,
  );
  _requireSecureWriteOk(primaryWrite, 'Write Drift DB primary key after rekey');
  await _safeDelete('${kDatabaseKeyStorageKey}_staging');
}

// ---------------------------------------------------------------------------
// Drift setup callback
// ---------------------------------------------------------------------------

/// Returns a Drift `DatabaseSetup` callback that sets the encryption key
/// via PRAGMA. Pass this to `NativeDatabase.createInBackground(setup: ...)`.
///
/// SQLite3MultipleCiphers (sqlite3mc) uses its default cipher (AES-256 CBC)
/// when you supply a raw hex key with `PRAGMA key = "x'...'";`.
void Function(raw.Database) makeCipherSetup(String hexKey) {
  assert(
    validateHexKey(hexKey),
    'Invalid hex key: expected 64 lowercase hex chars',
  );
  return (raw.Database db) {
    // x'...' hex syntax passes raw key bytes (avoids SQL string escaping issues).
    db.execute("PRAGMA key = \"x'$hexKey'\";");
  };
}
