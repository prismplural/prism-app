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
import 'package:prism_plurality/core/database/daos/pk_identity_sync_aliases_dao.dart';
import 'package:prism_plurality/core/database/daos/poll_options_dao.dart';
import 'package:prism_plurality/core/database/daos/poll_votes_dao.dart';
import 'package:prism_plurality/core/database/daos/polls_dao.dart';
import 'package:prism_plurality/core/database/daos/pluralkit_sync_dao.dart';
import 'package:prism_plurality/core/database/daos/sync_quarantine_dao.dart';
import 'package:prism_plurality/core/database/daos/sync_op_outbox_dao.dart';
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
    SyncOpOutbox,
    SyncMigrationRepairs,
    MemberGroups,
    MemberGroupEntries,
    PkGroupSyncAliases,
    PkIdentitySyncAliases,
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
    SyncOutboxDao,
    MemberGroupsDao,
    PkGroupSyncAliasesDao,
    PkIdentitySyncAliasesDao,
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

  static const currentSchemaVersion = 40;

  /// Optional view of the sync engine's absorbing-delete state. When the sync
  /// layer has a live engine handle it sets this so the deterministic-id rescue
  /// paths can refuse to (re)create a row whose canonical entity id is already
  /// tombstoned — emitting into a burned id is a silent fleet-wide no-op.
  /// `null` (the cold-migration default, before any engine exists) means
  /// "nothing is tombstoned", byte-identical to the pre-gate behavior. Settable
  /// so the sync bootstrap and tests can inject a gate.
  TombstoneGate? tombstoneGate;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      // Ensure the sync-repair queue exists before the runtime drain /
      // blanket backfill needs it, regardless of which step the upgrade resumes
      // from. The v37->v38 flatten step also creates it (and stamps it); this
      // create-if-absent is belt-and-braces so a chain that errors mid-upgrade
      // still leaves a valid target for MigrationSyncRepairService.
      await _createTableIfAbsent(migrator, syncMigrationRepairs);
      await _runMigrationSteps(migrator, from, to);
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
      await _createPkIdentitySyncIndexes();
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
      // F20: re-ensure the PK uniqueness backstop indexes idempotently. A DB
      // that reached currentSchemaVersion via renumbered migrations can have its
      // columns healed but these indexes absent (migrations don't re-run when
      // from == to), leaving the duplicate-uuid window open. Guarded: on a DB
      // that ALREADY holds duplicate active rows the UNIQUE create throws — don't
      // brick boot (the resolver tolerates transient duplicates); the index just
      // stays absent until those rows are reconciled.
      try {
        await _createPkUniqueIndexes();
      } catch (e) {
        debugPrint(
          '[DB] PK uniqueness index re-ensure skipped '
          '(likely pre-existing duplicate): $e',
        );
      }
    },
  );

  /// Executes the applicable [_migrationSteps] in order, making the upgrade
  /// chain atomic, idempotent, and resumable.
  ///
  /// Drift does NOT wrap onUpgrade in a transaction and only stamps the final
  /// schema version after the whole callback returns, so a process death
  /// mid-chain would otherwise leave a partially-applied schema stamped at the
  /// old version — every relaunch then re-runs the already-applied DDL and
  /// throws "duplicate column name", wedging boot forever. Here each step runs
  /// inside its own transaction that also writes `PRAGMA user_version` to the
  /// step target, so the stamp and the step's DDL commit together: a kill
  /// either rolls the whole step back (resume at `step.from`) or persists the
  /// stamp (resume at `step.to`). Drift's terminal `setSchemaVersion(to)` is a
  /// harmless overwrite of the last stamp on a clean run.
  ///
  /// Steps flagged [usesTableMigration] run their `alterTable`/`TableMigration`
  /// body OUTSIDE the outer transaction — drift toggles `PRAGMA foreign_keys`,
  /// which is a no-op inside a transaction — and stamp immediately after. Those
  /// bodies are already crash-idempotent (drift's copy-and-rename rebuild plus
  /// the table-shape sniff in `ensureFrontingMemberCheckConstraint`).
  /// Test-only fault injection: when set, [_runMigrationSteps] throws just
  /// before applying the step whose target equals this version, simulating a
  /// process death mid-chain. Earlier steps stay committed and stamped, so the
  /// test can assert the resumable user_version and re-open to finish.
  @visibleForTesting
  int? debugFailMigrationStepTo;

  Future<void> _runMigrationSteps(Migrator migrator, int from, int to) async {
    var current = from;
    for (final step in _migrationSteps) {
      if (current != step.from || to < step.to) continue;
      if (debugFailMigrationStepTo == step.to) {
        throw StateError('injected migration failure before step ${step.to}');
      }
      if (step.usesTableMigration) {
        await step.apply(migrator, to);
        await customStatement('PRAGMA user_version = ${step.to}');
      } else {
        await transaction(() async {
          await step.apply(migrator, to);
          await customStatement('PRAGMA user_version = ${step.to}');
        });
      }
      current = step.to;
    }
    if (current != to) {
      throw UnsupportedError(
        'Schema baseline was reset to v1 for the private beta. '
        'Databases from earlier builds (schema v$from) cannot be upgraded. '
        'Use the in-app export, reinstall, then import to migrate data.',
      );
    }
  }

  /// Adds [column] to [table] only when the column is absent, generalizing the
  /// per-step `PRAGMA table_info` guards that v25+/v27+ grew by hand. Lets the
  /// historical migration chain re-run safely against a DB that already carries
  /// the column (a wedged install stamped at a stale version, or a dev/test DB
  /// created at the current schema before its `user_version` was reset).
  Future<void> _addColumnIfAbsent(
    Migrator migrator,
    TableInfo table,
    GeneratedColumn column,
  ) async {
    final cols = await customSelect(
      'PRAGMA table_info(${table.actualTableName})',
    ).get();
    final names = cols.map((r) => r.read<String>('name')).toSet();
    if (!names.contains(column.name)) {
      await migrator.addColumn(table, column);
    }
  }

  /// Creates [table] only when it does not already exist (reusing
  /// [_tableExists]), so the historical chain re-runs safely.
  Future<void> _createTableIfAbsent(Migrator migrator, TableInfo table) async {
    if (!await _tableExists(table.actualTableName)) {
      await migrator.createTable(table);
    }
  }

  /// Enqueue a sync-repair for a rewrite of synced fields.
  ///
  /// The in-migration enqueue is dead post-flatten (the historical steps that
  /// rewrote synced columns are unreachable for real installs), so this is now
  /// driven by the LIVE apply-path orphan coercion via
  /// [enqueueFrontingOrphanRescueRepair] and the runtime blanket backfill.
  /// After boot, [MigrationSyncRepairService] re-reads CURRENT values and emits
  /// real ops.
  ///
  /// `INSERT OR REPLACE` on the `(table_name, entity_id, reason)` PK makes the
  /// enqueue idempotent: a re-entry coalesces onto the same row rather than
  /// duplicating. [fields] stores only the field NAMES — values are re-read at
  /// drain time so a later user edit is never clobbered with stale data.
  Future<void> _enqueueSyncRepair(
    String table,
    Iterable<String> entityIds,
    List<String> fields,
    String reason,
  ) async {
    // The queue is created at the top of onUpgrade and via createAll, so it is
    // present on every path that rewrites a synced column. Guard the renumbered
    // dev/test-DB edge (stamped at the current version, onUpgrade never ran) so
    // a rescue enqueue never aborts the surrounding migration or apply.
    if (!await _tableExists('sync_migration_repairs')) return;
    final fieldsJson = jsonEncode(fields);
    final enqueuedAt = DateTime.now().millisecondsSinceEpoch;
    for (final entityId in entityIds) {
      await customStatement(
        'INSERT OR REPLACE INTO sync_migration_repairs '
        '(table_name, entity_id, field_names_json, reason, enqueued_at) '
        'VALUES (?, ?, ?, ?, ?)',
        [table, entityId, fieldsJson, reason, enqueuedAt],
      );
    }
  }

  /// Enqueue the sync-repairs for an orphan fronting session that the
  /// remote-apply path coerced onto the Unknown sentinel. Public so
  /// [DriftSyncAdapter] can durably record the coercion inside the apply
  /// transaction; the drain re-reads the row, consults the TombstoneGate,
  /// and emits the member_id/pluralkit_uuid update plus the sentinel create as
  /// real ops once the engine is healthy. Coalesces with the migration rescue
  /// via the shared `(table, entity, reason)` PK.
  Future<void> enqueueFrontingOrphanRescueRepair(String sessionId) async {
    await _enqueueSyncRepair(
      'fronting_sessions',
      [sessionId],
      const ['member_id', 'pluralkit_uuid'],
      kFrontingOrphanRescueRepairReason,
    );
    await _enqueueSyncRepair(
      'members',
      [unknownSentinelMemberId],
      const ['__create__'],
      kFrontingOrphanRescueRepairReason,
    );
  }

  /// Whether the per-member fronting CHECK (`session_type != 0 OR member_id IS
  /// NOT NULL`) is installed — i.e. the DB is at v14+ shape. The remote-apply
  /// normalization gates the orphan coercion on this, so a pre-v14 DB (CHECK
  /// not yet installed) still applies a null-member session unchanged.
  Future<bool> isFrontingMemberCheckInstalled() async {
    final res = await customSelect('''
      SELECT sql FROM sqlite_master
      WHERE type = 'table' AND name = 'fronting_sessions'
    ''').get();
    if (res.isEmpty) return false;
    final sql = res.first.read<String?>('sql') ?? '';
    return RegExp(_frontingMemberCheckClausePattern).hasMatch(sql);
  }

  /// Test-only view of the `(from, to)` boundaries of every migration step, so
  /// the idempotency sweep can parameterize over the chain without reaching
  /// into the private step list.
  @visibleForTesting
  List<(int, int)> get debugMigrationStepBounds =>
      _migrationSteps.map((s) => (s.from, s.to)).toList(growable: false);

  /// Ordered, data-driven migration chain. Each step is wrapped in its own
  /// transaction by [_runMigrationSteps], which stamps `PRAGMA user_version`
  /// to the step target inside that transaction — so an interrupted upgrade
  /// either fully rolls a step back (resume at `from`) or durably persists the
  /// stamp (resume at `to`). Drift does NOT wrap onUpgrade in a transaction, so
  /// this is the only thing that makes the chain crash-safe. Every step body
  /// is idempotent (`_addColumnIfAbsent` / `_createTableIfAbsent` / `IF NOT
  /// EXISTS` / re-runnable DML) so an already-stamped or already-applied step
  /// is a no-op on re-entry.
  List<_MigrationStep> get _migrationSteps => [
    _MigrationStep(
      from: 1,
      to: 2,
      apply: (migrator, to) async {
        await _addColumnIfAbsent(
          migrator,
          memberGroupEntries,
          memberGroupEntries.pkGroupUuid,
        );
        await _addColumnIfAbsent(
          migrator,
          memberGroupEntries,
          memberGroupEntries.pkMemberUuid,
        );
        await _addColumnIfAbsent(migrator, memberGroups, memberGroups.syncSuppressed);
        await _addColumnIfAbsent(
          migrator,
          memberGroups,
          memberGroups.suspectedPkGroupUuid,
        );
        await _createTableIfAbsent(migrator, pkGroupSyncAliases);
        await _createTableIfAbsent(migrator, pkGroupEntryDeferredSyncOps);
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
      },
    ),
    _MigrationStep(
      from: 2,
      to: 3,
      apply: (migrator, to) async {
        await _addColumnIfAbsent(
          migrator,
          systemSettingsTable,
          systemSettingsTable.pkGroupSyncV2Enabled,
        );
      },
    ),
    _MigrationStep(
      from: 3,
      to: 4,
      apply: (migrator, to) async {
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
      },
    ),
    _MigrationStep(
      from: 4,
      to: 5,
      apply: (migrator, to) async {
        await _recreateMemberGroupPkUniqueIndex();
      },
    ),
    _MigrationStep(
      from: 5,
      to: 6,
      apply: (migrator, to) async {
        await _addColumnIfAbsent(migrator, members, members.pkBannerUrl);
      },
    ),
    _MigrationStep(
      from: 6,
      to: 7,
      apply: (migrator, to) async {
        // Phase 1: per-member fronting refactor — additive schema only.
        // Old columns (co_fronter_ids, pk_member_ids_json, comments.session_id)
        // stay in place; they are dropped in v8 cleanup.
        //
        // _runMigrationSteps wraps this whole body plus its user_version stamp
        // in one transaction, so a failure mid-step rolls the partial v7 schema
        // back to v6 — the inline transaction this block used to open is folded
        // into the runner.
          // New column: members.is_always_fronting (§2.3)
          await _addColumnIfAbsent(migrator, members, members.isAlwaysFronting);

          // New column: system_settings.pending_fronting_migration_mode (§4.1)
          // Column default is 'complete' (fresh-install semantics); immediately
          // upsert the singleton row with 'notStarted' so that users upgrading
          // from v6 see the migration modal.
          //
          // We use INSERT ... ON CONFLICT DO UPDATE rather than a plain UPDATE
          // because a test (or a very early-lifecycle production DB) might open
          // without ever calling getSettings() first, leaving the table empty.
          // The upsert creates the row when absent and updates it when present.
          await _addColumnIfAbsent(
          migrator,
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
          await _addColumnIfAbsent(
          migrator,
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
          await _addColumnIfAbsent(
          migrator,
            pluralKitSyncState,
            pluralKitSyncState.switchCursorTimestamp,
          );
          await _addColumnIfAbsent(
          migrator,
            pluralKitSyncState,
            pluralKitSyncState.switchCursorId,
          );

      },
    ),
    _MigrationStep(
      from: 7,
      to: 8,
      apply: (migrator, to) async {
        // Phase 1B: fronting preferences (docs/plans/fronting-preferences-1B.md).
        // Three new synced settings on `system_settings`. Purely additive;
        // no row-level data migration — Drift's column defaults supply
        // `combinedPeriods` (0) / `additive` (0) / `additive` (0) for any
        // pre-existing row.
        await _addColumnIfAbsent(
          migrator,
          systemSettingsTable,
          systemSettingsTable.frontingListViewMode,
        );
        await _addColumnIfAbsent(
          migrator,
          systemSettingsTable,
          systemSettingsTable.addFrontDefaultBehavior,
        );
        await _addColumnIfAbsent(
          migrator,
          systemSettingsTable,
          systemSettingsTable.quickFrontDefaultBehavior,
        );
      },
    ),
    _MigrationStep(
      from: 8,
      to: 9,
      apply: (migrator, to) async {
        // PluralKit file-origin fronting metadata. Additive nullable columns:
        // existing API/native/SP rows keep nulls, while future file-origin
        // imports can store a deterministic source switch key without
        // overloading `pluralkit_uuid`.
        await _addColumnIfAbsent(
          migrator,
          frontingSessions,
          frontingSessions.pkImportSource,
        );
        await _addColumnIfAbsent(
          migrator,
          frontingSessions,
          frontingSessions.pkFileSwitchId,
        );
      },
    ),
    _MigrationStep(
      from: 9,
      to: 10,
      apply: (migrator, to) async {
        // Member profile headers. Prism-owned headers and cached PluralKit
        // banners are stored as encrypted synced member blobs.
        await _addColumnIfAbsent(migrator, members, members.profileHeaderSource);
        await _addColumnIfAbsent(migrator, members, members.profileHeaderLayout);
        await _addColumnIfAbsent(migrator, members, members.profileHeaderImageData);
        await _addColumnIfAbsent(migrator, members, members.pkBannerImageData);
        await _addColumnIfAbsent(migrator, members, members.pkBannerCachedUrl);
        // The historical `UPDATE members SET profile_header_source = 0 ...
        // WHERE pk_banner_image_data IS NOT NULL` is removed as a provable
        // no-op — `pk_banner_image_data` is added (all-NULL) in this same step,
        // so the predicate never matches any pre-existing row. Dropping it
        // avoids enqueuing a sync repair for a synced column that never changed.
      },
    ),
    _MigrationStep(
      from: 10,
      to: 11,
      apply: (migrator, to) async {
        // Per-profile banner visibility. Source/layout stay configured while
        // hidden so users can temporarily suppress a banner without losing it.
        await _addColumnIfAbsent(migrator, members, members.profileHeaderVisible);
      },
    ),
    _MigrationStep(
      from: 11,
      to: 12,
      apply: (migrator, to) async {
        await _addColumnIfAbsent(migrator, members, members.nameStyleFont);
        await _addColumnIfAbsent(migrator, members, members.nameStyleBold);
        await _addColumnIfAbsent(migrator, members, members.nameStyleItalic);
        await _addColumnIfAbsent(migrator, members, members.nameStyleColorMode);
        await _addColumnIfAbsent(migrator, members, members.nameStyleColorHex);
      },
    ),
    _MigrationStep(
      from: 12,
      to: 13,
      apply: (migrator, to) async {
        // v13 briefly introduced a target_time range index for the abandoned
        // timestamp-anchored comment model. The restored v16 schema keeps
        // comments attached to session_id, so there is no v13 DDL left to
        // apply for fresh step-through upgrades.
      },
    ),
    _MigrationStep(
      from: 13,
      to: 14,
      usesTableMigration: true,
      apply: (migrator, to) async {
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
      },
    ),
    _MigrationStep(
      from: 14,
      to: 15,
      apply: (migrator, to) async {
        // Member Boards schema introduction.
        //
        // 1. New entity table: member_board_posts.
        // 2. New column on members: board_last_read_at (inbox HWM read state).
        // 3. New columns on system_settings: boards_enabled + sp_boards_backfilled_at.
        // 4–6. Three indexes covering the Inbox, Public, and author queries.
        //
        // Purely additive — no row-level data migration. All new columns have
        // safe defaults (null / false). _runMigrationSteps provides the outer
        // transaction + user_version stamp; this step adds no DDL of its own
        // that needs a nested one.
        await _createTableIfAbsent(migrator, memberBoardPosts);
        await _addColumnIfAbsent(migrator, members, members.boardLastReadAt);
        await _addColumnIfAbsent(
          migrator,
          systemSettingsTable,
          systemSettingsTable.boardsEnabled,
        );
        await _addColumnIfAbsent(
          migrator,
          systemSettingsTable,
          systemSettingsTable.spBoardsBackfilledAt,
        );
        await _createMemberBoardPostIndexes();
      },
    ),
    _MigrationStep(
      from: 15,
      to: 16,
      apply: (migrator, to) async {
        await _rebuildFrontSessionCommentsSessionAttached();
      },
    ),
    _MigrationStep(
      from: 16,
      to: 17,
      apply: (migrator, to) async {
        await _addColumnIfAbsent(
          migrator,
          systemSettingsTable,
          systemSettingsTable.autoPromoteLongFrontingSessions,
        );
      },
    ),
    _MigrationStep(
      from: 17,
      to: 18,
      apply: (migrator, to) async {
        // Members tab display preferences. Collapsed before the 0.8.0 release:
        // these were briefly developed as v18-v20, but no public build shipped
        // with those intermediate schema versions.
        await _addColumnIfAbsent(
          migrator,
          systemSettingsTable,
          systemSettingsTable.membersListViewMode,
        );
        await _addColumnIfAbsent(
          migrator,
          systemSettingsTable,
          systemSettingsTable.membersGroupedDefaultState,
        );
        await _addColumnIfAbsent(
          migrator,
          systemSettingsTable,
          systemSettingsTable.membersFolderMemberVisibility,
        );
        await _addColumnIfAbsent(
          migrator,
          systemSettingsTable,
          systemSettingsTable.membersShowFrontButtons,
        );
        await _addColumnIfAbsent(
          migrator,
          systemSettingsTable,
          systemSettingsTable.membersFrontButtonBehavior,
        );
        await _addColumnIfAbsent(
          migrator,
          systemSettingsTable,
          systemSettingsTable.membersShowPronouns,
        );
      },
    ),
    _MigrationStep(
      from: 18,
      to: 19,
      apply: (migrator, to) async {
        // 0.8.1 production flatten: all schema additions since 0.8.0 ship as
        // one v18→v19 migration because no public build used the intermediate
        // dev-only versions.
        //
        // Rebuild chat_messages_fts with prefix='2 3 4' so prefix-match
        // queries (every chat search) resolve in a single seek per term
        // instead of a dictionary range scan. The runner's per-step
        // transaction covers the drop+rebuild atomically, so a kill mid-step
        // never leaves search broken between the DROP and the next rebuild.
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
          await _addColumnIfAbsent(
          migrator,
            memberGroupEntries,
            memberGroupEntries.pendingPkOp,
          );
          await _addColumnIfAbsent(migrator, members, members.pluralkitDisplayName);
      },
    ),
    _MigrationStep(
      from: 19,
      to: 20,
      apply: (migrator, to) async {
        // Bio markdown defaults: flip column default to true and bring any
        // existing `false` per-member rows along so the new "markdown on by
        // default" behavior is consistent across the whole DB.  Users who
        // want it off get the new global `bio_markdown_enabled` switch (or
        // can flip the per-member toggle back per bio).
        await _addColumnIfAbsent(
          migrator,
          systemSettingsTable,
          systemSettingsTable.bioMarkdownEnabled,
        );
        // Rewrites a synced column, but this historical step is unreachable for
        // real installs post-flatten (they jump v32->v38), so the
        // in-migration repair enqueue is dead here; the one-time blanket
        // backfill in MigrationSyncRepairService converges any diverged install.
        await customStatement(
          'UPDATE members SET markdown_enabled = 1 WHERE markdown_enabled = 0',
        );
      },
    ),
    _MigrationStep(
      from: 20,
      to: 21,
      apply: (migrator, to) async {
        // Direction-first setup: add direction_confirmed to track whether the
        // user has picked a sync direction before the first sync runs.
        // Default false so fresh installs and mid-setup users see the wizard.
        // Backfill: existing fully-set-up users (mapping_acknowledged=1) have
        // already implicitly accepted a direction, so flip them to true so
        // they land on the steady-state screen after upgrading.
        await _addColumnIfAbsent(
          migrator,
          pluralKitSyncState,
          pluralKitSyncState.directionConfirmed,
        );
        await customStatement(
          'UPDATE plural_kit_sync_state '
          'SET direction_confirmed = 1 '
          'WHERE mapping_acknowledged = 1',
        );
      },
    ),
    _MigrationStep(
      from: 21,
      to: 25,
      apply: (migrator, to) async {
        // 0.9.0 production flatten: all schema additions since 0.8.4 ship as
        // one v21→v25 migration because no public build used the intermediate
        // dev-only versions.
          // Group sort state. Backfill orders entries by SQLite `rowid` as a
          // best-effort proxy for insertion order — no user has ever relied on
          // a persistent within-group order before this migration. Dart loop
          // instead of `ROW_NUMBER()` because non-INTEGER-PK rowids "might
          // change" (https://www.sqlite.org/rowidtable.html).
          await _addColumnIfAbsent(migrator, memberGroups, memberGroups.sortState);

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
          await _addColumnIfAbsent(
          migrator,
            systemSettingsTable,
            systemSettingsTable.paletteSource,
          );
          await _addColumnIfAbsent(
          migrator,
            systemSettingsTable,
            systemSettingsTable.paletteSeedColorHex,
          );
          await _addColumnIfAbsent(
          migrator,
            systemSettingsTable,
            systemSettingsTable.paletteMood,
          );
          await _addColumnIfAbsent(
          migrator,
            systemSettingsTable,
            systemSettingsTable.paletteContrast,
          );
          // palette_source is synced, but no repair is enqueued — this is
          // a deterministic projection of the already-synced theme_style, so
          // paired devices converge by construction (each applies the same flip
          // on the same incoming theme_style). Only a snapshot-joiner that never
          // saw theme_style change is theoretically at risk; the snapshot import
          // path owns that, not the migration chain.
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
          await _addColumnIfAbsent(
          migrator,
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
          // The everyone-group rewrites above touch synced columns, but this
          // historical step is unreachable post-flatten; the runtime blanket
          // backfill + GroupChatVisibilitySyncReemitService converge peers.
      },
    ),
    _MigrationStep(
      from: 25,
      to: 26,
      apply: (migrator, to) async {
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
          await _addColumnIfAbsent(migrator, memberGroups, memberGroups.avatarImageData);
        }
      },
    ),
    _MigrationStep(
      from: 26,
      to: 27,
      apply: (migrator, to) async {
        // Timestamp storage moves from seconds to milliseconds.
        await customStatement(
          'UPDATE chat_messages SET timestamp = timestamp * 1000 '
          'WHERE timestamp < 100000000000',
        );
        if (!await _tableExists('app_preference_values')) {
          await _createTableIfAbsent(migrator, appPreferenceValues);
        }
        if (!await _tableExists('member_profile_preference_values')) {
          await _createTableIfAbsent(migrator, memberProfilePreferenceValues);
        }
        await _createPreferenceValueIndexes();
      },
    ),
    _MigrationStep(
      from: 27,
      to: 28,
      apply: (migrator, to) async {
        // Idempotent — dev/test seeders may already have the columns.
        final cols = await customSelect(
          'PRAGMA table_info(custom_fields)',
        ).get();
        final names = cols.map((r) => r.read<String>('name')).toSet();
        if (!names.contains('field_type_id')) {
          await _addColumnIfAbsent(migrator, customFields, customFields.fieldTypeId);
        }
        if (!names.contains('parent_field_id')) {
          await _addColumnIfAbsent(migrator, customFields, customFields.parentFieldId);
        }
        if (!names.contains('type_config_json')) {
          await _addColumnIfAbsent(migrator, customFields, customFields.typeConfigJson);
        }
        // Backfill field_type_id from the existing int for back-compat.
        // Mapping mirrors custom_field_mapper.dart:12 (CustomFieldType enum order
        // text=0, color=1, date=2, longText=3) — keep in lockstep.
        // field_type_id is synced, but no repair is enqueued — it is a
        // deterministic projection of the already-synced field_type, so paired
        // devices converge by construction (same CASE on the same incoming
        // field_type). Only a snapshot-joiner is theoretically at risk; the
        // snapshot import path owns that, not the migration chain.
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
      },
    ),
    _MigrationStep(
      from: 28,
      to: 29,
      apply: (migrator, to) async {
        final cols = await customSelect('PRAGMA table_info(members)').get();
        final names = cols.map((r) => r.read<String>('name')).toSet();
        if (!names.contains('pk_avatar_cached_url')) {
          await _addColumnIfAbsent(migrator, members, members.pkAvatarCachedUrl);
        }
      },
    ),
    _MigrationStep(
      from: 29,
      to: 30,
      apply: (migrator, to) async {
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
          await _addColumnIfAbsent(
          migrator,
            systemSettingsTable,
            systemSettingsTable.membersShowGroups,
          );
        }

        final mediaNames = (await customSelect(
          'PRAGMA table_info(media_attachments)',
        ).get()).map((r) => r.read<String>('name')).toSet();
        if (!mediaNames.contains('member_id')) {
          await _addColumnIfAbsent(migrator, mediaAttachments, mediaAttachments.memberId);
        }
        if (!mediaNames.contains('tag')) {
          await _addColumnIfAbsent(migrator, mediaAttachments, mediaAttachments.tag);
        }
      },
    ),
    _MigrationStep(
      from: 30,
      to: 31,
      usesTableMigration: true,
      apply: (migrator, to) async {
        await migrator.alterTable(
          TableMigration(
            members,
            columnTransformer: {members.age: members.age.cast<String>()},
            // Columns added AFTER this v31 recreate don't exist on the old table
            // when a v1→current chain reaches this step, so drift must populate
            // them from default, not copy. createPushStartedAt (v40) is one.
            newColumns: [members.createPushStartedAt],
          ),
        );
      },
    ),
    _MigrationStep(
      from: 31,
      to: 32,
      apply: (migrator, to) async {
        // archived_for_everyone — convo-level archive flag. Idempotent:
        // dev/test DBs created at the current schema may already have it.
        final convoNames = (await customSelect(
          'PRAGMA table_info(conversations)',
        ).get()).map((r) => r.read<String>('name')).toSet();
        if (!convoNames.contains('archived_for_everyone')) {
          await _addColumnIfAbsent(
          migrator,
            conversations,
            conversations.archivedForEveryone,
          );
        }
      },
    ),
    _MigrationStep(
      from: 32,
      to: 37,
      apply: (migrator, to) async {
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

        // member_group_entries.created_at — local-only creation stamp for the
        // PK reconcile recency-grace window (2026-06 PK audit). NOT in
        // prismSyncSchema. Idempotent: dev/test DBs created at the current
        // schema may already carry it. Existing rows backfill to "now" so a
        // device that upgrades mid-flight does not treat its entire pre-fix
        // backlog as ancient and reconcile-delete it on the first pull; the
        // grace window simply protects everything for one window post-upgrade,
        // which is the fail-safe direction.
        final entryCols = (await customSelect(
          'PRAGMA table_info(member_group_entries)',
        ).get()).map((r) => r.read<String>('name')).toSet();
        if (!entryCols.contains('created_at')) {
          await _addColumnIfAbsent(
          migrator,
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
      },
    ),
    _MigrationStep(
      from: 37,
      to: 38,
      apply: (migrator, to) async {
        // 0.12.x -> 0.13.0 production flatten: all schema additions since v37
        // ship as one v37->v38 migration because no public build used the
        // intermediate dev-only versions. Each part is independently idempotent:
        // re-running on a DB that already created at v38, or retrying after a
        // partial failure, is safe.

        // Legacy repair (maintainer decision
        // 2026-06-11): clear EVERY pending PluralKit switch-deletion stamp.
        //
        // The canonicalization-destruction bug shipped on deployed 0.12.x
        // installs stamped delete_intent_epoch on PK-linked fronting-session
        // tombstones it created as "local cleanup". Those stamps are
        // indistinguishable from genuine user delete intents, and the new
        // cascade guard cannot protect leaver-only switches — so on upgrade
        // they would fire real PluralKit switch DELETEs against the user's
        // external account (getDeletedLinkedSessions selects exactly
        // is_deleted=1 AND pluralkit_uuid IS NOT NULL AND
        // delete_intent_epoch IS NOT NULL). One-time, idempotent
        // (re-runnable): drop the intent epoch and any in-flight push stamp
        // on every such row. Users must re-delete explicitly; at most queued
        // intentional deletions are lost, which is the fail-safe direction.
        await customStatement(
          'UPDATE fronting_sessions '
          'SET delete_intent_epoch = NULL, delete_push_started_at = NULL '
          'WHERE is_deleted = 1 '
          '  AND pluralkit_uuid IS NOT NULL '
          '  AND delete_intent_epoch IS NOT NULL',
        );

        // member_groups.sync_generation + member_group_entries.sync_generation
        // — LOCAL-ONLY incarnation counters for the absorbing-tombstone-
        // revive layer. NOT in prismSyncSchema; each
        // device tracks its own live incarnation. Idempotent: dev/test
        // DBs created at the current schema may already carry the columns, and
        // a partial-failure retry must be safe. Existing rows default to 0 (the
        // legacy id), which is correct — nothing has been re-incarnated yet.
        final groupCols = (await customSelect(
          'PRAGMA table_info(member_groups)',
        ).get()).map((r) => r.read<String>('name')).toSet();
        if (!groupCols.contains('sync_generation')) {
          await _addColumnIfAbsent(migrator, memberGroups, memberGroups.syncGeneration);
        }
        final genEntryCols = (await customSelect(
          'PRAGMA table_info(member_group_entries)',
        ).get()).map((r) => r.read<String>('name')).toSet();
        if (!genEntryCols.contains('sync_generation')) {
          await migrator.addColumn(
            memberGroupEntries,
            memberGroupEntries.syncGeneration,
          );
        }

        // pk_identity_sync_aliases — the generic PK-identity redirect alias
        // table for members + fronting_sessions. Local-only Drift table; no
        // wire/protocol change. Idempotent: createTableIfAbsent guards a
        // partial-failure retry and dev/test DBs created at the current schema.
        final tables = (await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        ).get()).map((r) => r.read<String>('name')).toSet();
        if (!tables.contains('pk_identity_sync_aliases')) {
          await _createTableIfAbsent(migrator, pkIdentitySyncAliases);
        }
        await _createPkIdentitySyncIndexes();

        // sync_op_outbox — the durable transactional outbox for CRDT emissions.
        // Local-only Drift table; no wire/protocol change. Folded into the
        // v32->v38 flatten because no public build used the intermediate dev
        // versions.
        if (!tables.contains('sync_op_outbox')) {
          await migrator.createTable(syncOpOutbox);
        }

        // Stale-self-alias purge. The v3->v4 cleanup only deleted self-aliases
        // whose member_groups row was active (is_deleted = 0) AND
        // whose pluralkit_uuid still matched, so it missed rows soft-deleted at
        // upgrade time and rows whose uuid was NULLed by deleteGroup. Those
        // surviving self-aliases make the emitters tombstone peers' ACTIVE
        // 'pk-group-<uuid>' rows on every group update. By construction every
        // importing device's own local row id is exactly 'pk-group-' ||
        // pk_group_uuid, so a self-alias is never a legitimate loser alias:
        // delete unconditionally on row state. Idempotent (no-op once purged).
        await customStatement(
          'DELETE FROM pk_group_sync_aliases '
          "WHERE legacy_entity_id = 'pk-group-' || pk_group_uuid",
        );

        // sync_migration_repairs — the durable sync-repair queue for migration
        // rewrites of synced fields. Local-only Drift table; no wire/protocol
        // change. Folded into the v37->v38 flatten leg alongside sync_op_outbox.
        // Idempotent: createTableIfAbsent guards a partial-failure retry
        // and dev/test DBs created at the current schema.
        await _createTableIfAbsent(migrator, syncMigrationRepairs);
      },
    ),
    _MigrationStep(
      from: 38,
      to: 39,
      apply: (migrator, to) async {
        await _addColumnIfAbsent(
          migrator,
          systemSettingsTable,
          systemSettingsTable.memberNameDisplay,
        );
      },
    ),
    _MigrationStep(
      from: 39,
      to: 40,
      apply: (migrator, to) async {
        // Narrow idx_members_pluralkit_id to active rows only: short ids are
        // user-recyclable, so a tombstone holding a recycled short id must not
        // occupy the unique index and block a live member that now owns it. The
        // new predicate is a strict subset of the old, so the recreate can't fail
        // on data valid under the covering index. The uuid index stays covering.
        await customStatement('DROP INDEX IF EXISTS idx_members_pluralkit_id');
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_members_pluralkit_id '
          'ON members(pluralkit_id) '
          'WHERE pluralkit_id IS NOT NULL AND is_deleted = 0',
        );
        // F4: synced create-push coordination lease, mirroring
        // delete_push_started_at, so paired devices don't both POST the same
        // unlinked member to PluralKit.
        await _addColumnIfAbsent(migrator, members, members.createPushStartedAt);
      },
    ),
  ];


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

    // Local-only Drift tables added inside the v32->v38 flatten. A dev DB that
    // already reached v38 through an earlier numbering won't re-run that step
    // (from == to), so create them here if absent. No-op once present.
    final existingTables = (await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    ).get()).map((r) => r.read<String>('name')).toSet();
    Future<void> ensureTable(String name, TableInfo table) async {
      if (!existingTables.contains(name)) {
        await Migrator(this).createTable(table);
      }
    }

    await ensureTable('sync_op_outbox', syncOpOutbox);
    await ensureTable('sync_migration_repairs', syncMigrationRepairs);

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
  /// Members + member_groups indexes have the same shape from v2 onward, EXCEPT
  /// `idx_members_pluralkit_id`, which narrows to active-only (`is_deleted = 0`)
  /// at v40 — short ids are user-recyclable, so a tombstone retaining a recycled
  /// short id must not block a live member that now owns it. The uuid index still
  /// covers tombstones (uuid is stable identity; PK delete-push needs it).
  /// Fronting-sessions indexes differ between v2 (single-column on `pluralkit_uuid`)
  /// and v7 (composite + orphan); each migration path or fresh-install call site
  /// adds the right fronting variant explicitly.  Putting fronting indexes in the
  /// shared helper would crash a v1→v7 upgrade with duplicate `(uuid, NULL)` rows
  /// at the v1→v2 step, before v6→v7 detect-and-refuse can run.
  // Best-effort backstop, also re-run from beforeOpen (F20). `IF NOT EXISTS`
  // skips by NAME, so this heals an ABSENT index but not a wrong-SHAPE one (a
  // same-named covering index from a pre-narrowing branch persists); that
  // residual is a recoverable constraint error, not data loss, so out of scope.
  Future<void> _createPkUniqueIndexes() async {
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_members_pluralkit_uuid '
      'ON members(pluralkit_uuid) WHERE pluralkit_uuid IS NOT NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_members_pluralkit_id '
      'ON members(pluralkit_id) WHERE pluralkit_id IS NOT NULL AND is_deleted = 0',
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
    // The (group_id, member_id) edge uniqueness the apply-layer collapse relies
    // on (idx_member_group_entries_unique) — re-ensured here so the F8/F9 entry
    // resolvers keep their ≤1-row guarantee on a renumbered DB.
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_member_group_entries_unique '
      'ON member_group_entries (group_id, member_id) WHERE is_deleted = 0',
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
    // Interaction with the sentinel gate: if `tombstoneGate` is set and
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
    // Ingress gate: the Unknown sentinel uses a deterministic UUIDv5 id, so if
    // a previously-synced sentinel was deleted, the engine holds an absorbing
    // tombstone for that id. Re-homing orphans onto it and re-creating the
    // member would write into a burned id — a silent fleet-wide no-op on peers
    // and a Rust/Dart divergence locally. The sentinel is NOT minted to a new
    // incarnation; when burned we simply skip the rescue. A null gate (cold
    // migration with no engine) keeps the pre-gate behavior byte-for-byte.
    final gate = tombstoneGate;
    if (gate != null &&
        await gate.isTombstoned('members', unknownSentinelMemberId)) {
      debugPrint(
        '[MIGRATION] skipping Unknown-sentinel orphan rescue before $reason — '
        'sentinel id is tombstoned in the sync engine (burned id).',
      );
      return 0;
    }

    // Capture the orphan ids BEFORE the rewrite so we can enqueue a
    // sync-repair for each. The rewrite mutates synced columns (member_id,
    // pluralkit_uuid) in raw SQL, which emits no CRDT op — so without a repair
    // these rescued sessions would render a missing member on peers and a
    // later remote member_id=NULL write would trip the new CHECK.
    final orphanRows = await customSelect(
      'SELECT id FROM fronting_sessions '
      'WHERE session_type = 0 AND member_id IS NULL AND is_deleted = 0',
    ).get();
    final orphanIds = [for (final r in orphanRows) r.read<String>('id')];

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

    // Enqueue the rescued sessions' member_id/pluralkit_uuid rewrites and a
    // whole-entity create for the sentinel member. The drain re-reads current
    // values and emits real ops once the engine is healthy; it consults the
    // TombstoneGate before emitting the sentinel create, so a burned
    // sentinel id is never written into. INSERT OR REPLACE keeps re-entry
    // idempotent.
    await _enqueueSyncRepair(
      'fronting_sessions',
      orphanIds,
      const ['member_id', 'pluralkit_uuid'],
      kFrontingOrphanRescueRepairReason,
    );
    await _enqueueSyncRepair(
      'members',
      [unknownSentinelMemberId],
      const ['__create__'],
      kFrontingOrphanRescueRepairReason,
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

  /// Lookup index for the generic PK-identity alias fan-out: the delete
  /// emitters query by (entity_table, identity) to plant tombstones under every
  /// legacy id of a merged logical entity.
  Future<void> _createPkIdentitySyncIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_pk_identity_sync_aliases_identity '
      'ON pk_identity_sync_aliases (entity_table, pk_uuid, pk_id, member_id)',
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
  SyncOutboxDao get syncOutboxDao => SyncOutboxDao(this);
  @override
  MemberGroupsDao get memberGroupsDao => MemberGroupsDao(this);
  @override
  PkGroupSyncAliasesDao get pkGroupSyncAliasesDao =>
      PkGroupSyncAliasesDao(this);
  @override
  PkIdentitySyncAliasesDao get pkIdentitySyncAliasesDao =>
      PkIdentitySyncAliasesDao(this);
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

/// One ordered upgrade leg in [AppDatabase]'s migration chain. [apply] runs the
/// step's DDL/DML; [_runMigrationSteps] owns the transaction and the
/// per-step `PRAGMA user_version` stamp. Set [usesTableMigration] for steps
/// whose body calls `alterTable`/`TableMigration` (drift opens its own
/// connection-level work there that cannot run inside an outer transaction).
class _MigrationStep {
  const _MigrationStep({
    required this.from,
    required this.to,
    required this.apply,
    this.usesTableMigration = false,
  });

  final int from;
  final int to;
  final bool usesTableMigration;
  final Future<void> Function(Migrator migrator, int to) apply;
}
