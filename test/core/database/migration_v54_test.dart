import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

/// Migration test for plan 06 — schema v53 → v54.
///
/// Adds nullable `target_member_id TEXT` to `reminders` for per-member
/// targeting of front-change reminders.
void main() {
  group('migration v53 → v54 (reminder target_member_id)', () {
    test('fresh database has the new column', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // Force schema creation.
      await db.customSelect('SELECT 1').get();

      final cols = await db.customSelect(
        "SELECT name FROM pragma_table_info('reminders')",
      ).get();
      final names = cols.map((r) => r.read<String>('name')).toSet();
      expect(names, contains('target_member_id'));
    });

    test('upgrade from v53 adds column and preserves data', () async {
      final tempDir =
          Directory.systemTemp.createTempSync('prism_migration_v54_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final dbFile = File('${tempDir.path}/upgrade.db');

      // Stub a v53 reminders table without the new column.
      final rawDb = raw.sqlite3.open(dbFile.path);
      try {
        rawDb.execute('PRAGMA user_version = 53;');
        rawDb.execute('''
          CREATE TABLE reminders (
            id TEXT NOT NULL PRIMARY KEY,
            name TEXT NOT NULL,
            message TEXT NOT NULL,
            trigger INTEGER NOT NULL DEFAULT 0,
            frequency TEXT,
            interval_days INTEGER,
            weekly_days TEXT,
            time_of_day TEXT,
            delay_hours INTEGER,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at INTEGER NOT NULL,
            modified_at INTEGER NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0
          )
        ''');
        rawDb.execute(
          "INSERT INTO reminders (id, name, message, trigger, is_active, "
          "created_at, modified_at, is_deleted) "
          "VALUES ('r1', 'Check in', 'Still fronting?', 1, 1, 0, 0, 0)",
        );
      } finally {
        rawDb.close();
      }

      final db = AppDatabase(NativeDatabase(dbFile));
      addTearDown(db.close);

      await db.customSelect('SELECT 1').get();

      final rows = await db.customSelect(
        'SELECT id, name, target_member_id FROM reminders',
      ).get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String>('id'), 'r1');
      expect(rows.single.read<String>('name'), 'Check in');
      // Existing row: new column defaults to null.
      expect(rows.single.read<String?>('target_member_id'), isNull);
    });
  });
}
