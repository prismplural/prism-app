import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
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

    // Check if we have a database encryption key cached in secure storage.
    final hexKey = await readDatabaseKeyHex();
    final encrypted = await isDatabaseEncrypted();

    if (hexKey != null && encrypted) {
      // Database is encrypted — open with the cipher setup callback.
      debugPrint('[DB_PROVIDER] Opening encrypted database');
      return NativeDatabase.createInBackground(
        file,
        setup: makeCipherSetup(hexKey),
      );
    }

    if (hexKey != null && !encrypted) {
      // Key is available but database hasn't been migrated yet.
      // This can happen if the migration at startup failed or was skipped.
      // Attempt migration now before opening.
      debugPrint('[DB_PROVIDER] Key available but DB not encrypted — attempting migration');
      final migrated = await migratePlaintextToEncrypted(
        dbFile: file,
        hexKey: hexKey,
      );
      if (migrated) {
        debugPrint('[DB_PROVIDER] Migration succeeded — opening encrypted');
        return NativeDatabase.createInBackground(
          file,
          setup: makeCipherSetup(hexKey),
        );
      } else {
        // Migration failed — fall back to plaintext to avoid data loss.
        debugPrint('[DB_PROVIDER] Migration failed — falling back to plaintext');
        return NativeDatabase.createInBackground(file);
      }
    }

    // No encryption key available (sync not set up) — open plaintext.
    debugPrint('[DB_PROVIDER] No database key — opening plaintext');
    return NativeDatabase.createInBackground(file);
  });
}
