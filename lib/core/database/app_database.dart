import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/daos/chat_messages_dao.dart';
import 'package:prism_plurality/core/database/daos/conversations_dao.dart';
import 'package:prism_plurality/core/database/daos/fronting_sessions_dao.dart';
import 'package:prism_plurality/core/database/daos/members_dao.dart';
import 'package:prism_plurality/core/database/daos/poll_options_dao.dart';
import 'package:prism_plurality/core/database/daos/poll_votes_dao.dart';
import 'package:prism_plurality/core/database/daos/polls_dao.dart';
import 'package:prism_plurality/core/database/daos/pluralkit_sync_dao.dart';
import 'package:prism_plurality/core/database/daos/sleep_sessions_dao.dart';
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
    SleepSessionsDao,
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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 29;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      if (from < 3) {
        // Add columns introduced since v2
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.customPluralTerminology,
        );
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.themeMode,
        );
      }
      if (from < 4) {
        // PluralKit integration columns
        await migrator.addColumn(members, members.pluralkitUuid);
        await migrator.addColumn(members, members.pluralkitId);
        await migrator.addColumn(
          frontingSessions,
          frontingSessions.pluralkitUuid,
        );
        await migrator.createTable(pluralKitSyncState);
      }
      if (from < 5) {
        // Habit tracking tables
        await migrator.createTable(habits);
        await migrator.createTable(habitCompletions);
      }
      if (from < 6) {
        // Feature toggle + onboarding columns
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.chatEnabled,
        );
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.pollsEnabled,
        );
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.habitsEnabled,
        );
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.sleepTrackingEnabled,
        );
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.hasCompletedOnboarding,
        );
      }
      if (from < 7) {
        // Two-axis theme: brightness + style
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.themeBrightness,
        );
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.themeStyle,
        );
      }
      if (from < 8) {
        // Create sleep_sessions for databases that predate it
        await migrator.createTable(sleepSessions);
        // Performance indexes for frequently-filtered queries
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_members_active ON members (is_active, is_deleted)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sessions_end ON fronting_sessions (end_time)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sessions_start ON fronting_sessions (start_time)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_messages_conv ON chat_messages (conversation_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sleep_end ON sleep_sessions (end_time)',
        );
      }
      if (from < 9) {
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.quickSwitchThresholdSeconds,
        );
      }
      if (from < 10) {
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.syncThemeEnabled,
        );
      }
      if (from < 11) {
        // Previously created sync tables — now managed by Rust; skipped in v16
      }
      if (from < 12) {
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.chatLogsFront,
        );
      }
      if (from < 13) {
        // Previously created pending_ops indexes — dropped in v16
      }
      if (from < 14) {
        await migrator.addColumn(systemSettingsTable, systemSettingsTable.timingMode);
      }
      if (from < 15) {
        await migrator.addColumn(conversations, conversations.archivedByMemberIds);
      }
      if (from < 16) {
        // Rename tables (Drift renameTable: new table def, old SQLite name)
        await migrator.renameTable(sleepSessions, 'sleep_sessions_table');
        await migrator.renameTable(habits, 'habits_table');
        await migrator.renameTable(habitCompletions, 'habit_completions_table');

        // Drop sync tables (Rust manages its own SQLite now)
        await customStatement('DROP TABLE IF EXISTS sync_metadata');
        await customStatement('DROP TABLE IF EXISTS pending_ops');
        await customStatement('DROP TABLE IF EXISTS applied_ops');
        await customStatement('DROP TABLE IF EXISTS field_versions');
        await customStatement('DROP TABLE IF EXISTS crdt_changes');

        // Drop sync indexes
        await customStatement('DROP INDEX IF EXISTS idx_pending_ops_sync_pushed_created');
        await customStatement('DROP INDEX IF EXISTS idx_pending_ops_batch_created');

        // Add mutedByMemberIds before alterTable so the column exists for the copy
        await migrator.addColumn(conversations, conversations.mutedByMemberIds);

        // Remove hlc and isDirty columns from entity tables via TableMigration
        await migrator.alterTable(TableMigration(members));
        await migrator.alterTable(TableMigration(frontingSessions));
        await migrator.alterTable(TableMigration(conversations));
        await migrator.alterTable(TableMigration(chatMessages));
        await migrator.alterTable(TableMigration(polls));
        await migrator.alterTable(TableMigration(pollOptions));
        await migrator.alterTable(TableMigration(pollVotes));
        await migrator.alterTable(TableMigration(systemSettingsTable));
        await migrator.alterTable(TableMigration(sleepSessions));
        await migrator.alterTable(TableMigration(habits));
        await migrator.alterTable(TableMigration(habitCompletions));
      }
      if (from < 17) {
        // Composite indexes for common multi-column query patterns

        // chat_messages: every query filters (conversation_id, is_deleted)
        // and orders by timestamp DESC — replaces single-column idx_messages_conv
        await customStatement(
          'DROP INDEX IF EXISTS idx_messages_conv',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_messages_conv_deleted_ts '
          'ON chat_messages (conversation_id, is_deleted, timestamp DESC)',
        );

        // fronting_sessions: queries filter is_deleted + order by start_time;
        // active sessions also filter end_time IS NULL
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sessions_deleted_start '
          'ON fronting_sessions (is_deleted, start_time DESC)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sessions_member_deleted_start '
          'ON fronting_sessions (member_id, is_deleted, start_time DESC)',
        );

        // habit_completions: queried per habit ordered by completed_at
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_habit_completions_habit_deleted_at '
          'ON habit_completions (habit_id, is_deleted, completed_at DESC)',
        );

        // poll_votes: queried per option, filtered by is_deleted
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_poll_votes_option_deleted '
          'ON poll_votes (poll_option_id, is_deleted, voted_at DESC)',
        );

        // poll_options: queried per poll, filtered by is_deleted, ordered by sort_order
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_poll_options_poll_deleted_order '
          'ON poll_options (poll_id, is_deleted, sort_order ASC)',
        );

        // conversations: filtered by is_deleted, ordered by last_activity_at
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_conversations_deleted_activity '
          'ON conversations (is_deleted, last_activity_at DESC)',
        );

        // polls: filtered by is_closed + is_deleted, ordered by created_at
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_polls_closed_deleted_created '
          'ON polls (is_closed, is_deleted, created_at DESC)',
        );
      }
      if (from < 18) {
        // Create sync_quarantine table for quarantining invalid remote changes
        await customStatement('''
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
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_quarantine_entity '
          'ON sync_quarantine (entity_type, entity_id)',
        );
        // Add previousAccentColorHex to system_settings
        await customStatement(
          "ALTER TABLE system_settings ADD COLUMN previous_accent_color_hex TEXT NOT NULL DEFAULT ''",
        );
      }
      if (from < 19) {
        await migrator.addColumn(chatMessages, chatMessages.replyToId);
        await migrator.addColumn(chatMessages, chatMessages.replyToAuthorId);
        await migrator.addColumn(chatMessages, chatMessages.replyToContent);
      }
      if (from < 20) {
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.habitsBadgeEnabled,
        );
      }
      if (from < 21) {
        // FTS5 full-text search index for chat messages
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
        // Backfill existing messages
        await customStatement('''
          INSERT INTO chat_messages_fts(content, message_id, conversation_id)
          SELECT content, id, conversation_id FROM chat_messages
          WHERE is_deleted = 0 AND is_system_message = 0 AND content != ''
        ''');
      }
      if (from < 22) {
        // Member groups
        await migrator.createTable(memberGroups);
        await migrator.createTable(memberGroupEntries);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_member_group_entries_group_deleted '
          'ON member_group_entries (group_id, is_deleted)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_member_group_entries_member_deleted '
          'ON member_group_entries (member_id, is_deleted)',
        );
        // Custom fields
        await migrator.createTable(customFields);
        await migrator.createTable(customFieldValues);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_custom_fields_deleted_order '
          'ON custom_fields (is_deleted, display_order ASC)',
        );
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_custom_field_values_field_member '
          'ON custom_field_values (custom_field_id, member_id) '
          'WHERE is_deleted = 0',
        );
      }
      if (from < 23) {
        // Notes
        await migrator.createTable(notes);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_notes_member '
          'ON notes (member_id, is_deleted, date DESC)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_notes_all '
          'ON notes (is_deleted, date DESC)',
        );
        // Front session comments
        await migrator.createTable(frontSessionComments);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_comments_session '
          'ON front_session_comments (session_id, is_deleted, timestamp ASC)',
        );
        // Notes feature toggle
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.notesEnabled,
        );
      }
      if (from < 24) {
        // Phase 3: New tables
        await migrator.createTable(conversationCategories);
        await migrator.createTable(reminders);
        // Phase 3: New columns on existing tables
        await migrator.addColumn(polls, polls.description);
        await migrator.addColumn(pollOptions, pollOptions.colorHex);
        await migrator.addColumn(conversations, conversations.description);
        await migrator.addColumn(conversations, conversations.categoryId);
        await migrator.addColumn(conversations, conversations.displayOrder);
        await migrator.addColumn(members, members.markdownEnabled);
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.systemDescription,
        );
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.systemAvatarData,
        );
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.remindersEnabled,
        );
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.fontScale,
        );
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.fontFamily,
        );
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.pinLockEnabled,
        );
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.biometricLockEnabled,
        );
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.autoLockDelaySeconds,
        );
        await migrator.addColumn(
          pluralKitSyncState,
          pluralKitSyncState.fieldSyncConfig,
        );
        // Phase 3: Indexes
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
      }
      if (from < 25) {
        // Friends table for sharing feature
        await migrator.createTable(friends);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_friends_deleted '
          'ON friends (is_deleted)',
        );
      }
      if (from < 26) {
        // Nav bar customization column (device-local)
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.navBarItems,
        );
      }
      if (from < 27) {
        // Nav bar overflow menu column (device-local)
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.navBarOverflowItems,
        );
      }
      if (from < 28) {
        // Sync navigation toggle (default true)
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.syncNavigationEnabled,
        );
      }
      if (from < 29) {
        // Chat badge preferences (JSON map of memberId → badge mode)
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.chatBadgePreferences,
        );
      }
    },
    onCreate: (migrator) async {
      await migrator.createAll();
      // FTS5 full-text search index for chat messages (fresh install)
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
    },
  );

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
  SleepSessionsDao get sleepSessionsDao => SleepSessionsDao(this);
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
}
