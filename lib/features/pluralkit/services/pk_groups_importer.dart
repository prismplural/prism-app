import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/member_groups_dao.dart';
import 'package:prism_plurality/core/database/sqlite_constraint.dart';
import 'package:prism_plurality/data/mappers/member_group_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/data/utils/sync_datetime.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_repair_run_gate.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';

typedef PkGroupSyncCreateOverride =
    Future<void> Function(
      String table,
      String entityId,
      Map<String, dynamic> fields,
    );
typedef PkGroupSyncUpdateOverride =
    Future<void> Function(
      String table,
      String entityId,
      Map<String, dynamic> fields,
    );
typedef PkGroupSyncDeleteOverride =
    Future<void> Function(String table, String entityId);

/// Result of a single PK-groups import pass.
class PkGroupsImportResult {
  final int groupsInserted;
  final int groupsUpdated;
  final int groupsObserved;
  final int entriesInserted;
  final int entriesRemoved;
  final int entriesDeferred;

  /// Count of groups whose `memberIds` came back as null (privacy / partial
  /// fetch). Surfaces flapping — a high number here means membership reconcile
  /// was intentionally skipped for those groups.
  final int groupsWithUnknownMembership;

  /// Entries that PK's authoritative set omits but were preserved anyway
  /// because they fall inside the H6b recency-grace window (2026-06 PK audit).
  /// Surfaces the fail-safe so a high count is visible rather than silent.
  final int entriesSkippedRecent;

  /// Groups the importer would otherwise have re-created from PK but skipped
  /// because the deterministic row id is a user-deleted tombstone (2026-06 PK
  /// audit M13 — board-delete-resurrection class). Mirrors the session
  /// tombstone-preserved counter pattern.
  final int groupsPreservedAsDeletedTombstone;

  const PkGroupsImportResult({
    this.groupsInserted = 0,
    this.groupsUpdated = 0,
    this.groupsObserved = 0,
    this.entriesInserted = 0,
    this.entriesRemoved = 0,
    this.entriesDeferred = 0,
    this.groupsWithUnknownMembership = 0,
    this.entriesSkippedRecent = 0,
    this.groupsPreservedAsDeletedTombstone = 0,
  });

  PkGroupsImportResult copyWith({
    int? groupsInserted,
    int? groupsUpdated,
    int? groupsObserved,
    int? entriesInserted,
    int? entriesRemoved,
    int? entriesDeferred,
    int? groupsWithUnknownMembership,
    int? entriesSkippedRecent,
    int? groupsPreservedAsDeletedTombstone,
  }) => PkGroupsImportResult(
    groupsInserted: groupsInserted ?? this.groupsInserted,
    groupsUpdated: groupsUpdated ?? this.groupsUpdated,
    groupsObserved: groupsObserved ?? this.groupsObserved,
    entriesInserted: entriesInserted ?? this.entriesInserted,
    entriesRemoved: entriesRemoved ?? this.entriesRemoved,
    entriesDeferred: entriesDeferred ?? this.entriesDeferred,
    groupsWithUnknownMembership:
        groupsWithUnknownMembership ?? this.groupsWithUnknownMembership,
    entriesSkippedRecent: entriesSkippedRecent ?? this.entriesSkippedRecent,
    groupsPreservedAsDeletedTombstone:
        groupsPreservedAsDeletedTombstone ??
        this.groupsPreservedAsDeletedTombstone,
  );

  bool get changedRepairInputs =>
      groupsInserted > 0 ||
      groupsUpdated > 0 ||
      entriesInserted > 0 ||
      entriesRemoved > 0;
}

/// Imports PluralKit groups and memberships into Prism.
///
/// Phase 1 (pull only). Implements the revisions documented in
/// `docs/plans/pk-sp-gaps/03-pk-groups.md`:
///
/// - R1: Authoritative-set diff — membership removals are driven by the PK
///   member UUID set, not by locally-resolved IDs. Unresolved members are
///   deferred, never treated as "missing on PK".
/// - R2: `memberIds == null` means "unknown" → skip removals entirely.
/// - R3: `reattribute(...)` insert-only pass for members that weren't linked
///   at first import.
/// - R5: `overwriteMetadata` — background sync reconciles membership only;
///   metadata (name/description/color/displayName) is only overwritten on
///   explicit user action.
/// - R6: Deterministic entry IDs `sha256(groupUuid\0memberPkUuid)[:16]`.
/// - R7: Identity matching is UUID-only.
/// - R8: Local emoji is never touched on PK pull.
/// - R9: `last_seen_from_pk_at` refreshed for every observed group.
/// - R10: PK-backed groups use deterministic local ids so parallel imports on
///   different devices converge on the same sync entity.
class PkGroupsImporter with SyncRecordMixin {
  final AppDatabase _db;
  final MemberGroupsDao _dao;
  final MemberRepository _memberRepository;
  final ffi.PrismSyncHandle? _syncHandle;
  final PkGroupSyncCreateOverride? _recordCreateOverride;
  final PkGroupSyncUpdateOverride? _recordUpdateOverride;
  final PkGroupSyncDeleteOverride? _recordDeleteOverride;

  /// Push-orchestrator mutex (step 6 of the membership push plan). Mirrors
  /// the cofronter pattern in pluralkit_sync_service: re-entrant calls await
  /// the in-flight push and return its result. Service-instance scope is
  /// fine because the importer is constructed once per sync service via
  /// pluralkit_providers, and providers give us a single instance per
  /// app session.
  Future<PkGroupMembershipPushResult>? _pushInFlight;

  static const _groupTable = 'member_groups';
  static const _entryTable = 'member_group_entries';

  /// Recency grace for destructive PK-removal reconcile (2026-06 PK audit H6b).
  ///
  /// A `member_group_entries` row younger than this window is NEVER
  /// reconcile-deleted, even when PK's authoritative member list omits it.
  /// Rationale: `pending_pk_op` is per-device, so a peer that just received a
  /// CRDT *create* for an add another device hasn't pushed to PK yet would
  /// otherwise treat PK as authoritative and soft-delete the brand-new entry
  /// (then sync a HARD delete back, destroying the originating device's
  /// unpushed `push_add` intent — H6 scenario A). `created_at` is local-only
  /// and set via `clientDefault` at *apply* time, so a sync-applied row is
  /// "recent" on the reconciling device precisely while that race window is
  /// open. 48h is deliberately generous: a genuine PK-side removal of an old
  /// entry still takes effect on the next reconcile after the window lapses,
  /// and removals of fresh entries fail SAFE (the membership survives locally
  /// a little longer) rather than fail DESTRUCTIVE (a real add is lost). The
  /// window only gates the soft-delete pass; inserts and metadata are
  /// unaffected.
  static const removalRecencyGrace = Duration(hours: 48);

  /// Minimum interval between pure `last_seen_from_pk_at` refresh emissions for
  /// a single group (2026-06 PK audit M14a). Without this, every pull emits an
  /// update op for every observed group even when nothing changed, churning the
  /// op log / relay. Real metadata or PK-link changes still emit immediately;
  /// only the lonely "I saw this group again" heartbeat is rate-limited.
  static const lastSeenRefreshInterval = Duration(hours: 24);

  /// Age cap for a permanently-failing group-membership push intent (2026-06 PK
  /// audit M15). The `member_group_entries` pending-op rows have no
  /// `retry_count` column, so we cap by INTENT age — `created_at` is refreshed
  /// whenever a pending op is set, so it reads as "time since the user queued
  /// this intent". A push candidate that keeps 4xx-failing past this window is
  /// marked terminal
  /// and counted in the result rather than retried forever every sync. 7 days
  /// is long enough to ride out a sustained PK outage or a slow user fix, short
  /// enough that a genuinely impossible push (e.g. an unmapped ref that will
  /// never resolve) stops churning the op log within a week.
  static const pushRetryMaxAge = Duration(days: 7);

  PkGroupsImporter({
    required AppDatabase db,
    required MemberRepository memberRepository,
    ffi.PrismSyncHandle? syncHandle,
    PkGroupSyncCreateOverride? recordCreateOverride,
    PkGroupSyncUpdateOverride? recordUpdateOverride,
    PkGroupSyncDeleteOverride? recordDeleteOverride,
  }) : _db = db,
       _dao = db.memberGroupsDao,
       _memberRepository = memberRepository,
       _syncHandle = syncHandle,
       _recordCreateOverride = recordCreateOverride,
       _recordUpdateOverride = recordUpdateOverride,
       _recordDeleteOverride = recordDeleteOverride;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  /// Derive a deterministic `member_group_entries.id` from PK identifiers so
  /// two offline devices produce the same row (see R6).
  static String deriveEntryId(String groupUuid, String memberPkUuid) {
    final digest = sha256.convert(utf8.encode('$groupUuid\u0000$memberPkUuid'));
    // Hex → first 16 chars = 64 bits of entropy.
    return digest.toString().substring(0, 16);
  }

  /// Derive a deterministic local group id from the PK UUID so independent
  /// devices import the same PK group under the same entity id.
  static String deriveGroupId(String groupUuid) => 'pk-group-$groupUuid';

  /// Canonical sync entity id for PK-backed groups.
  static String deriveGroupSyncEntityId(String groupUuid) =>
      'pk-group:$groupUuid';

  @visibleForTesting
  static Map<String, dynamic> groupCreateSyncFields(MemberGroupRow row) {
    return {
      'name': row.name,
      'description': row.description,
      'color_hex': row.colorHex,
      'emoji': row.emoji,
      'display_order': row.displayOrder,
      'parent_group_id': row.parentGroupId,
      'group_type': row.groupType,
      'filter_rules': row.filterRules,
      'created_at': toSyncUtc(row.createdAt),
      'pluralkit_id': row.pluralkitId,
      'pluralkit_uuid': row.pluralkitUuid,
      'last_seen_from_pk_at': toSyncUtcOrNull(row.lastSeenFromPkAt),
      'sort_state': sanitizeSortStateForEmission(
        row.sortState,
        contextId: row.id,
      ),
      'is_deleted': row.isDeleted,
    };
  }

  @visibleForTesting
  static Map<String, dynamic> entrySyncFields({
    required String groupId,
    required String memberId,
    required String pkGroupUuid,
    required String pkMemberUuid,
  }) {
    return {
      'group_id': groupId,
      'member_id': memberId,
      'pk_group_uuid': pkGroupUuid,
      'pk_member_uuid': pkMemberUuid,
      'is_deleted': false,
    };
  }

  /// Import a batch of PK groups.
  ///
  /// When [overwriteMetadata] is false (default for background sync),
  /// existing rows keep their local name/description/color/displayOrder and
  /// only membership is reconciled. When true (explicit re-import / user
  /// action), metadata is replaced with PK's values.
  ///
  /// When [pushClient] is supplied AND [direction] includes push, this device's
  /// pending `pending_pk_op` intents are drained to PluralKit BEFORE the
  /// membership reconcile (2026-06 PK audit H6a). Draining first means the PK
  /// authoritative set the reconcile reads already reflects this device's local
  /// adds/removes, so the destructive removal pass can't soft-delete (and
  /// HARD-delete to peers) an add that simply hadn't reached PK yet. The push
  /// is failure-isolated: a thrown error is swallowed so a transient PK outage
  /// never aborts the pull. Callers that already drive push separately can omit
  /// [pushClient]; passing it is idempotent with the orchestrator's own mutex.
  Future<PkGroupsImportResult> importGroups(
    List<PKGroup> pkGroups, {
    bool overwriteMetadata = false,
    // Default pullOnly preserves current behavior. Step 7 of the plan
    // wires the user's actual sync direction at top-level call sites
    // so push-disabled users skip the destructive reconcile entirely.
    PkSyncDirection direction = PkSyncDirection.pullOnly,
    PluralKitClient? pushClient,
  }) async {
    var result = const PkGroupsImportResult();
    if (pkGroups.isEmpty) return result;
    // Step 4 of docs/plans/pk-group-membership-push.md: pull-side work is
    // gated on direction.pullEnabled. push-side work is the orchestrator's
    // job (step 6) — this function never pushes. On pushOnly/disabled, we
    // skip the entire pull pass: no metadata writes, no last_seen_from_pk_at
    // updates, no destructive reconcile, no inserts.
    if (!direction.pullEnabled) return result;

    // H6a (2026-06 PK audit): drain this device's pending intents to PK FIRST
    // so the authoritative member set we reconcile against already reflects
    // them. MUST be failure-isolated — a push failure must not abort the pull
    // (which would block legitimate inbound PK changes whenever PK is flaky).
    if (pushClient != null && direction.pushEnabled) {
      try {
        await pushPendingGroupOps(pushClient, direction);
      } catch (error) {
        debugPrint(
          '[PK groups] H6a pre-reconcile push failed (non-fatal): $error',
        );
      }
    }

    final syncEnabled = await _pkGroupSyncV2Enabled();

    // Resolve members once up front so we know which PK UUIDs are locally
    // available *right now*. The authoritative set (R1) is the PK list, not
    // this map — the map only tells us which PK UUIDs map to a local row.
    //
    // Filter excluded locals here once so EVERY downstream consumer
    // (`pkUuidToLocalMemberId` build, `_processGroup`, remove path) only sees
    // non-excluded members. Otherwise a single missed call site could
    // re-attribute, push, or remove an excluded local. M14d: the
    // `pluralkit_sync_ignored = 0` filter is pushed into the SQL projection,
    // which also skips loading avatar blobs.
    final allMembers = await _loadReconcileMembers();
    final pkUuidToLocalMemberId = <String, String>{};
    for (final m in allMembers) {
      final pkUuid = m.pluralkitUuid?.trim();
      if (pkUuid != null && pkUuid.isNotEmpty) {
        pkUuidToLocalMemberId[pkUuid] = m.id;
      }
    }

    final now = DateTime.now();

    for (final pk in pkGroups) {
      result = result.copyWith(groupsObserved: result.groupsObserved + 1);

      final existing = await _dao.findByPluralkitUuid(pk.uuid);
      final groupLocalId = existing?.id ?? deriveGroupId(pk.uuid);

      if (existing == null) {
        // M13 (2026-06 PK audit): resurrection guard. Without this check the
        // upsert below would revive a user-deleted group's row
        // (is_deleted=false@fresh-HLC) AND re-create every entry, syncing
        // creates back to peers — the board-delete-resurrection UX class.
        // Two lookups (wave-3 verifier issue 3):
        //   1. By the deterministic `pk-group-<uuid>` row id — catches
        //      importer-created groups even when the tombstone's
        //      `pluralkit_uuid` was nulled (every deleteGroup before the
        //      wave-3 fix did that).
        //   2. By UUID including deleted — catches groups adopted under
        //      their ORIGINAL row id (repair's linkGroupToPluralkitUuid,
        //      pre-deterministic imports), whose tombstones the id lookup
        //      can't see. Works because deleteGroup now KEEPS the uuid on
        //      the tombstone (the partial unique index only covers active
        //      rows). The active-only lookup above already returned null, so
        //      any hit here is by construction a tombstone.
        // Residual: a LEGACY non-deterministic-id tombstone whose uuid was
        // already nulled by the old deleteGroup is invisible to both lookups
        // and can still resurrect once. Its replacement row then dies under
        // guard #1 or #2 on any later deletion.
        // PK has no group-deletion push yet, so "deleted locally, stays
        // deleted locally" is the honest behavior; we surface a count so the
        // skip is visible, not silent.
        var tombstone = await _dao.getGroupByIdIncludingDeleted(groupLocalId);
        if (tombstone == null || !tombstone.isDeleted) {
          // Id lookup yielded nothing deleted (no row, or an active unlinked
          // row squatting the deterministic id) — still consult the uuid.
          tombstone = await _dao.findByPluralkitUuidIncludingDeleted(pk.uuid);
        }
        if (tombstone != null && tombstone.isDeleted) {
          result = result.copyWith(
            groupsPreservedAsDeletedTombstone:
                result.groupsPreservedAsDeletedTombstone + 1,
          );
          debugPrint(
            '[PK groups] M13 preserve: group ${pk.uuid} is a user-deleted '
            'tombstone (${tombstone.id}); skipping re-create + entry revival.',
          );
          continue;
        }

        // Insert new row. Always writes metadata — there is nothing local to
        // preserve. Local emoji stays null (R8): PK's `icon` is a URL, not an
        // emoji.
        final displayOrder = await _dao.nextDisplayOrder(null);
        // Preserved across PK pulls — never overwrite avatar_image_data without an explicit migration plan.
        await _dao.upsertGroup(
          MemberGroupsCompanion.insert(
            id: groupLocalId,
            name: pk.displayName ?? pk.name,
            description: Value(pk.description),
            colorHex: Value(pk.color == null ? null : '#${pk.color}'),
            emoji: const Value(null),
            displayOrder: Value(displayOrder),
            createdAt: now,
            isDeleted: const Value(false),
            pluralkitId: Value(pk.id),
            pluralkitUuid: Value(pk.uuid),
            lastSeenFromPkAt: Value(now),
          ),
        );
        final createdRow = await _loadGroupRow(groupLocalId);
        if (syncEnabled) {
          await _emitCreate(
            _groupTable,
            deriveGroupSyncEntityId(pk.uuid),
            groupCreateSyncFields(createdRow),
          );
          await _emitLegacyAliasDeletesForPkGroup(pk.uuid);
        }
        result = result.copyWith(groupsInserted: result.groupsInserted + 1);
      } else {
        // Existing row. M14a (2026-06 PK audit): the pre-fix code wrote AND
        // emitted last_seen_from_pk_at for EVERY group on EVERY pull, churning
        // the op log / relay. Now:
        //   - PK-link columns (pluralkit_id / pluralkit_uuid) emit only when
        //     they actually change.
        //   - A pure last_seen_from_pk_at heartbeat refreshes (and emits) at
        //     most once per `lastSeenRefreshInterval` (24h) per group.
        //   - overwriteMetadata still forces a metadata write + emit.
        // Never touch emoji (R8). avatar_image_data preserved across PK pulls.
        final identityChanged =
            existing.pluralkitId != pk.id ||
            existing.pluralkitUuid != pk.uuid;
        final lastSeen = existing.lastSeenFromPkAt;
        final lastSeenRefreshDue =
            lastSeen == null ||
            now.difference(lastSeen) >= lastSeenRefreshInterval;
        // Write last_seen locally when its refresh is due OR identity changed
        // (so the row reflects the fresh observation); otherwise leave the
        // stored value alone to avoid an emit-worthy field flip every pull.
        final writeLastSeen = lastSeenRefreshDue || identityChanged;

        final updates = MemberGroupsCompanion(
          id: Value(existing.id),
          lastSeenFromPkAt: writeLastSeen
              ? Value(now)
              : const Value.absent(),
          pluralkitId: identityChanged
              ? Value(pk.id)
              : const Value.absent(),
          pluralkitUuid: identityChanged
              ? Value(pk.uuid)
              : const Value.absent(),
          name: overwriteMetadata
              ? Value(pk.displayName ?? pk.name)
              : const Value.absent(),
          description: overwriteMetadata
              ? Value(pk.description)
              : const Value.absent(),
          colorHex: overwriteMetadata
              ? Value(pk.color == null ? null : '#${pk.color}')
              : const Value.absent(),
        );
        // Only touch the DB when something is actually changing.
        final hasLocalWrite =
            writeLastSeen || identityChanged || overwriteMetadata;
        if (hasLocalWrite) {
          await (_db.update(
            _db.memberGroups,
          )..where((g) => g.id.equals(existing.id))).write(updates);
        }
        final updatedRow = hasLocalWrite
            ? await _loadGroupRow(existing.id)
            : existing;

        if (syncEnabled) {
          // Mirrors the columns the companion above writes — see
          // `lib/data/sync/field_diff.dart` on why update patches stay narrow.
          // Build the patch from ONLY the fields that actually changed so an
          // unchanged group emits nothing (M14a). A lone last_seen heartbeat is
          // gated by the 24h interval above (writeLastSeen).
          final changedFields = <String, dynamic>{
            if (writeLastSeen)
              'last_seen_from_pk_at': toSyncUtcOrNull(
                updatedRow.lastSeenFromPkAt,
              ),
            if (identityChanged) ...{
              'pluralkit_id': updatedRow.pluralkitId,
              'pluralkit_uuid': updatedRow.pluralkitUuid,
            },
            if (overwriteMetadata) ...{
              'name': updatedRow.name,
              'description': updatedRow.description,
              'color_hex': updatedRow.colorHex,
            },
          };
          if (changedFields.isNotEmpty) {
            await _emitUpdate(
              _groupTable,
              deriveGroupSyncEntityId(pk.uuid),
              changedFields,
            );
            // Legacy alias deletes are emit-once-then-cleaned (M14b); only
            // attempt them when we are already emitting a real change.
            await _emitLegacyAliasDeletesForPkGroup(pk.uuid);
          }
        }
        if (overwriteMetadata) {
          result = result.copyWith(groupsUpdated: result.groupsUpdated + 1);
        }
      }

      // Membership reconciliation — R1 + R2.
      if (pk.memberIds == null) {
        // Unknown → don't touch entries at all.
        result = result.copyWith(
          groupsWithUnknownMembership: result.groupsWithUnknownMembership + 1,
        );
        debugPrint(
          '[PK groups] unknown membership for group ${pk.uuid}; skipping '
          'reconciliation.',
        );
        continue;
      }

      final delta = await _reconcileMembership(
        groupLocalId: groupLocalId,
        groupPkUuid: pk.uuid,
        authoritativePkMemberUuids: pk.memberIds!,
        allMembers: allMembers,
        pkUuidToLocalMemberId: pkUuidToLocalMemberId,
        insertOnly: false,
        now: now,
      );
      if (syncEnabled) {
        await _emitMembershipSync(delta);
      }
      result = result.copyWith(
        entriesInserted: result.entriesInserted + delta.entriesInserted,
        entriesRemoved: result.entriesRemoved + delta.entriesRemoved,
        entriesDeferred: result.entriesDeferred + delta.entriesDeferred,
        entriesSkippedRecent:
            result.entriesSkippedRecent + delta.entriesSkippedRecent,
      );
    }

    await _markRepairDirtyIfNeeded(result);
    return result;
  }

  /// R3 — insert-only re-attribution pass. Called after member mapping has
  /// applied so PK UUIDs that were previously unknown can now be resolved.
  /// Never removes entries. Always pull-only by construction (insertOnly).
  /// The [direction] param is accepted for symmetry with [importGroups] but
  /// must include pull (asserted); push is never invoked from here. Per
  /// docs/plans/pk-group-membership-push.md step 4 / v3-patches-2 #6.
  Future<PkGroupsImportResult> reattribute(
    PluralKitClient client, {
    PkSyncDirection direction = PkSyncDirection.pullOnly,
  }) async {
    if (!direction.pullEnabled) return const PkGroupsImportResult();
    final pkGroups = await client.getGroups(withMembers: true);
    if (pkGroups.isEmpty) return const PkGroupsImportResult();
    final syncEnabled = await _pkGroupSyncV2Enabled();

    // Filter excluded locals at the fetch site (mirrors importGroups). The
    // remove path inside `_reconcileMembership` must not see them either.
    // M14d: light projection — no avatar blobs, filter pushed into SQL.
    final allMembers = await _loadReconcileMembers();
    final pkUuidToLocalMemberId = <String, String>{};
    for (final m in allMembers) {
      final pkUuid = m.pluralkitUuid?.trim();
      if (pkUuid != null && pkUuid.isNotEmpty) {
        pkUuidToLocalMemberId[pkUuid] = m.id;
      }
    }

    var result = const PkGroupsImportResult();
    for (final pk in pkGroups) {
      if (pk.memberIds == null) continue;
      final existing = await _dao.findByPluralkitUuid(pk.uuid);
      if (existing == null) continue; // Reattribute only touches known groups.
      final delta = await _reconcileMembership(
        groupLocalId: existing.id,
        groupPkUuid: pk.uuid,
        authoritativePkMemberUuids: pk.memberIds!,
        allMembers: allMembers,
        pkUuidToLocalMemberId: pkUuidToLocalMemberId,
        insertOnly: true,
        now: DateTime.now(),
      );
      if (syncEnabled) {
        await _emitMembershipSync(delta);
      }
      result = result.copyWith(
        groupsObserved: result.groupsObserved + 1,
        entriesInserted: result.entriesInserted + delta.entriesInserted,
      );
    }
    await _markRepairDirtyIfNeeded(result);
    return result;
  }

  Future<void> _markRepairDirtyIfNeeded(PkGroupsImportResult result) async {
    if (!result.changedRepairInputs) return;
    try {
      await PkGroupRepairRunGate.markDirtyInDefaultStore();
    } catch (error) {
      debugPrint('[PK groups] failed to mark repair dirty: $error');
    }
  }

  Future<_ReconcileDelta> _reconcileMembership({
    required String groupLocalId,
    required String groupPkUuid,
    required List<String> authoritativePkMemberUuids,
    required List<_PkReconcileMember> allMembers,
    required Map<String, String> pkUuidToLocalMemberId,
    required bool insertOnly,
    required DateTime now,
  }) async {
    final memberById = <String, _PkReconcileMember>{
      for (final m in allMembers) m.id: m,
    };

    final authoritativeSet = authoritativePkMemberUuids.toSet();
    // Step 4 of docs/plans/pk-group-membership-push.md: read via the new DAO
    // method so soft-deleted push_remove tombstones are visible. The vanilla
    // entriesForGroup filters is_deleted=true out, which would let the insert
    // branch revive a row the user explicitly removed (and queued for PK push).
    final entries = await _dao.entriesForGroupForReconcile(groupLocalId);

    // Member IDs whose entry is soft-deleted with push_remove pending. The
    // insert branch skips these to honor the user's intent: PK still has the
    // member but the user wants them gone, so don't re-insert locally.
    final pendingRemovalMemberIds = <String>{
      for (final e in entries)
        if (e.isDeleted && e.pendingPkOp == 'push_remove') e.memberId,
    };

    int inserted = 0;
    int removed = 0;
    int deferred = 0;
    int skippedRecent = 0;
    final insertedEntries = <_SyncedEntry>[];
    final removedEntryIds = <String>[];
    final graceCutoff = now.subtract(removalRecencyGrace);

    await _db.transaction(() async {
      if (!insertOnly) {
        for (final entry in entries) {
          if (entry.isDeleted) {
            continue; // already a tombstone, nothing to remove
          }
          if (entry.pendingPkOp == 'push_add') {
            // Locally-owned: user wants this in PK. The orchestrator will push
            // it on the next round. Don't soft-delete just because PK doesn't
            // have it yet — that would trigger the original data-loss bug
            // this whole plan exists to fix.
            continue;
          }
          final member = memberById[entry.memberId];
          if (member == null) continue; // orphan row — leave alone.
          final pkUuid = member.pluralkitUuid;
          if (pkUuid == null || pkUuid.isEmpty) {
            // Local-only member — preserve.
            continue;
          }
          if (authoritativeSet.contains(pkUuid)) continue; // preserve.
          // 2026-06 PK audit H6b: recency grace. A row younger than
          // `removalRecencyGrace` is never reconcile-deleted. This blocks the
          // cross-device intent-loss race: device B's local `push_add` synced
          // its CRDT create to device A; A pulls PK (which lacks the member
          // because B hasn't pushed yet) and would otherwise soft-delete +
          // emit a HARD delete that destroys B's row AND its unpushed intent.
          // The stamp is local + set at apply time, so a freshly synced row is
          // "recent" on A exactly during that window. A NULL stamp (rows that
          // predate the column) is treated as NOT recent → still eligible, so
          // a missing stamp never permanently leaks a PK membership.
          final createdAt = entry.createdAt;
          if (createdAt != null && createdAt.isAfter(graceCutoff)) {
            skippedRecent++;
            debugPrint(
              '[PK groups] H6b grace: skip removal of recent entry '
              '${entry.id} (group $groupPkUuid, member $pkUuid); '
              'created_at=$createdAt within ${removalRecencyGrace.inHours}h.',
            );
            continue;
          }
          // PK-linked member, not in authoritative set, past the grace
          // window → soft-delete.
          await _dao.softDeleteEntry(entry.id);
          removed++;
          removedEntryIds.add(entry.id);
        }
      }

      // Insert path — for every PK UUID in authoritative set, add an entry if
      // we can resolve it locally. Unresolved UUIDs count as deferred (R3).
      final existingActiveMemberIds = <String>{
        for (final e in entries)
          if (!e.isDeleted) e.memberId,
      };

      for (final pkMemberUuid in authoritativePkMemberUuids) {
        final localMemberId = pkUuidToLocalMemberId[pkMemberUuid];
        if (localMemberId == null) {
          deferred++;
          continue;
        }
        if (existingActiveMemberIds.contains(localMemberId)) continue;
        // Skip insert when there's a soft-deleted push_remove tombstone for
        // this member — user wants them out of PK, the orchestrator will
        // push the remove. Re-inserting locally would race with that.
        if (pendingRemovalMemberIds.contains(localMemberId)) continue;

        final entryId = deriveEntryId(groupPkUuid, pkMemberUuid);
        final existedBefore = entries.any((e) => e.id == entryId);
        try {
          await _dao.upsertEntry(
            MemberGroupEntriesCompanion.insert(
              id: entryId,
              groupId: groupLocalId,
              memberId: localMemberId,
              pkGroupUuid: Value(groupPkUuid),
              pkMemberUuid: Value(pkMemberUuid),
              isDeleted: const Value(false),
            ),
          );
        } catch (e) {
          // SQLITE_CONSTRAINT_UNIQUE (2067): concurrent sync already inserted
          // this entry. Treat as already-inserted.
          if (!isUniqueConstraintViolation(e)) rethrow;
        }
        inserted++;
        insertedEntries.add(
          _SyncedEntry(
            id: entryId,
            groupId: groupLocalId,
            memberId: localMemberId,
            pkGroupUuid: groupPkUuid,
            pkMemberUuid: pkMemberUuid,
            existedBefore: existedBefore,
          ),
        );
      }
    });

    return _ReconcileDelta(
      entriesInserted: inserted,
      entriesRemoved: removed,
      entriesDeferred: deferred,
      entriesSkippedRecent: skippedRecent,
      insertedEntries: insertedEntries,
      removedEntryIds: removedEntryIds,
    );
  }

  Future<MemberGroupRow> _loadGroupRow(String id) async {
    return (await (_db.select(
      _db.memberGroups,
    )..where((g) => g.id.equals(id))).getSingle());
  }

  Future<void> _emitCreate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    final override = _recordCreateOverride;
    if (override != null) {
      await override(table, entityId, fields);
      return;
    }
    await syncRecordCreate(table, entityId, fields);
  }

  Future<void> _emitUpdate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    final override = _recordUpdateOverride;
    if (override != null) {
      await override(table, entityId, fields);
      return;
    }
    await syncRecordUpdate(table, entityId, fields);
  }

  Future<void> _emitDelete(String table, String entityId) async {
    final override = _recordDeleteOverride;
    if (override != null) {
      await override(table, entityId);
      return;
    }
    await syncRecordDelete(table, entityId);
  }

  Future<void> _emitLegacyAliasDeletesForPkGroup(String pkGroupUuid) async {
    final canonicalEntityId = deriveGroupSyncEntityId(pkGroupUuid);
    final aliases = await _db.pkGroupSyncAliasesDao.getByPkGroupUuid(
      pkGroupUuid,
    );
    // M14b (2026-06 PK audit): emit each legacy alias's delete ONCE, then drop
    // the alias row. The pre-fix code re-emitted these tombstones on every pull
    // forever (deleteByLegacyEntityId had zero callers). The canonical alias
    // row (legacyEntityId == canonicalEntityId, or empty) is never a delete
    // target and is left untouched. The repair flow re-creates aliases when a
    // fresh duplicate is merged, so a NEW alias still gets its one delete on
    // the next pull before being cleaned — convergence is preserved, churn is
    // not.
    final legacyEntityIdsToDelete = <String, String>{}; // legacyEntityId -> raw
    for (final alias in aliases) {
      final raw = alias.legacyEntityId;
      final legacyEntityId = raw.trim();
      if (legacyEntityId.isEmpty || legacyEntityId == canonicalEntityId) {
        continue;
      }
      legacyEntityIdsToDelete[legacyEntityId] = raw;
    }
    for (final entry in legacyEntityIdsToDelete.entries) {
      await _emitDelete(_groupTable, entry.key);
      // Drop the alias row so this delete is not re-emitted on the next pull.
      // Keyed on the RAW stored value so the DELETE matches the persisted row
      // even when it carried surrounding whitespace.
      //
      // COUPLING NOTE (wave-3 verifier issue 5): the alias row also powers
      // the INBOUND legacy-id redirect — drift_sync_adapter's
      // `_pkGroupAliasForLegacyEntityId` (adapter ~:858) resolves inbound ops
      // addressed to a legacy entity id onto the canonical `pk-group:<uuid>`
      // row via this same table. Deleting the row here means a LATE inbound
      // op still addressed to the legacy id (a peer that hasn't processed
      // the canonicalization yet) loses that redirect. Accepted because it
      // is rare (legacy ids only originate from pre-canonicalization peers,
      // and ops are usually contiguous) and mitigated twice: the adapter
      // re-records an alias when it sees a genuinely-legacy inbound id, and
      // the legacy-id DELETE op emitted above is durable in the log, so any
      // peer replaying history still tombstones the legacy entity.
      await _db.pkGroupSyncAliasesDao.deleteByLegacyEntityId(entry.value);
    }
  }

  Future<void> _emitMembershipSync(_ReconcileDelta delta) async {
    for (final entry in delta.insertedEntries) {
      final fields = entrySyncFields(
        groupId: entry.groupId,
        memberId: entry.memberId,
        pkGroupUuid: entry.pkGroupUuid,
        pkMemberUuid: entry.pkMemberUuid,
      );
      if (entry.existedBefore) {
        // Revive of a locally soft-deleted entry: strip `is_deleted` from the
        // update patch so per-field LWW can't stamp a fresh HLC on
        // `is_deleted: false` and resurrect a row a peer concurrently
        // deleted. Mirrors the member_groups fix in commit 94f5d950 — see
        // `lib/data/sync/field_diff.dart` for why update patches stay narrow.
        await _emitUpdate(_entryTable, entry.id, {
          for (final entry in fields.entries)
            if (entry.key != 'is_deleted') entry.key: entry.value,
        });
      } else {
        await _emitCreate(_entryTable, entry.id, fields);
      }
    }
    for (final entryId in delta.removedEntryIds) {
      await _emitDelete(_entryTable, entryId);
    }
  }

  Future<bool> _pkGroupSyncV2Enabled() async {
    final settings = await _db.systemSettingsDao.getSettings();
    return settings.pkGroupSyncV2Enabled;
  }

  /// M14d (2026-06 PK audit): light projection of active, non-excluded members
  /// for the PK group reconcile. The importer only needs each member's id and
  /// PK UUID — never the avatar/banner/header blobs the full member rows carry.
  /// Projecting into [_PkReconcileMember] up front keeps the reconcile's
  /// working set (the `pkUuidToLocalMemberId` map and the `memberById` lookup
  /// it builds twice per pull, in importGroups + reattribute) blob-free, and
  /// drops excluded locals once at the source so no downstream call site can
  /// re-attribute / push / remove them.
  ///
  /// NOTE: this still routes through `MemberRepository.getAllMembers()` so the
  /// member source stays injectable (tests seed a fake repo). Eliminating the
  /// blob read at the repository layer itself needs a light-projection method
  /// on the MemberRepository interface, which lives outside this change's
  /// file ownership — see the wave-3 report deviation note.
  Future<List<_PkReconcileMember>> _loadReconcileMembers() async {
    final members = await _memberRepository.getAllMembers();
    return [
      for (final m in members)
        if (!m.pluralkitSyncIgnored)
          _PkReconcileMember(id: m.id, pluralkitUuid: m.pluralkitUuid),
    ];
  }

  /// Atomically terminate ALL pending intents for a group whose PK side
  /// went missing (refetch returned 404). Hard-deletes push_remove
  /// tombstones FIRST so the guarded DELETE matches on pending_pk_op =
  /// 'push_remove'; then clears any remaining pending (push_add rows that
  /// stay active as local-only memberships). Returns the count of rows
  /// hard-deleted (caller uses this for the `removed` counter).
  ///
  /// Called by both _refetchAndReconcileAddBucket AND
  /// _refetchAndReconcileRemoveBucket on the 404 path. Order matters when
  /// the same gone group appears in both buckets (2nd-pass review
  /// [P3]): if the add path's clearAllPendingPkOpForGroup ran first, it
  /// would wipe push_remove pending → the remove path's later DELETE
  /// misses → zombie. The shared helper handles both ops atomically;
  /// idempotent if called twice for the same group.
  Future<int> _terminalCleanupForGoneGroup(String groupPkUuid) async {
    final group = await _dao.findByPluralkitUuid(groupPkUuid);
    if (group == null) return 0;
    // Hard-delete every push_remove tombstone in the group while pending
    // still equals push_remove (guarded by DAO method).
    final tombstoneIds = await _db
        .customSelect(
          'SELECT id FROM member_group_entries '
          "WHERE group_id = ? AND pending_pk_op = 'push_remove' AND is_deleted = 1",
          variables: [Variable.withString(group.id)],
          readsFrom: {_db.memberGroupEntries},
        )
        .get();
    var removed = 0;
    for (final row in tombstoneIds) {
      final hits = await _dao.hardDeleteRemoveTombstoneGuarded(
        row.read<String>('id'),
      );
      if (hits > 0) removed++;
    }
    // Clear pending on the rest (push_add rows; nothing to push to a gone
    // PK group). Soft-deleted-pending=none rows are stable.
    await _dao.clearAllPendingPkOpForGroup(group.id);
    return removed;
  }

  // ── Step 6: push orchestrator ──────────────────────────────────────────

  /// Push every pending group-membership op to PluralKit.
  ///
  /// Reads `member_group_entries WHERE pending_pk_op != 'none'`, validates
  /// each row's current state against its intent (compensating CRDT-conflict
  /// contradictions in flight), buckets the survivors by `(groupPkUuid, op)`,
  /// and POSTs to PluralKit's `/groups/{ref}/members/add` and
  /// `/members/remove` endpoints. On 204 a guarded UPDATE/DELETE clears the
  /// pending intent (or hard-deletes the tombstone). On 4xx the importer
  /// refetches the affected group's authoritative member list once and
  /// reconciles each entry per its desired state. On 5xx / network the
  /// pending intent is left in place for the next sync round.
  ///
  /// Re-entrant via [_pushInFlight]: parallel callers await the same Future
  /// and get the same result. Bails immediately when [direction.pushEnabled]
  /// is false.
  ///
  /// See docs/plans/pk-group-membership-push.md (step 6 + v3-patches-2 #7
  /// + v3-patches-2 #8 + cleanup-pass refinements) for the full algorithm.
  Future<PkGroupMembershipPushResult> pushPendingGroupOps(
    PluralKitClient client,
    PkSyncDirection direction,
  ) async {
    if (!direction.pushEnabled) {
      return const PkGroupMembershipPushResult();
    }
    final existing = _pushInFlight;
    if (existing != null) return existing;

    late final Future<PkGroupMembershipPushResult> future;
    future = _doPushPendingGroupOps(client).whenComplete(() {
      if (identical(_pushInFlight, future)) {
        _pushInFlight = null;
      }
    });
    _pushInFlight = future;
    return future;
  }

  /// Read-only preview of pending destructive group-membership push work.
  ///
  /// Mirrors [_doPushPendingGroupOps] through linkage resolution,
  /// compensation checks, and bucket-building. Unlike the real push path, this
  /// does not mutate pending rows and never calls PluralKit.
  Future<PkGroupMembershipRemovalPreview>
  previewPendingGroupMembershipRemovals() async {
    final pending = await _dao.entriesWithPendingPkOp();
    if (pending.isEmpty) return const PkGroupMembershipRemovalPreview();

    final groupIdsToFetch = pending.map((e) => e.groupId).toSet().toList();
    final memberIdsToFetch = pending.map((e) => e.memberId).toSet().toList();
    final groupRowsById = <String, MemberGroupRow>{};
    for (final id in groupIdsToFetch) {
      final row = await _dao.getGroupById(id);
      if (row != null) groupRowsById[id] = row;
    }
    final membersById = <String, domain.Member>{
      for (final m in await _memberRepository.getMembersByIds(memberIdsToFetch))
        m.id: m,
    };

    var toRemove = 0;
    var skipped = 0;

    for (final entry in pending) {
      final group = groupRowsById[entry.groupId];
      final member = membersById[entry.memberId];
      final entryGroupPk = (entry.pkGroupUuid ?? '').trim();
      final entryMemberPk = (entry.pkMemberUuid ?? '').trim();
      final groupPkUuid = entryGroupPk.isNotEmpty
          ? entryGroupPk
          : group?.pluralkitUuid;
      final memberPkUuid = entryMemberPk.isNotEmpty
          ? entryMemberPk
          : member?.pluralkitUuid;

      if (groupPkUuid == null ||
          groupPkUuid.isEmpty ||
          memberPkUuid == null ||
          memberPkUuid.isEmpty) {
        skipped++;
        continue;
      }

      final isAdd = entry.pendingPkOp == 'push_add';
      final isRemove = entry.pendingPkOp == 'push_remove';
      if (isRemove && entry.isDeleted) {
        toRemove++;
      } else if ((isRemove && !entry.isDeleted) || (isAdd && entry.isDeleted)) {
        skipped++;
      }
    }

    return PkGroupMembershipRemovalPreview(
      toRemove: toRemove,
      skipped: skipped,
    );
  }

  Future<PkGroupMembershipPushResult> _doPushPendingGroupOps(
    PluralKitClient client,
  ) async {
    var result = const PkGroupMembershipPushResult();
    final pending = await _dao.entriesWithPendingPkOp();
    if (pending.isEmpty) return result;

    // Resolve PK linkage info for every pending row up front. We need both
    // the group's PK UUID and the member's PK UUID to push; either being
    // missing means the row is stranded (link gone since intent was set).
    final groupIdsToFetch = pending.map((e) => e.groupId).toSet().toList();
    final memberIdsToFetch = pending.map((e) => e.memberId).toSet().toList();
    final groupRowsById = <String, MemberGroupRow>{};
    for (final id in groupIdsToFetch) {
      final row = await _dao.getGroupById(id);
      if (row != null) groupRowsById[id] = row;
    }
    final membersById = <String, domain.Member>{
      for (final m in await _memberRepository.getMembersByIds(memberIdsToFetch))
        m.id: m,
    };

    // Pre-push validation + stale-link terminal policy.
    // Each entry is bucketed into one of:
    //   - compensate: state contradicts intent → flip intent, skip push.
    //   - strand: PK link gone → clear pending, skip push.
    //   - push_add bucket: ready to push add.
    //   - push_remove bucket: ready to push remove.
    final pushAddByGroupPk = <String, List<_PushCandidate>>{};
    final pushRemoveByGroupPk = <String, List<_PushCandidate>>{};
    int compensated = 0;
    int stranded = 0;

    for (final entry in pending) {
      final group = groupRowsById[entry.groupId];
      final member = membersById[entry.memberId];
      // Prefer the entry's STORED PK UUIDs (the snapshot at edge-creation
      // time) over the current group/member values. Otherwise a relink
      // between intent set and push would target the wrong PK identifier:
      // user adds member-with-uuid-A → entry.pkMemberUuid = A → user
      // relinks to B → push reads CURRENT member.pluralkitUuid (B) and
      // pushes B, leaving A in the PK group permanently. Later review [P2].
      // Empty-string is treated as "not set" and falls back to current.
      final entryGroupPk = (entry.pkGroupUuid ?? '').trim();
      final entryMemberPk = (entry.pkMemberUuid ?? '').trim();
      final groupPkUuid = entryGroupPk.isNotEmpty
          ? entryGroupPk
          : group?.pluralkitUuid;
      final memberPkUuid = entryMemberPk.isNotEmpty
          ? entryMemberPk
          : member?.pluralkitUuid;

      // Stale-link terminal policy (v3-patches #5): if either side lost
      // its PK link, clear pending and move on. The row stays in its
      // current is_deleted state; future syncs will not destructively
      // touch it (the pull reconcile no-ops on rows with pending=none
      // when the group has no PK UUID).
      if (groupPkUuid == null ||
          groupPkUuid.isEmpty ||
          memberPkUuid == null ||
          memberPkUuid.isEmpty) {
        await _dao.flipPendingPkOpGuarded(
          entry.id,
          from: entry.pendingPkOp,
          to: 'none',
          expectedIsDeleted: entry.isDeleted,
        );
        stranded++;
        continue;
      }

      // Pre-push CRDT-conflict compensation (v3-patches-2 #8, refined by the
      // 2026-06 PK audit H6c). state disagrees with intent.
      final isAdd = entry.pendingPkOp == 'push_add';
      var isRemove = entry.pendingPkOp == 'push_remove';
      if (isAdd && entry.isDeleted) {
        // CRDT delete or local revival landed after we set push_add. PK
        // might already have it; queue a remove to converge.
        final hits = await _dao.flipPendingPkOpGuarded(
          entry.id,
          from: 'push_add',
          to: 'push_remove',
          expectedIsDeleted: true,
        );
        if (hits > 0) compensated++;
        continue;
      }
      if (isRemove && !entry.isDeleted) {
        // H6c (2026-06 PK audit): a push_remove row that is currently ACTIVE
        // can ONLY have got here via a CRDT REVIVE from a peer — verified at
        // drift_member_groups_repository.addMemberToGroup, the local re-add
        // path sets push_add ITSELF (the companion overwrites the queued
        // push_remove), so a genuine local re-add never reaches this branch.
        // The pre-fix code flipped push_remove → push_add here, which silently
        // pushed the member BACK to PK and permanently lost the user's remove
        // intent (scenario B in the audit). The user's remove must win: re-
        // assert the tombstone (is_deleted = true), KEEP push_remove, and let
        // it push as a remove this round so PK converges to the deletion.
        //
        // DELIBERATE NO-EMIT TRADE-OFF (wave-3 verifier issue 4): neither
        // this re-tombstone nor the orchestrator's hard-deletes (the post-204
        // cleanup in _pushRemoveBucket and the M15 cap's
        // _failOrCapRemoveCandidates) emit ANY CRDT op. Emitting a delete
        // here would hand peers a back-door HARD delete of what might be a
        // peer's legitimate re-add racing this compensation — the exact
        // intent-destruction class H6 exists to close. The cost is a bounded
        // divergence window: this device shows the member removed while
        // peers still show the revived entry, and the CRDT log alone will
        // NOT reconcile it. Convergence instead arrives via PluralKit: once
        // the remove lands on PK, each peer's next pull reconciles its own
        // copy against the post-remove authoritative set (subject to its own
        // H6b grace window, so a peer protecting a fresh revive converges
        // one grace-window later). PK is the tiebreaker of record for
        // membership, which is the contract bidirectional group sync
        // already assumes everywhere else in this file.
        final hits = await _dao.softDeleteEntryWithPendingOpGuarded(
          entry.id,
          pendingPkOp: 'push_remove',
          expectedActive: true,
        );
        if (hits == 0) {
          // Lost the race (concurrent local re-add to push_add, or another
          // mutation). Skip; next round re-reads the settled state.
          compensated++;
          continue;
        }
        compensated++;
        // Fall through into the push_remove bucket below.
        isRemove = true;
      }

      final candidate = _PushCandidate(
        entryId: entry.id,
        groupPkUuid: groupPkUuid,
        memberPkUuid: memberPkUuid,
      );
      if (isAdd) {
        pushAddByGroupPk
            .putIfAbsent(groupPkUuid, () => <_PushCandidate>[])
            .add(candidate);
      } else if (isRemove) {
        pushRemoveByGroupPk
            .putIfAbsent(groupPkUuid, () => <_PushCandidate>[])
            .add(candidate);
      }
    }

    result = result.copyWith(compensated: compensated, stranded: stranded);

    // Push each bucket. Failures are per-bucket; a bad UUID in one bucket
    // does not poison another bucket's cleanup.
    for (final entry in pushAddByGroupPk.entries) {
      result = await _pushAddBucket(client, entry.key, entry.value, result);
    }
    for (final entry in pushRemoveByGroupPk.entries) {
      result = await _pushRemoveBucket(client, entry.key, entry.value, result);
    }

    return result;
  }

  Future<PkGroupMembershipPushResult> _pushAddBucket(
    PluralKitClient client,
    String groupPkUuid,
    List<_PushCandidate> candidates,
    PkGroupMembershipPushResult result,
  ) async {
    if (candidates.isEmpty) return result;
    final memberRefs = candidates.map((c) => c.memberPkUuid).toList();
    try {
      await client.addMembersToGroup(groupPkUuid, memberRefs);
      // 204 — guarded cleanup per entry.
      var added = 0;
      for (final c in candidates) {
        final hits = await _dao.flipPendingPkOpGuarded(
          c.entryId,
          from: 'push_add',
          to: 'none',
          expectedIsDeleted: false,
        );
        if (hits > 0) added++;
      }
      return result.copyWith(added: result.added + added);
    } on PluralKitApiError catch (e) {
      // Wave-3 verifier issue 1 (2026-06 PK audit): PluralKitAuthError (401)
      // and PluralKitRateLimitError (429) SUBCLASS PluralKitApiError
      // (pluralkit_client.dart:34,46), so without this explicit exclusion
      // they satisfy the 4xx range check below and enter the refetch/cap
      // path — where the refetch fails the same way (same token / same
      // rate-limit window) and the age cap could then destroy intents on a
      // routine token rotation or 429 burst. Auth / rate-limit failures are
      // environmental, not per-intent: keep every intent pending and
      // untouched; the next sync round retries.
      if (e is PluralKitAuthError || e is PluralKitRateLimitError) {
        debugPrint(
          '[PK push] addMembersToGroup($groupPkUuid) ${e.statusCode} '
          '(auth/rate-limit) — intents kept pending, no refetch/cap.',
        );
        return result.copyWith(failed: result.failed + candidates.length);
      }
      // M15c (2026-06 PK audit): a bulk add with one invalid ref fails ATOMIC
      // with 404 code 20003, and the message NAMES the bad ref (live-verified).
      // Without isolating it, the single bad ref poisons the whole bucket
      // forever — every retry re-sends all refs, hits the same 20003, and no
      // valid add ever lands. Drop just the named ref's intent as terminal,
      // then retry the bucket with the survivors so the valid adds proceed.
      if (e.statusCode == 404 && e.code == 20003) {
        final reconciled = await _dropPoisonedAddRefAndRetry(
          client,
          groupPkUuid,
          candidates,
          e,
          result,
        );
        if (reconciled != null) return reconciled;
        // Couldn't identify the bad ref from the message — fall through to the
        // generic refetch path rather than guessing.
      }
      if (e.statusCode >= 400 && e.statusCode < 500) {
        return _refetchAndReconcileAddBucket(
          client,
          groupPkUuid,
          candidates,
          result,
        );
      }
      // 5xx — leave pending; record per-entry failures.
      debugPrint(
        '[PK push] addMembersToGroup($groupPkUuid) ${e.statusCode}: ${e.message}',
      );
      return result.copyWith(failed: result.failed + candidates.length);
    } catch (e) {
      // Network / transport errors that aren't PluralKitApiError. (Auth and
      // rate-limit ARE PluralKitApiError subclasses — they're excluded
      // explicitly in the typed catch above.) Leave pending.
      debugPrint('[PK push] addMembersToGroup($groupPkUuid) failed: $e');
      return result.copyWith(failed: result.failed + candidates.length);
    }
  }

  /// M15c: handle a bulk-add 404 code 20003 by dropping the single bad ref the
  /// error names (terminal — it will never resolve) and retrying the bucket
  /// with the remaining valid candidates. Returns the updated result, or null
  /// when the bad ref couldn't be located in the error message (caller falls
  /// back to the generic refetch path).
  Future<PkGroupMembershipPushResult?> _dropPoisonedAddRefAndRetry(
    PluralKitClient client,
    String groupPkUuid,
    List<_PushCandidate> candidates,
    PluralKitApiError error,
    PkGroupMembershipPushResult result,
  ) async {
    final poisoned = candidates
        .where((c) => error.message.contains(c.memberPkUuid))
        .toList(growable: false);
    if (poisoned.isEmpty) return null;

    var terminallyFailed = 0;
    for (final c in poisoned) {
      final hits = await _dao.flipPendingPkOpGuarded(
        c.entryId,
        from: 'push_add',
        to: 'none',
        expectedIsDeleted: false,
      );
      if (hits > 0) terminallyFailed++;
      debugPrint(
        '[PK push] M15c: dropping poisoned add ref ${c.memberPkUuid} '
        '(entry ${c.entryId}, group $groupPkUuid) — PK 20003 named it bad.',
      );
    }
    final next = result.copyWith(
      terminallyFailed: result.terminallyFailed + terminallyFailed,
    );

    final survivors = candidates
        .where((c) => !poisoned.contains(c))
        .toList(growable: false);
    if (survivors.isEmpty) return next;
    // Retry the survivors as their own bucket. A second poisoned ref recurses
    // here; the survivor set strictly shrinks so this terminates.
    return _pushAddBucket(client, groupPkUuid, survivors, next);
  }

  Future<PkGroupMembershipPushResult> _pushRemoveBucket(
    PluralKitClient client,
    String groupPkUuid,
    List<_PushCandidate> candidates,
    PkGroupMembershipPushResult result,
  ) async {
    final memberRefs = candidates.map((c) => c.memberPkUuid).toList();
    try {
      await client.removeMembersFromGroup(groupPkUuid, memberRefs);
      var removed = 0;
      for (final c in candidates) {
        final hits = await _dao.hardDeleteRemoveTombstoneGuarded(c.entryId);
        if (hits > 0) removed++;
      }
      return result.copyWith(removed: result.removed + removed);
    } on PluralKitApiError catch (e) {
      // Wave-3 verifier issue 1: auth (401) / rate-limit (429) are
      // PluralKitApiError SUBCLASSES and would otherwise enter the
      // refetch/cap path below, where the cap can hard-delete push_remove
      // tombstones on a routine token rotation or 429 burst — silently
      // reverting the user's remove fleet-wide on the next pull. Keep every
      // intent pending and untouched. See _pushAddBucket for the full note.
      if (e is PluralKitAuthError || e is PluralKitRateLimitError) {
        debugPrint(
          '[PK push] removeMembersFromGroup($groupPkUuid) ${e.statusCode} '
          '(auth/rate-limit) — intents kept pending, no refetch/cap.',
        );
        return result.copyWith(failed: result.failed + candidates.length);
      }
      if (e.statusCode >= 400 && e.statusCode < 500) {
        return _refetchAndReconcileRemoveBucket(
          client,
          groupPkUuid,
          candidates,
          result,
        );
      }
      debugPrint(
        '[PK push] removeMembersFromGroup($groupPkUuid) ${e.statusCode}: ${e.message}',
      );
      return result.copyWith(failed: result.failed + candidates.length);
    } catch (e) {
      // Network / transport errors that aren't PluralKitApiError. Leave
      // pending.
      debugPrint('[PK push] removeMembersFromGroup($groupPkUuid) failed: $e');
      return result.copyWith(failed: result.failed + candidates.length);
    }
  }

  Future<PkGroupMembershipPushResult> _refetchAndReconcileAddBucket(
    PluralKitClient client,
    String groupPkUuid,
    List<_PushCandidate> candidates,
    PkGroupMembershipPushResult result,
  ) async {
    // 4xx + push_add: a v3-patches-2 cleanup pass narrowed the policy.
    // Group-absence alone does NOT prove the member's UUID is stale on PK
    // (could be auth, validation, transient). We refetch this group's
    // authoritative member list and per-entry compare:
    //   - member now in PK → desired state satisfied → guarded cleanup.
    //   - member not in PK → leave pending; record failure; retry next sync.
    //   - refetch itself 404s → terminal policy: clear pending for ALL
    //     entries in this group (PK group is gone).
    Set<String> authoritative;
    try {
      authoritative = (await client.getGroupMembers(groupPkUuid)).toSet();
    } on PluralKitApiError catch (e) {
      if (_isGroupGone404(e)) {
        // PK group is genuinely gone (404 + code 20004 — M15a, 2026-06 PK
        // audit). 2nd-pass review [P3]: we have to handle BOTH push_add AND
        // push_remove rows in the same group atomically, otherwise a later
        // push_remove bucket for the same gone group will see its tombstones
        // already cleared to pending=none and the guarded DELETE will miss →
        // zombie. Use the shared helper that hard-deletes remove tombstones
        // first, then clears the rest. push_add candidates count as stranded
        // (no local row hard-delete needed; they stay active as local-only).
        await _terminalCleanupForGoneGroup(groupPkUuid);
        return result.copyWith(stranded: result.stranded + candidates.length);
      }
      // Wave-3 verifier issue 1: an auth/rate-limit/5xx failure on the
      // REFETCH is environmental too (same token / same 429 window that just
      // failed the POST, or a server-side blip) — it must bypass the age cap
      // entirely, or a token rotation could terminal-drop intents that would
      // push fine tomorrow.
      if (e is PluralKitAuthError ||
          e is PluralKitRateLimitError ||
          e.statusCode >= 500) {
        debugPrint(
          '[PK push] refetch /groups/$groupPkUuid/members ${e.statusCode} '
          '(environmental) — intents kept pending, no cap.',
        );
        return result.copyWith(failed: result.failed + candidates.length);
      }
      // Refetch failed for some other reason — including a 404 WITHOUT code
      // 20004, which is transient (proxy/transport), not "group gone".
      // Leave the bucket pending; the retry cap below catches permanent
      // failures by age.
      debugPrint(
        '[PK push] refetch /groups/$groupPkUuid/members ${e.statusCode}'
        '${e.code == null ? '' : ' code ${e.code}'}',
      );
      return _failOrCapAddCandidates(groupPkUuid, candidates, result);
    } catch (e) {
      // Transport failure — environmental, like auth/rate-limit above: keep
      // pending WITHOUT the cap (an offline week must not drop intents).
      debugPrint('[PK push] refetch /groups/$groupPkUuid/members failed: $e');
      return result.copyWith(failed: result.failed + candidates.length);
    }

    var added = 0;
    final stillPending = <_PushCandidate>[];
    for (final c in candidates) {
      if (authoritative.contains(c.memberPkUuid)) {
        // Desired state already satisfied — clean up pending.
        final hits = await _dao.flipPendingPkOpGuarded(
          c.entryId,
          from: 'push_add',
          to: 'none',
          expectedIsDeleted: false,
        );
        if (hits > 0) added++;
      } else {
        // Group-absence alone is not a terminal signal; leave pending (subject
        // to the age-based retry cap).
        stillPending.add(c);
      }
    }
    result = result.copyWith(added: result.added + added);
    return _failOrCapAddCandidates(groupPkUuid, stillPending, result);
  }

  Future<PkGroupMembershipPushResult> _refetchAndReconcileRemoveBucket(
    PluralKitClient client,
    String groupPkUuid,
    List<_PushCandidate> candidates,
    PkGroupMembershipPushResult result,
  ) async {
    Set<String> authoritative;
    try {
      authoritative = (await client.getGroupMembers(groupPkUuid)).toSet();
    } on PluralKitApiError catch (e) {
      if (_isGroupGone404(e)) {
        // PK group is genuinely gone (404 + code 20004 — M15a) → desired
        // remove satisfied for every candidate. Use the shared terminal-
        // cleanup helper which hard-deletes ALL push_remove tombstones in the
        // group first (including any not in this bucket), then clears push_add
        // to none. 2nd-pass review [P3]: a single bucket's local hard-delete
        // is not enough when another bucket for the same gone group runs after
        // this one.
        final removed = await _terminalCleanupForGoneGroup(groupPkUuid);
        return result.copyWith(removed: result.removed + removed);
      }
      // Wave-3 verifier issue 1: auth/rate-limit/5xx on the refetch bypasses
      // the cap — a hard-deleted push_remove tombstone is unrecoverable (the
      // next pull re-imports the member), so environmental failures must
      // never reach _failOrCapRemoveCandidates.
      if (e is PluralKitAuthError ||
          e is PluralKitRateLimitError ||
          e.statusCode >= 500) {
        debugPrint(
          '[PK push] refetch /groups/$groupPkUuid/members ${e.statusCode} '
          '(environmental) — intents kept pending, no cap.',
        );
        return result.copyWith(failed: result.failed + candidates.length);
      }
      // A bare 404 (no code 20004) is transient — keep intents, retry later.
      debugPrint(
        '[PK push] refetch /groups/$groupPkUuid/members ${e.statusCode}'
        '${e.code == null ? '' : ' code ${e.code}'}',
      );
      return _failOrCapRemoveCandidates(groupPkUuid, candidates, result);
    } catch (e) {
      // Transport failure — environmental: keep pending WITHOUT the cap.
      debugPrint('[PK push] refetch /groups/$groupPkUuid/members failed: $e');
      return result.copyWith(failed: result.failed + candidates.length);
    }

    var removed = 0;
    final stillPending = <_PushCandidate>[];
    for (final c in candidates) {
      if (!authoritative.contains(c.memberPkUuid)) {
        // Member is not in PK — desired remove satisfied. Hard-delete.
        final hits = await _dao.hardDeleteRemoveTombstoneGuarded(c.entryId);
        if (hits > 0) removed++;
      } else {
        // PK still has the member — leave pending (subject to retry cap).
        stillPending.add(c);
      }
    }
    result = result.copyWith(removed: result.removed + removed);
    return _failOrCapRemoveCandidates(groupPkUuid, stillPending, result);
  }

  /// True when [e] is a PK 404 whose parsed `code` is 20004 — the
  /// "group not found" code (M15a, 2026-06 PK audit; live-verified that
  /// `GET /groups/{deleted}/members` returns 404 code 20004). Any other 404
  /// shape (auth proxy, transient) must NOT trigger terminal intent cleanup.
  static bool _isGroupGone404(PluralKitApiError e) =>
      e.statusCode == 404 && e.code == 20004;

  /// Age-based retry cap (M15, 2026-06 PK audit). `member_group_entries`
  /// pending ops have no `retry_count` column (only the deferred-ops table
  /// does), so we cap by INTENT age (`created_at` is refreshed whenever a
  /// pending op is set): a push candidate
  /// that has kept failing past [pushRetryMaxAge] is marked terminal (pending
  /// cleared / tombstone hard-deleted) and counted under [
  /// PkGroupMembershipPushResult.terminallyFailed] so it is surfaceable, rather
  /// than retried forever every sync. Candidates younger than the cap stay
  /// pending and count as ordinary [failed]. Returns the updated result.
  Future<PkGroupMembershipPushResult> _failOrCapAddCandidates(
    String groupPkUuid,
    List<_PushCandidate> candidates,
    PkGroupMembershipPushResult result,
  ) async {
    if (candidates.isEmpty) return result;
    var failed = 0;
    var terminallyFailed = 0;
    for (final c in candidates) {
      if (await _isPushCandidateExpired(c.entryId)) {
        // Past the cap → terminal. Clear push_add to none; the row stays an
        // active local-only membership (PK never accepted it).
        final hits = await _dao.flipPendingPkOpGuarded(
          c.entryId,
          from: 'push_add',
          to: 'none',
          expectedIsDeleted: false,
        );
        if (hits > 0) {
          terminallyFailed++;
          debugPrint(
            '[PK push] retry cap: giving up push_add ${c.entryId} '
            '(group $groupPkUuid) after ${pushRetryMaxAge.inDays}d.',
          );
        } else {
          failed++;
        }
      } else {
        failed++;
      }
    }
    return result.copyWith(
      failed: result.failed + failed,
      terminallyFailed: result.terminallyFailed + terminallyFailed,
    );
  }

  Future<PkGroupMembershipPushResult> _failOrCapRemoveCandidates(
    String groupPkUuid,
    List<_PushCandidate> candidates,
    PkGroupMembershipPushResult result,
  ) async {
    if (candidates.isEmpty) return result;
    var failed = 0;
    var terminallyFailed = 0;
    for (final c in candidates) {
      if (await _isPushCandidateExpired(c.entryId)) {
        // Past the cap → terminal. Hard-delete the push_remove tombstone; the
        // member stays in PK (we never managed to remove it) but the local row
        // stops churning. Guarded so a concurrent revive is preserved.
        final hits = await _dao.hardDeleteRemoveTombstoneGuarded(c.entryId);
        if (hits > 0) {
          terminallyFailed++;
          debugPrint(
            '[PK push] retry cap: giving up push_remove ${c.entryId} '
            '(group $groupPkUuid) after ${pushRetryMaxAge.inDays}d.',
          );
        } else {
          failed++;
        }
      } else {
        failed++;
      }
    }
    return result.copyWith(
      failed: result.failed + failed,
      terminallyFailed: result.terminallyFailed + terminallyFailed,
    );
  }

  /// True when the entry's local `created_at` is older than [pushRetryMaxAge].
  /// A NULL stamp (rows predating the column) is treated as NOT expired so a
  /// missing stamp never silently drops a real intent.
  Future<bool> _isPushCandidateExpired(String entryId) async {
    final rows = await _db
        .customSelect(
          'SELECT created_at FROM member_group_entries WHERE id = ?',
          variables: [Variable.withString(entryId)],
          readsFrom: {_db.memberGroupEntries},
        )
        .get();
    if (rows.isEmpty) return false;
    final raw = rows.single.data['created_at'];
    if (raw == null) return false;
    // Drift stores DateTime columns as unix seconds.
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      (raw as int) * 1000,
      isUtc: true,
    );
    return DateTime.now().toUtc().difference(createdAt) > pushRetryMaxAge;
  }
}

class _PushCandidate {
  final String entryId;
  final String groupPkUuid;
  final String memberPkUuid;

  const _PushCandidate({
    required this.entryId,
    required this.groupPkUuid,
    required this.memberPkUuid,
  });
}

/// Light member projection for the PK group reconcile (M14d). Carries only the
/// fields the reconcile reads — never avatar/banner blobs.
class _PkReconcileMember {
  final String id;
  final String? pluralkitUuid;

  const _PkReconcileMember({required this.id, required this.pluralkitUuid});
}

class _ReconcileDelta {
  final int entriesInserted;
  final int entriesRemoved;
  final int entriesDeferred;
  final int entriesSkippedRecent;
  final List<_SyncedEntry> insertedEntries;
  final List<String> removedEntryIds;
  const _ReconcileDelta({
    required this.entriesInserted,
    required this.entriesRemoved,
    required this.entriesDeferred,
    required this.entriesSkippedRecent,
    required this.insertedEntries,
    required this.removedEntryIds,
  });
}

class _SyncedEntry {
  final String id;
  final String groupId;
  final String memberId;
  final String pkGroupUuid;
  final String pkMemberUuid;
  final bool existedBefore;

  const _SyncedEntry({
    required this.id,
    required this.groupId,
    required this.memberId,
    required this.pkGroupUuid,
    required this.pkMemberUuid,
    required this.existedBefore,
  });
}

/// Step 6 result type. Counts are best-effort; per-bucket failures may
/// leave pending intents in the DB to retry on the next sync round.
class PkGroupMembershipPushResult {
  /// Successful /members/add calls × member count → cleanup UPDATE landed.
  final int added;

  /// Successful /members/remove calls → cleanup DELETE landed.
  final int removed;

  /// Per-entry failures left in pending state. Includes 4xx where refetch
  /// did not satisfy the desired state, 5xx, and network errors.
  final int failed;

  /// Per-entry rows whose group or member lost its PK link before the
  /// push could run. Pending was cleared (terminal local state).
  final int stranded;

  /// Compensations applied by pre-push validation (CRDT-conflict detection
  /// flipped intent in either direction). These rows do not push this round
  /// — the next round picks up the new intent.
  final int compensated;

  /// Per-entry intents the orchestrator gave up on permanently (M15, 2026-06
  /// PK audit): a poisoned bulk-add ref the server named bad (404 code 20003),
  /// or a candidate that kept 4xx-failing past [
  /// PkGroupsImporter.pushRetryMaxAge]. Distinct from [failed] (retry next
  /// round) and [stranded] (PK link gone) so a UI/log surface can show
  /// "permanently could not push N memberships" instead of silently looping.
  final int terminallyFailed;

  const PkGroupMembershipPushResult({
    this.added = 0,
    this.removed = 0,
    this.failed = 0,
    this.stranded = 0,
    this.compensated = 0,
    this.terminallyFailed = 0,
  });

  PkGroupMembershipPushResult copyWith({
    int? added,
    int? removed,
    int? failed,
    int? stranded,
    int? compensated,
    int? terminallyFailed,
  }) {
    return PkGroupMembershipPushResult(
      added: added ?? this.added,
      removed: removed ?? this.removed,
      failed: failed ?? this.failed,
      stranded: stranded ?? this.stranded,
      compensated: compensated ?? this.compensated,
      terminallyFailed: terminallyFailed ?? this.terminallyFailed,
    );
  }
}
