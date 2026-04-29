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
  int get schemaVersion => 9;

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
        // Only create the v2-era single-column fronting index if we're stopping
        // at v2.  When stepping through to v7, skip it: the v6→v7 detect-and-refuse
        // is the single source of truth for handling pre-existing duplicates.
        // Creating a UNIQUE index here would throw on a v1 DB with duplicate
        // pluralkit_uuid rows before that block could run.
        if (to < 7) {
          await _createPkFrontingV2SingleColumnIndex();
        }
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
        // Three raw-SQL sites wrote ms-since-epoch into DateTimeColumn
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
      if (current == 5 && to >= 6) {
        await migrator.addColumn(members, members.pkBannerUrl);
        current = 6;
      }
      if (current == 6 && to >= 7) {
        // Phase 1: per-member fronting refactor — additive schema only.
        // Old columns (co_fronter_ids, pk_member_ids_json, comments.session_id)
        // stay in place; they are dropped in v8 cleanup.
        //
        // The entire v6→v7 block is wrapped in a transaction (P2-C).  Drift
        // does NOT auto-wrap onUpgrade; without an explicit transaction a
        // failure mid-migration leaves user_version=6 with partial v7 schema.
        // The user_version bump is applied by Drift after this callback returns
        // successfully, so the transaction here covers all DDL + DML.
        await transaction(() async {
          // New column: members.is_always_fronting (§2.3)
          await migrator.addColumn(members, members.isAlwaysFronting);

          // New column: system_settings.pending_fronting_migration_mode (§4.1)
          // Column default is 'complete' (fresh-install semantics); immediately
          // upsert the singleton row with 'notStarted' so that users upgrading
          // from v6 see the migration modal (P2-B).
          //
          // We use INSERT ... ON CONFLICT DO UPDATE rather than a plain UPDATE
          // because a test (or a very early-lifecycle production DB) might open
          // without ever calling getSettings() first, leaving the table empty.
          // The upsert creates the row when absent and updates it when present.
          await migrator.addColumn(
            systemSettingsTable,
            systemSettingsTable.pendingFrontingMigrationMode,
          );
          // Codex pass 2 #B-NEW3 — folded into the v6→v7 block alongside the
          // mode column it disambiguates. Defaults to '' (no destructive
          // post-tx step has run yet); the migration service flips it to
          // 'resetDone' between the Rust reset and the remaining post-tx
          // steps so resumeCleanup() can distinguish "must run reset" from
          // "reset already succeeded — skip it."
          await migrator.addColumn(
            systemSettingsTable,
            systemSettingsTable.pendingFrontingMigrationCleanupSubstate,
          );
          await customStatement(
            'INSERT INTO system_settings (id, pending_fronting_migration_mode) '
            "VALUES ('singleton', 'notStarted') "
            'ON CONFLICT(id) DO UPDATE SET '
            "pending_fronting_migration_mode = 'notStarted'",
          );

          // New columns: front_session_comments.target_time + author_member_id (§3.5)
          await migrator.addColumn(
            frontSessionComments,
            frontSessionComments.targetTime,
          );
          await migrator.addColumn(
            frontSessionComments,
            frontSessionComments.authorMemberId,
          );

          // Create the migration-blockers side table used by detect-and-refuse
          // (P2-D).  Using IF NOT EXISTS so a partial-failure retry is safe.
          await customStatement('''
            CREATE TABLE IF NOT EXISTS _v7_migration_blockers (
              table_name TEXT NOT NULL,
              row_id     TEXT NOT NULL,
              reason     TEXT NOT NULL,
              detected_at INTEGER NOT NULL
            )
          ''');

          // Pre-flight duplicate detection before creating the composite unique
          // index (§3.7 + §4.1).
          //
          // The old single-column unique index on pluralkit_uuid prevents
          // duplicate (uuid, member_id) pairs by construction — a repeated uuid
          // implies a repeated (uuid, member_id) unless member_id differs, which
          // the old index can't catch.  In practice duplicates should be absent,
          // but rather than delete data at Phase 1 launch (before the Phase 5
          // PRISM1 backup), we detect-and-refuse: log any blockers, set the
          // migration mode to 'blocked', and skip creating the composite index
          // so the app can surface the problem to the user (P2-D).
          //
          // Check both partitions (P2-E):
          //   (a) resolved rows:  (pluralkit_uuid, member_id) where member_id IS NOT NULL
          //   (b) orphan rows:    (pluralkit_uuid)            where member_id IS NULL
          final now = DateTime.now().millisecondsSinceEpoch;

          // (a) Resolved duplicate pairs
          final resolvedDups = await customSelect('''
            SELECT id
            FROM fronting_sessions
            WHERE pluralkit_uuid IS NOT NULL AND member_id IS NOT NULL
              AND (pluralkit_uuid, member_id) IN (
                SELECT pluralkit_uuid, member_id
                FROM fronting_sessions
                WHERE pluralkit_uuid IS NOT NULL AND member_id IS NOT NULL
                GROUP BY pluralkit_uuid, member_id
                HAVING COUNT(*) > 1
              )
          ''').get();

          // (b) Orphan duplicate rows (same uuid, both member_id=null)
          final orphanDups = await customSelect('''
            SELECT id
            FROM fronting_sessions
            WHERE pluralkit_uuid IS NOT NULL AND member_id IS NULL
              AND pluralkit_uuid IN (
                SELECT pluralkit_uuid
                FROM fronting_sessions
                WHERE pluralkit_uuid IS NOT NULL AND member_id IS NULL
                GROUP BY pluralkit_uuid
                HAVING COUNT(*) > 1
              )
          ''').get();

          final allDups = [...resolvedDups, ...orphanDups];

          if (allDups.isNotEmpty) {
            // Log every affected row id to the blocker side table.
            for (final row in allDups) {
              final rowId = row.read<String>('id');
              await customStatement(
                'INSERT INTO _v7_migration_blockers '
                '(table_name, row_id, reason, detected_at) '
                'VALUES (?, ?, ?, ?)',
                [
                  'fronting_sessions',
                  rowId,
                  'duplicate_pk_uuid_member_id',
                  now,
                ],
              );
            }
            // Flip migration mode to 'blocked' so Phase 5 startup surfaces this
            // to the user rather than silently leaving the index absent.
            await customStatement(
              'INSERT INTO system_settings (id, pending_fronting_migration_mode) '
              "VALUES ('singleton', 'blocked') "
              'ON CONFLICT(id) DO UPDATE SET '
              "pending_fronting_migration_mode = 'blocked'",
            );
            // Do NOT create the composite index.  On real v6→v7 upgrades from
            // prior app builds, the old single-column index already exists and
            // continues to enforce uuid uniqueness.  On synthetic v1→v7
            // step-throughs (test fixtures only) the old index was never
            // created — but Phase 5 gates writes to fronting_sessions until
            // the user resolves the blocker, so unprotected blocked DBs never
            // accept new duplicate inserts.
          } else {
            // No duplicates: safe to replace the old single-column index with
            // the new composite + orphan pair (P2-E).
            await customStatement(
              'DROP INDEX IF EXISTS idx_fronting_sessions_pluralkit_uuid',
            );
            await _createPkFrontingCompositeIndex();
            await _createPkFrontingOrphanIndex();
          }

          // Phase 4B: diff-sweep resume cursor for PluralKit sync (§2.6).
          // Folded into v7 (was briefly a standalone v8 bump before any
          // production data existed at v8).  Additive-only — two nullable
          // columns; no data migration required.
          await migrator.addColumn(
            pluralKitSyncState,
            pluralKitSyncState.switchCursorTimestamp,
          );
          await migrator.addColumn(
            pluralKitSyncState,
            pluralKitSyncState.switchCursorId,
          );
        });

        current = 7;
      }
      if (current == 7 && to >= 8) {
        // Phase 1B: fronting preferences (docs/plans/fronting-preferences-1B.md).
        // Three new synced settings on `system_settings`. Purely additive;
        // no row-level data migration — Drift's column defaults supply
        // `combinedPeriods` (0) / `additive` (0) / `additive` (0) for any
        // pre-existing row.
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.frontingListViewMode,
        );
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.addFrontDefaultBehavior,
        );
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.quickFrontDefaultBehavior,
        );
        current = 8;
      }
      if (current == 8 && to >= 9) {
        // PluralKit file-origin fronting metadata. Additive nullable columns:
        // existing API/native/SP rows keep nulls, while future file-origin
        // imports can store a deterministic source switch key without
        // overloading `pluralkit_uuid`.
        await migrator.addColumn(
          frontingSessions,
          frontingSessions.pkImportSource,
        );
        await migrator.addColumn(
          frontingSessions,
          frontingSessions.pkFileSwitchId,
        );
        current = 9;
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
      // Fresh v7 install: jump straight to composite + orphan fronting indexes.
      // Empty table, so no detect-and-refuse needed.
      await _createPkFrontingCompositeIndex();
      await _createPkFrontingOrphanIndex();
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

  /// PK uniqueness indexes that are stable across v2 → v7.
  ///
  /// Members + member_groups indexes have the same shape from v2 onward.
  /// Fronting-sessions indexes differ between v2 (single-column on `pluralkit_uuid`)
  /// and v7 (composite + orphan); each migration path or fresh-install call site
  /// adds the right fronting variant explicitly.  Putting fronting indexes in the
  /// shared helper would crash a v1→v7 upgrade with duplicate `(uuid, NULL)` rows
  /// at the v1→v2 step, before v6→v7 detect-and-refuse can run.
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
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_member_groups_pluralkit_uuid '
      'ON member_groups(pluralkit_uuid) '
      'WHERE pluralkit_uuid IS NOT NULL AND is_deleted = 0',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_member_groups_pluralkit_id '
      'ON member_groups(pluralkit_id) WHERE pluralkit_id IS NOT NULL',
    );
  }

  /// The pre-v7 single-column fronting index, recreated for the v1→v2 step
  /// of step-through upgrades.  v6→v7 drops this and replaces it with the
  /// composite + orphan pair (after detect-and-refuse).
  Future<void> _createPkFrontingV2SingleColumnIndex() async {
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_fronting_sessions_pluralkit_uuid '
      'ON fronting_sessions(pluralkit_uuid) WHERE pluralkit_uuid IS NOT NULL',
    );
  }

  /// Creates the composite partial unique index on fronting_sessions for
  /// PluralKit dedup (§3.7) — resolved rows partition.
  ///
  /// Covers rows where both pluralkit_uuid and member_id are non-null.
  /// Together with [_createPkFrontingOrphanIndex] this fully replaces the old
  /// single-column `idx_fronting_sessions_pluralkit_uuid` index from v1.
  Future<void> _createPkFrontingCompositeIndex() async {
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS '
      'idx_fronting_sessions_pluralkit_uuid_member_id '
      'ON fronting_sessions(pluralkit_uuid, member_id) '
      'WHERE pluralkit_uuid IS NOT NULL AND member_id IS NOT NULL',
    );
  }

  /// Creates the orphan partial unique index on fronting_sessions (P2-E).
  ///
  /// Covers rows where pluralkit_uuid is non-null but member_id IS NULL.
  /// SQLite treats NULL as distinct in unique constraints, so without this
  /// index two `(uuid='X', member_id=null)` rows would both succeed.  This
  /// closes the gap during the Phase 1→2 window while the importer can still
  /// produce unresolvable-member rows.
  Future<void> _createPkFrontingOrphanIndex() async {
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS '
      'idx_fronting_sessions_pluralkit_uuid_orphan '
      'ON fronting_sessions(pluralkit_uuid) '
      'WHERE pluralkit_uuid IS NOT NULL AND member_id IS NULL',
    );
  }

  /// Idempotent ensure step for the v7 fronting indexes — called from the
  /// migration service's success path so blocked-mode recovery never lands
  /// without the protective constraints.
  ///
  /// v7 onUpgrade's detect-and-refuse branch (duplicates present) skips
  /// composite + orphan index creation so it can surface the blocker to
  /// the user without throwing.  Once the user resolves the duplicates and
  /// the migration service marks the migration complete, we MUST install
  /// the v7 indexes — otherwise the post-migration DB has no DB-layer
  /// protection against future duplicate `(pluralkit_uuid, member_id)`
  /// inserts, AND it may still carry the v2-era single-column unique
  /// index on `pluralkit_uuid` which would reject legitimate multi-member
  /// PK switches.
  ///
  /// Safe to call when state is already correct: every statement uses
  /// `IF NOT EXISTS` / `IF EXISTS`, so calling this on a normal-flow v7
  /// DB (where v7 onUpgrade already created the indexes) is a no-op.
  Future<void> ensurePkFrontingIndexes() async {
    // Drop the v2-era single-column uniqueness index if it survived an
    // earlier migration step (e.g., the v1→v2 leg of a step-through, or
    // a v6 DB whose v6→v7 onUpgrade hit the blocked path and left the
    // pre-v7 index in place).
    await customStatement(
      'DROP INDEX IF EXISTS idx_fronting_sessions_pluralkit_uuid',
    );
    // Re-use the same helpers v7 onUpgrade uses on the no-duplicates
    // path; both already use CREATE UNIQUE INDEX IF NOT EXISTS.
    await _createPkFrontingCompositeIndex();
    await _createPkFrontingOrphanIndex();
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
