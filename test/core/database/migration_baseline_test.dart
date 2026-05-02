import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

bool _hasColumn(raw.Database db, String tableName, String columnName) {
  final rows = db.select('PRAGMA table_info($tableName)');
  return rows.any((row) => row['name'] == columnName);
}

void _dropColumnIfExists(raw.Database db, String tableName, String columnName) {
  if (_hasColumn(db, tableName, columnName)) {
    db.execute('ALTER TABLE $tableName DROP COLUMN $columnName;');
  }
}

void _dropPostV3Schema(raw.Database db) {
  // These tests create a fresh current-schema DB, seed data through current
  // DAOs, then force an older user_version. Keep the resulting fixture
  // coherent by removing columns that did not exist at schema v3 before
  // Drift runs the v3 -> current migration chain.
  db.execute('DROP INDEX IF EXISTS idx_member_group_entries_pk_canonicalize;');
  db.execute(
    'DROP INDEX IF EXISTS idx_fronting_sessions_pluralkit_uuid_member_id;',
  );
  db.execute(
    'DROP INDEX IF EXISTS idx_fronting_sessions_pluralkit_uuid_orphan;',
  );
  db.execute('DROP INDEX IF EXISTS idx_comments_target_time;');
  db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_fronting_sessions_pluralkit_uuid '
    'ON fronting_sessions(pluralkit_uuid) WHERE pluralkit_uuid IS NOT NULL;',
  );

  const drops = <List<String>>[
    ['members', 'profile_header_visible'],
    ['members', 'name_style_font'],
    ['members', 'name_style_bold'],
    ['members', 'name_style_italic'],
    ['members', 'name_style_color_mode'],
    ['members', 'name_style_color_hex'],
    ['members', 'profile_header_source'],
    ['members', 'profile_header_layout'],
    ['members', 'profile_header_image_data'],
    ['members', 'pk_banner_image_data'],
    ['members', 'pk_banner_cached_url'],
    ['members', 'is_always_fronting'],
    ['members', 'pk_banner_url'],
    ['fronting_sessions', 'pk_import_source'],
    ['fronting_sessions', 'pk_file_switch_id'],
    ['system_settings', 'fronting_list_view_mode'],
    ['system_settings', 'add_front_default_behavior'],
    ['system_settings', 'quick_front_default_behavior'],
    ['system_settings', 'pending_fronting_migration_mode'],
    ['system_settings', 'pending_fronting_migration_cleanup_substate'],
    ['front_session_comments', 'target_time'],
    ['front_session_comments', 'author_member_id'],
    ['plural_kit_sync_state', 'switch_cursor_timestamp'],
    ['plural_kit_sync_state', 'switch_cursor_id'],
  ];

  for (final drop in drops) {
    _dropColumnIfExists(db, drop[0], drop[1]);
  }
}

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
          'idx_member_group_entries_pk_canonicalize',
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
          'idx_member_group_entries_pk_canonicalize',
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

      final canonicalizeIndex = await db
          .customSelect(
            'SELECT sql FROM sqlite_master '
            "WHERE name = 'idx_member_group_entries_pk_canonicalize'",
          )
          .getSingle();
      final canonicalizeIndexSql = canonicalizeIndex.read<String>('sql');
      expect(
        canonicalizeIndexSql,
        contains('ON member_group_entries (pk_group_uuid, pk_member_uuid)'),
      );
      expect(canonicalizeIndexSql, contains('WHERE is_deleted = 0'));
      expect(canonicalizeIndexSql, contains('pk_group_uuid IS NOT NULL'));
      expect(canonicalizeIndexSql, contains('pk_member_uuid IS NOT NULL'));
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

    test('v3 → v4 migration drops auto-aliases pointing at active member_groups '
        'ids for the same PK UUID', () async {
      final tempDir = Directory.systemTemp.createTempSync('prism_migration_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final dbFile = File('${tempDir.path}/v3_to_v4_alias.db');
      // Stand up a fresh v4 database, then downgrade the stored
      // user_version to 3 so opening it runs the v3 → v4 migration
      // (which consolidates H3's DateTime divide-by-1000 fixups with
      // C1's hazardous-auto-alias cleanup).
      final seeded = AppDatabase(NativeDatabase(dbFile));
      await seeded.customSelect('SELECT 1').get();
      final pkAliasTable = await seeded
          .customSelect(
            "SELECT name FROM sqlite_master WHERE name = 'pk_group_sync_aliases'",
          )
          .getSingleOrNull();
      expect(
        pkAliasTable,
        isNotNull,
        reason:
            'The downgraded v3 fixture must include pk_group_sync_aliases '
            'before the v3 → v4 cleanup is seeded.',
      );

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
        rawDb.execute('PRAGMA foreign_keys = OFF;');
        _dropPostV3Schema(rawDb);
        rawDb.execute('PRAGMA user_version = 3;');
        rawDb.execute('PRAGMA foreign_keys = ON;');
      } finally {
        rawDb.close();
      }

      final upgraded = AppDatabase(NativeDatabase(dbFile));
      addTearDown(upgraded.close);

      final aliases = await upgraded
          .customSelect('SELECT legacy_entity_id FROM pk_group_sync_aliases')
          .get();
      final legacyIds = aliases
          .map((row) => row.read<String>('legacy_entity_id'))
          .toSet();

      // Hazardous auto-alias is gone; unrelated legacy alias survives.
      expect(legacyIds, contains(legacyAliasId));
      expect(legacyIds, isNot(contains(activeLocalId)));
    });

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
        _dropPostV3Schema(rawDb);
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
          'DROP INDEX IF EXISTS idx_member_group_entries_pk_canonicalize;',
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

    test(
      'schema v3 → v4 migration divides ms-encoded DateTime columns by 1000',
      () async {
        final tempDir = Directory.systemTemp.createTempSync('prism_migration_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        // Bring the file up to current schema, seed ms-encoded rows via raw
        // SQL (mimicking the pre-H3 raw-insert paths), then downgrade
        // user_version to 3 so reopening forces the v3 → v4 branch of
        // onUpgrade to run.
        final dbFile = File('${tempDir.path}/v3_to_v4.db');
        final seeded = AppDatabase(NativeDatabase(dbFile));
        await seeded.customSelect('SELECT 1').get();
        final pkAliasTable = await seeded
            .customSelect(
              "SELECT name FROM sqlite_master WHERE name = 'pk_group_sync_aliases'",
            )
            .getSingleOrNull();
        expect(
          pkAliasTable,
          isNotNull,
          reason:
              'The downgraded v3 fixture must include pk_group_sync_aliases '
              'before the v3 → v4 DateTime rows are seeded.',
        );

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        await seeded.customStatement(
          'INSERT INTO pk_group_sync_aliases '
          '(legacy_entity_id, pk_group_uuid, canonical_entity_id, created_at) '
          'VALUES (?, ?, ?, ?)',
          ['legacy-v3', 'pk-g-uuid-v3', 'pk-group:pk-g-uuid-v3', nowMs],
        );
        await seeded.customStatement(
          'INSERT INTO pk_group_entry_deferred_sync_ops '
          '(id, entity_type, entity_id, fields_json, reason, '
          'created_at, last_retry_at, retry_count) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [
            'deferred-v3',
            'member_group_entries',
            'entry-v3',
            '{}',
            'seeded',
            nowMs,
            nowMs,
            0,
          ],
        );
        await seeded.close();

        final rawDb = raw.sqlite3.open(dbFile.path);
        try {
          rawDb.execute('PRAGMA foreign_keys = OFF;');
          _dropPostV3Schema(rawDb);
          rawDb.execute('PRAGMA user_version = 3;');
          rawDb.execute('PRAGMA foreign_keys = ON;');
        } finally {
          rawDb.close();
        }

        final upgraded = AppDatabase(NativeDatabase(dbFile));
        addTearDown(upgraded.close);

        final aliasRow = await upgraded.pkGroupSyncAliasesDao
            .getByLegacyEntityId('legacy-v3');
        expect(aliasRow, isNotNull);
        final expectedYear = DateTime.now().year;
        expect(
          aliasRow!.createdAt.year,
          inInclusiveRange(expectedYear - 1, expectedYear + 1),
          reason:
              'Migration should divide ms-encoded createdAt by 1000 so '
              'Drift decodes it as the current wall clock year.',
        );

        final deferredRows = await upgraded.pkGroupEntryDeferredSyncOpsDao
            .getAll();
        expect(deferredRows, hasLength(1));
        final deferred = deferredRows.single;
        expect(
          deferred.createdAt.year,
          inInclusiveRange(expectedYear - 1, expectedYear + 1),
        );
        expect(deferred.lastRetryAt, isNotNull);
        expect(
          deferred.lastRetryAt!.year,
          inInclusiveRange(expectedYear - 1, expectedYear + 1),
        );
      },
    );
  });
}
