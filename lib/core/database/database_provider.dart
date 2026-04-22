import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw;
import 'app_database.dart';
import 'database_encryption.dart';
import 'package:prism_plurality/core/services/app_data_dir.dart';
import 'package:prism_plurality/core/services/backup_exclusion.dart';

/// The path to the app's main database file.
///
/// Exposed so that startup and reset flows can access the file before Drift
/// opens the database.
Future<File> getDatabaseFile() async {
  final dbFolder = await getAppDataDir();
  return File(p.join(dbFolder.path, 'prism.db'));
}

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(_openConnection());
  ref.onDispose(db.close);
  return db;
});

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final file = await getDatabaseFile();
    await excludeFromiCloudBackup(file.path);

    // Crash-recovery: if the staging slot exists, a previous rekey call may
    // have completed PRAGMA rekey but crashed before writing the primary slot.
    // Verify the staging key actually opens the DB before promoting — if the
    // crash happened before PRAGMA rekey, the staging key was written but the
    // DB was never rekeyed, so promoting it would make the DB unopenable.
    final stagingKey = await _readStagingKey();
    if (stagingKey != null) {
      await _recoverFromStagingKey(stagingKey, file.path);
    }

    final hexKey = await readDatabaseKeyHex();

    // ── Path 1: No DB file on disk ──────────────────────────────────────
    // Fresh install or post-reset. Generate a key if needed, then let Drift
    // create a new encrypted database.
    if (!file.existsSync()) {
      final key = hexKey ?? await ensureLocalDatabaseKey();
      debugPrint('[DB_PROVIDER] Fresh install — creating encrypted database');
      return NativeDatabase.createInBackground(
        file,
        setup: makeCipherSetup(key),
      );
    }

    // ── Path 2: DB file exists + key exists ─────────────────────────────
    // Most common path on a normal restart.
    if (hexKey != null) {
      if (_tryOpenEncrypted(file.path, hexKey)) {
        debugPrint('[DB_PROVIDER] Opening encrypted database');
        return NativeDatabase.createInBackground(
          file,
          setup: makeCipherSetup(hexKey),
        );
      }

      // Key exists but DB does not open with it. Fail closed: the DB may be
      // encrypted with a different key (for example after backup/restore where
      // the keychain did not transfer), or it may be corrupted.
      throw StateError(
        'Database file exists but cannot be opened with the stored key '
        'or is corrupted. A full data reset may be required.',
      );
    }

    // ── Path 3: DB file exists + no key ─────────────────────────────────
    // DB exists but the keychain has no DB key. Fail closed. This can happen
    // after backup/restore where the first_unlock_this_device keychain item
    // did not transfer.
    throw StateError(
      'Database file exists but no encryption key is available. The key may '
      'have been lost during backup/restore. A full data reset may be required.',
    );
  });
}

// ---------------------------------------------------------------------------
// DB state probes — lightweight open/query/close to determine file state.
// ---------------------------------------------------------------------------

/// Try to open the database with the given encryption key and read from it.
/// Returns true if the DB is readable with this key.
bool _tryOpenEncrypted(String path, String hexKey) {
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

/// Read the staging key slot written by `rotateDatabaseToKey` for crash
/// recovery. Returns the hex key string, or null if no staging slot exists.
Future<String?> _readStagingKey() async {
  final staging = await readStagingDatabaseKeyHex();
  if (staging != null && validateHexKey(staging)) return staging;
  return null;
}

/// Promote the staging key to the primary slot if — and only if — the DB
/// actually opens with that key.
///
/// Two crash scenarios:
/// 1. Crash AFTER PRAGMA rekey, BEFORE primary-slot write → staging key opens
///    the DB. Safe to promote.
/// 2. Crash BEFORE PRAGMA rekey (during or after staging-slot write) → staging
///    key does NOT open the DB (old key still applies). Discard staging slot;
///    startup proceeds with the existing primary key.
Future<void> _recoverFromStagingKey(String stagingHexKey, String dbPath) async {
  if (!File(dbPath).existsSync()) {
    // No DB file yet — staging slot is stale. Clean it up.
    await discardStagingDatabaseKey();
    return;
  }

  if (_tryOpenEncrypted(dbPath, stagingHexKey)) {
    // PRAGMA rekey completed. Staging key is the real key — promote it.
    debugPrint(
      '[DB_PROVIDER] Crash-recovery: staging key verified — promoting to primary slot',
    );
    await promoteStagingDatabaseKey(stagingHexKey);
  } else {
    // PRAGMA rekey did not complete. DB still has the old key.
    // Discard the staging slot; startup will use the existing primary key.
    await discardStagingDatabaseKey();
  }
}
