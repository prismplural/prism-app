import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

/// Migration test for plan 08 Phase 0 — schema v47 → v48.
///
/// Verifies that upgrading an existing v47 database adds:
/// - new PK columns on `members` and `fronting_sessions`
/// - the `pk_mapping_state` table
/// - the three PK partial unique indexes
///
/// The v47 baseline is stubbed with just the minimum tables the v48 migration
/// touches — we don't need a full v47 dump, since the migration only runs
/// ALTER / CREATE statements against specific tables.
void main() {
  group('migration v47 → v48 (pk bidirectional sync prereqs)', () {
    test('fresh database has new columns + table + partial indexes', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      Future<List<String>> columnsOf(String table) async {
        final rows = await db.customSelect(
          "SELECT name FROM pragma_table_info('$table')",
        ).get();
        return rows.map((r) => r.read<String>('name')).toList();
      }

      final memberCols = await columnsOf('members');
      expect(memberCols, contains('display_name'));
      expect(memberCols, contains('birthday'));
      expect(memberCols, contains('proxy_tags_json'));
      expect(memberCols, contains('pluralkit_sync_ignored'));

      final sessionCols = await columnsOf('fronting_sessions');
      expect(sessionCols, contains('pk_member_ids_json'));

      // pk_mapping_state table exists.
      final tables = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name='pk_mapping_state'",
      ).get();
      expect(tables, hasLength(1));

      // Partial unique indexes exist.
      final indexes = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='index' AND name IN ("
        "'idx_members_pluralkit_uuid', 'idx_members_pluralkit_id', "
        "'idx_fronting_sessions_pluralkit_uuid')",
      ).get();
      expect(indexes, hasLength(3));
    });

    test('upgrade from v47 adds new columns, table, and indexes', () async {
      final tempDir =
          Directory.systemTemp.createTempSync('prism_migration_v48_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final dbFile = File('${tempDir.path}/upgrade.db');

      // Stub a v47 database with minimal `members` and `fronting_sessions`
      // tables — the migration only needs these to exist to ALTER them.
      final rawDb = raw.sqlite3.open(dbFile.path);
      try {
        rawDb.execute('PRAGMA user_version = 47;');
        rawDb.execute('''
          CREATE TABLE members (
            id TEXT NOT NULL PRIMARY KEY,
            name TEXT NOT NULL,
            pronouns TEXT,
            emoji TEXT NOT NULL DEFAULT '❔',
            age INTEGER,
            bio TEXT,
            avatar_image_data BLOB,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at INTEGER NOT NULL,
            display_order INTEGER NOT NULL DEFAULT 0,
            is_admin INTEGER NOT NULL DEFAULT 0,
            custom_color_enabled INTEGER NOT NULL DEFAULT 0,
            custom_color_hex TEXT,
            parent_system_id TEXT,
            pluralkit_uuid TEXT,
            pluralkit_id TEXT,
            markdown_enabled INTEGER NOT NULL DEFAULT 0,
            is_deleted INTEGER NOT NULL DEFAULT 0
          )
        ''');
        rawDb.execute('''
          CREATE TABLE fronting_sessions (
            id TEXT NOT NULL PRIMARY KEY,
            session_type INTEGER NOT NULL DEFAULT 0,
            start_time INTEGER NOT NULL,
            end_time INTEGER,
            member_id TEXT,
            co_fronter_ids TEXT NOT NULL DEFAULT '[]',
            notes TEXT,
            confidence INTEGER,
            quality INTEGER,
            is_health_kit_import INTEGER NOT NULL DEFAULT 0,
            pluralkit_uuid TEXT,
            is_deleted INTEGER NOT NULL DEFAULT 0
          )
        ''');
        // Seed data so we can verify the migration preserves it.
        rawDb.execute(
          'INSERT INTO members (id, name, created_at, pluralkit_id, '
          "pluralkit_uuid) VALUES ('m1', 'Alice', 1700000000000, 'abcde', "
          "'11111111-1111-1111-1111-111111111111')",
        );
        rawDb.execute(
          'INSERT INTO members (id, name, created_at) '
          "VALUES ('m2', 'Bob', 1700000001000)",
        );
        rawDb.execute(
          'INSERT INTO fronting_sessions (id, start_time, member_id, '
          "pluralkit_uuid) VALUES ('s1', 1700000000000, 'm1', "
          "'22222222-2222-2222-2222-222222222222')",
        );
      } finally {
        rawDb.close();
      }

      // Opening through Drift triggers v47 → v48. This must not throw.
      final db = AppDatabase(NativeDatabase(dbFile));
      addTearDown(db.close);

      // Force connection open.
      await db.customSelect('SELECT 1').get();

      final memberCols = await db.customSelect(
        "SELECT name FROM pragma_table_info('members')",
      ).get();
      final memberNames = memberCols.map((r) => r.read<String>('name')).toSet();
      expect(memberNames, containsAll(<String>[
        'display_name',
        'birthday',
        'proxy_tags_json',
        'pluralkit_sync_ignored',
      ]));

      final sessionCols = await db.customSelect(
        "SELECT name FROM pragma_table_info('fronting_sessions')",
      ).get();
      expect(
        sessionCols.map((r) => r.read<String>('name')),
        contains('pk_member_ids_json'),
      );

      final tables = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name='pk_mapping_state'",
      ).get();
      expect(tables, hasLength(1));

      final indexes = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='index' AND name IN ("
        "'idx_members_pluralkit_uuid', 'idx_members_pluralkit_id', "
        "'idx_fronting_sessions_pluralkit_uuid')",
      ).get();
      expect(indexes, hasLength(3));

      // Data preservation — the seeded rows must still be readable, and the
      // new NOT NULL column `pluralkit_sync_ignored` must carry its default.
      final members = await db.customSelect(
        'SELECT id, name, pluralkit_id, pluralkit_uuid, display_name, '
        'birthday, proxy_tags_json, pluralkit_sync_ignored '
        'FROM members ORDER BY id',
      ).get();
      expect(members, hasLength(2));
      expect(members[0].read<String>('id'), 'm1');
      expect(members[0].read<String>('name'), 'Alice');
      expect(members[0].read<String>('pluralkit_id'), 'abcde');
      expect(members[0].read<String>('pluralkit_uuid'),
          '11111111-1111-1111-1111-111111111111');
      expect(members[0].readNullable<String>('display_name'), isNull);
      expect(members[0].readNullable<String>('birthday'), isNull);
      expect(members[0].readNullable<String>('proxy_tags_json'), isNull);
      expect(members[0].read<int>('pluralkit_sync_ignored'), 0);
      expect(members[1].read<String>('name'), 'Bob');
      expect(members[1].read<int>('pluralkit_sync_ignored'), 0);

      final sessions = await db.customSelect(
        'SELECT id, member_id, pluralkit_uuid, pk_member_ids_json '
        'FROM fronting_sessions ORDER BY id',
      ).get();
      expect(sessions, hasLength(1));
      expect(sessions[0].read<String>('id'), 's1');
      expect(sessions[0].read<String>('member_id'), 'm1');
      expect(sessions[0].read<String>('pluralkit_uuid'),
          '22222222-2222-2222-2222-222222222222');
      expect(sessions[0].readNullable<String>('pk_member_ids_json'), isNull);
    });
  });
}
