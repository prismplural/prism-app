import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:prism_plurality/core/database/app_database.dart';

// ────────────────────────────────────────────────────────────────────────────
// V1 SCHEMA FIXTURE
//
// Reconstructed from the squash commit `6161c4f3` (schemaVersion = 1) via
// `git show 6161c4f3:app/lib/core/database/tables/<table>.dart` for every
// table file.  The approach chosen was Option A (git archaeology) per the task
// spec: read the Dart table classes at the v1-baseline commit and translate
// them to raw SQL CREATE TABLE statements.
//
// What is intentionally ABSENT (added in v2+):
//   - Tables: pk_group_sync_aliases (v2), pk_group_entry_deferred_sync_ops (v2)
//   - Columns: member_group_entries.{pk_group_uuid, pk_member_uuid} (v2)
//              member_groups.{sync_suppressed, suspected_pk_group_uuid} (v2)
//              system_settings.pk_group_sync_v2_enabled (v3)
//              members.pk_banner_url (v6)
//              members.is_always_fronting (v7)
//              system_settings.pending_fronting_migration_mode (v7)
//              front_session_comments.{target_time, author_member_id} (v7)
//   - Indexes referencing v2+ columns (sync_suppressed, suspected_pk_group_uuid,
//     pk_group_uuid, pk_member_uuid)
//   - The composite/orphan fronting indexes (v7)
//
// What IS present and represents v1:
//   - idx_fronting_sessions_pluralkit_uuid  (single-column, dropped by v6→v7)
//   - idx_member_groups_pluralkit_uuid WITHOUT is_deleted filter (v4→v5 recreates it)
//
// NOTE: When seeding scenarios 2 and 3 (duplicate rows) we intentionally omit
// the single-column unique index on fronting_sessions. This simulates a
// corrupted/edge-case DB where the index was bypassed (e.g., previously
// imported via raw SQL, or a crash mid-index-creation). The whole point of
// the detect-and-refuse in v6→v7 is to handle exactly this case gracefully.
// ────────────────────────────────────────────────────────────────────────────

/// Creates a raw SQLite database at [dbFile] with the exact v1 schema.
///
/// Mirrors the table definitions from `6161c4f3` (schemaVersion = 1).
/// [includeV1FrontingIndex] controls whether the single-column
/// `idx_fronting_sessions_pluralkit_uuid` is created — pass false when
/// seeding duplicate-uuid scenarios (Scenario 2 and 3) so we can insert
/// conflicting rows before AppDatabase runs the v6→v7 detect-and-refuse.
void _seedV1Schema(
  raw.Database rawDb, {
  bool includeV1FrontingIndex = true,
}) {
  // ── Core tables ─────────────────────────────────────────────────────────

  // v1 members — no pk_banner_url, no is_always_fronting
  rawDb.execute('''
    CREATE TABLE IF NOT EXISTS members (
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
      display_name TEXT,
      birthday TEXT,
      proxy_tags_json TEXT,
      pluralkit_sync_ignored INTEGER NOT NULL DEFAULT 0,
      markdown_enabled INTEGER NOT NULL DEFAULT 0,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      delete_intent_epoch INTEGER,
      delete_push_started_at INTEGER
    )
  ''');

  // v1 fronting_sessions — no is_always_fronting (that's on members), no
  // per-member session fields yet
  rawDb.execute('''
    CREATE TABLE IF NOT EXISTS fronting_sessions (
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
      pk_member_ids_json TEXT,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      delete_intent_epoch INTEGER,
      delete_push_started_at INTEGER
    )
  ''');

  // v1 front_session_comments — no target_time, no author_member_id
  rawDb.execute('''
    CREATE TABLE IF NOT EXISTS front_session_comments (
      id TEXT NOT NULL PRIMARY KEY,
      session_id TEXT NOT NULL,
      body TEXT NOT NULL,
      timestamp INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0
    )
  ''');

  rawDb.execute('''
    CREATE TABLE IF NOT EXISTS conversations (
      id TEXT NOT NULL PRIMARY KEY,
      created_at INTEGER NOT NULL,
      last_activity_at INTEGER NOT NULL,
      title TEXT,
      emoji TEXT,
      is_direct_message INTEGER NOT NULL DEFAULT 0,
      creator_id TEXT,
      participant_ids TEXT NOT NULL DEFAULT '[]',
      last_read_timestamps TEXT NOT NULL DEFAULT '{}',
      archived_by_member_ids TEXT NOT NULL DEFAULT '[]',
      muted_by_member_ids TEXT NOT NULL DEFAULT '[]',
      description TEXT,
      category_id TEXT,
      display_order INTEGER NOT NULL DEFAULT 0,
      is_deleted INTEGER NOT NULL DEFAULT 0
    )
  ''');

  rawDb.execute('''
    CREATE TABLE IF NOT EXISTS chat_messages (
      id TEXT NOT NULL PRIMARY KEY,
      content TEXT NOT NULL,
      timestamp INTEGER NOT NULL,
      is_system_message INTEGER NOT NULL DEFAULT 0,
      edited_at INTEGER,
      author_id TEXT,
      conversation_id TEXT NOT NULL,
      reactions TEXT NOT NULL DEFAULT '[]',
      reply_to_id TEXT,
      reply_to_author_id TEXT,
      reply_to_content TEXT,
      is_deleted INTEGER NOT NULL DEFAULT 0
    )
  ''');

  rawDb.execute('''
    CREATE TABLE IF NOT EXISTS system_settings (
      id TEXT NOT NULL DEFAULT 'singleton' PRIMARY KEY,
      system_name TEXT,
      show_quick_front INTEGER NOT NULL DEFAULT 1,
      accent_color_hex TEXT NOT NULL DEFAULT '#AF8EE9',
      per_member_accent_colors INTEGER NOT NULL DEFAULT 0,
      terminology INTEGER NOT NULL DEFAULT 0,
      custom_terminology TEXT,
      custom_plural_terminology TEXT,
      locale_override TEXT,
      terminology_use_english INTEGER NOT NULL DEFAULT 0,
      sharing_id TEXT,
      fronting_reminders_enabled INTEGER NOT NULL DEFAULT 0,
      fronting_reminder_interval_minutes INTEGER NOT NULL DEFAULT 60,
      theme_mode INTEGER NOT NULL DEFAULT 0,
      theme_brightness INTEGER NOT NULL DEFAULT 0,
      theme_style INTEGER NOT NULL DEFAULT 0,
      theme_corner_style INTEGER NOT NULL DEFAULT 0,
      chat_enabled INTEGER NOT NULL DEFAULT 1,
      polls_enabled INTEGER NOT NULL DEFAULT 1,
      habits_enabled INTEGER NOT NULL DEFAULT 1,
      sleep_tracking_enabled INTEGER NOT NULL DEFAULT 1,
      gif_search_enabled INTEGER NOT NULL DEFAULT 1,
      voice_notes_enabled INTEGER NOT NULL DEFAULT 1,
      sleep_suggestion_enabled INTEGER NOT NULL DEFAULT 0,
      sleep_suggestion_hour INTEGER NOT NULL DEFAULT 22,
      sleep_suggestion_minute INTEGER NOT NULL DEFAULT 0,
      wake_suggestion_enabled INTEGER NOT NULL DEFAULT 0,
      wake_suggestion_after_hours REAL NOT NULL DEFAULT 8.0,
      quick_switch_threshold_seconds INTEGER NOT NULL DEFAULT 30,
      identity_generation INTEGER NOT NULL DEFAULT 0,
      chat_logs_front INTEGER NOT NULL DEFAULT 0,
      has_completed_onboarding INTEGER NOT NULL DEFAULT 0,
      sync_theme_enabled INTEGER NOT NULL DEFAULT 0,
      timing_mode INTEGER NOT NULL DEFAULT 0,
      habits_badge_enabled INTEGER NOT NULL DEFAULT 1,
      notes_enabled INTEGER NOT NULL DEFAULT 1,
      system_description TEXT,
      system_color TEXT,
      system_tag TEXT,
      system_avatar_data BLOB,
      reminders_enabled INTEGER NOT NULL DEFAULT 1,
      gif_consent_state INTEGER NOT NULL DEFAULT 0,
      font_scale REAL NOT NULL DEFAULT 1.0,
      font_family INTEGER NOT NULL DEFAULT 0,
      pin_lock_enabled INTEGER NOT NULL DEFAULT 0,
      biometric_lock_enabled INTEGER NOT NULL DEFAULT 0,
      auto_lock_delay_seconds INTEGER NOT NULL DEFAULT 0,
      display_font_in_app_bar INTEGER NOT NULL DEFAULT 1,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      previous_accent_color_hex TEXT NOT NULL DEFAULT '',
      nav_bar_items TEXT NOT NULL DEFAULT '',
      nav_bar_overflow_items TEXT NOT NULL DEFAULT '',
      sync_navigation_enabled INTEGER NOT NULL DEFAULT 1,
      chat_badge_preferences TEXT NOT NULL DEFAULT '{}',
      default_sleep_quality TEXT
    )
  ''');

  rawDb.execute('''
    CREATE TABLE IF NOT EXISTS polls (
      id TEXT NOT NULL PRIMARY KEY,
      question TEXT NOT NULL,
      is_anonymous INTEGER NOT NULL DEFAULT 0,
      allows_multiple_votes INTEGER NOT NULL DEFAULT 0,
      is_closed INTEGER NOT NULL DEFAULT 0,
      description TEXT,
      expires_at INTEGER,
      created_at INTEGER NOT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0
    )
  ''');

  rawDb.execute('''
    CREATE TABLE IF NOT EXISTS poll_options (
      id TEXT NOT NULL PRIMARY KEY,
      poll_id TEXT NOT NULL,
      option_text TEXT NOT NULL,
      sort_order INTEGER NOT NULL DEFAULT 0,
      is_other_option INTEGER NOT NULL DEFAULT 0,
      color_hex TEXT,
      is_deleted INTEGER NOT NULL DEFAULT 0
    )
  ''');

  rawDb.execute('''
    CREATE TABLE IF NOT EXISTS poll_votes (
      id TEXT NOT NULL PRIMARY KEY,
      poll_option_id TEXT NOT NULL,
      member_id TEXT NOT NULL,
      voted_at INTEGER NOT NULL,
      response_text TEXT,
      is_deleted INTEGER NOT NULL DEFAULT 0
    )
  ''');

  rawDb.execute('''
    CREATE TABLE IF NOT EXISTS sleep_sessions (
      id TEXT NOT NULL PRIMARY KEY,
      start_time INTEGER NOT NULL,
      end_time INTEGER,
      quality INTEGER NOT NULL DEFAULT 0,
      notes TEXT,
      is_health_kit_import INTEGER NOT NULL DEFAULT 0,
      is_deleted INTEGER NOT NULL DEFAULT 0
    )
  ''');

  rawDb.execute('''
    CREATE TABLE IF NOT EXISTS plural_kit_sync_state (
      id TEXT NOT NULL PRIMARY KEY,
      system_id TEXT,
      last_sync_date INTEGER,
      last_manual_sync_date INTEGER,
      is_connected INTEGER NOT NULL DEFAULT 0,
      field_sync_config TEXT,
      mapping_acknowledged INTEGER NOT NULL DEFAULT 0,
      linked_at INTEGER,
      link_epoch INTEGER NOT NULL DEFAULT 0
    )
  ''');

  rawDb.execute('''
    CREATE TABLE IF NOT EXISTS habits (
      id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL,
      description TEXT,
      icon TEXT,
      color_hex TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL,
      modified_at INTEGER NOT NULL,
      frequency TEXT NOT NULL DEFAULT 'daily',
      weekly_days TEXT,
      interval_days INTEGER,
      reminder_time TEXT,
      notifications_enabled INTEGER NOT NULL DEFAULT 0,
      notification_message TEXT,
      assigned_member_id TEXT,
      only_notify_when_fronting INTEGER NOT NULL DEFAULT 0,
      is_private INTEGER NOT NULL DEFAULT 0,
      current_streak INTEGER NOT NULL DEFAULT 0,
      best_streak INTEGER NOT NULL DEFAULT 0,
      total_completions INTEGER NOT NULL DEFAULT 0,
      is_deleted INTEGER NOT NULL DEFAULT 0
    )
  ''');

  rawDb.execute('''
    CREATE TABLE IF NOT EXISTS habit_completions (
      id TEXT NOT NULL PRIMARY KEY,
      habit_id TEXT NOT NULL,
      completed_at INTEGER NOT NULL,
      completed_by_member_id TEXT,
      notes TEXT,
      was_fronting INTEGER NOT NULL DEFAULT 0,
      rating INTEGER,
      created_at INTEGER NOT NULL,
      modified_at INTEGER NOT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0
    )
  ''');

  rawDb.execute('''
    CREATE TABLE IF NOT EXISTS sync_quarantine (
      id TEXT NOT NULL PRIMARY KEY,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      field_name TEXT,
      expected_type TEXT NOT NULL,
      received_type TEXT NOT NULL,
      received_value TEXT,
      source_device TEXT,
      retry_count INTEGER NOT NULL DEFAULT 0,
      last_retry_at INTEGER,
      created_at INTEGER NOT NULL,
      error_message TEXT
    )
  ''');

  // v1 member_groups — no sync_suppressed, no suspected_pk_group_uuid
  rawDb.execute('''
    CREATE TABLE IF NOT EXISTS member_groups (
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
      is_deleted INTEGER NOT NULL DEFAULT 0,
      pluralkit_id TEXT,
      pluralkit_uuid TEXT,
      last_seen_from_pk_at INTEGER
    )
  ''');

  // v1 member_group_entries — no pk_group_uuid, no pk_member_uuid
  rawDb.execute('''
    CREATE TABLE IF NOT EXISTS member_group_entries (
      id TEXT NOT NULL PRIMARY KEY,
      group_id TEXT NOT NULL,
      member_id TEXT NOT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0
    )
  ''');

  rawDb.execute('''
    CREATE TABLE IF NOT EXISTS custom_fields (
      id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL,
      field_type INTEGER NOT NULL,
      date_precision INTEGER,
      display_order INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0
    )
  ''');

  rawDb.execute('''
    CREATE TABLE IF NOT EXISTS custom_field_values (
      id TEXT NOT NULL PRIMARY KEY,
      custom_field_id TEXT NOT NULL,
      member_id TEXT NOT NULL,
      value TEXT NOT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0
    )
  ''');

  rawDb.execute('''
    CREATE TABLE IF NOT EXISTS notes (
      id TEXT NOT NULL PRIMARY KEY,
      title TEXT NOT NULL,
      body TEXT NOT NULL,
      color_hex TEXT,
      member_id TEXT,
      date INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      modified_at INTEGER NOT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0
    )
  ''');

  rawDb.execute('''
    CREATE TABLE IF NOT EXISTS conversation_categories (
      id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL,
      display_order INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      modified_at INTEGER NOT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0
    )
  ''');

  rawDb.execute('''
    CREATE TABLE IF NOT EXISTS reminders (
      id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL,
      message TEXT NOT NULL,
      trigger INTEGER NOT NULL DEFAULT 0,
      frequency TEXT,
      interval_days INTEGER,
      weekly_days TEXT,
      time_of_day TEXT,
      delay_hours INTEGER,
      target_member_id TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL,
      modified_at INTEGER NOT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0
    )
  ''');

  rawDb.execute('''
    CREATE TABLE IF NOT EXISTS friends (
      id TEXT NOT NULL PRIMARY KEY,
      display_name TEXT NOT NULL,
      peer_sharing_id TEXT,
      pairwise_secret BLOB,
      pinned_identity BLOB,
      offered_scopes TEXT NOT NULL DEFAULT '[]',
      public_key_hex TEXT NOT NULL,
      shared_secret_hex TEXT,
      granted_scopes TEXT NOT NULL DEFAULT '[]',
      is_verified INTEGER NOT NULL DEFAULT 0,
      init_id TEXT,
      created_at INTEGER NOT NULL,
      established_at INTEGER,
      last_sync_at INTEGER,
      is_deleted INTEGER NOT NULL DEFAULT 0
    )
  ''');

  rawDb.execute('''
    CREATE TABLE IF NOT EXISTS sharing_requests (
      init_id TEXT NOT NULL PRIMARY KEY,
      sender_sharing_id TEXT NOT NULL,
      display_name TEXT NOT NULL,
      offered_scopes TEXT NOT NULL DEFAULT '[]',
      sender_identity BLOB,
      pairwise_secret BLOB,
      fingerprint TEXT,
      trust_decision TEXT NOT NULL,
      error_message TEXT,
      is_resolved INTEGER NOT NULL DEFAULT 0,
      received_at INTEGER NOT NULL,
      resolved_at INTEGER
    )
  ''');

  rawDb.execute('''
    CREATE TABLE IF NOT EXISTS media_attachments (
      id TEXT NOT NULL PRIMARY KEY,
      message_id TEXT NOT NULL DEFAULT '',
      media_id TEXT NOT NULL DEFAULT '',
      media_type TEXT NOT NULL DEFAULT '',
      encryption_key_b64 TEXT NOT NULL DEFAULT '',
      content_hash TEXT NOT NULL DEFAULT '',
      plaintext_hash TEXT NOT NULL DEFAULT '',
      mime_type TEXT NOT NULL DEFAULT '',
      size_bytes INTEGER NOT NULL DEFAULT 0,
      width INTEGER NOT NULL DEFAULT 0,
      height INTEGER NOT NULL DEFAULT 0,
      duration_ms INTEGER NOT NULL DEFAULT 0,
      blurhash TEXT NOT NULL DEFAULT '',
      waveform_b64 TEXT NOT NULL DEFAULT '',
      thumbnail_media_id TEXT NOT NULL DEFAULT '',
      source_url TEXT NOT NULL DEFAULT '',
      preview_url TEXT NOT NULL DEFAULT '',
      is_deleted INTEGER NOT NULL DEFAULT 0
    )
  ''');

  rawDb.execute('''
    CREATE TABLE IF NOT EXISTS sp_sync_state (
      id TEXT NOT NULL PRIMARY KEY,
      last_import_at INTEGER,
      sp_system_id TEXT
    )
  ''');

  rawDb.execute('''
    CREATE TABLE IF NOT EXISTS sp_id_map (
      sp_id TEXT NOT NULL,
      entity_type TEXT NOT NULL,
      prism_id TEXT NOT NULL,
      PRIMARY KEY (sp_id, entity_type)
    )
  ''');

  rawDb.execute('''
    CREATE TABLE IF NOT EXISTS pk_mapping_state (
      id TEXT NOT NULL PRIMARY KEY,
      decision_type TEXT NOT NULL,
      pk_member_id TEXT,
      pk_member_uuid TEXT,
      local_member_id TEXT,
      status TEXT NOT NULL DEFAULT 'pending',
      error_message TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');

  // ── V1-era indexes ───────────────────────────────────────────────────────
  // These are the indexes that existed at v1 (from _createCurrentIndexes +
  // _createPkUniqueIndexes at the 6161c4f3 squash commit).
  //
  // Notably ABSENT (added in migrations):
  //   - idx_member_groups_sync_suppressed (v2 column)
  //   - idx_member_groups_suspected_pk_group_uuid (v2 column)
  //   - idx_member_group_entries_pk_group_uuid (v2, created in v1→v2 step)
  //   - idx_member_group_entries_pk_member_uuid (v2, created in v1→v2 step)
  //   - idx_member_group_entries_pk_canonicalize (v4 step)
  //   - idx_pk_group_sync_aliases_pk_group_uuid (v2, table doesn't exist yet)
  //   - idx_pk_group_entry_deferred_ops_entity (v2, table doesn't exist yet)
  //   - idx_fronting_sessions_pluralkit_uuid_member_id (v7)
  //   - idx_fronting_sessions_pluralkit_uuid_orphan (v7)
  //
  // The v1 _createPkUniqueIndexes had idx_member_groups_pluralkit_uuid
  // WITHOUT the `is_deleted = 0` partial filter. v4→v5 drops and recreates
  // it with the filter.

  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_members_active '
    'ON members (is_active, is_deleted)',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_sessions_end '
    'ON fronting_sessions (end_time)',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_sessions_start '
    'ON fronting_sessions (start_time)',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_messages_conv_deleted_ts '
    'ON chat_messages (conversation_id, is_deleted, timestamp DESC)',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_sessions_deleted_start '
    'ON fronting_sessions (is_deleted, start_time DESC)',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_sessions_member_deleted_start '
    'ON fronting_sessions (member_id, session_type, is_deleted, start_time DESC)',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_sessions_type '
    'ON fronting_sessions (session_type, is_deleted, start_time DESC)',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_habit_completions_habit_deleted_at '
    'ON habit_completions (habit_id, is_deleted, completed_at DESC)',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_poll_votes_option_deleted '
    'ON poll_votes (poll_option_id, is_deleted, voted_at DESC)',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_poll_options_poll_deleted_order '
    'ON poll_options (poll_id, is_deleted, sort_order ASC)',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_conversations_deleted_activity '
    'ON conversations (is_deleted, last_activity_at DESC)',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_polls_closed_deleted_created '
    'ON polls (is_closed, is_deleted, created_at DESC)',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_quarantine_entity '
    'ON sync_quarantine (entity_type, entity_id)',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_member_group_entries_group_deleted '
    'ON member_group_entries (group_id, is_deleted)',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_member_group_entries_member_deleted '
    'ON member_group_entries (member_id, is_deleted)',
  );
  rawDb.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_member_group_entries_unique '
    'ON member_group_entries (group_id, member_id) WHERE is_deleted = 0',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_custom_fields_deleted_order '
    'ON custom_fields (is_deleted, display_order ASC)',
  );
  rawDb.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_custom_field_values_field_member '
    'ON custom_field_values (custom_field_id, member_id) '
    'WHERE is_deleted = 0',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_notes_member '
    'ON notes (member_id, is_deleted, date DESC)',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_notes_all '
    'ON notes (is_deleted, date DESC)',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_comments_session '
    'ON front_session_comments (session_id, is_deleted, timestamp ASC)',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_conv_categories_deleted_order '
    'ON conversation_categories (is_deleted, display_order ASC)',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_reminders_active_deleted '
    'ON reminders (is_active, is_deleted)',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_conversations_category '
    'ON conversations (category_id) WHERE category_id IS NOT NULL',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_friends_deleted '
    'ON friends (is_deleted)',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_friends_peer_sharing '
    'ON friends (peer_sharing_id, is_deleted)',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_sharing_requests_resolved_received '
    'ON sharing_requests (is_resolved, received_at DESC)',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_custom_field_values_member '
    'ON custom_field_values (member_id, is_deleted)',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_habit_completions_member '
    'ON habit_completions (completed_by_member_id, is_deleted, completed_at DESC)',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_media_attachments_message_id '
    'ON media_attachments (message_id)',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_sp_id_map_entity_type '
    'ON sp_id_map (entity_type)',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_member_groups_parent_id '
    'ON member_groups (parent_group_id) WHERE parent_group_id IS NOT NULL',
  );

  // PK uniqueness indexes as they existed at v1:
  //   - members pluralkit_uuid / pluralkit_id
  //   - fronting_sessions single-column (optionally omitted for dup scenarios)
  //   - member_groups pluralkit_uuid WITHOUT is_deleted=0 filter (pre-v5)
  //   - member_groups pluralkit_id plain index
  rawDb.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_members_pluralkit_uuid '
    'ON members(pluralkit_uuid) WHERE pluralkit_uuid IS NOT NULL',
  );
  rawDb.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_members_pluralkit_id '
    'ON members(pluralkit_id) WHERE pluralkit_id IS NOT NULL',
  );
  if (includeV1FrontingIndex) {
    rawDb.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_fronting_sessions_pluralkit_uuid '
      'ON fronting_sessions(pluralkit_uuid) WHERE pluralkit_uuid IS NOT NULL',
    );
  }
  rawDb.execute(
    // v1 shape: no `is_deleted = 0` partial filter (added by v4→v5 recreate)
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_member_groups_pluralkit_uuid '
    'ON member_groups(pluralkit_uuid) WHERE pluralkit_uuid IS NOT NULL',
  );
  rawDb.execute(
    'CREATE INDEX IF NOT EXISTS idx_member_groups_pluralkit_id '
    'ON member_groups(pluralkit_id) WHERE pluralkit_id IS NOT NULL',
  );

  // Set user_version = 1 so AppDatabase enters the upgrade path at step 1.
  rawDb.execute('PRAGMA user_version = 1;');
}

void main() {
  group('v1 → v7 step-through migration', () {
    // ── Scenario 1: clean v1 → v7 ────────────────────────────────────────

    test(
      'Scenario 1: clean v1 DB upgrades to v7 with all new columns, '
      "composite+orphan indexes, and mode='notStarted'",
      () async {
        final tempDir =
            Directory.systemTemp.createTempSync('prism_v1_to_v7_clean_');
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });

        final dbFile = File('${tempDir.path}/v1_clean.db');
        final rawDb = raw.sqlite3.open(dbFile.path);
        try {
          _seedV1Schema(rawDb);
          // Seed two clean fronting_sessions rows: non-null + unique
          // pluralkit_uuid and non-null member_id.  These are the happy-path
          // rows that the v1 single-column index would normally protect.
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          rawDb.execute(
            "INSERT INTO fronting_sessions "
            "(id, session_type, start_time, end_time, member_id, "
            " co_fronter_ids, is_health_kit_import, is_deleted, pluralkit_uuid) "
            "VALUES ('s1', 0, $now, NULL, 'member-a', '[]', 0, 0, 'pk-uuid-1')",
          );
          rawDb.execute(
            "INSERT INTO fronting_sessions "
            "(id, session_type, start_time, end_time, member_id, "
            " co_fronter_ids, is_health_kit_import, is_deleted, pluralkit_uuid) "
            "VALUES ('s2', 0, ${now + 1}, NULL, 'member-b', '[]', 0, 0, 'pk-uuid-2')",
          );
        } finally {
          rawDb.close();
        }

        final db = AppDatabase(NativeDatabase(dbFile));
        addTearDown(db.close);

        // Trigger open — runs onUpgrade v1→v2→v3→v4→v5→v6→v7
        await db.customSelect('SELECT 1').get();

        // user_version must be 7
        final uv = await db
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(uv.read<int>('user_version'), 7,
            reason: 'all migration steps must complete');

        // v7-only column: members.is_always_fronting
        final memberCols =
            await db.customSelect('PRAGMA table_info(members)').get();
        expect(
          memberCols.map((r) => r.read<String>('name')).toSet(),
          contains('is_always_fronting'),
          reason: 'members.is_always_fronting must be added by v6→v7',
        );

        // v7-only column: system_settings.pending_fronting_migration_mode
        final settingsCols =
            await db.customSelect('PRAGMA table_info(system_settings)').get();
        expect(
          settingsCols.map((r) => r.read<String>('name')).toSet(),
          contains('pending_fronting_migration_mode'),
          reason:
              'system_settings.pending_fronting_migration_mode must be '
              'added by v6→v7',
        );

        // v7-only columns: front_session_comments.target_time + author_member_id
        final commentCols =
            await db.customSelect('PRAGMA table_info(front_session_comments)').get();
        final commentColNames =
            commentCols.map((r) => r.read<String>('name')).toSet();
        expect(commentColNames, contains('target_time'));
        expect(commentColNames, contains('author_member_id'));

        // mode = 'notStarted' (upgrade path, not fresh install)
        final settings = await db.systemSettingsDao.getSettings();
        expect(
          settings.pendingFrontingMigrationMode,
          'notStarted',
          reason: "upgrade path must set mode to 'notStarted'",
        );

        // Composite + orphan fronting indexes must exist
        final compositeIndex = await db
            .customSelect(
              "SELECT sql FROM sqlite_master "
              "WHERE name = 'idx_fronting_sessions_pluralkit_uuid_member_id'",
            )
            .getSingleOrNull();
        expect(compositeIndex, isNotNull,
            reason: 'composite unique fronting index must exist after v7');
        expect(
          compositeIndex!.read<String>('sql'),
          contains('member_id IS NOT NULL'),
        );

        final orphanIndex = await db
            .customSelect(
              "SELECT sql FROM sqlite_master "
              "WHERE name = 'idx_fronting_sessions_pluralkit_uuid_orphan'",
            )
            .getSingleOrNull();
        expect(orphanIndex, isNotNull,
            reason: 'orphan fronting index must exist after v7');
        expect(
          orphanIndex!.read<String>('sql'),
          contains('member_id IS NULL'),
        );

        // Old single-column fronting index must be gone (dropped by v6→v7)
        final oldFrontingIndex = await db
            .customSelect(
              "SELECT name FROM sqlite_master "
              "WHERE name = 'idx_fronting_sessions_pluralkit_uuid'",
            )
            .get();
        expect(oldFrontingIndex, isEmpty,
            reason:
                'v1 single-column fronting index must be dropped by v6→v7');

        // _v7_migration_blockers side table must exist and be empty
        final blockers = await db
            .customSelect('SELECT * FROM _v7_migration_blockers')
            .get();
        expect(blockers, isEmpty,
            reason: 'no blockers expected for clean v1 data');
      },
    );

    // ── Scenario 2: v1 with duplicate (uuid, member_id) pairs ────────────

    test(
      'Scenario 2: v1 with duplicate (pluralkit_uuid, member_id) pairs: '
      "mode='blocked', blockers logged, composite+orphan indexes absent",
      () async {
        // NOTE: we intentionally omit the v1 single-column unique index for
        // this scenario (includeV1FrontingIndex: false). This simulates a
        // corrupted DB where duplicate (uuid, member_id) pairs exist — e.g.,
        // rows inserted via raw SQL that bypassed the index. The
        // detect-and-refuse in v6→v7 must catch this gracefully.
        final tempDir =
            Directory.systemTemp.createTempSync('prism_v1_to_v7_dup_');
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });

        final dbFile = File('${tempDir.path}/v1_dup.db');
        final rawDb = raw.sqlite3.open(dbFile.path);
        try {
          _seedV1Schema(rawDb, includeV1FrontingIndex: false);
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          // Two rows sharing (pluralkit_uuid='pk-dup', member_id='member-x')
          rawDb.execute(
            "INSERT INTO fronting_sessions "
            "(id, session_type, start_time, end_time, member_id, "
            " co_fronter_ids, is_health_kit_import, is_deleted, pluralkit_uuid) "
            "VALUES ('dup-a', 0, $now, NULL, 'member-x', '[]', 0, 0, 'pk-dup')",
          );
          rawDb.execute(
            "INSERT INTO fronting_sessions "
            "(id, session_type, start_time, end_time, member_id, "
            " co_fronter_ids, is_health_kit_import, is_deleted, pluralkit_uuid) "
            "VALUES ('dup-b', 0, ${now + 1}, NULL, 'member-x', '[]', 0, 0, 'pk-dup')",
          );
        } finally {
          rawDb.close();
        }

        final db = AppDatabase(NativeDatabase(dbFile));
        addTearDown(db.close);

        // Must NOT throw despite duplicate rows
        await db.customSelect('SELECT 1').get();

        // user_version must be 7
        final uv = await db
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(uv.read<int>('user_version'), 7);

        // mode = 'blocked'
        final settings = await db.systemSettingsDao.getSettings();
        expect(
          settings.pendingFrontingMigrationMode,
          'blocked',
          reason: 'duplicate rows must flip mode to blocked',
        );

        // Both duplicate row ids must be logged in _v7_migration_blockers
        final blockers = await db
            .customSelect(
              "SELECT row_id FROM _v7_migration_blockers "
              "WHERE table_name = 'fronting_sessions'",
            )
            .get();
        final blockerIds =
            blockers.map((r) => r.read<String>('row_id')).toSet();
        expect(blockerIds, contains('dup-a'));
        expect(blockerIds, contains('dup-b'));

        // Composite index must NOT exist (skipped due to blocker)
        final compositeIndex = await db
            .customSelect(
              "SELECT name FROM sqlite_master "
              "WHERE name = 'idx_fronting_sessions_pluralkit_uuid_member_id'",
            )
            .get();
        expect(compositeIndex, isEmpty,
            reason: 'composite index must not be created when blockers exist');

        // Orphan index must NOT exist either
        final orphanIndex = await db
            .customSelect(
              "SELECT name FROM sqlite_master "
              "WHERE name = 'idx_fronting_sessions_pluralkit_uuid_orphan'",
            )
            .get();
        expect(orphanIndex, isEmpty,
            reason: 'orphan index must not be created when blockers exist');

        // Rows must NOT have been deleted (detect-and-refuse, not detect-and-fix)
        final remaining = await db
            .customSelect(
              "SELECT id FROM fronting_sessions "
              "WHERE pluralkit_uuid = 'pk-dup' AND member_id = 'member-x'",
            )
            .get();
        expect(remaining, hasLength(2),
            reason: 'detect-and-refuse must not delete any rows');
      },
    );

    // ── Scenario 3: v1 with duplicate (uuid, NULL member_id) orphan rows ──

    test(
      'Scenario 3: v1 with duplicate (pluralkit_uuid, NULL member_id) orphan rows: '
      "mode='blocked', blockers logged, indexes absent",
      () async {
        // Same rationale as Scenario 2: we omit the v1 single-column unique
        // index so we can insert two orphan rows with the same uuid. This
        // simulates corruption where the index was absent or bypassed.
        final tempDir =
            Directory.systemTemp.createTempSync('prism_v1_to_v7_orphan_');
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });

        final dbFile = File('${tempDir.path}/v1_orphan.db');
        final rawDb = raw.sqlite3.open(dbFile.path);
        try {
          _seedV1Schema(rawDb, includeV1FrontingIndex: false);
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          // Two orphan rows: same pluralkit_uuid, both member_id=NULL
          rawDb.execute(
            "INSERT INTO fronting_sessions "
            "(id, session_type, start_time, end_time, member_id, "
            " co_fronter_ids, is_health_kit_import, is_deleted, pluralkit_uuid) "
            "VALUES ('orphan-a', 0, $now, NULL, NULL, '[]', 0, 0, 'pk-orphan')",
          );
          rawDb.execute(
            "INSERT INTO fronting_sessions "
            "(id, session_type, start_time, end_time, member_id, "
            " co_fronter_ids, is_health_kit_import, is_deleted, pluralkit_uuid) "
            "VALUES ('orphan-b', 0, ${now + 1}, NULL, NULL, '[]', 0, 0, 'pk-orphan')",
          );
        } finally {
          rawDb.close();
        }

        final db = AppDatabase(NativeDatabase(dbFile));
        addTearDown(db.close);

        // Must NOT throw
        await db.customSelect('SELECT 1').get();

        // user_version must be 7
        final uv = await db
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(uv.read<int>('user_version'), 7);

        // mode = 'blocked'
        final settings = await db.systemSettingsDao.getSettings();
        expect(
          settings.pendingFrontingMigrationMode,
          'blocked',
          reason: 'orphan duplicate rows must flip mode to blocked',
        );

        // Both orphan row ids must be in _v7_migration_blockers
        final blockers = await db
            .customSelect(
              "SELECT row_id FROM _v7_migration_blockers "
              "WHERE table_name = 'fronting_sessions'",
            )
            .get();
        final blockerIds =
            blockers.map((r) => r.read<String>('row_id')).toSet();
        expect(blockerIds, containsAll(['orphan-a', 'orphan-b']));

        // Neither composite nor orphan index must exist
        final compositeIndex = await db
            .customSelect(
              "SELECT name FROM sqlite_master "
              "WHERE name = 'idx_fronting_sessions_pluralkit_uuid_member_id'",
            )
            .get();
        expect(compositeIndex, isEmpty);

        final orphanIndex = await db
            .customSelect(
              "SELECT name FROM sqlite_master "
              "WHERE name = 'idx_fronting_sessions_pluralkit_uuid_orphan'",
            )
            .get();
        expect(orphanIndex, isEmpty);

        // Rows must be untouched
        final remaining = await db
            .customSelect(
              "SELECT id FROM fronting_sessions "
              "WHERE pluralkit_uuid = 'pk-orphan'",
            )
            .get();
        expect(remaining, hasLength(2),
            reason: 'detect-and-refuse must not delete any rows');
      },
    );
  });
}
