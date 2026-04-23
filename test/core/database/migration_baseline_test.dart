import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

void main() {
  group('squashed database baseline', () {
    test('fresh database creates expected indexes and FTS artifacts', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final rows = await db.customSelect('''
        SELECT name
        FROM sqlite_master
        WHERE name IN (
          'idx_members_active',
          'idx_sessions_end',
          'idx_sessions_start',
          'idx_messages_conv_deleted_ts',
          'idx_sessions_deleted_start',
          'idx_sessions_member_deleted_start',
          'idx_sessions_type',
          'idx_habit_completions_habit_deleted_at',
          'idx_poll_votes_option_deleted',
          'idx_poll_options_poll_deleted_order',
          'idx_conversations_deleted_activity',
          'idx_polls_closed_deleted_created',
          'idx_quarantine_entity',
          'idx_member_group_entries_group_deleted',
          'idx_member_group_entries_member_deleted',
          'idx_custom_fields_deleted_order',
          'idx_custom_field_values_field_member',
          'idx_notes_member',
          'idx_notes_all',
          'idx_comments_session',
          'idx_conv_categories_deleted_order',
          'idx_reminders_active_deleted',
          'idx_conversations_category',
          'idx_friends_deleted',
          'chat_messages_fts',
          'chat_messages_fts_insert',
          'chat_messages_fts_update',
          'chat_messages_fts_delete'
        )
      ''').get();

      final names = rows.map((row) => row.read<String>('name')).toSet();

      expect(
        names,
        equals({
          'idx_members_active',
          'idx_sessions_end',
          'idx_sessions_start',
          'idx_messages_conv_deleted_ts',
          'idx_sessions_deleted_start',
          'idx_sessions_member_deleted_start',
          'idx_sessions_type',
          'idx_habit_completions_habit_deleted_at',
          'idx_poll_votes_option_deleted',
          'idx_poll_options_poll_deleted_order',
          'idx_conversations_deleted_activity',
          'idx_polls_closed_deleted_created',
          'idx_quarantine_entity',
          'idx_member_group_entries_group_deleted',
          'idx_member_group_entries_member_deleted',
          'idx_custom_fields_deleted_order',
          'idx_custom_field_values_field_member',
          'idx_notes_member',
          'idx_notes_all',
          'idx_comments_session',
          'idx_conv_categories_deleted_order',
          'idx_reminders_active_deleted',
          'idx_conversations_category',
          'idx_friends_deleted',
          'chat_messages_fts',
          'chat_messages_fts_insert',
          'chat_messages_fts_update',
          'chat_messages_fts_delete',
        }),
      );

      final legacySleepIndex = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE name = 'idx_sleep_end'",
          )
          .get();
      expect(legacySleepIndex, isEmpty);
    });

    test(
      'non-fresh databases are rejected with the v1-baseline error',
      () async {
        final tempDir = Directory.systemTemp.createTempSync('prism_migration_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        final dbFile = File('${tempDir.path}/legacy.db');
        final rawDb = raw.sqlite3.open(dbFile.path);
        try {
          // Any pre-beta schema version (v30..v58) hits the same rejection.
          rawDb.execute('PRAGMA user_version = 58;');
        } finally {
          rawDb.close();
        }

        final db = AppDatabase(NativeDatabase(dbFile));
        addTearDown(db.close);

        await expectLater(
          db.customSelect('SELECT 1').get(),
          throwsA(
            isA<UnsupportedError>().having(
              (error) => error.message,
              'message',
              contains('Schema baseline was reset to v1'),
            ),
          ),
        );
      },
    );

    test(
      'v4 → v5 migration drops auto-aliases pointing at active member_groups '
      'ids for the same PK UUID',
      () async {
        final tempDir = Directory.systemTemp.createTempSync('prism_migration_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        final dbFile = File('${tempDir.path}/v4_to_v5.db');
        // Stand up a fresh v5 database, then downgrade the stored
        // user_version to 4 so opening it runs the v4 → v5 migration.
        final seeded = AppDatabase(NativeDatabase(dbFile));
        await seeded.customSelect('SELECT 1').get();

        const pkUuid = 'pk-uuid-cascade';
        const pkUuidOther = 'pk-uuid-other';
        const activeLocalId = 'pk-group-$pkUuid';
        const canonicalId = 'pk-group:$pkUuid';
        const legacyAliasId = 'random-legacy-id';
        final createdAt = DateTime.utc(2026, 4, 18, 12);

        // Hazardous auto-alias: legacy_entity_id equals an active
        // member_groups.id for the same pk_group_uuid (C1 scenario).
        await seeded
            .into(seeded.memberGroups)
            .insert(
              MemberGroupsCompanion.insert(
                id: activeLocalId,
                name: 'Active',
                createdAt: createdAt,
                pluralkitUuid: const Value(pkUuid),
              ),
            );
        // Safe legacy alias: legacy_entity_id does NOT match any active row.
        await seeded
            .into(seeded.memberGroups)
            .insert(
              MemberGroupsCompanion.insert(
                id: 'pk-group-$pkUuidOther',
                name: 'Unrelated',
                createdAt: createdAt,
                pluralkitUuid: const Value(pkUuidOther),
              ),
            );

        await seeded.customStatement(
          '''
          INSERT INTO pk_group_sync_aliases
            (legacy_entity_id, pk_group_uuid, canonical_entity_id, created_at)
          VALUES (?, ?, ?, ?)
          ''',
          [
            activeLocalId,
            pkUuid,
            canonicalId,
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
          ],
        );
        await seeded.customStatement(
          '''
          INSERT INTO pk_group_sync_aliases
            (legacy_entity_id, pk_group_uuid, canonical_entity_id, created_at)
          VALUES (?, ?, ?, ?)
          ''',
          [
            legacyAliasId,
            pkUuidOther,
            'pk-group:$pkUuidOther',
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
          ],
        );
        await seeded.close();

        final rawDb = raw.sqlite3.open(dbFile.path);
        try {
          rawDb.execute('PRAGMA user_version = 4;');
        } finally {
          rawDb.close();
        }

        final upgraded = AppDatabase(NativeDatabase(dbFile));
        addTearDown(upgraded.close);

        final aliases = await upgraded
            .customSelect(
              'SELECT legacy_entity_id FROM pk_group_sync_aliases',
            )
            .get();
        final legacyIds = aliases
            .map((row) => row.read<String>('legacy_entity_id'))
            .toSet();

        // Hazardous auto-alias is gone; unrelated legacy alias survives.
        expect(legacyIds, contains(legacyAliasId));
        expect(legacyIds, isNot(contains(activeLocalId)));
      },
    );

    test('schema v1 databases upgrade through v2 and v3 additions', () async {
      final tempDir = Directory.systemTemp.createTempSync('prism_migration_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final dbFile = File('${tempDir.path}/v1_to_v3.db');
      final seeded = AppDatabase(NativeDatabase(dbFile));
      await seeded.customSelect('SELECT 1').get();
      await seeded.close();

      final rawDb = raw.sqlite3.open(dbFile.path);
      try {
        rawDb.execute('PRAGMA foreign_keys = OFF;');
        rawDb.execute(
          'DROP INDEX IF EXISTS idx_member_groups_sync_suppressed;',
        );
        rawDb.execute(
          'DROP INDEX IF EXISTS idx_member_groups_suspected_pk_group_uuid;',
        );
        rawDb.execute(
          'DROP INDEX IF EXISTS idx_member_group_entries_pk_group_uuid;',
        );
        rawDb.execute(
          'DROP INDEX IF EXISTS idx_member_group_entries_pk_member_uuid;',
        );
        rawDb.execute(
          'DROP INDEX IF EXISTS idx_pk_group_sync_aliases_pk_group_uuid;',
        );
        rawDb.execute(
          'DROP INDEX IF EXISTS idx_pk_group_entry_deferred_ops_entity;',
        );
        rawDb.execute('DROP TABLE IF EXISTS pk_group_sync_aliases;');
        rawDb.execute('DROP TABLE IF EXISTS pk_group_entry_deferred_sync_ops;');
        rawDb.execute(
          'ALTER TABLE member_group_entries DROP COLUMN pk_group_uuid;',
        );
        rawDb.execute(
          'ALTER TABLE member_group_entries DROP COLUMN pk_member_uuid;',
        );
        rawDb.execute('ALTER TABLE member_groups DROP COLUMN sync_suppressed;');
        rawDb.execute(
          'ALTER TABLE member_groups DROP COLUMN suspected_pk_group_uuid;',
        );
        rawDb.execute(
          'ALTER TABLE system_settings DROP COLUMN pk_group_sync_v2_enabled;',
        );
        rawDb.execute('PRAGMA user_version = 1;');
        rawDb.execute('PRAGMA foreign_keys = ON;');
      } finally {
        rawDb.close();
      }

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);

      final entryColumns = await upgraded
          .customSelect('PRAGMA table_info(member_group_entries)')
          .get();
      final groupColumns = await upgraded
          .customSelect('PRAGMA table_info(member_groups)')
          .get();
      final settingsColumns = await upgraded
          .customSelect('PRAGMA table_info(system_settings)')
          .get();
      final pkSyncTables = await upgraded.customSelect('''
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
          AND name IN (
            'pk_group_sync_aliases',
            'pk_group_entry_deferred_sync_ops'
          )
      ''').get();

      expect(
        entryColumns.map((row) => row.read<String>('name')).toSet(),
        containsAll({'pk_group_uuid', 'pk_member_uuid'}),
      );
      expect(
        groupColumns.map((row) => row.read<String>('name')).toSet(),
        containsAll({'sync_suppressed', 'suspected_pk_group_uuid'}),
      );
      expect(
        settingsColumns.map((row) => row.read<String>('name')).toSet(),
        contains('pk_group_sync_v2_enabled'),
      );
      expect(
        pkSyncTables.map((row) => row.read<String>('name')).toSet(),
        equals({'pk_group_sync_aliases', 'pk_group_entry_deferred_sync_ops'}),
      );
      expect(
        await upgraded.systemSettingsDao.getSettings(),
        isA<SystemSettingsData>().having(
          (row) => row.pkGroupSyncV2Enabled,
          'pkGroupSyncV2Enabled',
          isFalse,
        ),
      );
    });
  });
}
