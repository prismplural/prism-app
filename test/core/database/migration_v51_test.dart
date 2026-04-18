import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

/// Migration test for plan 03 Phase 1 — schema v50 → v51.
///
/// Adds `pluralkit_id`, `pluralkit_uuid`, `last_seen_from_pk_at` columns to
/// `member_groups` + partial unique indexes on the two PK columns.
void main() {
  group('migration v50 → v51 (PK group link columns)', () {
    test('fresh database has the new columns + indexes', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // Force schema creation.
      await db.customSelect('SELECT 1').get();

      final cols = await db.customSelect(
        "SELECT name FROM pragma_table_info('member_groups')",
      ).get();
      final names = cols.map((r) => r.read<String>('name')).toSet();
      expect(names, containsAll(<String>{
        'pluralkit_id',
        'pluralkit_uuid',
        'last_seen_from_pk_at',
      }));

      final indexes = await db.customSelect(
        "SELECT name, [unique] FROM pragma_index_list('member_groups')",
      ).get();
      final indexByName = {
        for (final r in indexes)
          r.read<String>('name'): r.read<int>('unique'),
      };
      expect(indexByName.keys, contains('idx_member_groups_pluralkit_uuid'));
      expect(indexByName.keys, contains('idx_member_groups_pluralkit_id'));
      // UUID index is unique; short-ID index is NOT (R7: PK short IDs can be
      // recycled across groups).
      expect(indexByName['idx_member_groups_pluralkit_uuid'], 1);
      expect(indexByName['idx_member_groups_pluralkit_id'], 0);
    });

    test('upgrade from v50 adds columns, preserves existing data', () async {
      final tempDir =
          Directory.systemTemp.createTempSync('prism_migration_v51_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final dbFile = File('${tempDir.path}/upgrade.db');

      // Stub a v50 member_groups table (without the new columns).
      final rawDb = raw.sqlite3.open(dbFile.path);
      try {
        rawDb.execute('PRAGMA user_version = 50;');
        rawDb.execute('''
          CREATE TABLE member_groups (
            id TEXT NOT NULL PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT,
            color_hex TEXT,
            emoji TEXT,
            display_order INTEGER NOT NULL DEFAULT 0,
            parent_group_id TEXT,
            group_type INTEGER NOT NULL DEFAULT 0,
            filter_rules TEXT,
            created_at INTEGER NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0
          )
        ''');
        rawDb.execute(
          "INSERT INTO member_groups (id, name, display_order, group_type, "
          "created_at, is_deleted) VALUES ('g1', 'Core', 0, 0, 0, 0)",
        );
      } finally {
        rawDb.close();
      }

      final db = AppDatabase(NativeDatabase(dbFile));
      addTearDown(db.close);

      await db.customSelect('SELECT 1').get();

      final rows = await db.customSelect(
        'SELECT id, name, pluralkit_id, pluralkit_uuid, last_seen_from_pk_at '
        'FROM member_groups',
      ).get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String>('id'), 'g1');
      expect(rows.single.read<String>('name'), 'Core');
      // New columns default to null on existing rows.
      expect(rows.single.read<String?>('pluralkit_id'), isNull);
      expect(rows.single.read<String?>('pluralkit_uuid'), isNull);

      final indexes = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='index' "
        "AND tbl_name='member_groups'",
      ).get();
      final indexNames =
          indexes.map((r) => r.read<String>('name')).toSet();
      expect(indexNames, contains('idx_member_groups_pluralkit_uuid'));
      expect(indexNames, contains('idx_member_groups_pluralkit_id'));
    });
  });
}
