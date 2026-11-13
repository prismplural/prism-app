import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm, Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_provider.dart'
    show DatabaseReadyReport;
import 'package:prism_plurality/core/sync/sync_schema.dart';

/// Release-critical upgrade proof for a **released v0.15.3 install**.
///
/// v0.15.3 shipped `AppDatabase.currentSchemaVersion == 40`; the current build
/// is v41, whose only schema delta is the `plural_port_unsupported` table
/// (imported interchange records retained for re-export). This test starts from
/// the *released* v40 DDL captured in [fixturePath] — never from current tables
/// — seeds representative user data, and proves the upgrade path:
///
///  1. open diagnostics: `user_version` 40 before, 41 after, reported as a
///     migration rather than a fresh install;
///  2. data preservation for every seeded row (settings, members, groups,
///     fronts, reminders, custom fields/values, media metadata, tombstones and
///     burned incarnation ids, chats + FTS, sync bookkeeping);
///  3. the expected v41 objects: `plural_port_unsupported` with its exact
///     columns, plus the pre-existing columns and indexes the upgrade keeps;
///  4. idempotent reopen, and resumability after an injected mid-chain kill;
///  5. fresh-schema / upgraded-schema equivalence, object by object;
///  6. no downgrade claim: a v42 file is still refused with the actionable
///     "upgrade or export-reimport" error.
const fixturePath = 'test/core/database/fixtures/v0_15_3_schema.sql';

/// The schema version the fixture was captured from (annotated tag v0.15.3).
const releasedSchemaVersion = 40;

/// Synthetic rows written into the released v40 DDL. Raw SQL keeps the fixture
/// as the sole description of the *pre-upgrade* shape: nothing here relies on
/// current Drift table classes.
const _seedStatements = <String>[
  // Singleton settings, with synced and device-local fields set away from their
  // defaults.
  '''
  INSERT INTO system_settings
    (id, system_name, show_quick_front, accent_color_hex, terminology,
     member_name_display, custom_terminology, locale_override,
     fronting_reminders_enabled, fronting_reminder_interval_minutes,
     nav_bar_label_display_mode, nav_bar_reveal_labels_when_expanded,
     members_show_groups)
  VALUES
    ('singleton', 'Released 0.15.3 System', 0, '#123456', 2, 1,
     'headmates', 'en-GB', 1, 45, 2, 1, 0)
  ''',
  // A live PK-linked member, a local-only member, and a soft-deleted tombstone
  // that still holds a short id (the recycled-id case the v40 index narrowed
  // for) plus the v40 create-push lease.
  '''
  INSERT INTO members
    (id, name, pronouns, emoji, age, bio, created_at, display_order, is_active,
     pluralkit_uuid, pluralkit_id, pluralkit_display_name, display_name,
     birthday, proxy_tags_json, pk_banner_url, is_deleted,
     create_push_started_at)
  VALUES
    ('member-live', 'Live Member', 'they/them', '🌱', '27', 'live bio',
     1717200000, 0, 1, 'uuid-live', 'live1', 'Live Member (PK)',
     'Live Member', '1998-04-02', '[{"prefix":"L:","suffix":""}]',
     'https://example.test/banner.png', 0, 1717300000),
    ('member-local', 'Local Member', NULL, '🕯', NULL, NULL,
     1717203600, 1, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 0, NULL),
    ('member-tombstone', 'Burned Tombstone', NULL, '🧱', NULL,
     'kept for delete-push', 1717207200, 2, 0, 'uuid-burned', 'burn1',
     'Burned in PK', NULL, NULL, NULL, NULL, 1, NULL)
  ''',
  // A PK-linked group with a burned incarnation generation, plus a local group.
  '''
  INSERT INTO member_groups
    (id, name, description, color_hex, emoji, display_order, group_type,
     created_at, is_deleted, pluralkit_id, pluralkit_uuid, sync_generation,
     sort_state)
  VALUES
    ('group-pk', 'PK Group', 'imported from PluralKit', '#AABBCC', '🗂', 0, 0,
     1717210000, 0, 'grp01', 'uuid-group', 1, '{"mode":2,"order":["entry-1"]}'),
    ('group-local', 'Local Group', NULL, NULL, NULL, 1, 0,
     1717213600, 0, NULL, NULL, 0, '{"mode":0,"order":[]}')
  ''',
  // Group membership edges, including a burned (re-incarnated) entry id and a
  // pending PluralKit push intent.
  '''
  INSERT INTO member_group_entries
    (id, group_id, member_id, pk_group_uuid, pk_member_uuid, pending_pk_op,
     created_at, sync_generation, is_deleted)
  VALUES
    ('entry-1', 'group-pk', 'member-live', 'uuid-group', 'uuid-live', 'none',
     1717217200, 2, 0),
    ('entry-2', 'group-pk', 'member-tombstone', 'uuid-group', 'uuid-burned',
     'remove', 1717220800, 0, 1)
  ''',
  // Fronts: an open front, an ended front, and a soft-deleted PluralKit front
  // carrying a user delete intent — the v37 -> v38 clearing step must NOT
  // re-run for a v40 database.
  '''
  INSERT INTO fronting_sessions
    (id, session_type, start_time, end_time, member_id, notes, pluralkit_uuid,
     pk_import_source, pk_file_switch_id, is_deleted, delete_intent_epoch,
     delete_push_started_at)
  VALUES
    ('front-open', 0, 1717230000, NULL, 'member-live', 'current front', NULL,
     NULL, NULL, 0, NULL, NULL),
    ('front-ended', 0, 1717240000, 1717243600, 'member-local', NULL, NULL,
     NULL, NULL, 0, NULL, NULL),
    ('front-pk-tombstone', 0, 1717250000, 1717253600, 'member-tombstone', NULL,
     'uuid-burned', 'file', 'switch-9', 1, 1717260000, 1717260100)
  ''',
  // Reminders: one active and member-targeted, one soft-deleted.
  '''
  INSERT INTO reminders
    (id, name, message, trigger, frequency, interval_days, weekly_days,
     time_of_day, delay_hours, target_member_id, is_active, created_at,
     modified_at, is_deleted)
  VALUES
    ('reminder-live', 'Hydrate', 'Drink water', 1, 'weekly', NULL, '[1,4]',
     '09:30', NULL, 'member-live', 1, 1717270000, 1717273600, 0),
    ('reminder-deleted', 'Old one', 'Removed', 0, 'daily', 1, NULL, '08:00',
     2, NULL, 0, 1717280000, 1717283600, 1)
  ''',
  // Custom field schema (flat + nested) and values (live + soft-deleted).
  '''
  INSERT INTO custom_fields
    (id, name, field_type, date_precision, display_order, created_at,
     field_type_id, parent_field_id, type_config_json, is_deleted)
  VALUES
    ('field-text', 'Favorite colour', 0, NULL, 0, 1717290000, 'text', NULL,
     NULL, 0),
    ('field-nested', 'Nested: pronouns detail', 5, NULL, 1, 1717293600,
     'text', 'field-text', '{"maxLength":40}', 0)
  ''',
  '''
  INSERT INTO custom_field_values
    (id, custom_field_id, member_id, value, is_deleted)
  VALUES
    ('value-live', 'field-text', 'member-live', 'teal', 0),
    ('value-nested', 'field-nested', 'member-live', 'they/them/their', 0),
    ('value-deleted', 'field-text', 'member-tombstone', 'grey', 1)
  ''',
  // Media metadata: a chat image with the v37 thumbnail hash pair, and a bio
  // image that has none.
  '''
  INSERT INTO media_attachments
    (id, message_id, member_id, tag, media_id, media_type, encryption_key_b64,
     content_hash, plaintext_hash, mime_type, size_bytes, width, height,
     duration_ms, blurhash, waveform_b64, thumbnail_media_id,
     thumbnail_content_hash, thumbnail_plaintext_hash, source_url,
     preview_url, is_deleted)
  VALUES
    ('media-chat', 'message-1', '', 'chat', 'media-1', 'image', 'a2V5', 'ch',
     'ph', 'image/png', 2048, 64, 64, 0, 'LEHV6nWB2yk8pyo0adR*.7kCMdnj', '',
     'thumb-1', 'tch', 'tph', '', '', 0),
    ('media-bio', '', 'member-live', 'bio', 'media-2', 'image', 'a2V5', 'ch2',
     'ph2', 'image/jpeg', 4096, 128, 128, 0, '', '', '', '', '', '', '', 0)
  ''',
  // Durable upload queue (blob payload) and the missing-media heal set.
  '''
  INSERT INTO upload_queue_entries
    (media_id, content_hash, ciphertext, ttl_secs, attempts, next_attempt_at,
     created_at, state, last_error)
  VALUES
    ('media-queued', 'queued-hash', X'00FF10', NULL, 2, 1717330000,
     1717320000, 'pending', 'network down')
  ''',
  '''
  INSERT INTO missing_media
    (media_id, priority, first_missing_at, last_requested_at, attempts,
     next_eligible_at, state)
  VALUES
    ('media-missing', 0, 1717340000, 1717343600, 3, 1717350000, 'waiting')
  ''',
  // Notes, and a conversation whose messages the released FTS triggers indexed.
  '''
  INSERT INTO notes
    (id, title, body, color_hex, member_id, date, created_at, modified_at,
     is_deleted)
  VALUES
    ('note-1', 'Front log', 'historical needle from 0.15.3', '#FFEE99',
     'member-live', 1717360000, 1717360000, 1717363600, 0)
  ''',
  '''
  INSERT INTO conversations
    (id, created_at, last_activity_at, title, participant_ids, is_deleted)
  VALUES
    ('conversation-1', 1717370000, 1717373600, 'Release chat',
     '["member-live","member-local"]', 0)
  ''',
  '''
  INSERT INTO chat_messages
    (id, content, timestamp, author_id, conversation_id, reactions,
     reply_to_id, is_deleted)
  VALUES
    ('message-1', 'historical needle from 0.15.3', 1717370000, 'member-live',
     'conversation-1', '[]', NULL, 0),
    ('message-2', 'second message', 1717373600, 'member-local',
     'conversation-1', '[]', 'message-1', 0)
  ''',
  // Preference rows: app-level key/value and per-member profile.
  '''
  INSERT INTO app_preference_values (key, value_type, value_json, is_deleted)
  VALUES ('theme.mode', 'string', '"light"', 0)
  ''',
  '''
  INSERT INTO member_profile_preference_values
    (id, member_id, key, value_type, value_json, is_deleted)
  VALUES ('pref-1', 'member-live', 'profile.layout', 'string', '"grid"', 0)
  ''',
  // PluralKit redirect aliases (identity + group), including a legacy id whose
  // row was redirected during an apply-time dedup.
  '''
  INSERT INTO pk_identity_sync_aliases
    (entity_table, legacy_entity_id, pk_uuid, pk_id, member_id, target_row_id,
     created_at)
  VALUES
    ('members', 'legacy-member-id', 'uuid-live', 'live1', NULL, 'member-live',
     1717380000),
    ('fronting_sessions', 'legacy-front-id', 'uuid-burned', NULL,
     'member-tombstone', 'front-pk-tombstone', 1717383600)
  ''',
  '''
  INSERT INTO pk_group_sync_aliases
    (legacy_entity_id, pk_group_uuid, canonical_entity_id, created_at)
  VALUES ('pk-group:uuid-group', 'uuid-group', 'pk-group:uuid-group',
     1717390000)
  ''',
  // Sync bookkeeping rows a v40 install can legitimately hold.
  '''
  INSERT INTO sync_op_outbox
    (table_name, entity_id, op_type, fields_json, created_at, attempts,
     last_error, quarantined)
  VALUES
    ('notes', 'note-1', 'update', '{"title":"Front log"}', 1717400000, 1,
     NULL, 0)
  ''',
  '''
  INSERT INTO sync_migration_repairs
    (table_name, entity_id, field_names_json, reason, enqueued_at)
  VALUES
    ('member_group_entries', 'entry-1', '["created_at"]',
     'migration_v32_to_v37_entries_created_at', 1717410000)
  ''',
  '''
  INSERT INTO sync_quarantine
    (id, entity_type, entity_id, field_name, expected_type, received_type,
     received_value, source_device, retry_count, last_retry_at, created_at,
     error_message)
  VALUES
    ('quarantine-1', 'members', 'member-live', 'is_active', 'Bool', 'String',
     'yes', 'peer-device', 2, 1717420000, 1717415000, 'type mismatch')
  ''',
];

/// Tables the seed statements touch; each one's rows are snapshotted before the
/// upgrade and re-read after it.
const _seededTables = <String>[
  'app_preference_values',
  'chat_messages',
  'conversations',
  'custom_field_values',
  'custom_fields',
  'fronting_sessions',
  'member_group_entries',
  'member_groups',
  'member_profile_preference_values',
  'members',
  'media_attachments',
  'missing_media',
  'notes',
  'pk_group_sync_aliases',
  'pk_identity_sync_aliases',
  'reminders',
  'sync_migration_repairs',
  'sync_op_outbox',
  'sync_quarantine',
  'system_settings',
  'upload_queue_entries',
];

/// FTS5 shadow tables SQLite materializes from the virtual-table DDL; their
/// shape is not part of the app schema, and their contents are covered by the
/// `MATCH` assertion instead.
const _ftsShadowTables = <String>{
  'chat_messages_fts_config',
  'chat_messages_fts_content',
  'chat_messages_fts_data',
  'chat_messages_fts_docsize',
  'chat_messages_fts_idx',
};

Future<Directory> _temporaryDirectory(String name) async {
  final directory = Directory.systemTemp.createTempSync(name);
  addTearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  return directory;
}

/// Materializes the released v0.15.3 DDL plus [_seedStatements] into a new file.
Future<File> _seedReleasedV0153Database(String name) async {
  final directory = await _temporaryDirectory(name);
  final fixture = File(fixturePath);
  expect(
    fixture.existsSync(),
    isTrue,
    reason: 'released v0.15.3 schema fixture is missing',
  );

  final databaseFile = File('${directory.path}/prism.sqlite');
  final database = raw.sqlite3.open(databaseFile.path);
  try {
    database.execute(fixture.readAsStringSync());
    expect(
      _userVersion(database),
      releasedSchemaVersion,
      reason: 'the fixture must carry the released v0.15.3 user_version',
    );
    for (final statement in _seedStatements) {
      database.execute(statement);
    }
  } finally {
    database.close();
  }
  return databaseFile;
}

int _userVersion(raw.Database database) =>
    database.select('PRAGMA user_version').single['user_version'] as int;

/// Canonical, type-tagged rendering of a cell so pre/post upgrades compare
/// exactly (integer seconds stay integers, blobs compare by bytes).
String _canonicalCell(Object? value) {
  if (value == null) return 'null';
  if (value is List<int>) return 'blob:${value.join(",")}';
  return '${value.runtimeType}:$value';
}

/// Row-by-row snapshot of [_seededTables], read through a raw connection so the
/// comparison is independent of Drift's decoding.
Map<String, List<Map<String, String>>> _rowSnapshot(String path) {
  final database = raw.sqlite3.open(path);
  try {
    final snapshot = <String, List<Map<String, String>>>{};
    for (final table in _seededTables) {
      final columns = database
          .select('PRAGMA table_info($table)')
          .map((row) => row['name'] as String)
          .toList();
      final rows = database.select(
        'SELECT * FROM $table ORDER BY ${columns.join(', ')}',
      );
      snapshot[table] = [
        for (final row in rows)
          {for (final column in columns) column: _canonicalCell(row[column])},
      ];
    }
    return snapshot;
  } finally {
    database.close();
  }
}

/// Column shape of one table: name, declared type, NOT NULL, default, PK flag.
List<String> _tableShape(raw.Database database, String table) {
  return database
      .select('PRAGMA table_info($table)')
      .map(
        (row) =>
            '${row['name']}|${row['type']}|${row['notnull']}|'
            '${row['dflt_value']}|${row['pk']}',
      )
      .toList();
}

String _normalizeSql(String sql) => sql.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Object-level schema fingerprint: table shapes plus index/trigger SQL.
/// Excludes SQLite internals and FTS5 shadow tables.
Map<String, List<String>> _schemaFingerprint(String path) {
  final database = raw.sqlite3.open(path);
  try {
    final fingerprint = <String, List<String>>{};
    final tables = database
        .select(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )
        .map((row) => row['name'] as String)
        .where((name) => !_ftsShadowTables.contains(name));
    for (final table in tables) {
      fingerprint['table:$table'] = _tableShape(database, table);
    }
    final objects = database.select(
      'SELECT type, name, sql FROM sqlite_master '
      "WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' "
      "AND type IN ('table', 'index', 'trigger') ORDER BY type, name",
    );
    for (final object in objects) {
      final name = object['name'] as String;
      if (_ftsShadowTables.contains(name)) continue;
      // Table shapes are compared column by column above; the DDL text is
      // compared here so index definitions and CHECK clauses are covered too.
      fingerprint['ddl:${object['type']}:$name'] = [
        _normalizeSql(object['sql'] as String),
      ];
    }
    return fingerprint;
  } finally {
    database.close();
  }
}

Future<int> _schemaVersion(AppDatabase database) async {
  final row = await database.customSelect('PRAGMA user_version').getSingle();
  return row.read<int>('user_version');
}

Future<String?> _sqliteObjectSql(AppDatabase database, String name) async {
  final row = await database
      .customSelect(
        'SELECT sql FROM sqlite_master WHERE name = ?',
        variables: [Variable<String>(name)],
      )
      .getSingleOrNull();
  return row?.read<String?>('sql');
}

Future<Set<String>> _columns(AppDatabase database, String table) async {
  final rows = await database.customSelect('PRAGMA table_info($table)').get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

Future<Set<String>> _tables(AppDatabase database) async {
  final rows = await database
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
      .get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

Future<String?> _scalar(
  AppDatabase database,
  String sql, [
  List<Variable<Object>> variables = const [],
]) async {
  final row = await database
      .customSelect(sql, variables: variables)
      .getSingle();
  return row.data.values.first?.toString();
}

/// Every post-upgrade assertion, shared by the plain-open and the
/// resume-after-interruption cases.
Future<void> _expectUpgradedFromReleasedV0153(
  AppDatabase database, {
  required Map<String, List<Map<String, String>>> seededRows,
  required String path,
}) async {
  expect(AppDatabase.currentSchemaVersion, 41);
  expect(await _schemaVersion(database), AppDatabase.currentSchemaVersion);

  // 1. Open diagnostics: released v40 -> current v41, reported as a migration
  //    rather than a fresh install. `DatabaseReadyReport` is what the startup
  //    gate renders its copy from.
  const diagnostics = DatabaseReadyReport(
    schemaVersionBeforeOpen: releasedSchemaVersion,
    schemaVersionAfterOpen: 41,
  );
  expect(diagnostics.createdFresh, isFalse);
  expect(diagnostics.migrated, isTrue);

  // 2. Data preservation: every seeded row survives with identical values.
  expect(
    _rowSnapshot(path),
    seededRows,
    reason: 'the v40 -> v41 upgrade must not rewrite or drop released data',
  );

  // The v37 -> v38 PluralKit delete-intent clearing step must not re-run for a
  // v40 database: only the v40 -> v41 step applies.
  expect(
    await _scalar(
      database,
      'SELECT delete_intent_epoch FROM fronting_sessions WHERE id = ?',
      [const Variable<String>('front-pk-tombstone')],
    ),
    '1717260000',
  );
  // The v40 create-push lease column and its value survive too.
  expect(
    await _scalar(
      database,
      'SELECT create_push_started_at FROM members WHERE id = ?',
      [const Variable<String>('member-live')],
    ),
    '1717300000',
  );

  // 3. The new table, with its exact shape.
  expect(await _tables(database), contains('plural_port_unsupported'));
  expect(await _columns(database, 'plural_port_unsupported'), {
    'id',
    'document_id',
    'chunk_index',
    'chunk_count',
    'payload',
    'is_deleted',
  });
  expect(_schemaFingerprint(path)['table:plural_port_unsupported'], [
    'id|TEXT|1|null|1',
    'document_id|TEXT|1|null|0',
    'chunk_index|INTEGER|1|null|0',
    'chunk_count|INTEGER|1|null|0',
    'payload|TEXT|1|null|0',
    'is_deleted|INTEGER|1|0|0',
  ]);

  // The table is also in the synced schema, so the new entity is not silently
  // device-local.
  expect(prismSyncSchema, contains('"plural_port_unsupported"'));

  // Pre-existing columns the v40 -> v41 step must leave alone.
  expect(
    await _columns(database, 'members'),
    containsAll(<String>[
      'pluralkit_uuid',
      'pluralkit_id',
      'create_push_started_at',
    ]),
  );
  expect(
    await _columns(database, 'member_groups'),
    containsAll(<String>['sync_generation', 'sort_state']),
  );
  expect(
    await _columns(database, 'member_group_entries'),
    containsAll(<String>['created_at', 'sync_generation', 'pending_pk_op']),
  );
  expect(
    await _columns(database, 'media_attachments'),
    containsAll(<String>['thumbnail_content_hash', 'thumbnail_plaintext_hash']),
  );
  expect(
    await _columns(database, 'system_settings'),
    containsAll(<String>[
      'member_name_display',
      'nav_bar_label_display_mode',
      'nav_bar_reveal_labels_when_expanded',
    ]),
  );

  // Expected indexes: the v40 narrowing of the short-id index, the covering
  // uuid index, the uniqueness backstops, and the fronting pair.
  final shortIdIndex = await _sqliteObjectSql(
    database,
    'idx_members_pluralkit_id',
  );
  expect(shortIdIndex, isNotNull);
  expect(shortIdIndex, contains('is_deleted = 0'));
  expect(
    await _sqliteObjectSql(database, 'idx_members_pluralkit_uuid'),
    isNotNull,
  );
  expect(
    await _sqliteObjectSql(
      database,
      'idx_fronting_sessions_pluralkit_uuid_member_id',
    ),
    isNotNull,
  );
  expect(
    await _sqliteObjectSql(
      database,
      'idx_fronting_sessions_pluralkit_uuid_orphan',
    ),
    isNotNull,
  );
  expect(
    await _sqliteObjectSql(database, 'idx_custom_field_values_field_member'),
    isNotNull,
  );
  expect(
    await _sqliteObjectSql(database, 'idx_member_profile_pref_member_key'),
    isNotNull,
  );
  expect(
    await _sqliteObjectSql(database, 'idx_member_group_entries_unique'),
    isNotNull,
  );

  // Tombstones and burned ids stay addressable: the PK front keeps its uuid, the
  // tombstoned member keeps its recycled short id, and the burned incarnation
  // generations are untouched.
  expect(
    await _scalar(database, 'SELECT pluralkit_uuid FROM members WHERE id = ?', [
      const Variable<String>('member-tombstone'),
    ]),
    'uuid-burned',
  );
  expect(
    await _scalar(database, 'SELECT pluralkit_id FROM members WHERE id = ?', [
      const Variable<String>('member-tombstone'),
    ]),
    'burn1',
  );
  expect(
    await _scalar(
      database,
      'SELECT sync_generation FROM member_groups WHERE id = ?',
      [const Variable<String>('group-pk')],
    ),
    '1',
  );
  expect(
    await _scalar(
      database,
      'SELECT sync_generation FROM member_group_entries WHERE id = ?',
      [const Variable<String>('entry-1')],
    ),
    '2',
  );

  // Chat search still works: the released FTS index and triggers survive.
  final ftsRows = await database
      .customSelect(
        'SELECT message_id FROM chat_messages_fts '
        "WHERE chat_messages_fts MATCH 'needle'",
      )
      .get();
  expect(ftsRows.map((row) => row.read<String>('message_id')), ['message-1']);

  // 4. The new table round-trips through its Drift table class: two chunks of a
  //    single opaque imported document, the second already tombstoned.
  await database
      .into(database.pluralPortUnsupported)
      .insert(
        PluralPortUnsupportedCompanion.insert(
          id: 'unsupported-chunk-1',
          documentId: 'document-1',
          chunkIndex: 0,
          chunkCount: 2,
          payload: '{"opaque":"interchange"}',
        ),
      );
  await database
      .into(database.pluralPortUnsupported)
      .insert(
        PluralPortUnsupportedCompanion.insert(
          id: 'unsupported-chunk-2',
          documentId: 'document-1',
          chunkIndex: 1,
          chunkCount: 2,
          payload: '{"opaque":"tail"}',
          isDeleted: const Value(true),
        ),
      );
  final stored = await (database.select(
    database.pluralPortUnsupported,
  )..orderBy([(t) => OrderingTerm(expression: t.chunkIndex)])).get();
  expect(stored.map((row) => row.documentId), ['document-1', 'document-1']);
  expect(stored.map((row) => row.payload), [
    '{"opaque":"interchange"}',
    '{"opaque":"tail"}',
  ]);
  expect(stored.map((row) => row.isDeleted), [false, true]);
}

void main() {
  group('released v0.15.3 (schema v40) upgrade fixture', () {
    test(
      'opens as v41 with diagnostics, data, indexes and the new table',
      () async {
        final databaseFile = await _seedReleasedV0153Database(
          'prism_released_v0153_normal_',
        );
        final seededRows = _rowSnapshot(databaseFile.path);

        final database = AppDatabase(NativeDatabase(databaseFile));
        addTearDown(database.close);
        await database.customSelect('SELECT 1').get();

        await _expectUpgradedFromReleasedV0153(
          database,
          seededRows: seededRows,
          path: databaseFile.path,
        );
      },
    );

    test('reopening the upgraded database is idempotent', () async {
      final databaseFile = await _seedReleasedV0153Database(
        'prism_released_v0153_reopen_',
      );
      final seededRows = _rowSnapshot(databaseFile.path);

      final first = AppDatabase(NativeDatabase(databaseFile));
      await first.customSelect('SELECT 1').get();
      final firstFingerprint = _schemaFingerprint(databaseFile.path);
      await first.close();

      final second = AppDatabase(NativeDatabase(databaseFile));
      addTearDown(second.close);
      await second.customSelect('SELECT 1').get();

      expect(await _schemaVersion(second), AppDatabase.currentSchemaVersion);
      expect(_schemaFingerprint(databaseFile.path), firstFingerprint);
      expect(
        _rowSnapshot(databaseFile.path),
        seededRows,
        reason:
            're-running the chain from 41 must be a no-op for released rows',
      );
      final importedRows = await second
          .customSelect('SELECT COUNT(*) AS c FROM plural_port_unsupported')
          .getSingle();
      expect(
        importedRows.read<int>('c'),
        0,
        reason: 'reopening must not invent imported interchange rows',
      );
    });

    test(
      'resumes an injected mid-chain kill without losing released data',
      () async {
        final databaseFile = await _seedReleasedV0153Database(
          'prism_released_v0153_resume_',
        );
        final seededRows = _rowSnapshot(databaseFile.path);

        final interrupted = AppDatabase(NativeDatabase(databaseFile))
          ..debugFailMigrationStepTo = 41;
        await expectLater(
          interrupted.customSelect('SELECT 1').get(),
          throwsA(isA<StateError>()),
        );
        await interrupted.close();

        final afterKill = raw.sqlite3.open(databaseFile.path);
        try {
          expect(
            _userVersion(afterKill),
            40,
            reason:
                'the v40 -> v41 step committed neither its DDL nor its stamp',
          );
          final tables = afterKill
              .select("SELECT name FROM sqlite_master WHERE type = 'table'")
              .map((row) => row['name'] as String)
              .toSet();
          expect(tables, isNot(contains('plural_port_unsupported')));
        } finally {
          afterKill.close();
        }
        expect(
          _rowSnapshot(databaseFile.path),
          seededRows,
          reason: 'a failed upgrade step must roll back completely',
        );

        final resumed = AppDatabase(NativeDatabase(databaseFile));
        addTearDown(resumed.close);
        await resumed.customSelect('SELECT 1').get();

        await _expectUpgradedFromReleasedV0153(
          resumed,
          seededRows: seededRows,
          path: databaseFile.path,
        );
      },
    );

    test('fresh v41 schema and upgraded v40 schema are equivalent', () async {
      final upgradedFile = await _seedReleasedV0153Database(
        'prism_released_v0153_equivalence_',
      );
      final upgraded = AppDatabase(NativeDatabase(upgradedFile));
      await upgraded.customSelect('SELECT 1').get();
      await upgraded.close();

      final freshDirectory = await _temporaryDirectory(
        'prism_fresh_v41_equivalence_',
      );
      final freshFile = File('${freshDirectory.path}/prism.sqlite');
      final fresh = AppDatabase(NativeDatabase(freshFile));
      await fresh.customSelect('SELECT 1').get();
      await fresh.close();

      expect(
        _schemaFingerprint(upgradedFile.path),
        _schemaFingerprint(freshFile.path),
        reason:
            'an upgraded v40 database must match a freshly created v41 '
            'database object for object',
      );
    });

    test(
      'does not claim a downgrade path: a v42 file is refused up front, untouched',
      () async {
        final futureFile = await _seedReleasedV0153Database(
          'prism_released_v0153_downgrade_',
        );
        final seededRows = _rowSnapshot(futureFile.path);
        final seededFingerprint = _schemaFingerprint(futureFile.path);
        final stamped = raw.sqlite3.open(futureFile.path);
        try {
          stamped.execute('PRAGMA user_version = 42');
        } finally {
          stamped.close();
        }

        // No downgrade path is claimed: a file stamped newer than this build is
        // refused before any migration step runs, with the actionable
        // "you have downgraded" diagnosis (drift calls onUpgrade before
        // beforeOpen, so the refusal has to happen there to win the race).
        final refused = AppDatabase(NativeDatabase(futureFile));
        addTearDown(refused.close);
        await expectLater(
          refused.customSelect('SELECT 1').get(),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('schema v42 is newer than this app (v41)'),
                contains('downgraded to an older build'),
                contains('re-import'),
                isNot(contains('Schema baseline was reset to v1')),
              ),
            ),
          ),
        );

        final afterRefusal = raw.sqlite3.open(futureFile.path);
        try {
          expect(
            _userVersion(afterRefusal),
            42,
            reason: 'a refused open must not stamp the file with this schema',
          );
        } finally {
          afterRefusal.close();
        }
        // No DDL ran: not even the v40 -> v41 table the runner creates before
        // any step, and the schema object set is identical to the seeded one.
        expect(_schemaFingerprint(futureFile.path), seededFingerprint);
        expect(
          _rowSnapshot(futureFile.path),
          seededRows,
          reason: 'a refused downgrade must leave the newer file untouched',
        );
      },
    );
  });
}
