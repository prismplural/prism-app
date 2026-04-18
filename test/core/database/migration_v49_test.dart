import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

/// Migration test for plan 08 Phase 1 — schema v48 → v49.
///
/// Adds the `mapping_acknowledged` column to `plural_kit_sync_state` so the
/// connection can be gated in `connected_pending_map` until the user runs
/// the mapping flow.
void main() {
  group('migration v48 → v49 (connected_pending_map)', () {
    test('fresh database has mapping_acknowledged column', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // Force schema creation.
      await db.customSelect('SELECT 1').get();

      final cols = await db.customSelect(
        "SELECT name FROM pragma_table_info('plural_kit_sync_state')",
      ).get();
      expect(
        cols.map((r) => r.read<String>('name')),
        contains('mapping_acknowledged'),
      );
    });

    test('upgrade from v48 adds column, defaults to 0 for existing rows',
        () async {
      final tempDir =
          Directory.systemTemp.createTempSync('prism_migration_v49_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final dbFile = File('${tempDir.path}/upgrade.db');

      // Stub a v48 plural_kit_sync_state table (without the new column).
      final rawDb = raw.sqlite3.open(dbFile.path);
      try {
        rawDb.execute('PRAGMA user_version = 48;');
        rawDb.execute('''
          CREATE TABLE plural_kit_sync_state (
            id TEXT NOT NULL PRIMARY KEY,
            system_id TEXT,
            last_sync_date INTEGER,
            last_manual_sync_date INTEGER,
            is_connected INTEGER NOT NULL DEFAULT 0,
            field_sync_config TEXT
          )
        ''');
        rawDb.execute(
          "INSERT INTO plural_kit_sync_state (id, system_id, is_connected) "
          "VALUES ('pk_config', 'sys-1', 1)",
        );
      } finally {
        rawDb.close();
      }

      final db = AppDatabase(NativeDatabase(dbFile));
      addTearDown(db.close);

      await db.customSelect('SELECT 1').get();

      final rows = await db.customSelect(
        'SELECT id, is_connected, mapping_acknowledged '
        'FROM plural_kit_sync_state',
      ).get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String>('id'), 'pk_config');
      expect(rows.single.read<int>('is_connected'), 1);
      // Existing connections get mapping_acknowledged=0 → flagged for the
      // mapping flow, not silently auto-syncing.
      expect(rows.single.read<int>('mapping_acknowledged'), 0);
    });
  });
}
