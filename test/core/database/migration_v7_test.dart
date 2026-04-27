import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

// Shared helper: seed a file DB to v7, then downgrade to v6 + undo v7 changes
// so the upgrade path has real work to do.
Future<void> _seedV6Db(
  File dbFile, {
  List<String> extraStatements = const [],
}) async {
  final seeded = AppDatabase(NativeDatabase(dbFile));
  await seeded.customSelect('SELECT 1').get();
  await seeded.close();

  final rawDb = raw.sqlite3.open(dbFile.path);
  try {
    rawDb.execute('PRAGMA user_version = 6;');
    rawDb.execute('ALTER TABLE members DROP COLUMN is_always_fronting');
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
    // Phase 4B cursor columns (folded into v7) — must also be absent at v6.
    rawDb.execute(
      'ALTER TABLE plural_kit_sync_state DROP COLUMN switch_cursor_timestamp',
    );
    rawDb.execute(
      'ALTER TABLE plural_kit_sync_state DROP COLUMN switch_cursor_id',
    );
    rawDb.execute(
      'DROP INDEX IF EXISTS idx_fronting_sessions_pluralkit_uuid_member_id',
    );
    rawDb.execute(
      'DROP INDEX IF EXISTS idx_fronting_sessions_pluralkit_uuid_orphan',
    );
    rawDb.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_fronting_sessions_pluralkit_uuid '
      'ON fronting_sessions(pluralkit_uuid) WHERE pluralkit_uuid IS NOT NULL',
    );
    for (final stmt in extraStatements) {
      rawDb.execute(stmt);
    }
  } finally {
    rawDb.close();
  }
}

void main() {
  group('schema v7 migration', () {
    // ── 1. Fresh schema at v7 ─────────────────────────────────────────────────

    test('fresh v7 schema has new columns, composite + orphan PK indexes, '
        "and pending_fronting_migration_mode defaults to 'complete'", () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // Trigger open / onCreate
      await db.customSelect('SELECT 1').get();

      // members.is_always_fronting
      final memberCols =
          await db.customSelect('PRAGMA table_info(members)').get();
      expect(
        memberCols.map((r) => r.read<String>('name')).toSet(),
        contains('is_always_fronting'),
      );

      // system_settings.pending_fronting_migration_mode
      final settingsCols =
          await db.customSelect('PRAGMA table_info(system_settings)').get();
      expect(
        settingsCols.map((r) => r.read<String>('name')).toSet(),
        contains('pending_fronting_migration_mode'),
      );

      // front_session_comments new columns
      final commentCols =
          await db.customSelect('PRAGMA table_info(front_session_comments)').get();
      final commentColNames =
          commentCols.map((r) => r.read<String>('name')).toSet();
      expect(commentColNames, contains('target_time'));
      expect(commentColNames, contains('author_member_id'));

      // Phase 4B cursor columns (folded into v7): plural_kit_sync_state
      final pkStateCols =
          await db.customSelect('PRAGMA table_info(plural_kit_sync_state)').get();
      final pkStateColNames =
          pkStateCols.map((r) => r.read<String>('name')).toSet();
      expect(pkStateColNames, contains('switch_cursor_timestamp'));
      expect(pkStateColNames, contains('switch_cursor_id'));

      // Old single-column index must not exist on fresh install
      final oldIndex = await db
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE name = 'idx_fronting_sessions_pluralkit_uuid'",
          )
          .get();
      expect(oldIndex, isEmpty, reason: 'old single-column index must not exist');

      // New composite index (resolved-rows partition) must exist
      final compositeIndex = await db
          .customSelect(
            "SELECT sql FROM sqlite_master "
            "WHERE name = 'idx_fronting_sessions_pluralkit_uuid_member_id'",
          )
          .getSingleOrNull();
      expect(compositeIndex, isNotNull, reason: 'composite unique index must exist');
      final compositeSql = compositeIndex!.read<String>('sql');
      expect(compositeSql, contains('(pluralkit_uuid, member_id)'));
      expect(compositeSql, contains('member_id IS NOT NULL'));

      // Orphan index (null-member_id partition) must exist
      final orphanIndex = await db
          .customSelect(
            "SELECT sql FROM sqlite_master "
            "WHERE name = 'idx_fronting_sessions_pluralkit_uuid_orphan'",
          )
          .getSingleOrNull();
      expect(orphanIndex, isNotNull, reason: 'orphan unique index must exist');
      final orphanSql = orphanIndex!.read<String>('sql');
      expect(orphanSql, contains('member_id IS NULL'));

      // Fresh-install singleton must default to 'complete' — no migration needed
      final settingsDao = db.systemSettingsDao;
      final settings = await settingsDao.getSettings();
      expect(
        settings.pendingFrontingMigrationMode,
        'complete',
        reason: "fresh install has no legacy data; modal must not appear",
      );
    });

    // ── 2. v6 → v7 upgrade ───────────────────────────────────────────────────

    test('v6 → v7 upgrade adds columns, indexes, and sets mode to notStarted',
        () async {
      final tempDir =
          Directory.systemTemp.createTempSync('prism_migration_v7_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final dbFile = File('${tempDir.path}/v6_to_v7.db');
      await _seedV6Db(dbFile);

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);

      // Force open
      await upgraded.customSelect('SELECT 1').get();

      // New columns must be present
      final memberCols =
          await upgraded.customSelect('PRAGMA table_info(members)').get();
      expect(
        memberCols.map((r) => r.read<String>('name')).toSet(),
        contains('is_always_fronting'),
      );

      final settingsCols =
          await upgraded.customSelect('PRAGMA table_info(system_settings)').get();
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

      // Phase 4B cursor columns (folded into v7): plural_kit_sync_state
      final pkStateCols = await upgraded
          .customSelect('PRAGMA table_info(plural_kit_sync_state)')
          .get();
      final pkStateColNames =
          pkStateCols.map((r) => r.read<String>('name')).toSet();
      expect(pkStateColNames, contains('switch_cursor_timestamp'));
      expect(pkStateColNames, contains('switch_cursor_id'));

      // Old single-column index must be gone
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

      // Composite index must be present
      final compositeIndex = await upgraded
          .customSelect(
            "SELECT sql FROM sqlite_master "
            "WHERE name = 'idx_fronting_sessions_pluralkit_uuid_member_id'",
          )
          .getSingleOrNull();
      expect(
        compositeIndex,
        isNotNull,
        reason: 'composite unique index must be created by migration',
      );
      final compositeSql = compositeIndex!.read<String>('sql');
      expect(compositeSql, contains('member_id IS NOT NULL'));

      // Orphan index must be present
      final orphanIndex = await upgraded
          .customSelect(
            "SELECT sql FROM sqlite_master "
            "WHERE name = 'idx_fronting_sessions_pluralkit_uuid_orphan'",
          )
          .getSingleOrNull();
      expect(orphanIndex, isNotNull, reason: 'orphan index must be created');

      // Upgraded singleton must be 'notStarted' — existing users need to see modal
      final settings = await upgraded.systemSettingsDao.getSettings();
      expect(
        settings.pendingFrontingMigrationMode,
        'notStarted',
        reason: 'upgrading devices have legacy data and must see the modal',
      );
    });

    // ── 3. Detect-and-refuse: resolved-row duplicates ─────────────────────────

    test(
      'v6 → v7 with duplicate (pluralkit_uuid, member_id) pairs: '
      "logs blockers, sets mode to 'blocked', skips composite index",
      () async {
        final tempDir =
            Directory.systemTemp.createTempSync('prism_migration_v7_blocked_');
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });

        final dbFile = File('${tempDir.path}/v6_blocked.db');
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        await _seedV6Db(dbFile, extraStatements: [
          // Drop old unique index so we can insert duplicates
          'DROP INDEX IF EXISTS idx_fronting_sessions_pluralkit_uuid',
          // Two rows sharing (pk-uuid-abc, member-1) — resolved-row duplicate
          "INSERT INTO fronting_sessions "
              "(id, session_type, start_time, end_time, member_id, "
              " co_fronter_ids, is_health_kit_import, is_deleted, "
              " pluralkit_uuid) "
              "VALUES "
              "('dup-a', 0, $now, NULL, 'member-1', '[]', 0, 0, 'pk-uuid-abc')",
          "INSERT INTO fronting_sessions "
              "(id, session_type, start_time, end_time, member_id, "
              " co_fronter_ids, is_health_kit_import, is_deleted, "
              " pluralkit_uuid) "
              "VALUES "
              "('dup-b', 0, ${now + 1}, NULL, 'member-1', '[]', 0, 0, 'pk-uuid-abc')",
        ]);

        final upgraded = AppDatabase(NativeDatabase(dbFile));
        addTearDown(upgraded.close);

        // Trigger migration — must NOT throw despite duplicates
        await upgraded.customSelect('SELECT 1').get();

        // mode must be 'blocked'
        final settings = await upgraded.systemSettingsDao.getSettings();
        expect(
          settings.pendingFrontingMigrationMode,
          'blocked',
          reason: 'duplicates detected: migration mode must be blocked',
        );

        // Blocker rows must be logged
        final blockers = await upgraded
            .customSelect(
              "SELECT row_id FROM _v7_migration_blockers "
              "WHERE table_name = 'fronting_sessions'",
            )
            .get();
        final blockerIds = blockers.map((r) => r.read<String>('row_id')).toSet();
        expect(blockerIds, contains('dup-a'));
        expect(blockerIds, contains('dup-b'));

        // Composite index must NOT have been created
        final compositeIndex = await upgraded
            .customSelect(
              "SELECT name FROM sqlite_master "
              "WHERE name = 'idx_fronting_sessions_pluralkit_uuid_member_id'",
            )
            .get();
        expect(
          compositeIndex,
          isEmpty,
          reason: 'composite index must not be created when duplicates exist',
        );

        // No rows must have been deleted
        final remaining = await upgraded
            .customSelect(
              "SELECT id FROM fronting_sessions "
              "WHERE pluralkit_uuid = 'pk-uuid-abc' AND member_id = 'member-1'",
            )
            .get();
        expect(
          remaining,
          hasLength(2),
          reason: 'detect-and-refuse must not delete any rows',
        );
      },
    );

    // ── 4. Detect-and-refuse: orphan-row duplicates ───────────────────────────

    test(
      'v6 → v7 with duplicate (pluralkit_uuid, NULL member_id) orphan rows: '
      "logs blockers, sets mode to 'blocked'",
      () async {
        final tempDir =
            Directory.systemTemp.createTempSync('prism_migration_v7_orphan_dup_');
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });

        final dbFile = File('${tempDir.path}/v6_orphan_dup.db');
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        await _seedV6Db(dbFile, extraStatements: [
          'DROP INDEX IF EXISTS idx_fronting_sessions_pluralkit_uuid',
          // Two rows with same uuid but NULL member_id — orphan duplicate
          "INSERT INTO fronting_sessions "
              "(id, session_type, start_time, end_time, member_id, "
              " co_fronter_ids, is_health_kit_import, is_deleted, "
              " pluralkit_uuid) "
              "VALUES "
              "('orphan-a', 0, $now, NULL, NULL, '[]', 0, 0, 'pk-orphan-uuid')",
          "INSERT INTO fronting_sessions "
              "(id, session_type, start_time, end_time, member_id, "
              " co_fronter_ids, is_health_kit_import, is_deleted, "
              " pluralkit_uuid) "
              "VALUES "
              "('orphan-b', 0, ${now + 1}, NULL, NULL, '[]', 0, 0, 'pk-orphan-uuid')",
        ]);

        final upgraded = AppDatabase(NativeDatabase(dbFile));
        addTearDown(upgraded.close);

        await upgraded.customSelect('SELECT 1').get();

        final settings = await upgraded.systemSettingsDao.getSettings();
        expect(settings.pendingFrontingMigrationMode, 'blocked');

        final blockers = await upgraded
            .customSelect(
              "SELECT row_id FROM _v7_migration_blockers "
              "WHERE table_name = 'fronting_sessions'",
            )
            .get();
        final blockerIds = blockers.map((r) => r.read<String>('row_id')).toSet();
        expect(blockerIds, containsAll(['orphan-a', 'orphan-b']));

        // Rows must be untouched
        final remaining = await upgraded
            .customSelect(
              "SELECT id FROM fronting_sessions "
              "WHERE pluralkit_uuid = 'pk-orphan-uuid'",
            )
            .get();
        expect(remaining, hasLength(2));
      },
    );

    // ── 5. Orphan index enforcement on fresh schema ───────────────────────────

    test(
      'orphan index blocks duplicate (uuid, null member_id) inserts '
      'and allows (uuid, A) + (uuid, B) with different non-null member_ids',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        await db.customSelect('SELECT 1').get();

        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        // Insert first orphan row (member_id=null)
        await db.customStatement(
          "INSERT INTO fronting_sessions "
          "(id, session_type, start_time, end_time, member_id, "
          " co_fronter_ids, is_health_kit_import, is_deleted, pluralkit_uuid) "
          "VALUES ('orph-1', 0, $now, NULL, NULL, '[]', 0, 0, 'pk-x')",
        );

        // Second orphan with same uuid must be blocked
        expect(
          () => db.customStatement(
            "INSERT INTO fronting_sessions "
            "(id, session_type, start_time, end_time, member_id, "
            " co_fronter_ids, is_health_kit_import, is_deleted, pluralkit_uuid) "
            "VALUES ('orph-2', 0, $now, NULL, NULL, '[]', 0, 0, 'pk-x')",
          ),
          throwsA(anything),
          reason: 'orphan index must block duplicate (uuid, NULL) row',
        );

        // Two rows with same uuid but different non-null member_ids must both succeed
        await db.customStatement(
          "INSERT INTO fronting_sessions "
          "(id, session_type, start_time, end_time, member_id, "
          " co_fronter_ids, is_health_kit_import, is_deleted, pluralkit_uuid) "
          "VALUES ('res-a', 0, $now, NULL, 'member-A', '[]', 0, 0, 'pk-y')",
        );
        await db.customStatement(
          "INSERT INTO fronting_sessions "
          "(id, session_type, start_time, end_time, member_id, "
          " co_fronter_ids, is_health_kit_import, is_deleted, pluralkit_uuid) "
          "VALUES ('res-b', 0, $now, NULL, 'member-B', '[]', 0, 0, 'pk-y')",
        );

        final resolved = await db
            .customSelect(
              "SELECT id FROM fronting_sessions "
              "WHERE pluralkit_uuid = 'pk-y'",
            )
            .get();
        expect(
          resolved,
          hasLength(2),
          reason: 'same uuid with different member_ids must both succeed',
        );
      },
    );
  });
}
