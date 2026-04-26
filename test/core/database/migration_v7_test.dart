import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

void main() {
  group('schema v7 migration', () {
    // ── 1. Fresh schema at v7 ─────────────────────────────────────────────────

    test('fresh v7 schema has new columns and composite PK index', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // Trigger open / onCreate
      await db.customSelect('SELECT 1').get();

      // members.is_always_fronting
      final memberCols = await db
          .customSelect('PRAGMA table_info(members)')
          .get();
      final memberColNames =
          memberCols.map((r) => r.read<String>('name')).toSet();
      expect(memberColNames, contains('is_always_fronting'));

      // system_settings.pending_fronting_migration_mode
      final settingsCols = await db
          .customSelect('PRAGMA table_info(system_settings)')
          .get();
      final settingsColNames =
          settingsCols.map((r) => r.read<String>('name')).toSet();
      expect(settingsColNames, contains('pending_fronting_migration_mode'));

      // front_session_comments.target_time + author_member_id
      final commentCols = await db
          .customSelect('PRAGMA table_info(front_session_comments)')
          .get();
      final commentColNames =
          commentCols.map((r) => r.read<String>('name')).toSet();
      expect(commentColNames, contains('target_time'));
      expect(commentColNames, contains('author_member_id'));

      // Old index gone; new composite index present
      final oldIndex = await db
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE name = 'idx_fronting_sessions_pluralkit_uuid'",
          )
          .get();
      expect(oldIndex, isEmpty, reason: 'old single-column index must be gone');

      final newIndex = await db
          .customSelect(
            "SELECT sql FROM sqlite_master "
            "WHERE name = 'idx_fronting_sessions_pluralkit_uuid_member_id'",
          )
          .getSingleOrNull();
      expect(
        newIndex,
        isNotNull,
        reason: 'composite unique index must exist',
      );
      final sql = newIndex!.read<String>('sql');
      expect(sql, contains('(pluralkit_uuid, member_id)'));
      expect(sql, contains('WHERE pluralkit_uuid IS NOT NULL'));
    });

    // ── 2. v6 → v7 upgrade adds new columns and composite index ──────────────

    test('upgrading from v6 to v7 adds new columns and composite PK index',
        () async {
      final tempDir =
          Directory.systemTemp.createTempSync('prism_migration_v7_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final dbFile = File('${tempDir.path}/v6_to_v7.db');

      // Bring up to current schema, then downgrade user_version to 6 so the
      // next open runs the v6 → v7 branch of onUpgrade.
      final seeded = AppDatabase(NativeDatabase(dbFile));
      await seeded.customSelect('SELECT 1').get();
      await seeded.close();

      final rawDb = raw.sqlite3.open(dbFile.path);
      try {
        rawDb.execute('PRAGMA user_version = 6;');
        // Manually remove the v7 columns so the migration has real work to do.
        rawDb.execute(
          'ALTER TABLE members DROP COLUMN is_always_fronting',
        );
        rawDb.execute(
          'ALTER TABLE system_settings '
          'DROP COLUMN pending_fronting_migration_mode',
        );
        rawDb.execute(
          'ALTER TABLE front_session_comments DROP COLUMN target_time',
        );
        rawDb.execute(
          'ALTER TABLE front_session_comments DROP COLUMN author_member_id',
        );
        // Remove composite index and restore the old single-column one.
        rawDb.execute(
          'DROP INDEX IF EXISTS '
          'idx_fronting_sessions_pluralkit_uuid_member_id',
        );
        rawDb.execute(
          'CREATE UNIQUE INDEX idx_fronting_sessions_pluralkit_uuid '
          'ON fronting_sessions(pluralkit_uuid) '
          'WHERE pluralkit_uuid IS NOT NULL',
        );
      } finally {
        rawDb.close();
      }

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);

      // Force open
      await upgraded.customSelect('SELECT 1').get();

      final memberCols = await upgraded
          .customSelect('PRAGMA table_info(members)')
          .get();
      expect(
        memberCols.map((r) => r.read<String>('name')).toSet(),
        contains('is_always_fronting'),
      );

      final settingsCols = await upgraded
          .customSelect('PRAGMA table_info(system_settings)')
          .get();
      expect(
        settingsCols.map((r) => r.read<String>('name')).toSet(),
        contains('pending_fronting_migration_mode'),
      );

      final commentCols = await upgraded
          .customSelect('PRAGMA table_info(front_session_comments)')
          .get();
      final commentColNames =
          commentCols.map((r) => r.read<String>('name')).toSet();
      expect(commentColNames, contains('target_time'));
      expect(commentColNames, contains('author_member_id'));

      final oldIndex = await upgraded
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE name = 'idx_fronting_sessions_pluralkit_uuid'",
          )
          .get();
      expect(
        oldIndex,
        isEmpty,
        reason: 'old single-column index must be dropped by migration',
      );

      final newIndex = await upgraded
          .customSelect(
            "SELECT sql FROM sqlite_master "
            "WHERE name = 'idx_fronting_sessions_pluralkit_uuid_member_id'",
          )
          .getSingleOrNull();
      expect(
        newIndex,
        isNotNull,
        reason: 'composite unique index must be created by migration',
      );
    });

    // ── 3. Pre-flight duplicate cleanup ───────────────────────────────────────

    test(
      'v6 → v7 upgrade collapses duplicate (pluralkit_uuid, member_id) pairs '
      'before creating the composite unique index',
      () async {
        final tempDir =
            Directory.systemTemp.createTempSync('prism_migration_v7_dedup_');
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });

        final dbFile = File('${tempDir.path}/v6_dedup.db');

        // Seed a v6-schema database with a duplicate (pluralkit_uuid, member_id)
        // pair that would block CREATE UNIQUE INDEX without the pre-flight cleanup.
        final seeded = AppDatabase(NativeDatabase(dbFile));
        await seeded.customSelect('SELECT 1').get();
        await seeded.close();

        final rawDb = raw.sqlite3.open(dbFile.path);
        try {
          // Downgrade to v6.
          rawDb.execute('PRAGMA user_version = 6;');

          // Remove v7-only additions so the migration path has real work.
          rawDb.execute(
            'ALTER TABLE members DROP COLUMN is_always_fronting',
          );
          rawDb.execute(
            'ALTER TABLE system_settings '
            'DROP COLUMN pending_fronting_migration_mode',
          );
          rawDb.execute(
            'ALTER TABLE front_session_comments DROP COLUMN target_time',
          );
          rawDb.execute(
            'ALTER TABLE front_session_comments DROP COLUMN author_member_id',
          );
          rawDb.execute(
            'DROP INDEX IF EXISTS '
            'idx_fronting_sessions_pluralkit_uuid_member_id',
          );
          // Drop the old unique index entirely so we can seed duplicate pairs.
          // This simulates a real-world scenario where the index was absent or
          // bypassed (e.g., the DB was opened with a pre-v2 build, or the
          // importer wrote via raw SQL without going through the unique path).
          // The v7 pre-flight cleanup must handle this before the new composite
          // index is created.
          rawDb.execute(
            'DROP INDEX IF EXISTS idx_fronting_sessions_pluralkit_uuid',
          );

          // Seed three rows: two duplicates sharing (uuid-abc, member-1) and
          // one unrelated row.  The duplicate with the higher rowid should survive.
          // Insertion order determines rowid, so 'dup-session-b' is inserted last
          // and will have the higher rowid — making it the survivor.
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          rawDb.execute(
            "INSERT INTO fronting_sessions "
            "(id, session_type, start_time, end_time, member_id, "
            " co_fronter_ids, is_health_kit_import, is_deleted, "
            " pluralkit_uuid) "
            "VALUES "
            "('dup-session-a', 0, $now, NULL, 'member-1', "
            " '[]', 0, 0, 'pk-uuid-abc')",
          );
          rawDb.execute(
            "INSERT INTO fronting_sessions "
            "(id, session_type, start_time, end_time, member_id, "
            " co_fronter_ids, is_health_kit_import, is_deleted, "
            " pluralkit_uuid) "
            "VALUES "
            "('dup-session-b', 0, ${now + 1}, NULL, 'member-1', "
            " '[]', 0, 0, 'pk-uuid-abc')",
          );
          rawDb.execute(
            "INSERT INTO fronting_sessions "
            "(id, session_type, start_time, end_time, member_id, "
            " co_fronter_ids, is_health_kit_import, is_deleted, "
            " pluralkit_uuid) "
            "VALUES "
            "('unique-session', 0, $now, NULL, 'member-2', "
            " '[]', 0, 0, 'pk-uuid-abc')",
          );
        } finally {
          rawDb.close();
        }

        // Open with the current schema — triggers v6 → v7 migration.
        final upgraded = AppDatabase(NativeDatabase(dbFile));
        addTearDown(upgraded.close);

        final sessions = await upgraded
            .customSelect(
              'SELECT id FROM fronting_sessions '
              "WHERE pluralkit_uuid = 'pk-uuid-abc' "
              "  AND member_id = 'member-1'",
            )
            .get();

        // The duplicate pair must be collapsed to exactly one row.
        expect(
          sessions,
          hasLength(1),
          reason: 'pre-flight cleanup must reduce duplicate pair to one row',
        );

        // The surviving row must be the one with the higher rowid (last
        // inserted) — 'dup-session-b'.
        final survivingId = sessions.single.read<String>('id');
        expect(
          survivingId,
          'dup-session-b',
          reason: 'MAX(rowid) tiebreak must keep the later-inserted row',
        );

        // The unrelated (pk-uuid-abc, member-2) row must survive untouched.
        final unrelated = await upgraded
            .customSelect(
              'SELECT id FROM fronting_sessions '
              "WHERE id = 'unique-session'",
            )
            .get();
        expect(
          unrelated,
          hasLength(1),
          reason: 'non-duplicate row must not be deleted',
        );

        // The composite unique index must have been created successfully.
        final idx = await upgraded
            .customSelect(
              "SELECT name FROM sqlite_master "
              "WHERE name = 'idx_fronting_sessions_pluralkit_uuid_member_id'",
            )
            .get();
        expect(idx, hasLength(1));
      },
    );
  });
}
