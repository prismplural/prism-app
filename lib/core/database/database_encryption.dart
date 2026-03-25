import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/services/secure_storage.dart';

// ---------------------------------------------------------------------------
// Secure storage keys
// ---------------------------------------------------------------------------

/// Hex-encoded 32-byte database encryption key, derived from DEK via HKDF.
///
/// Written when sync is first set up and the DEK becomes available.
/// Read on every subsequent app startup to open the database encrypted.
const kDatabaseKeyStorageKey = 'prism_sync.database_key';

/// Flag indicating the on-disk database file has been migrated to encrypted.
///
/// Set to "true" after a successful plaintext-to-encrypted migration so that
/// subsequent launches skip the migration step and open directly with the key.
const kDatabaseEncryptedFlag = 'prism_sync.database_encrypted';

const _storage = secureStorage;

// ---------------------------------------------------------------------------
// Key management
// ---------------------------------------------------------------------------

/// Read the cached database encryption key from secure storage.
///
/// Returns the hex-encoded key string suitable for
/// `PRAGMA key = "x'<hex>'";`, or null if no key has been cached yet
/// (sync not set up).
Future<String?> readDatabaseKeyHex() async {
  return _storage.read(key: kDatabaseKeyStorageKey);
}

/// Cache the database encryption key in secure storage.
///
/// [keyBytes] should be the raw 32-byte key from `ffi.databaseKey()`.
/// Stored as a lowercase hex string for direct use with PRAGMA key.
Future<void> cacheDatabaseKey(Uint8List keyBytes) async {
  final hex = keyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  await _storage.write(key: kDatabaseKeyStorageKey, value: hex);
}

// ---------------------------------------------------------------------------
// Encryption state tracking
// ---------------------------------------------------------------------------

/// Whether the on-disk database has already been migrated to encrypted format.
Future<bool> isDatabaseEncrypted() async {
  final flag = await _storage.read(key: kDatabaseEncryptedFlag);
  return flag == 'true';
}

/// Mark the database as encrypted in secure storage.
Future<void> markDatabaseEncrypted() async {
  await _storage.write(key: kDatabaseEncryptedFlag, value: 'true');
}

/// Clear all encryption-related keys from secure storage.
///
/// Called during a full data/sync reset to allow a fresh start.
Future<void> clearDatabaseEncryptionState() async {
  await _storage.delete(key: kDatabaseEncryptedFlag);
  await _storage.delete(key: kDatabaseKeyStorageKey);
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
  return (raw.Database db) {
    // Set the encryption key. The x'...' syntax passes raw key bytes.
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
    await markDatabaseEncrypted();
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
      checkpointDb.dispose();
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
      db.dispose();
    }

    // Verify we can open the now-encrypted database with the key
    final verifyDb = raw.sqlite3.open(dbFile.path);
    try {
      verifyDb.execute("PRAGMA key = \"x'$hexKey'\";");
      final result = verifyDb.select('SELECT count(*) FROM sqlite_master;');
      final tableCount = result.first.values.first as int;
      debugPrint('[DB_ENCRYPT] Verification passed: $tableCount tables found');
    } finally {
      verifyDb.dispose();
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

    await markDatabaseEncrypted();
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
          testDb.dispose();
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
