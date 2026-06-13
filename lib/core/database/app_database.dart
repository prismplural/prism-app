import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/sync/tombstone_gate.dart';
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
import 'package:prism_plurality/core/database/daos/member_board_posts_dao.dart';
import 'package:prism_plurality/core/database/daos/front_session_comments_dao.dart';
import 'package:prism_plurality/core/database/daos/conversation_categories_dao.dart';
import 'package:prism_plurality/core/database/daos/reminders_dao.dart';
import 'package:prism_plurality/core/database/daos/friends_dao.dart';
import 'package:prism_plurality/core/database/daos/sharing_requests_dao.dart';
import 'package:prism_plurality/core/database/daos/media_attachments_dao.dart';
import 'package:prism_plurality/core/database/daos/sp_import_dao.dart';
import 'package:prism_plurality/core/database/daos/pk_mapping_state_dao.dart';
import 'package:prism_plurality/core/database/daos/preference_values_dao.dart';
import 'package:prism_plurality/core/database/daos/upload_queue_dao.dart';
import 'package:prism_plurality/core/database/daos/missing_media_dao.dart';
import 'package:prism_plurality/core/services/fronting_migration_breadcrumb_log.dart';
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
    MemberBoardPosts,
    FrontSessionComments,
    ConversationCategories,
    Reminders,
    Friends,
    SharingRequests,
    MediaAttachments,
    SpSyncStateTable,
    SpIdMapTable,
    PkMappingState,
    AppPreferenceValues,
    MemberProfilePreferenceValues,
    UploadQueueEntries,
    MissingMediaEntries,
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
    MemberBoardPostsDao,
    FrontSessionCommentsDao,
    ConversationCategoriesDao,
    RemindersDao,
    FriendsDao,
    SharingRequestsDao,
    MediaAttachmentsDao,
    SpImportDao,
    PkMappingStateDao,
    PreferenceValuesDao,
    UploadQueueDao,
    MissingMediaDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  static const currentSchemaVersion = 37;

  /// Optional view of the sync engine's absorbing-delete state (R1/C12). When
  /// the sync layer has a live engine handle it sets this so the deterministic-
  /// id rescue paths can refuse to (re)create a row whose canonical entity id is
  /// already tombstoned — emitting into a burned id is a silent fleet-wide
  /// no-op. `null` (the cold-migration default, before any engine exists) means
  /// "nothing is tombstoned", byte-identical to the pre-R6 behavior. Settable so
  /// the sync bootstrap and tests can inject a gate.
  TombstoneGate? tombstoneGate;

  @override
  int get schemaVersion => currentSchemaVersion;

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
        // The entire v6→v7 block is wrapped in a transaction. Drift does
        // NOT auto-wrap onUpgrade; without an explicit transaction a
        // failure mid-migration leaves user_version=6 with partial v7
        // schema. The user_version bump is applied by Drift after this
        // callback returns successfully, so the transaction here covers
        // all DDL + DML.
        await transaction(() async {
          // New column: members.is_always_fronting (§2.3)
          await migrator.addColumn(members, members.isAlwaysFronting);

          // New column: system_settings.pending_fronting_migration_mode (§4.1)
          // Column default is 'complete' (fresh-install semantics); immediately
          // upsert the singleton row with 'notStarted' so that users upgrading
          // from v6 see the migration modal.
          //
          // We use INSERT ... ON CONFLICT DO UPDATE rather than a plain UPDATE
          // because a test (or a very early-lifecycle production DB) might open
          // without ever calling getSettings() first, leaving the table empty.
          // The upsert creates the row when absent and updates it when present.
          await migrator.addColumn(
            systemSettingsTable,
            systemSettingsTable.pendingFrontingMigrationMode,
          );
          // Cleanup substate for the in-progress migration window. Folded
          // into the v6→v7 block alongside the mode column it
          // disambiguates. Defaults to '' (no destructive post-tx step has
          // run yet); the migration service flips it to 'resetDone'
          // between the Rust reset and the remaining post-tx steps so
          // resumeCleanup() can distinguish "must run reset" from "reset
          // already succeeded — skip it."
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

          // Create the migration-blockers side table used by
          // detect-and-refuse. Using IF NOT EXISTS so a partial-failure
          // retry is safe.
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
          // so the app can surface the problem to the user.
          //
          // Check both partitions:
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
            // No duplicates: safe to replace the old single-column index
            // with the new composite + orphan pair.
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
      if (current == 9 && to >= 10) {
        // Member profile headers. Prism-owned headers and cached PluralKit
        // banners are stored as encrypted synced member blobs.
        await migrator.addColumn(members, members.profileHeaderSource);
        await migrator.addColumn(members, members.profileHeaderLayout);
        await migrator.addColumn(members, members.profileHeaderImageData);
        await migrator.addColumn(members, members.pkBannerImageData);
        await migrator.addColumn(members, members.pkBannerCachedUrl);
        // Flip the header source to PluralKit only when the banner has
        // actually been resolved to local image bytes. A URL alone isn't a
        // useful banner; the resolver may not have fetched it yet, and
        // marking the source as PK would suppress the user's Prism-owned
        // header without any pixels to show in its place.
        await customStatement(
          'UPDATE members SET profile_header_source = 0 '
          "WHERE pk_banner_url IS NOT NULL AND TRIM(pk_banner_url) != '' "
          'AND pk_banner_image_data IS NOT NULL',
        );
        current = 10;
      }
      if (current == 10 && to >= 11) {
        // Per-profile banner visibility. Source/layout stay configured while
        // hidden so users can temporarily suppress a banner without losing it.
        await migrator.addColumn(members, members.profileHeaderVisible);
        current = 11;
      }
      if (current == 11 && to >= 12) {
        await migrator.addColumn(members, members.nameStyleFont);
        await migrator.addColumn(members, members.nameStyleBold);
        await migrator.addColumn(members, members.nameStyleItalic);
        await migrator.addColumn(members, members.nameStyleColorMode);
        await migrator.addColumn(members, members.nameStyleColorHex);
        current = 12;
      }
      if (current == 12 && to >= 13) {
        // v13 briefly introduced a target_time range index for the abandoned
        // timestamp-anchored comment model. The restored v16 schema keeps
        // comments attached to session_id, so there is no v13 DDL left to
        // apply for fresh step-through upgrades.
        current = 13;
      }
      if (current == 13 && to >= 14) {
        // Per-member fronting CHECK constraint (docs/plans/
        // fronting-per-member-sessions.md §2.1, §4.1). Adds
        //   CHECK (session_type != 0 OR member_id IS NOT NULL)
        // to fronting_sessions. Sleep rows (session_type = 1) keep
        // their nullable member_id; normal rows MUST point at a real
        // member from this migration forward.
        //
        // Application is gated on the per-member migration being
        // complete, because users upgrading directly from a pre-v7
        // schema have orphan normal rows (member_id IS NULL) sitting
        // on disk that the modal-driven migration hasn't yet routed
        // to the Unknown sentinel. Adding CHECK with violating rows
        // present would fail and abort the whole DB upgrade.
        //
        // - mode == 'complete': step 7 of §4.1 has already routed
        //   every orphan to the sentinel. Apply CHECK now via
        //   TableMigration so subsequent writes are protected.
        //
        // - mode != 'complete': skip; the migration service's
        //   success path calls `ensureFrontingMemberCheckConstraint`
        //   after step 7, applying the constraint then. The
        //   `customConstraints` declaration on the table class also
        //   means fresh installs created at v14+ get CHECK via
        //   `createAll()` without ever touching this branch.
        final modeRows = await customSelect('''
          SELECT pending_fronting_migration_mode FROM system_settings
          WHERE id = 'singleton'
        ''').get();
        final mode = modeRows.isEmpty
            ? null
            : modeRows.first.read<String?>('pending_fronting_migration_mode');
        if (mode == 'complete') {
          await ensureFrontingMemberCheckConstraint();
        }
        current = 14;
      }
      if (current == 14 && to >= 15) {
        // Member Boards schema introduction.
        //
        // 1. New entity table: member_board_posts.
        // 2. New column on members: board_last_read_at (inbox HWM read state).
        // 3. New columns on system_settings: boards_enabled + sp_boards_backfilled_at.
        // 4–6. Three indexes covering the Inbox, Public, and author queries.
        //
        // Purely additive — no row-level data migration. All new columns have
        // safe defaults (null / false). Do NOT wrap in an extra transaction:
        // Drift's migration framework handles the outer transaction and the
        // v13→v14 block's fragile CHECK logic is untouched.
        await migrator.createTable(memberBoardPosts);
        await migrator.addColumn(members, members.boardLastReadAt);
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.boardsEnabled,
        );
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.spBoardsBackfilledAt,
        );
        await _createMemberBoardPostIndexes();
        current = 15;
      }
      if (current == 15 && to >= 16) {
        await _rebuildFrontSessionCommentsSessionAttached();
        current = 16;
      }
      if (current == 16 && to >= 17) {
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.autoPromoteLongFrontingSessions,
        );
        current = 17;
      }
      if (current == 17 && to >= 18) {
        // Members tab display preferences. Collapsed before the 0.8.0 release:
        // these were briefly developed as v18-v20, but no public build shipped
        // with those intermediate schema versions.
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.membersListViewMode,
        );
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.membersGroupedDefaultState,
        );
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.membersFolderMemberVisibility,
        );
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.membersShowFrontButtons,
        );
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.membersFrontButtonBehavior,
        );
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.membersShowPronouns,
        );
        current = 18;
      }
      if (current == 18 && to >= 19) {
        // 0.8.1 production flatten: all schema additions since 0.8.0 ship as
        // one v18→v19 migration because no public build used the intermediate
        // dev-only versions.
        //
        // Rebuild chat_messages_fts with prefix='2 3 4' so prefix-match
        // queries (every chat search) resolve in a single seek per term
        // instead of a dictionary range scan. Wrap in a transaction:
        // dropping the FTS table mid-migration without recovery would
        // leave search broken until the next rebuild.
        await transaction(() async {
          await customStatement(
            'DROP TRIGGER IF EXISTS chat_messages_fts_insert',
          );
          await customStatement(
            'DROP TRIGGER IF EXISTS chat_messages_fts_update',
          );
          await customStatement(
            'DROP TRIGGER IF EXISTS chat_messages_fts_delete',
          );
          await customStatement('DROP TABLE IF EXISTS chat_messages_fts');
          await _createChatMessagesFtsArtifacts();
          await customStatement(
            'INSERT INTO chat_messages_fts (content, message_id, conversation_id) '
            'SELECT content, id, conversation_id FROM chat_messages '
            "WHERE is_deleted = 0 AND is_system_message = 0 AND content != ''",
          );

          // Add member_group_entries.pending_pk_op for PluralKit bidirectional
          // group membership sync. Local-only (NOT in prismSyncSchema). Default
          // 'none' means existing rows are treated as already-synced — correct
          // semantic since the column tracks fresh local intent. See
          // docs/plans/pk-group-membership-push.md.
          await migrator.addColumn(
            memberGroupEntries,
            memberGroupEntries.pendingPkOp,
          );
          await migrator.addColumn(members, members.pluralkitDisplayName);
        });
        current = 19;
      }
      if (current == 19 && to >= 20) {
        // Bio markdown defaults: flip column default to true and bring any
        // existing `false` per-member rows along so the new "markdown on by
        // default" behavior is consistent across the whole DB.  Users who
        // want it off get the new global `bio_markdown_enabled` switch (or
        // can flip the per-member toggle back per bio).
        await migrator.addColumn(
          systemSettingsTable,
          systemSettingsTable.bioMarkdownEnabled,
        );
        await customStatement(
          'UPDATE members SET markdown_enabled = 1 WHERE markdown_enabled = 0',
        );
        current = 20;
      }
      if (current == 20 && to >= 21) {
        // Direction-first setup: add direction_confirmed to track whether the
        // user has picked a sync direction before the first sync runs.
        // Default false so fresh installs and mid-setup users see the wizard.
        // Backfill: existing fully-set-up users (mapping_acknowledged=1) have
        // already implicitly accepted a direction, so flip them to true so
        // they land on the steady-state screen after upgrading.
        await migrator.addColumn(
          pluralKitSyncState,
          pluralKitSyncState.directionConfirmed,
        );
        await customStatement(
          'UPDATE plural_kit_sync_state '
          'SET direction_confirmed = 1 '
          'WHERE mapping_acknowledged = 1',
        );
        current = 21;
      }
      if (current == 21 && to >= 25) {
        // 0.9.0 production flatten: all schema additions since 0.8.4 ship as
        // one v21→v25 migration because no public build used the intermediate
        // dev-only versions.
        await transaction(() async {
          // Group sort state. Backfill orders entries by SQLite `rowid` as a
          // best-effort proxy for insertion order — no user has ever relied on
          // a persistent within-group order before this migration. Dart loop
          // instead of `ROW_NUMBER()` because non-INTEGER-PK rowids "might
          // change" (https://www.sqlite.org/rowidtable.html).
          await migrator.addColumn(memberGroups, memberGroups.sortState);

          final groupRows = await customSelect(
            'SELECT id FROM member_groups WHERE is_deleted = 0',
          ).get();
          for (final groupRow in groupRows) {
            final groupId = groupRow.read<String>('id');
            final entryRows = await customSelect(
              'SELECT id FROM member_group_entries '
              'WHERE group_id = ? AND is_deleted = 0 '
              'ORDER BY rowid',
              variables: [Variable.withString(groupId)],
            ).get();
            final orderedEntryIds = entryRows
                .map((row) => row.read<String>('id'))
                .toList(growable: false);
            final sortStateJson = jsonEncode({
              'mode': 0,
              'order': orderedEntryIds,
            });
            await customStatement(
              'UPDATE member_groups SET sort_state = ? WHERE id = ?',
              [sortStateJson, groupId],
            );
          }

          // Palette theme controls.
          await migrator.addColumn(
            systemSettingsTable,
            systemSettingsTable.paletteSource,
          );
          await migrator.addColumn(
            systemSettingsTable,
            systemSettingsTable.paletteSeedColorHex,
          );
          await migrator.addColumn(
            systemSettingsTable,
            systemSettingsTable.paletteMood,
          );
          await migrator.addColumn(
            systemSettingsTable,
            systemSettingsTable.paletteContrast,
          );
          await customStatement(
            'UPDATE system_settings SET palette_source = 0 '
            'WHERE theme_style = 2',
          );

          // Repair rows created by app paths that still used the old domain
          // default after the DB column default moved to true.
          await customStatement(
            'UPDATE members SET markdown_enabled = 1 '
            'WHERE markdown_enabled = 0',
          );

          // Everyone-group conversations.
          await migrator.addColumn(
            conversations,
            conversations.includesAllMembers,
          );
          await customStatement(
            'UPDATE conversations SET includes_all_members = 1 '
            'WHERE is_direct_message = 0 '
            'AND is_deleted = 0 '
            'AND NOT ('
            '  json_array_length(participant_ids) = 2 '
            '  AND (title IS NULL OR TRIM(title) = \'\') '
            '  AND emoji IS NULL '
            '  AND category_id IS NULL'
            ')',
          );
          await customStatement(
            'UPDATE conversations '
            'SET participant_ids = json_array(creator_id) '
            'WHERE is_direct_message = 0 '
            'AND is_deleted = 0 '
            'AND includes_all_members = 1 '
            'AND json_array_length(participant_ids) = 0 '
            'AND creator_id IN ('
            '  SELECT id FROM members '
            '  WHERE is_deleted = 0 '
            '  AND is_active = 1 '
            '  AND id != ?'
            ')',
            [unknownSentinelMemberId],
          );
          // If an empty everyone-group has no active creator, assign the first
          // active admin/member as owner so someone can manage the conversation.
          await customStatement(
            '''
            WITH fallback_owner AS (
              SELECT id
              FROM members
              WHERE is_deleted = 0
                AND is_active = 1
                AND id != ?
              ORDER BY is_admin DESC, display_order ASC, created_at ASC, id ASC
              LIMIT 1
            )
            UPDATE conversations
            SET
              creator_id = (SELECT id FROM fallback_owner),
              participant_ids = json_array((SELECT id FROM fallback_owner))
            WHERE is_direct_message = 0
              AND is_deleted = 0
              AND includes_all_members = 1
              AND json_array_length(participant_ids) = 0
              AND (SELECT id FROM fallback_owner) IS NOT NULL
            ''',
            [unknownSentinelMemberId],
          );
        });
        current = 25;
      }
      if (current == 25 && to >= 26) {
        // Idempotent: test seeders and dev DBs may already carry this column
        // because AppDatabase.open() creates tables at the current schema
        // before the seeder resets PRAGMA user_version back to 25.
        final cols = await customSelect(
          'PRAGMA table_info(member_groups)',
        ).get();
        final hasAvatar = cols.any(
          (row) => row.read<String>('name') == 'avatar_image_data',
        );
        if (!hasAvatar) {
          await migrator.addColumn(memberGroups, memberGroups.avatarImageData);
        }
        current = 26;
      }
      if (current == 26 && to >= 27) {
        // Timestamp storage moves from seconds to milliseconds.
        await customStatement(
          'UPDATE chat_messages SET timestamp = timestamp * 1000 '
          'WHERE timestamp < 100000000000',
        );
        if (!await _tableExists('app_preference_values')) {
          await migrator.createTable(appPreferenceValues);
        }
        if (!await _tableExists('member_profile_preference_values')) {
          await migrator.createTable(memberProfilePreferenceValues);
        }
        await _createPreferenceValueIndexes();
        current = 27;
      }
      if (current == 27 && to >= 28) {
        // Idempotent — dev/test seeders may already have the columns.
        final cols = await customSelect(
          'PRAGMA table_info(custom_fields)',
        ).get();
        final names = cols.map((r) => r.read<String>('name')).toSet();
        if (!names.contains('field_type_id')) {
          await migrator.addColumn(customFields, customFields.fieldTypeId);
        }
        if (!names.contains('parent_field_id')) {
          await migrator.addColumn(customFields, customFields.parentFieldId);
        }
        if (!names.contains('type_config_json')) {
          await migrator.addColumn(customFields, customFields.typeConfigJson);
        }
        // Backfill field_type_id from the existing int for back-compat.
        // Mapping mirrors custom_field_mapper.dart:12 (CustomFieldType enum order
        // text=0, color=1, date=2, longText=3) — keep in lockstep.
        await customStatement('''
          UPDATE custom_fields
          SET field_type_id = CASE field_type
            WHEN 0 THEN 'text'
            WHEN 1 THEN 'color'
            WHEN 2 THEN 'date'
            WHEN 3 THEN 'long_text'
            ELSE NULL
          END
          WHERE field_type_id IS NULL
        ''');
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_custom_fields_parent '
          'ON custom_fields(parent_field_id) WHERE parent_field_id IS NOT NULL',
        );
        current = 28;
      }
      if (current == 28 && to >= 29) {
        final cols = await customSelect('PRAGMA table_info(members)').get();
        final names = cols.map((r) => r.read<String>('name')).toSet();
        if (!names.contains('pk_avatar_cached_url')) {
          await migrator.addColumn(members, members.pkAvatarCachedUrl);
        }
        current = 29;
      }
      if (current == 29 && to >= 30) {
        // Collapsed migration: the show/hide-groups toggle
        // (system_settings.members_show_groups) and the bio-image library
        // columns (media_attachments.member_id + tag) ship as one v29→v30 step
        // because no public build used the intermediate dev-only versions.
        // Idempotent — dev/test DBs created at the current schema may already
        // carry these columns.
        final settingsNames = (await customSelect(
          'PRAGMA table_info(system_settings)',
        ).get()).map((r) => r.read<String>('name')).toSet();
        if (!settingsNames.contains('members_show_groups')) {
          await migrator.addColumn(
            systemSettingsTable,
            systemSettingsTable.membersShowGroups,
          );
        }

        final mediaNames = (await customSelect(
          'PRAGMA table_info(media_attachments)',
        ).get()).map((r) => r.read<String>('name')).toSet();
        if (!mediaNames.contains('member_id')) {
          await migrator.addColumn(mediaAttachments, mediaAttachments.memberId);
        }
        if (!mediaNames.contains('tag')) {
          await migrator.addColumn(mediaAttachments, mediaAttachments.tag);
        }
        current = 30;
      }
      if (current == 30 && to >= 31) {
        await migrator.alterTable(
          TableMigration(
            members,
            columnTransformer: {members.age: members.age.cast<String>()},
          ),
        );
        current = 31;
      }
      if (current == 31 && to >= 32) {
        // archived_for_everyone — convo-level archive flag. Idempotent:
        // dev/test DBs created at the current schema may already have it.
        final convoNames = (await customSelect(
          'PRAGMA table_info(conversations)',
        ).get()).map((r) => r.read<String>('name')).toSet();
        if (!convoNames.contains('archived_for_everyone')) {
          await migrator.addColumn(
            conversations,
            conversations.archivedForEveryone,
          );
        }
        current = 32;
      }
      if (current == 32 && to >= 37) {
        // 0.12.x production flatten: all schema additions since the v32 floor
        // ship as one v32→v37 migration because no public build used the
        // intermediate dev-only versions. Each step keeps its idempotent guard
        // so dev/test DBs materialised at the current schema re-run cleanly.

        // durable media upload queue: durable, resumable media upload queue.
        final tables = (await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        ).get()).map((r) => r.read<String>('name')).toSet();
        if (!tables.contains('upload_queue_entries')) {
          await migrator.createTable(uploadQueueEntries);
        }

        // media heal: the demand-driven heal's missing-media set.
        if (!tables.contains('missing_media')) {
          await migrator.createTable(missingMediaEntries);
        }

        // media thumbnails: thumbnail crypto material so a peer can fetch +
        // integrity-verify the (already-uploaded) thumbnail blob. Reuses the
        // main blob's encryption key, so only the two hashes are new.
        final mediaCols = (await customSelect(
          'PRAGMA table_info(media_attachments)',
        ).get()).map((r) => r.read<String>('name')).toSet();
        if (!mediaCols.contains('thumbnail_content_hash')) {
          await migrator.addColumn(
            mediaAttachments,
            mediaAttachments.thumbnailContentHash,
          );
        }
        if (!mediaCols.contains('thumbnail_plaintext_hash')) {
          await migrator.addColumn(
            mediaAttachments,
            mediaAttachments.thumbnailPlaintextHash,
          );
        }

        // nav bar label display controls.
        final settingsCols = (await customSelect(
          'PRAGMA table_info(system_settings)',
        ).get()).map((r) => r.read<String>('name')).toSet();
        if (!settingsCols.contains('nav_bar_label_display_mode')) {
          await migrator.addColumn(
            systemSettingsTable,
            systemSettingsTable.navBarLabelDisplayMode,
          );
        }
        if (!settingsCols.contains('nav_bar_reveal_labels_when_expanded')) {
          await migrator.addColumn(
            systemSettingsTable,
            systemSettingsTable.navBarRevealLabelsWhenExpanded,
          );
        }

        // member_group_entries.created_at — local-only recency stamp for the
        // PK reconcile grace window (H6); NOT in prismSyncSchema. Existing rows
        // backfill to "now" so an upgrading device doesn't reconcile-delete its
        // pre-fix backlog as ancient.
        final entryCols = (await customSelect(
          'PRAGMA table_info(member_group_entries)',
        ).get()).map((r) => r.read<String>('name')).toSet();
        if (!entryCols.contains('created_at')) {
          await migrator.addColumn(
            memberGroupEntries,
            memberGroupEntries.createdAt,
          );
          // addColumn with a clientDefault leaves existing rows NULL; backfill
          // to the migration wall-clock so the grace check has a real stamp.
          await customStatement(
            'UPDATE member_group_entries '
            'SET created_at = ? WHERE created_at IS NULL',
            [DateTime.now().millisecondsSinceEpoch ~/ 1000],
          );
        }
        current = 37;
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
      await _createMemberBoardPostIndexes();
      await _createPkUniqueIndexes();
      // Fresh v7 install: jump straight to composite + orphan fronting indexes.
      // Empty table, so no detect-and-refuse needed.
      await _createPkFrontingCompositeIndex();
      await _createPkFrontingOrphanIndex();
      await _createPkGroupSyncIndexes();
      await _createPreferenceValueIndexes();
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

      // Idempotent column reconcile. Heals databases that reached the current
      // schemaVersion under a *different* migration numbering — e.g. a dev DB
      // migrated by an earlier unshipped branch that stamped v31 before these
      // columns were renumbered. The version counter won't re-run migrations
      // (from == to), so verify the expected columns exist and add any that
      // are missing. No-op for correctly-migrated and fresh databases.
      await _reconcileExpectedColumns();
      await _createFirstRenderIndexes();
    },
  );

  /// Best-effort idempotent column reconcile run in [beforeOpen]. Adds columns
  /// that should exist at the current schema but may be absent on databases
  /// that reached this version through a divergent (unshipped) migration path.
  Future<void> _reconcileExpectedColumns() async {
    Future<void> ensure(String table, String column, String ddlType) async {
      final cols = await customSelect('PRAGMA table_info($table)').get();
      final names = cols.map((r) => r.read<String>('name')).toSet();
      if (!names.contains(column)) {
        await customStatement('ALTER TABLE $table ADD COLUMN $column $ddlType');
      }
    }

    await ensure('media_attachments', 'member_id', "TEXT NOT NULL DEFAULT ''");
    await ensure('media_attachments', 'tag', "TEXT NOT NULL DEFAULT ''");
    await ensure(
      'media_attachments',
      'thumbnail_content_hash',
      "TEXT NOT NULL DEFAULT ''",
    );
    await ensure(
      'media_attachments',
      'thumbnail_plaintext_hash',
      "TEXT NOT NULL DEFAULT ''",
    );
    await ensure(
      'system_settings',
      'members_show_groups',
      'INTEGER NOT NULL DEFAULT 1 CHECK ("members_show_groups" IN (0, 1))',
    );
    await ensure(
      'conversations',
      'archived_for_everyone',
      'INTEGER NOT NULL DEFAULT 0 CHECK ("archived_for_everyone" IN (0, 1))',
    );
  }

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

  /// Creates the orphan partial unique index on fronting_sessions.
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
  /// Test-only escape hatch: strips the v14 CHECK constraint from
  /// `fronting_sessions` so a test can seed orphan rows that simulate
  /// a pre-v14 database. Mirrors the wire shape `ensureFrontingMember-
  /// CheckConstraint` is the inverse of: after calling this, you can
  /// insert `(session_type=0, member_id=NULL)` rows; calling the
  /// ensure helper restores the constraint via TableMigration.
  ///
  /// Uses `PRAGMA writable_schema` to mutate `sqlite_master.sql`
  /// directly. Production code MUST NOT call this — there's no
  /// scenario where stripping a structural backstop is correct in
  /// shipping code.
  @visibleForTesting
  Future<void> disableFrontingMemberCheckConstraintForTesting() async {
    final res = await customSelect('''
      SELECT sql FROM sqlite_master
      WHERE type = 'table' AND name = 'fronting_sessions'
    ''').get();
    if (res.isEmpty) return;
    final originalSql = res.first.read<String?>('sql') ?? '';
    // Match only the per-member-fronting CHECK — Drift also emits
    // `CHECK (is_health_kit_import IN (0, 1))` and similar for every
    // BoolColumn, and stripping those would corrupt the schema.
    final pattern = RegExp(_frontingMemberCheckClausePattern);
    if (!pattern.hasMatch(originalSql)) return;
    final newSql = originalSql.replaceAll(pattern, '');

    // SQLite caches the parsed schema in memory and only invalidates
    // it on connection reopen — so editing sqlite_master.sql via
    // `writable_schema` won't actually relax the constraint for the
    // running connection. Instead, drop and recreate the table from
    // the modified CREATE statement. Tests call this in setUp before
    // any rows exist, so there's no data to preserve.
    final idxRows = await customSelect('''
      SELECT sql FROM sqlite_master
      WHERE type = 'index'
        AND tbl_name = 'fronting_sessions'
        AND sql IS NOT NULL
    ''').get();
    final indexSqls = [for (final r in idxRows) r.read<String>('sql')];

    await transaction(() async {
      await customStatement('PRAGMA foreign_keys = OFF');
      await customStatement('DROP TABLE fronting_sessions');
      await customStatement(newSql);
      for (final sql in indexSqls) {
        await customStatement(sql);
      }
      await customStatement('PRAGMA foreign_keys = ON');
    });
  }

  /// Matches the per-member-fronting CHECK clause as Drift emits it
  /// in the fronting_sessions CREATE TABLE statement. Used to detect
  /// whether the constraint is currently applied (and to strip it in
  /// tests). The leading `,\s*` swallows the comma + whitespace from
  /// the surrounding constraint list so the resulting SQL stays
  /// well-formed.
  static const String _frontingMemberCheckClausePattern =
      r',\s*CHECK\s*\(\s*session_type\s*!=\s*0\s+OR\s+member_id\s+IS\s+NOT\s+NULL\s*\)';

  /// Idempotent ensure step for the v14 CHECK constraint on
  /// fronting_sessions (`CHECK (session_type != 0 OR member_id IS NOT NULL)`).
  ///
  /// Sniffs the table's CREATE statement first — calling this on a
  /// table that already carries the constraint is a no-op.
  ///
  /// Two call sites:
  ///
  /// 1. v13→v14 onUpgrade when the per-member fronting migration is
  ///    already complete (typical upgrade path for users on v13).
  /// 2. The migration service's success path, after step 7 of §4.1
  ///    routes orphan normal rows to the Unknown sentinel — for users
  ///    upgrading from a pre-v7 schema in one shot, where the v13→v14
  ///    branch saw mode != 'complete' and deferred.
  ///
  /// Fresh installs at v14+ never need this — `customConstraints` on
  /// the FrontingSessions table class makes `createAll()` emit the
  /// constraint as part of the initial CREATE TABLE.
  Future<void> ensureFrontingMemberCheckConstraint() async {
    final res = await customSelect('''
      SELECT sql FROM sqlite_master
      WHERE type = 'table' AND name = 'fronting_sessions'
    ''').get();
    if (res.isEmpty) return;
    final sql = res.first.read<String?>('sql') ?? '';
    // Look for the specific per-member-fronting CHECK; ignore Drift's
    // auto-emitted `CHECK (... IN (0, 1))` clauses on BoolColumns,
    // which are present from the very first `createAll()`.
    if (RegExp(_frontingMemberCheckClausePattern).hasMatch(sql)) return;

    // Rescue live orphans to the Unknown sentinel before we install the
    // CHECK. This keeps locally-visible session history intact for devices
    // that somehow reached mode=complete with active `(session_type=0,
    // member_id=NULL)` rows still on disk.
    //
    // Interaction with the R6/C12 sentinel gate: if `tombstoneGate` is set and
    // the sentinel id is tombstoned, the rescue SKIPS — active orphans then
    // keep `member_id IS NULL`, and the `TableMigration` copy below would throw
    // on the new CHECK. This is shielded in practice: the cold-migration leg
    // (v13→v14 onUpgrade) runs with `tombstoneGate == null` so the rescue never
    // skips, and the migration service's step 7 re-homes orphans before any
    // gated call reaches here. The `_purgeUnrecoverableFrontingOrphans` call
    // below only removes is_deleted=1 debris, not live orphans, so it is not a
    // backstop for this case — the shield is the gate-null cold path.
    await _rescueActiveFrontingOrphansToUnknownSentinel('CHECK install');

    // Hard-delete unrecoverable deleted leftovers BEFORE the CHECK install.
    // Drift's TableMigration copies every row including is_deleted=1 ones, so
    // any tombstoned `(session_type=0, member_id NULL)` row would trip the
    // new constraint and abort the table rebuild.
    await _purgeUnrecoverableFrontingOrphans('CHECK install');

    final migrator = Migrator(this);
    await migrator.alterTable(TableMigration(frontingSessions));
  }

  Future<void> ensurePkFrontingIndexes() async {
    // Rescue live orphans before index installation. We clear their stale
    // pluralkit_uuid at the same time because on orphan rows it stores a
    // switch id, not a resolvable member identity; preserving it would make
    // multiple rescued Unknown rows collide on the composite PK fronting
    // index.
    await _rescueActiveFrontingOrphansToUnknownSentinel('PK index install');

    // Scrub unrecoverable deleted leftovers so the orphan/composite unique
    // index install cannot fail on tombstones surfacing through any path that
    // reaches this helper without going through the migration service's step 7.
    await _purgeUnrecoverableFrontingOrphans('PK index install');

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

  /// Re-home active orphan fronting rows to the deterministic Unknown
  /// sentinel member and clear any stale PK switch UUIDs that would
  /// otherwise collide on the composite fronting indexes.
  ///
  /// These rows are user-visible history, so preserving them is better than
  /// silently deleting them during a structural upgrade. The migration
  /// service's primary path already routes such rows to the same sentinel in
  /// step 7; this helper is the defensive backstop for unexpected
  /// post-migration leftovers that reach the schema ensure steps directly.
  Future<int> _rescueActiveFrontingOrphansToUnknownSentinel(
    String reason,
  ) async {
    // C12 / R6 ingress gate: the Unknown sentinel uses a deterministic UUIDv5
    // id, so if a previously-synced sentinel was deleted, the engine holds an
    // absorbing tombstone for that id. Re-homing orphans onto it and re-creating
    // the member would write into a burned id — a silent fleet-wide no-op on
    // peers and a Rust/Dart divergence locally. The sentinel is NOT minted to a
    // new incarnation (family-5 open question 6, not adopted); when burned we
    // simply skip the rescue. A null gate (cold migration with no engine) keeps
    // the pre-gate behavior byte-for-byte.
    final gate = tombstoneGate;
    if (gate != null &&
        await gate.isTombstoned('members', unknownSentinelMemberId)) {
      debugPrint(
        '[MIGRATION] skipping Unknown-sentinel orphan rescue before $reason — '
        'sentinel id is tombstoned in the sync engine (burned id).',
      );
      return 0;
    }

    final activeOrphans = await customUpdate(
      'UPDATE fronting_sessions '
      'SET member_id = ?, pluralkit_uuid = NULL '
      'WHERE session_type = 0 AND member_id IS NULL AND is_deleted = 0',
      variables: [Variable<String>(unknownSentinelMemberId)],
      updates: {frontingSessions},
    );
    if (activeOrphans <= 0) {
      return 0;
    }

    await membersDao.upsertMember(
      MembersCompanion.insert(
        id: unknownSentinelMemberId,
        name: 'Unknown',
        createdAt: DateTime.now().toUtc(),
        emoji: const Value('❔'),
        isActive: const Value(true),
      ),
    );

    debugPrint(
      '[MIGRATION] rescued $activeOrphans active orphan fronting rows '
      'to the Unknown sentinel before $reason.',
    );
    await FrontingMigrationBreadcrumbLog.instance.append(
      FrontingMigrationBreadcrumb(
        timestamp: DateTime.now().toUtc(),
        kind: 'rescued_active_orphans',
        reason: reason,
        count: activeOrphans,
        data: <String, dynamic>{
          'target_member_id': unknownSentinelMemberId,
          'pluralkit_uuid_cleared': true,
        },
      ),
    );
    return activeOrphans;
  }

  /// Removes deleted fronting rows with `session_type = 0 AND member_id IS NULL`.
  ///
  /// Active rows are rescued by [_rescueActiveFrontingOrphansToUnknownSentinel]
  /// before this helper runs. What remains here is deleted historical debris
  /// that would otherwise block CHECK/index installation.
  ///
  /// Idempotent — a no-op when the table holds no offending tombstones.
  Future<void> _purgeUnrecoverableFrontingOrphans(String reason) async {
    final purged = await customUpdate(
      'DELETE FROM fronting_sessions '
      'WHERE session_type = 0 AND member_id IS NULL AND is_deleted = 1',
      updates: {frontingSessions},
    );
    if (purged > 0) {
      debugPrint(
        '[MIGRATION] purged $purged unrecoverable orphan fronting rows '
        'before $reason.',
      );
      await FrontingMigrationBreadcrumbLog.instance.append(
        FrontingMigrationBreadcrumb(
          timestamp: DateTime.now().toUtc(),
          kind: 'purged_deleted_orphans',
          reason: reason,
          count: purged,
        ),
      );
    }
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

  Future<void> _rebuildFrontSessionCommentsSessionAttached() async {
    await transaction(() async {
      await customStatement('DROP INDEX IF EXISTS idx_comments_target_time');
      await customStatement('DROP INDEX IF EXISTS idx_comments_session');
      await customStatement('''
        CREATE TABLE front_session_comments_new (
          id TEXT NOT NULL,
          session_id TEXT NOT NULL,
          body TEXT NOT NULL,
          timestamp INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0 CHECK (is_deleted IN (0, 1)),
          PRIMARY KEY (id)
        )
      ''');
      await customStatement('''
        INSERT INTO front_session_comments_new (
          id,
          session_id,
          body,
          timestamp,
          created_at,
          is_deleted
        )
        SELECT
          id,
          session_id,
          body,
          timestamp,
          created_at,
          is_deleted
        FROM front_session_comments
        WHERE session_id IS NOT NULL AND session_id != ''
      ''');
      await customStatement('DROP TABLE front_session_comments');
      await customStatement(
        'ALTER TABLE front_session_comments_new RENAME TO front_session_comments',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_comments_session '
        'ON front_session_comments (session_id, is_deleted, timestamp ASC)',
      );
    });
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
    await _createFirstRenderIndexes();
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
    if (await _columnExists('custom_fields', 'parent_field_id')) {
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_custom_fields_parent '
        'ON custom_fields(parent_field_id) WHERE parent_field_id IS NOT NULL',
      );
    }
  }

  Future<void> _createFirstRenderIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sessions_active_fronting '
      'ON fronting_sessions '
      '(session_type, is_deleted, end_time, start_time DESC, member_id) '
      'WHERE session_type = 0 AND is_deleted = 0 AND end_time IS NULL',
    );
  }

  Future<bool> _columnExists(String table, String column) async {
    final cols = await customSelect('PRAGMA table_info($table)').get();
    return cols.any((r) => r.read<String>('name') == column);
  }

  Future<void> _createPreferenceValueIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_app_preference_values_deleted '
      'ON app_preference_values (is_deleted)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_member_profile_pref_member_key '
      'ON member_profile_preference_values (member_id, key)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_member_profile_pref_member_deleted_key '
      'ON member_profile_preference_values (member_id, is_deleted, key)',
    );
  }

  Future<bool> _tableExists(String tableName) async {
    final rows = await customSelect(
      '''
      SELECT 1
      FROM sqlite_master
      WHERE type = 'table' AND name = ?
      LIMIT 1
      ''',
      variables: [Variable<String>(tableName)],
    ).get();
    return rows.isNotEmpty;
  }

  Future<void> _createMemberBoardPostIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_mbp_target_audience '
      'ON member_board_posts (target_member_id, audience, written_at DESC, is_deleted)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_mbp_audience '
      'ON member_board_posts (audience, written_at DESC, is_deleted)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_mbp_author '
      'ON member_board_posts (author_id, written_at DESC, is_deleted)',
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
    // prefix='2 3 4' indexes 2-, 3-, and 4-char prefix terms so that
    // `"abc"*` queries — every chat search uses the prefix-match form —
    // resolve via single seeks instead of dictionary range scans.
    await customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS chat_messages_fts USING fts5(
        content,
        message_id UNINDEXED,
        conversation_id UNINDEXED,
        tokenize='unicode61 remove_diacritics 2',
        prefix='2 3 4'
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
      WHEN OLD.content != NEW.content
        OR OLD.is_deleted != NEW.is_deleted
        OR OLD.is_system_message != NEW.is_system_message
        OR OLD.conversation_id != NEW.conversation_id
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
  MemberBoardPostsDao get memberBoardPostsDao => MemberBoardPostsDao(this);
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
