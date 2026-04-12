import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw;
import 'app_database.dart';
import 'database_encryption.dart';

/// The path to the app's main database file.
///
/// Exposed so that callers (e.g. the encryption migration in main.dart) can
/// access the file before the database is opened by Drift.
Future<File> getDatabaseFile() async {
  final dbFolder = await getApplicationDocumentsDirectory();
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
    await _excludeFromiCloudBackup(file.path);

    // Crash-recovery: if the staging slot exists, a previous rekey call
    // completed the PRAGMA rekey but crashed before writing the primary slot.
    // Use the staging slot as the authoritative key and clean it up.
    final stagingKey = await _readStagingKey();
    if (stagingKey != null) {
      await _recoverFromStagingKey(stagingKey);
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

      // Key exists but can't open as encrypted — DB may be plaintext
      // (upgrade from pre-encryption version where key was backfilled
      // before migration ran).
      // NOTE: migratePlaintextToEncrypted runs on the calling isolate (not a
      // background isolate). This is acceptable because:
      // 1. PRAGMA rekey is fast for typical database sizes (<100ms)
      // 2. This is a one-time migration from pre-encryption app versions
      // 3. LazyDatabase defers opening until first query, by which point
      //    the UI typically shows a loading state
      // For very large databases (>100MB), consider moving to compute().
      if (_tryOpenPlaintext(file.path)) {
        debugPrint('[DB_PROVIDER] Key exists but DB is plaintext — migrating');
        final migrated = await migratePlaintextToEncrypted(
          dbFile: file,
          hexKey: hexKey,
        );
        if (migrated) {
          return NativeDatabase.createInBackground(
            file,
            setup: makeCipherSetup(hexKey),
          );
        }
        // Migration failed — fall back to plaintext to preserve data.
        debugPrint('[DB_PROVIDER] Migration failed — falling back to plaintext');
        return NativeDatabase.createInBackground(file);
      }

      // Key exists but DB is neither openable with it nor plaintext.
      // Fail closed — the DB may be encrypted with a different key
      // (e.g. backup/restore where the keychain didn't transfer).
      throw StateError(
        'Database file exists but cannot be opened with the stored key '
        'or as plaintext. It may be encrypted with a different key or '
        'corrupted. A full data reset may be required.',
      );
    }

    // ── Path 3: DB file exists + no key ─────────────────────────────────
    // Upgrade from a version before always-on encryption, or keychain was
    // cleared. Probe the file to determine its state.
    if (_tryOpenPlaintext(file.path)) {
      debugPrint('[DB_PROVIDER] No key, plaintext DB — generating key and migrating');
      final key = await ensureLocalDatabaseKey();
      final migrated = await migratePlaintextToEncrypted(
        dbFile: file,
        hexKey: key,
      );
      if (migrated) {
        return NativeDatabase.createInBackground(
          file,
          setup: makeCipherSetup(key),
        );
      }
      // Migration failed — fall back to plaintext to preserve data.
      debugPrint('[DB_PROVIDER] Migration failed — falling back to plaintext');
      return NativeDatabase.createInBackground(file);
    }

    // DB exists, no key, and it's not plaintext — encrypted with a lost key.
    // Fail closed. This can happen after backup/restore where the
    // first_unlock_this_device keychain item didn't transfer.
    throw StateError(
      'Database file exists but cannot be opened as plaintext and no '
      'encryption key is available. The key may have been lost during '
      'backup/restore. A full data reset may be required.',
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

/// Try to open the database as plaintext (no encryption key) and read from it.
/// Returns true if the DB is readable without a key.
bool _tryOpenPlaintext(String path) {
  try {
    final db = raw.sqlite3.open(path);
    try {
      db.select('SELECT count(*) FROM sqlite_master;');
      return true;
    } finally {
      db.close();
    }
  } catch (_) {
    return false;
  }
}

Future<void> _excludeFromiCloudBackup(String path) async {
  if (!Platform.isIOS) return;
  try {
    const channel = MethodChannel('com.prism.prism_plurality/file_utils');
    await channel.invokeMethod<void>('excludeFromBackup', {'path': path});
  } catch (_) {
    // Non-fatal: if the channel call fails, the file is still encrypted.
  }
}

/// Read the staging key slot written by `rotateDatabaseToKey` for crash
/// recovery. Returns the hex key string, or null if no staging slot exists.
Future<String?> _readStagingKey() async {
  final staging = await readStagingDatabaseKeyHex();
  if (staging != null && validateHexKey(staging)) return staging;
  return null;
}

/// Promote the staging key to the primary slot and remove the staging slot.
Future<void> _recoverFromStagingKey(String stagingHexKey) async {
  debugPrint(
    '[DB_PROVIDER] Crash-recovery: promoting staging key to primary slot',
  );
  await promoteStagingDatabaseKey(stagingHexKey);
}
