import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/daos/chat_messages_dao.dart';
import 'package:prism_plurality/core/database/daos/conversations_dao.dart';
import 'package:prism_plurality/core/database/daos/fronting_sessions_dao.dart';
import 'package:prism_plurality/core/database/daos/members_dao.dart';
import 'package:prism_plurality/core/database/daos/poll_options_dao.dart';
import 'package:prism_plurality/core/database/daos/poll_votes_dao.dart';
import 'package:prism_plurality/core/database/daos/polls_dao.dart';
import 'package:prism_plurality/core/database/daos/pluralkit_sync_dao.dart';
import 'package:prism_plurality/core/database/daos/sync_quarantine_dao.dart';
import 'package:prism_plurality/core/database/daos/system_settings_dao.dart';
import 'package:prism_plurality/core/database/daos/habits_dao.dart';
import 'package:prism_plurality/core/database/daos/member_groups_dao.dart';
import 'package:prism_plurality/core/database/daos/custom_fields_dao.dart';
import 'package:prism_plurality/core/database/daos/notes_dao.dart';
import 'package:prism_plurality/core/database/daos/front_session_comments_dao.dart';
import 'package:prism_plurality/core/database/daos/conversation_categories_dao.dart';
import 'package:prism_plurality/core/database/daos/reminders_dao.dart';
import 'package:prism_plurality/core/database/daos/friends_dao.dart';
import 'package:prism_plurality/core/database/daos/sharing_requests_dao.dart';
import 'package:prism_plurality/core/database/daos/media_attachments_dao.dart';
import 'package:prism_plurality/core/database/daos/sp_import_dao.dart';
import 'package:prism_plurality/core/database/daos/pk_mapping_state_dao.dart';
import 'package:prism_plurality/core/database/tables/tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Members,
    FrontingSessions,
    Conversations,
    ChatMessages,
    SystemSettingsTable,
    Polls,
    PollOptions,
    PollVotes,
    SleepSessions,
    PluralKitSyncState,
    Habits,
    HabitCompletions,
    SyncQuarantineTable,
    MemberGroups,
    MemberGroupEntries,
    CustomFields,
    CustomFieldValues,
    Notes,
    FrontSessionComments,
    ConversationCategories,
    Reminders,
    Friends,
    SharingRequests,
    MediaAttachments,
    SpSyncStateTable,
    SpIdMapTable,
    PkMappingState,
  ],
  daos: [
    MembersDao,
    FrontingSessionsDao,
    ConversationsDao,
    ChatMessagesDao,
    SystemSettingsDao,
    PollsDao,
    PollOptionsDao,
    PollVotesDao,
    PluralKitSyncDao,
    HabitsDao,
    SyncQuarantineDao,
    MemberGroupsDao,
    CustomFieldsDao,
    NotesDao,
    FrontSessionCommentsDao,
    ConversationCategoriesDao,
    RemindersDao,
    FriendsDao,
    SharingRequestsDao,
    MediaAttachmentsDao,
    SpImportDao,
    PkMappingStateDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 55;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      // Migrations v1-v29 were consolidated into the initial schema to keep
      // this file maintainable. Devices with schema <30 must export data,
      // do a fresh install, and re-import.
      if (from < 30) {
        throw UnsupportedError(
          'Upgrade paths before schema v30 have been squashed. '
          'Use export/import into a fresh install for older databases.',
        );
      }

      if (from < 31) {
        await customStatement('DROP INDEX IF EXISTS idx_sleep_end');
        await _createCurrentIndexes();
        await _createChatMessagesFtsArtifacts();
      }

      if (from < 32) {
        await customStatement(
          'ALTER TABLE system_settings ADD COLUMN display_font_in_app_bar INTEGER NOT NULL DEFAULT 1',
        );
      }

      if (from < 33) {
        await _createCurrentIndexes();
      }

      if (from < 34) {
        await customStatement(
          'ALTER TABLE system_settings ADD COLUMN sharing_id TEXT',
        );
        await customStatement(
          'ALTER TABLE friends ADD COLUMN peer_sharing_id TEXT',
        );
        await customStatement(
          'ALTER TABLE friends ADD COLUMN pairwise_secret BLOB',
        );
        await customStatement(
          'ALTER TABLE friends ADD COLUMN pinned_identity BLOB',
        );
        await customStatement(
          "ALTER TABLE friends ADD COLUMN offered_scopes TEXT NOT NULL DEFAULT '[]'",
        );
        await customStatement('ALTER TABLE friends ADD COLUMN init_id TEXT');
        await customStatement(
          'ALTER TABLE friends ADD COLUMN established_at INTEGER',
        );
        await customStatement(
          'UPDATE friends SET established_at = created_at WHERE established_at IS NULL',
        );
        await migrator.createTable(sharingRequests);
        await _createCurrentIndexes();
      }

      if (from < 35) {
        await customStatement(
          'ALTER TABLE system_settings ADD COLUMN identity_generation INTEGER NOT NULL DEFAULT 0',
        );
      }

      if (from < 36) {
        await migrator.createTable(mediaAttachments);
      }

      if (from < 37) {
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_media_attachments_message_id '
          'ON media_attachments (message_id)',
        );
      }

      if (from < 38) {
        await customStatement(
          'ALTER TABLE system_settings ADD COLUMN gif_search_enabled INTEGER NOT NULL DEFAULT 1',
        );
      }

      if (from < 39) {
        await customStatement(
          'ALTER TABLE system_settings ADD COLUMN terminology_use_english INTEGER NOT NULL DEFAULT 0',
        );
      }

      if (from < 40) {
        await customStatement(
          'ALTER TABLE system_settings ADD COLUMN voice_notes_enabled INTEGER NOT NULL DEFAULT 1',
        );
      }

      if (from < 41) {
        await customStatement(
          'ALTER TABLE system_settings ADD COLUMN locale_override TEXT',
        );
      }

      if (from < 42) {
        await customStatement(
          'ALTER TABLE system_settings ADD COLUMN gif_consent_state INTEGER NOT NULL DEFAULT 0',
        );
      }

      if (from < 43) {
        await customStatement(
            'ALTER TABLE system_settings ADD COLUMN sleep_suggestion_enabled INTEGER NOT NULL DEFAULT 0');
        await customStatement(
            'ALTER TABLE system_settings ADD COLUMN sleep_suggestion_hour INTEGER NOT NULL DEFAULT 22');
        await customStatement(
            'ALTER TABLE system_settings ADD COLUMN sleep_suggestion_minute INTEGER NOT NULL DEFAULT 0');
        await customStatement(
            'ALTER TABLE system_settings ADD COLUMN wake_suggestion_enabled INTEGER NOT NULL DEFAULT 0');
        await customStatement(
            'ALTER TABLE system_settings ADD COLUMN wake_suggestion_after_hours REAL NOT NULL DEFAULT 8.0');
      }

      if (from < 44) {
        // Guard: reminders table may not exist in very old test databases
        // that were created before the reminders table was introduced.
        final tableExists = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name='reminders'",
        ).get();
        if (tableExists.isNotEmpty) {
          await customStatement(
              'ALTER TABLE reminders ADD COLUMN frequency TEXT');
          await customStatement(
              'ALTER TABLE reminders ADD COLUMN weekly_days TEXT');
        }
      }

      if (from < 45) {
        final memberGroupsExists = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name='member_groups'",
        ).get();
        if (memberGroupsExists.isNotEmpty) {
          await customStatement(
            'ALTER TABLE member_groups ADD COLUMN group_type INTEGER NOT NULL DEFAULT 0');
          await customStatement(
            'ALTER TABLE member_groups ADD COLUMN filter_rules TEXT');
        }
      }

      if (from < 46) {
        final entriesExists = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name='member_group_entries'",
        ).get();
        if (entriesExists.isNotEmpty) {
          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_member_group_entries_unique '
            'ON member_group_entries (group_id, member_id) WHERE is_deleted = 0',
          );
        }
      }

      if (from < 47) {
        await customStatement('''
          CREATE TABLE IF NOT EXISTS sp_sync_state (
            id TEXT NOT NULL PRIMARY KEY,
            last_import_at INTEGER,
            sp_system_id TEXT
          )
        ''');
        await customStatement('''
          CREATE TABLE IF NOT EXISTS sp_id_map (
            sp_id TEXT NOT NULL,
            entity_type TEXT NOT NULL,
            prism_id TEXT NOT NULL,
            PRIMARY KEY (sp_id, entity_type)
          )
        ''');
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sp_id_map_entity_type '
          'ON sp_id_map (entity_type)',
        );
      }

      if (from < 48) {
        // New PK-sync columns on existing tables. All nullable / default
        // false so existing rows remain valid without a data migration.
        // Guard each ALTER by table existence — older baseline test stubs
        // don't include every table.
        final membersExists = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name='members'",
        ).get();
        if (membersExists.isNotEmpty) {
          await customStatement(
            'ALTER TABLE members ADD COLUMN display_name TEXT',
          );
          await customStatement(
            'ALTER TABLE members ADD COLUMN birthday TEXT',
          );
          await customStatement(
            'ALTER TABLE members ADD COLUMN proxy_tags_json TEXT',
          );
          await customStatement(
            'ALTER TABLE members ADD COLUMN pluralkit_sync_ignored '
            'INTEGER NOT NULL DEFAULT 0',
          );
        }
        final sessionsExists = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' "
          "AND name='fronting_sessions'",
        ).get();
        if (sessionsExists.isNotEmpty) {
          await customStatement(
            'ALTER TABLE fronting_sessions ADD COLUMN pk_member_ids_json TEXT',
          );
        }

        // Resumable mapping-applier state table (see pk_mapping_state_table.dart).
        // Use Drift's generated DDL so the upgrade matches onCreate exactly and
        // tracks any future schema changes to the PkMappingState table.
        final pkMappingStateExists = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' "
          "AND name='pk_mapping_state'",
        ).get();
        if (pkMappingStateExists.isEmpty) {
          await migrator.createTable(pkMappingState);
        }

        // Partial unique indexes — enforce "at most one local row per PK
        // identifier" without blocking rows that have no PK linkage.
        if (membersExists.isNotEmpty) {
          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_members_pluralkit_uuid '
            'ON members(pluralkit_uuid) WHERE pluralkit_uuid IS NOT NULL',
          );
          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_members_pluralkit_id '
            'ON members(pluralkit_id) WHERE pluralkit_id IS NOT NULL',
          );
        }
        if (sessionsExists.isNotEmpty) {
          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS '
            'idx_fronting_sessions_pluralkit_uuid '
            'ON fronting_sessions(pluralkit_uuid) '
            'WHERE pluralkit_uuid IS NOT NULL',
          );
        }
      }

      if (from < 49) {
        // Plan 08 Phase 1: connected_pending_map gate. Existing rows keep
        // `mapping_acknowledged = 0` so anyone already connected is routed
        // through the new mapping flow once, instead of silently skipping it.
        final pkExists = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' "
          "AND name='plural_kit_sync_state'",
        ).get();
        if (pkExists.isNotEmpty) {
          await customStatement(
            'ALTER TABLE plural_kit_sync_state ADD COLUMN '
            'mapping_acknowledged INTEGER NOT NULL DEFAULT 0',
          );
        }
      }

      if (from < 50) {
        // Plan 08 Phase 4: `linked_at` timestamp for scoped switch push.
        // Nullable — already-connected users who don't have one will only
        // start pushing switches created after they re-acknowledge the
        // mapping screen (which will backfill linkedAt).
        final pkExists = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' "
          "AND name='plural_kit_sync_state'",
        ).get();
        if (pkExists.isNotEmpty) {
          await customStatement(
            'ALTER TABLE plural_kit_sync_state ADD COLUMN linked_at INTEGER',
          );
        }
      }

      if (from < 51) {
        // Plan 03 Phase 1: PK-group link columns + partial unique indexes.
        // Also `last_seen_from_pk_at` for the "stale" UI hint (R9).
        final groupsExists = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' "
          "AND name='member_groups'",
        ).get();
        if (groupsExists.isNotEmpty) {
          await customStatement(
            'ALTER TABLE member_groups ADD COLUMN pluralkit_id TEXT',
          );
          await customStatement(
            'ALTER TABLE member_groups ADD COLUMN pluralkit_uuid TEXT',
          );
          await customStatement(
            'ALTER TABLE member_groups ADD COLUMN last_seen_from_pk_at '
            'INTEGER',
          );
          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS '
            'idx_member_groups_pluralkit_uuid '
            'ON member_groups(pluralkit_uuid) '
            'WHERE pluralkit_uuid IS NOT NULL',
          );
          // NOT unique (see plan R7): PK short IDs can be recycled across
          // groups, so identity is UUID-only. Plain index for lookup speed.
          await customStatement(
            'CREATE INDEX IF NOT EXISTS '
            'idx_member_groups_pluralkit_id '
            'ON member_groups(pluralkit_id) '
            'WHERE pluralkit_id IS NOT NULL',
          );
        }
      }

      if (from < 52) {
        // Plan 02 (PK deletion push): link_epoch on sync state, plus
        // delete_intent_epoch (local) + delete_push_started_at (synced) on
        // members and fronting_sessions. All nullable / defaulted so the
        // ALTERs leave existing rows valid without a data migration.
        final pkStateExists = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' "
          "AND name='plural_kit_sync_state'",
        ).get();
        if (pkStateExists.isNotEmpty) {
          await customStatement(
            'ALTER TABLE plural_kit_sync_state ADD COLUMN '
            'link_epoch INTEGER NOT NULL DEFAULT 0',
          );
        }
        final membersExists = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name='members'",
        ).get();
        if (membersExists.isNotEmpty) {
          await customStatement(
            'ALTER TABLE members ADD COLUMN delete_intent_epoch INTEGER',
          );
          await customStatement(
            'ALTER TABLE members ADD COLUMN delete_push_started_at INTEGER',
          );
        }
        final sessionsExists = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' "
          "AND name='fronting_sessions'",
        ).get();
        if (sessionsExists.isNotEmpty) {
          await customStatement(
            'ALTER TABLE fronting_sessions ADD COLUMN '
            'delete_intent_epoch INTEGER',
          );
          await customStatement(
            'ALTER TABLE fronting_sessions ADD COLUMN '
            'delete_push_started_at INTEGER',
          );
        }
      }

      if (from < 53) {
        // Plan 04: PluralKit system profile disclosure — adds synced
        // `system_tag` column to mirror the PK system `tag` field.
        // Guard by table existence for old test stubs that upgrade from
        // a fixture pre-dating the system_settings table.
        final systemSettingsExists = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' "
          "AND name='system_settings'",
        ).get();
        if (systemSettingsExists.isNotEmpty) {
          await customStatement(
            'ALTER TABLE system_settings ADD COLUMN system_tag TEXT',
          );
        }
      }

      if (from < 54) {
        // Plan 06: SP timer targeting — per-member reminders.
        // Adds `target_member_id` to reminders. Nullable: null keeps the
        // existing "fires on any front change" behavior, a non-null value
        // narrows firing to switches where that member is in the current
        // fronter set. Guard by table existence for old test stubs.
        final remindersExists = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name='reminders'",
        ).get();
        if (remindersExists.isNotEmpty) {
          await customStatement(
            'ALTER TABLE reminders ADD COLUMN target_member_id TEXT',
          );
        }
      }

      if (from < 55) {
        // System Info redesign: nullable hex color for the system.
        // Imported from Simply Plural's system color field; also exposed
        // by the upcoming System Info page color picker.
        final systemSettingsExists = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' "
          "AND name='system_settings'",
        ).get();
        if (systemSettingsExists.isNotEmpty) {
          await customStatement(
            'ALTER TABLE system_settings ADD COLUMN system_color TEXT',
          );
        }
      }
    },
    onCreate: (migrator) async {
      await migrator.createAll();
      await _createCurrentIndexes();
      await _createPkUniqueIndexes();
      await _createChatMessagesFtsArtifacts();
    },
  );

  Future<void> _createPkUniqueIndexes() async {
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_members_pluralkit_uuid '
      'ON members(pluralkit_uuid) WHERE pluralkit_uuid IS NOT NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_members_pluralkit_id '
      'ON members(pluralkit_id) WHERE pluralkit_id IS NOT NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_fronting_sessions_pluralkit_uuid '
      'ON fronting_sessions(pluralkit_uuid) WHERE pluralkit_uuid IS NOT NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_member_groups_pluralkit_uuid '
      'ON member_groups(pluralkit_uuid) WHERE pluralkit_uuid IS NOT NULL',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_member_groups_pluralkit_id '
      'ON member_groups(pluralkit_id) WHERE pluralkit_id IS NOT NULL',
    );
  }

  Future<void> _createCurrentIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_members_active '
      'ON members (is_active, is_deleted)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sessions_end '
      'ON fronting_sessions (end_time)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sessions_start '
      'ON fronting_sessions (start_time)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_messages_conv_deleted_ts '
      'ON chat_messages (conversation_id, is_deleted, timestamp DESC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sessions_deleted_start '
      'ON fronting_sessions (is_deleted, start_time DESC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sessions_member_deleted_start '
      'ON fronting_sessions (member_id, session_type, is_deleted, start_time DESC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sessions_type '
      'ON fronting_sessions (session_type, is_deleted, start_time DESC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_habit_completions_habit_deleted_at '
      'ON habit_completions (habit_id, is_deleted, completed_at DESC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_poll_votes_option_deleted '
      'ON poll_votes (poll_option_id, is_deleted, voted_at DESC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_poll_options_poll_deleted_order '
      'ON poll_options (poll_id, is_deleted, sort_order ASC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_conversations_deleted_activity '
      'ON conversations (is_deleted, last_activity_at DESC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_polls_closed_deleted_created '
      'ON polls (is_closed, is_deleted, created_at DESC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_quarantine_entity '
      'ON sync_quarantine (entity_type, entity_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_member_group_entries_group_deleted '
      'ON member_group_entries (group_id, is_deleted)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_member_group_entries_member_deleted '
      'ON member_group_entries (member_id, is_deleted)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_member_group_entries_unique '
      'ON member_group_entries (group_id, member_id) WHERE is_deleted = 0',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_custom_fields_deleted_order '
      'ON custom_fields (is_deleted, display_order ASC)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_custom_field_values_field_member '
      'ON custom_field_values (custom_field_id, member_id) '
      'WHERE is_deleted = 0',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_notes_member '
      'ON notes (member_id, is_deleted, date DESC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_notes_all '
      'ON notes (is_deleted, date DESC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_comments_session '
      'ON front_session_comments (session_id, is_deleted, timestamp ASC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_conv_categories_deleted_order '
      'ON conversation_categories (is_deleted, display_order ASC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_reminders_active_deleted '
      'ON reminders (is_active, is_deleted)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_conversations_category '
      'ON conversations (category_id) WHERE category_id IS NOT NULL',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_friends_deleted '
      'ON friends (is_deleted)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_friends_peer_sharing '
      'ON friends (peer_sharing_id, is_deleted)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sharing_requests_resolved_received '
      'ON sharing_requests (is_resolved, received_at DESC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_custom_field_values_member '
      'ON custom_field_values (member_id, is_deleted)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_habit_completions_member '
      'ON habit_completions (completed_by_member_id, is_deleted, completed_at DESC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_media_attachments_message_id '
      'ON media_attachments (message_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sp_id_map_entity_type '
      'ON sp_id_map (entity_type)',
    );
  }

  Future<void> _createChatMessagesFtsArtifacts() async {
    await customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS chat_messages_fts USING fts5(
        content,
        message_id UNINDEXED,
        conversation_id UNINDEXED,
        tokenize='unicode61 remove_diacritics 2'
      )
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS chat_messages_fts_insert
      AFTER INSERT ON chat_messages
      WHEN NEW.is_deleted = 0 AND NEW.is_system_message = 0 AND NEW.content != ''
      BEGIN
        INSERT INTO chat_messages_fts(content, message_id, conversation_id)
        VALUES (NEW.content, NEW.id, NEW.conversation_id);
      END
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS chat_messages_fts_update
      AFTER UPDATE ON chat_messages
      WHEN OLD.content != NEW.content OR OLD.is_deleted != NEW.is_deleted
      BEGIN
        DELETE FROM chat_messages_fts WHERE message_id = OLD.id;
        INSERT INTO chat_messages_fts(content, message_id, conversation_id)
        SELECT NEW.content, NEW.id, NEW.conversation_id
        WHERE NEW.is_deleted = 0 AND NEW.is_system_message = 0 AND NEW.content != '';
      END
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS chat_messages_fts_delete
      AFTER DELETE ON chat_messages
      BEGIN
        DELETE FROM chat_messages_fts WHERE message_id = OLD.id;
      END
    ''');
  }

  // DAO accessors
  @override
  MembersDao get membersDao => MembersDao(this);
  @override
  FrontingSessionsDao get frontingSessionsDao => FrontingSessionsDao(this);
  @override
  ConversationsDao get conversationsDao => ConversationsDao(this);
  @override
  ChatMessagesDao get chatMessagesDao => ChatMessagesDao(this);
  @override
  SystemSettingsDao get systemSettingsDao => SystemSettingsDao(this);
  @override
  PollsDao get pollsDao => PollsDao(this);
  @override
  PollOptionsDao get pollOptionsDao => PollOptionsDao(this);
  @override
  PollVotesDao get pollVotesDao => PollVotesDao(this);
  @override
  PluralKitSyncDao get pluralKitSyncDao => PluralKitSyncDao(this);
  @override
  HabitsDao get habitsDao => HabitsDao(this);
  @override
  SyncQuarantineDao get syncQuarantineDao => SyncQuarantineDao(this);
  @override
  MemberGroupsDao get memberGroupsDao => MemberGroupsDao(this);
  @override
  CustomFieldsDao get customFieldsDao => CustomFieldsDao(this);
  @override
  NotesDao get notesDao => NotesDao(this);
  @override
  FrontSessionCommentsDao get frontSessionCommentsDao =>
      FrontSessionCommentsDao(this);
  @override
  ConversationCategoriesDao get conversationCategoriesDao =>
      ConversationCategoriesDao(this);
  @override
  RemindersDao get remindersDao => RemindersDao(this);
  @override
  SpImportDao get spImportDao => SpImportDao(this);
  @override
  PkMappingStateDao get pkMappingStateDao => PkMappingStateDao(this);
}
