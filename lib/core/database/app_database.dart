import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/daos/chat_messages_dao.dart';
import 'package:prism_plurality/core/database/daos/conversations_dao.dart';
import 'package:prism_plurality/core/database/daos/fronting_sessions_dao.dart';
import 'package:prism_plurality/core/database/daos/members_dao.dart';
import 'package:prism_plurality/core/database/daos/pk_group_entry_deferred_sync_ops_dao.dart';
import 'package:prism_plurality/core/database/daos/pk_group_sync_aliases_dao.dart';
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
    PkGroupSyncAliases,
    PkGroupEntryDeferredSyncOps,
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
    PkGroupSyncAliasesDao,
    PkGroupEntryDeferredSyncOpsDao,
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
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      var current = from;
      if (current == 1 && to >= 2) {
        await migrator.addColumn(
          memberGroupEntries,
          memberGroupEntries.pkGroupUuid,
        );
        await migrator.addColumn(
          memberGroupEntries,
          memberGroupEntries.pkMemberUuid,
        );
        await migrator.addColumn(memberGroups, memberGroups.syncSuppressed);
        await migrator.addColumn(
          memberGroups,
          memberGroups.suspectedPkGroupUuid,
        );
        await migrator.createTable(pkGroupSyncAliases);
        await migrator.createTable(pkGroupEntryDeferredSyncOps);
        await _createCurrentIndexes();
        await _createPkUniqueIndexes();
        await _createPkGroupSyncIndexes();
        await _createChatMessagesFtsArtifacts();
        current = 2;
      }
      if (current == 2 && to >= 3) {
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.pkGroupSyncV2Enabled,
        );
        current = 3;
      }
      if (current == 3 && to >= 4) {
        // H3: three raw-SQL sites wrote ms-since-epoch into DateTimeColumn
        // fields that Drift decodes as seconds. Any value > 1e11 (year
        // 5138 AD in seconds) is almost certainly an ms value that should
        // be seconds. Divide in place so existing rows decode to the
        // right wall clock.
        await customStatement(
          'UPDATE pk_group_entry_deferred_sync_ops '
          'SET created_at = created_at / 1000 '
          'WHERE created_at > 100000000000',
        );
        await customStatement(
          'UPDATE pk_group_entry_deferred_sync_ops '
          'SET last_retry_at = last_retry_at / 1000 '
          'WHERE last_retry_at IS NOT NULL AND last_retry_at > 100000000000',
        );
        await customStatement(
          'UPDATE pk_group_sync_aliases '
          'SET created_at = created_at / 1000 '
          'WHERE created_at > 100000000000',
        );
        // C1: drop pk_group_sync_aliases rows whose legacy_entity_id
        // matches an active member_groups.id for the same pk_group_uuid.
        // Those are auto-aliases for the device's OWN row id; emitting
        // tombstones for them would hard-delete peers' active PK-group
        // rows whenever two devices both imported PK groups under the
        // importer's `pk-group-<uuid>` hyphen-form local id.
        await customStatement(
          'DELETE FROM pk_group_sync_aliases '
          'WHERE legacy_entity_id IN ('
          '  SELECT id FROM member_groups '
          '  WHERE pluralkit_uuid = pk_group_sync_aliases.pk_group_uuid '
          '    AND is_deleted = 0'
          ')',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_member_group_entries_pk_canonicalize '
          'ON member_group_entries (pk_group_uuid, pk_member_uuid) '
          'WHERE is_deleted = 0 AND pk_group_uuid IS NOT NULL '
          'AND pk_member_uuid IS NOT NULL',
        );
        current = 4;
      }
      if (current == 4 && to >= 5) {
        await _recreateMemberGroupPkUniqueIndex();
        current = 5;
      }
      if (current != to) {
        throw UnsupportedError(
          'Schema baseline was reset to v1 for the private beta. '
          'Databases from earlier builds (schema v$from) cannot be upgraded. '
          'Use the in-app export, reinstall, then import to migrate data.',
        );
      }
    },
    onCreate: (migrator) async {
      await migrator.createAll();
      await _createCurrentIndexes();
      await _createPkUniqueIndexes();
      await _createPkGroupSyncIndexes();
      await _createChatMessagesFtsArtifacts();
    },
    beforeOpen: (details) async {
      // Downgrade guard. SQLite itself will happily open a file whose
      // user_version is newer than the running app's schemaVersion —
      // queries then fail at runtime with confusing "no such column"
      // errors because the DAOs expect columns the older build never
      // learned to add. Fail fast with an actionable message so a user
      // who rolled back from TestFlight / beta knows to upgrade or
      // export-reimport rather than hitting a corrupted-looking app.
      final before = details.versionBefore;
      if (before != null && before > schemaVersion) {
        throw StateError(
          'Database schema v$before is newer than this app (v$schemaVersion). '
          'You have downgraded to an older build. Upgrade the app, or export '
          'your data from the newer version and re-import into a fresh install.',
        );
      }
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
      'ON member_groups(pluralkit_uuid) '
      'WHERE pluralkit_uuid IS NOT NULL AND is_deleted = 0',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_member_groups_pluralkit_id '
      'ON member_groups(pluralkit_id) WHERE pluralkit_id IS NOT NULL',
    );
  }

  Future<void> _recreateMemberGroupPkUniqueIndex() async {
    await customStatement(
      'DROP INDEX IF EXISTS idx_member_groups_pluralkit_uuid',
    );
    await customStatement(
      'CREATE UNIQUE INDEX idx_member_groups_pluralkit_uuid '
      'ON member_groups(pluralkit_uuid) '
      'WHERE pluralkit_uuid IS NOT NULL AND is_deleted = 0',
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
      'CREATE INDEX IF NOT EXISTS idx_member_groups_sync_suppressed '
      'ON member_groups (sync_suppressed, is_deleted)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_member_groups_suspected_pk_group_uuid '
      'ON member_groups (suspected_pk_group_uuid) '
      'WHERE suspected_pk_group_uuid IS NOT NULL',
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
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_member_groups_parent_id '
      'ON member_groups (parent_group_id) WHERE parent_group_id IS NOT NULL',
    );
  }

  Future<void> _createPkGroupSyncIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_member_group_entries_pk_group_uuid '
      'ON member_group_entries (pk_group_uuid) '
      'WHERE pk_group_uuid IS NOT NULL',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_member_group_entries_pk_member_uuid '
      'ON member_group_entries (pk_member_uuid) '
      'WHERE pk_member_uuid IS NOT NULL',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_member_group_entries_pk_canonicalize '
      'ON member_group_entries (pk_group_uuid, pk_member_uuid) '
      'WHERE is_deleted = 0 AND pk_group_uuid IS NOT NULL '
      'AND pk_member_uuid IS NOT NULL',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_pk_group_sync_aliases_pk_group_uuid '
      'ON pk_group_sync_aliases (pk_group_uuid)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_pk_group_entry_deferred_ops_entity '
      'ON pk_group_entry_deferred_sync_ops (entity_type, entity_id)',
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
  PkGroupSyncAliasesDao get pkGroupSyncAliasesDao =>
      PkGroupSyncAliasesDao(this);
  @override
  PkGroupEntryDeferredSyncOpsDao get pkGroupEntryDeferredSyncOpsDao =>
      PkGroupEntryDeferredSyncOpsDao(this);
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
