import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/services/secure_storage.dart';

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

const _storage = secureStorage;

// ---------------------------------------------------------------------------
// Key validation
// ---------------------------------------------------------------------------

/// Whether [hex] is a valid 64-character lowercase hex string (32 bytes).
bool validateHexKey(String? hex) {
  if (hex == null || hex.length != 64) return false;
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(hex);
}

// ---------------------------------------------------------------------------
// Key management
// ---------------------------------------------------------------------------

/// Read the cached database encryption key from secure storage.
///
/// Returns the hex-encoded key string suitable for
/// `PRAGMA key = "x'<hex>'";`, or null if no key has been cached yet.
Future<String?> readDatabaseKeyHex() async {
  final hex = await _storage.read(key: kDatabaseKeyStorageKey);
  // Treat corrupted/invalid keys as missing so the caller can recover.
  if (hex != null && !validateHexKey(hex)) {
    debugPrint('[DB_ENCRYPT] Invalid key in keychain (${hex.length} chars) — treating as missing');
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
  final hex = await _storage.read(key: '${kDatabaseKeyStorageKey}_staging');
  if (hex != null && !validateHexKey(hex)) {
    debugPrint('[DB_ENCRYPT] Invalid staging key (${hex.length} chars) — ignoring');
    return null;
  }
  return hex;
}

/// Promote the staging key to the primary slot and clean up the staging slot.
///
/// Called during startup crash recovery when the staging key has been verified
/// to open the database (PRAGMA rekey completed before the crash).
Future<void> promoteStagingDatabaseKey(String stagingHexKey) async {
  await _storage.write(key: kDatabaseKeyStorageKey, value: stagingHexKey);
  await _storage.delete(key: '${kDatabaseKeyStorageKey}_staging');
  debugPrint('[DB_ENCRYPT] Promoted staging key to primary slot');
}

/// Discard the staging key slot without promoting it.
///
/// Called during startup crash recovery when the staging key does NOT open the
/// database — meaning the crash happened before PRAGMA rekey, so the DB still
/// has the old primary key and the staging slot is stale.
Future<void> discardStagingDatabaseKey() async {
  await _storage.delete(key: '${kDatabaseKeyStorageKey}_staging');
  debugPrint('[DB_ENCRYPT] Discarded stale staging key (crash before rekey)');
}

/// Cache the database encryption key in secure storage.
///
/// [keyBytes] should be the raw 32-byte key from `ffi.databaseKey()`.
/// Stored as a lowercase hex string for direct use with PRAGMA key.
Future<void> cacheDatabaseKey(Uint8List keyBytes) async {
  final hex = keyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  await _storage.write(key: kDatabaseKeyStorageKey, value: hex);
}

/// Ensure a database encryption key exists in the platform keychain.
///
/// If a valid key already exists, returns it. Otherwise generates a new
/// 32-byte key via the platform CSPRNG (`Random.secure()`), persists it,
/// and verifies the write succeeded before returning.
///
/// This is the Signal model: encryption is always on, the key is device-bound,
/// and the user never interacts with it.
Future<String> ensureLocalDatabaseKey() async {
  final existing = await readDatabaseKeyHex();
  if (existing != null) return existing;

  // Generate 32 random bytes via platform CSPRNG.
  final rng = Random.secure();
  final bytes = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    bytes[i] = rng.nextInt(256);
  }
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  // Persist and verify the write succeeded.
  await _storage.write(key: kDatabaseKeyStorageKey, value: hex);
  final readBack = await _storage.read(key: kDatabaseKeyStorageKey);
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
  await _storage.delete(key: kDatabaseKeyStorageKey);
  await _storage.delete(key: '${kDatabaseKeyStorageKey}_staging');
  // Also clear the sync DB dedicated slot and its staging slot.
  await _storage.delete(key: kSyncDatabaseKeyStorageKey);
  await _storage.delete(key: '${kSyncDatabaseKeyStorageKey}_staging');
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

/// Read the Rust sync database key from secure storage.
Future<String?> readSyncDatabaseKeyHex() async {
  final hex = await _storage.read(key: kSyncDatabaseKeyStorageKey);
  if (hex != null && !validateHexKey(hex)) {
    debugPrint(
      '[DB_ENCRYPT] Invalid sync DB key in keychain (${hex.length} chars) — treating as missing',
    );
    return null;
  }
  return hex;
}

/// Read the staging sync database key from secure storage.
Future<String?> readStagingSyncDatabaseKeyHex() async {
  final hex =
      await _storage.read(key: '${kSyncDatabaseKeyStorageKey}_staging');
  if (hex != null && !validateHexKey(hex)) {
    debugPrint('[DB_ENCRYPT] Invalid sync DB staging key — ignoring');
    return null;
  }
  return hex;
}

/// Promote the sync DB staging key to the primary slot.
Future<void> promoteStagingSyncDatabaseKey(String stagingHexKey) async {
  await _storage.write(key: kSyncDatabaseKeyStorageKey, value: stagingHexKey);
  await _storage.delete(key: '${kSyncDatabaseKeyStorageKey}_staging');
  debugPrint('[DB_ENCRYPT] Promoted sync DB staging key to primary slot');
}

/// Discard the sync DB staging slot without promoting it.
Future<void> discardStagingSyncDatabaseKey() async {
  await _storage.delete(key: '${kSyncDatabaseKeyStorageKey}_staging');
  debugPrint('[DB_ENCRYPT] Discarded stale sync DB staging key');
}

/// Ensure a Rust sync database key exists in the platform keychain.
///
/// For existing installs (before this slot was introduced), seeds the sync
/// slot from the Drift [kDatabaseKeyStorageKey] slot so that `createPrismSync`
/// continues to open the sync DB with the same key it was using before the
/// split. On fresh installs both slots are generated independently.
Future<String> ensureLocalSyncDatabaseKey() async {
  final existing = await readSyncDatabaseKeyHex();
  if (existing != null) return existing;

  // Migration path: the sync DB was previously opened with the Drift key.
  // Copy it to the new dedicated slot so the DB remains openable.
  final driftKey = await readDatabaseKeyHex();
  if (driftKey != null) {
    await _storage.write(key: kSyncDatabaseKeyStorageKey, value: driftKey);
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
  await _storage.write(key: kSyncDatabaseKeyStorageKey, value: hex);
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
Future<void> rotateDatabaseToKey({
  required AppDatabase db,
  required Uint8List newKey,
}) async {
  if (newKey.length != 32) {
    throw ArgumentError(
      'rotateDatabaseToKey: key must be exactly 32 bytes, got ${newKey.length}',
    );
  }
  final newHexKey =
      newKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  // Write staging slot first — crash recovery: if we crash after PRAGMA rekey
  // but before the primary keychain write, startup reads the staging slot.
  await _storage.write(
    key: '${kDatabaseKeyStorageKey}_staging',
    value: newHexKey,
  );
  await db.customStatement("PRAGMA rekey = \"x'$newHexKey'\";");
  await _storage.write(key: kDatabaseKeyStorageKey, value: newHexKey);
  await _storage.delete(key: '${kDatabaseKeyStorageKey}_staging');
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
  assert(validateHexKey(hexKey), 'Invalid hex key: expected 64 lowercase hex chars');
  return (raw.Database db) {
    // x'...' hex syntax passes raw key bytes (avoids SQL string escaping issues).
    db.execute("PRAGMA key = \"x'$hexKey'\";");
  };
}

// ---------------------------------------------------------------------------
// Plaintext -> encrypted migration
// ---------------------------------------------------------------------------

/// Migrate a plaintext database file to an encrypted one.
///
/// Uses a safe copy-based approach:
/// 1. Back up the plaintext database
/// 2. Open plaintext, ATTACH a new encrypted DB, copy all data via backup API
/// 3. Verify the encrypted database is readable
/// 4. Replace the original with the encrypted version
///
/// On failure the original plaintext DB is preserved.
///
/// **Must be called before Drift opens the database** (i.e. at startup).
Future<bool> migratePlaintextToEncrypted({
  required File dbFile,
  required String hexKey,
}) async {
  if (!dbFile.existsSync()) {
    // No database file yet -- nothing to migrate. Drift will create a new
    // encrypted database when it opens with the setup callback.
    return true;
  }

  final backupPath = '${dbFile.path}.bak';
  final backupFile = File(backupPath);

  try {
    // Clean up leftover files from a previous failed migration
    if (backupFile.existsSync()) backupFile.deleteSync();

    // First, make a safety backup of the plaintext database.
    dbFile.copySync(backupPath);

    // Checkpoint any WAL data into the main database file first.
    // This ensures all data is in the main file before we encrypt it.
    final checkpointDb = raw.sqlite3.open(dbFile.path);
    try {
      checkpointDb.execute('PRAGMA wal_checkpoint(TRUNCATE);');
    } catch (_) {
      // WAL checkpoint may fail if there's no WAL — that's fine.
    } finally {
      checkpointDb.close();
    }

    // Open the plaintext database and encrypt it using PRAGMA rekey.
    // SQLite3MultipleCiphers supports rekey on unencrypted databases
    // to encrypt them in-place.
    final db = raw.sqlite3.open(dbFile.path);
    try {
      // Verify it's readable as plaintext
      db.execute('SELECT count(*) FROM sqlite_master;');

      // Encrypt the database in-place with PRAGMA rekey
      db.execute("PRAGMA rekey = \"x'$hexKey'\";");
    } finally {
      db.close();
    }

    // Verify we can open the now-encrypted database with the key
    final verifyDb = raw.sqlite3.open(dbFile.path);
    try {
      verifyDb.execute("PRAGMA key = \"x'$hexKey'\";");
      final result = verifyDb.select('SELECT count(*) FROM sqlite_master;');
      final tableCount = result.first.values.first as int;
      debugPrint('[DB_ENCRYPT] Verification passed: $tableCount tables found');
    } finally {
      verifyDb.close();
    }

    // Remove WAL/SHM files (encrypted DB starts with a clean journal)
    for (final suffix in ['-wal', '-shm']) {
      final f = File('${dbFile.path}$suffix');
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }

    // Clean up the backup now that encryption succeeded
    if (backupFile.existsSync()) {
      try {
        backupFile.deleteSync();
      } catch (_) {}
    }

    debugPrint('[DB_ENCRYPT] Successfully encrypted database');
    return true;
  } catch (e, st) {
    debugPrint('[DB_ENCRYPT] Migration failed: $e');
    if (kDebugMode) {
      debugPrint('[DB_ENCRYPT] Stack trace: $st');
    }

    // Restore backup if the in-place encryption corrupted the file
    if (backupFile.existsSync()) {
      try {
        // Check if the original is still readable
        bool originalOk = false;
        try {
          final testDb = raw.sqlite3.open(dbFile.path);
          testDb.execute('SELECT count(*) FROM sqlite_master;');
          testDb.close();
          originalOk = true;
        } catch (_) {
          originalOk = false;
        }

        if (!originalOk) {
          // Original is corrupted -- restore from backup
          if (dbFile.existsSync()) dbFile.deleteSync();
          backupFile.renameSync(dbFile.path);
          debugPrint('[DB_ENCRYPT] Restored plaintext backup after failure');
        } else {
          // Original is still fine -- just clean up backup
          backupFile.deleteSync();
        }
      } catch (restoreError) {
        debugPrint(
          '[DB_ENCRYPT] CRITICAL: Failed to restore backup: $restoreError',
        );
      }
    }

    return false;
  }
}
