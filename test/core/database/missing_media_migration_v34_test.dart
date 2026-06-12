import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/missing_media_dao.dart';

/// Seeds a v32 (released floor) database: open via [AppDatabase] to materialise
/// the current schema, then drop the media heal `missing_media` table and reset
/// PRAGMA user_version = 32 so the collapsed v32→v37 migration is forced to run
/// (and recreate it) on the next open.
Future<void> _seedV32Db(File dbFile) async {
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  await seeded.close();

  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    rawDb.execute('DROP TABLE IF EXISTS missing_media');
    rawDb.execute('PRAGMA user_version = 32;');
  } finally {
    rawDb.close();
  }
}

void main() {
  test('v32→v37 migration creates the missing_media table', () async {
    final dir = await Directory.systemTemp.createTemp('mm_migration');
    addTearDown(() => dir.delete(recursive: true));
    final dbFile = File('${dir.path}/app.db');

    await _seedV32Db(dbFile);

    // Confirm the table is gone pre-migration.
    final before = raw.sqlite3.open(dbFile.path);
    final missing = before
        .select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='missing_media'",
        )
        .isEmpty;
    before.close();
    expect(missing, isTrue, reason: 'seed removed the table');

    // Reopen → onUpgrade 32→37 runs.
    final upgraded = AppDatabase(NativeDatabase(dbFile));
    addTearDown(upgraded.close);
    await upgraded.customSelect('SELECT 1').get();

    // The table now exists and the DAO round-trips.
    await upgraded.missingMediaDao.markMissing(
      mediaId: 'm',
      priority: MissingMediaDao.priorityChat,
      nowMs: 1000,
    );
    final row = await upgraded.missingMediaDao.getById('m');
    expect(row, isNotNull);
    expect(row!.firstMissingAt, 1000);
    expect(row.state, 'pending');
    expect(row.priority, MissingMediaDao.priorityChat);
  });

  test('v32→v37 migration is idempotent when the table already exists', () async {
    final dir = await Directory.systemTemp.createTemp('mm_migration2');
    addTearDown(() => dir.delete(recursive: true));
    final dbFile = File('${dir.path}/app.db');

    // Open at current schema (table present), then force user_version back to
    // 32 WITHOUT dropping the table — the guarded createTable must not throw.
    final seeded = AppDatabase(NativeDatabase(dbFile));
    await seeded.customSelect('SELECT 1').get();
    await seeded.close();
    final rawDb = raw.sqlite3.open(dbFile.path);
    rawDb.execute('PRAGMA user_version = 32;');
    rawDb.close();

    final upgraded = AppDatabase(NativeDatabase(dbFile));
    addTearDown(upgraded.close);
    // Should not throw despite the table already existing.
    await upgraded.customSelect('SELECT 1').get();
    expect(await upgraded.missingMediaDao.pendingCount(), 0);
  });
}
