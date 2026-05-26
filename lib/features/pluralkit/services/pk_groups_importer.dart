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

  const PkGroupsImportResult({
    this.groupsInserted = 0,
    this.groupsUpdated = 0,
    this.groupsObserved = 0,
    this.entriesInserted = 0,
    this.entriesRemoved = 0,
    this.entriesDeferred = 0,
    this.groupsWithUnknownMembership = 0,
  });

  PkGroupsImportResult copyWith({
    int? groupsInserted,
    int? groupsUpdated,
    int? groupsObserved,
    int? entriesInserted,
    int? entriesRemoved,
    int? entriesDeferred,
    int? groupsWithUnknownMembership,
  }) => PkGroupsImportResult(
    groupsInserted: groupsInserted ?? this.groupsInserted,
    groupsUpdated: groupsUpdated ?? this.groupsUpdated,
    groupsObserved: groupsObserved ?? this.groupsObserved,
    entriesInserted: entriesInserted ?? this.entriesInserted,
    entriesRemoved: entriesRemoved ?? this.entriesRemoved,
    entriesDeferred: entriesDeferred ?? this.entriesDeferred,
    groupsWithUnknownMembership:
        groupsWithUnknownMembership ?? this.groupsWithUnknownMembership,
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
  Future<PkGroupsImportResult> importGroups(
    List<PKGroup> pkGroups, {
    bool overwriteMetadata = false,
    // Default pullOnly preserves current behavior. Step 7 of the plan
    // wires the user's actual sync direction at top-level call sites
    // so push-disabled users skip the destructive reconcile entirely.
    PkSyncDirection direction = PkSyncDirection.pullOnly,
  }) async {
    var result = const PkGroupsImportResult();
    if (pkGroups.isEmpty) return result;
    // Step 4 of docs/plans/pk-group-membership-push.md: pull-side work is
    // gated on direction.pullEnabled. push-side work is the orchestrator's
    // job (step 6) — this function never pushes. On pushOnly/disabled, we
    // skip the entire pull pass: no metadata writes, no last_seen_from_pk_at
    // updates, no destructive reconcile, no inserts.
    if (!direction.pullEnabled) return result;
    final syncEnabled = await _pkGroupSyncV2Enabled();

    // Resolve members once up front so we know which PK UUIDs are locally
    // available *right now*. The authoritative set (R1) is the PK list, not
    // this map — the map only tells us which PK UUIDs map to a local row.
    final allMembers = await _memberRepository.getAllMembers();
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
        // Existing row. Refresh last_seen_from_pk_at always; only update
        // metadata when the caller asked us to (R5). Never touch emoji (R8).
        // Preserved across PK pulls — never overwrite avatar_image_data without an explicit migration plan.
        final updates = MemberGroupsCompanion(
          id: Value(existing.id),
          lastSeenFromPkAt: Value(now),
          pluralkitId: Value(pk.id),
          pluralkitUuid: Value(pk.uuid),
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
        await (_db.update(
          _db.memberGroups,
        )..where((g) => g.id.equals(existing.id))).write(updates);
        final updatedRow = await _loadGroupRow(existing.id);
        if (syncEnabled) {
          // Mirrors the columns the companion above writes — see
          // `lib/data/sync/field_diff.dart` on why update patches stay narrow.
          final changedFields = <String, dynamic>{
            'last_seen_from_pk_at': toSyncUtcOrNull(updatedRow.lastSeenFromPkAt),
            'pluralkit_id': updatedRow.pluralkitId,
            'pluralkit_uuid': updatedRow.pluralkitUuid,
            if (overwriteMetadata) ...{
              'name': updatedRow.name,
              'description': updatedRow.description,
              'color_hex': updatedRow.colorHex,
            },
          };
          await _emitUpdate(
            _groupTable,
            deriveGroupSyncEntityId(pk.uuid),
            changedFields,
          );
          await _emitLegacyAliasDeletesForPkGroup(pk.uuid);
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
      );
      if (syncEnabled) {
        await _emitMembershipSync(delta);
      }
      result = result.copyWith(
        entriesInserted: result.entriesInserted + delta.entriesInserted,
        entriesRemoved: result.entriesRemoved + delta.entriesRemoved,
        entriesDeferred: result.entriesDeferred + delta.entriesDeferred,
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

    final allMembers = await _memberRepository.getAllMembers();
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
    required List<domain.Member> allMembers,
    required Map<String, String> pkUuidToLocalMemberId,
    required bool insertOnly,
  }) async {
    final memberById = <String, domain.Member>{
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
    final insertedEntries = <_SyncedEntry>[];
    final removedEntryIds = <String>[];

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
          // PK-linked member, not in authoritative set → soft-delete.
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
    final legacyEntityIds = <String>{};
    for (final alias in aliases) {
      final legacyEntityId = alias.legacyEntityId.trim();
      if (legacyEntityId.isEmpty || legacyEntityId == canonicalEntityId) {
        continue;
      }
      legacyEntityIds.add(legacyEntityId);
    }
    for (final legacyEntityId in legacyEntityIds) {
      await _emitDelete(_groupTable, legacyEntityId);
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
        await _emitUpdate(_entryTable, entry.id, fields);
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

      // Pre-push CRDT-conflict compensation (v3-patches-2 #8). state
      // disagrees with intent → flip intent, skip push this round.
      final isAdd = entry.pendingPkOp == 'push_add';
      final isRemove = entry.pendingPkOp == 'push_remove';
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
        // Symmetric: tombstone got revived. Queue an add.
        final hits = await _dao.flipPendingPkOpGuarded(
          entry.id,
          from: 'push_remove',
          to: 'push_add',
          expectedIsDeleted: false,
        );
        if (hits > 0) compensated++;
        continue;
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
      // Network / typed errors that aren't PluralKitApiError (auth, rate
      // limit, generic). Leave pending; queue handles 429 backoff.
      debugPrint('[PK push] addMembersToGroup($groupPkUuid) failed: $e');
      return result.copyWith(failed: result.failed + candidates.length);
    }
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
      if (e.statusCode == 404) {
        // PK group is gone — terminal policy. 2nd-pass review [P3]:
        // we have to handle BOTH push_add AND push_remove rows in the same
        // group atomically, otherwise a later push_remove bucket for the
        // same gone group will see its tombstones already cleared to
        // pending=none and the guarded DELETE will miss → zombie. Use the
        // shared helper that hard-deletes remove tombstones first, then
        // clears the rest. push_add candidates count as stranded (no
        // local row hard-delete needed; they stay active as local-only).
        await _terminalCleanupForGoneGroup(groupPkUuid);
        return result.copyWith(stranded: result.stranded + candidates.length);
      }
      // Refetch failed for some other reason — leave the bucket pending.
      debugPrint(
        '[PK push] refetch /groups/$groupPkUuid/members ${e.statusCode}',
      );
      return result.copyWith(failed: result.failed + candidates.length);
    } catch (e) {
      debugPrint('[PK push] refetch /groups/$groupPkUuid/members failed: $e');
      return result.copyWith(failed: result.failed + candidates.length);
    }

    var added = 0;
    var failed = 0;
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
        // Group-absence alone is not a terminal signal; leave pending.
        failed++;
      }
    }
    return result.copyWith(
      added: result.added + added,
      failed: result.failed + failed,
    );
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
      if (e.statusCode == 404) {
        // PK group is gone — desired remove satisfied for every candidate.
        // Use the shared terminal-cleanup helper which hard-deletes ALL
        // push_remove tombstones in the group first (including any not in
        // this bucket), then clears push_add to none. 2nd-pass review
        // [P3]: a single bucket's local hard-delete is not enough
        // when another bucket for the same gone group runs after this one.
        final removed = await _terminalCleanupForGoneGroup(groupPkUuid);
        return result.copyWith(removed: result.removed + removed);
      }
      debugPrint(
        '[PK push] refetch /groups/$groupPkUuid/members ${e.statusCode}',
      );
      return result.copyWith(failed: result.failed + candidates.length);
    } catch (e) {
      debugPrint('[PK push] refetch /groups/$groupPkUuid/members failed: $e');
      return result.copyWith(failed: result.failed + candidates.length);
    }

    var removed = 0;
    var failed = 0;
    for (final c in candidates) {
      if (!authoritative.contains(c.memberPkUuid)) {
        // Member is not in PK — desired remove satisfied. Hard-delete.
        final hits = await _dao.hardDeleteRemoveTombstoneGuarded(c.entryId);
        if (hits > 0) removed++;
      } else {
        // PK still has the member — leave pending for retry.
        failed++;
      }
    }
    return result.copyWith(
      removed: result.removed + removed,
      failed: result.failed + failed,
    );
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

class _ReconcileDelta {
  final int entriesInserted;
  final int entriesRemoved;
  final int entriesDeferred;
  final List<_SyncedEntry> insertedEntries;
  final List<String> removedEntryIds;
  const _ReconcileDelta({
    required this.entriesInserted,
    required this.entriesRemoved,
    required this.entriesDeferred,
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

  const PkGroupMembershipPushResult({
    this.added = 0,
    this.removed = 0,
    this.failed = 0,
    this.stranded = 0,
    this.compensated = 0,
  });

  PkGroupMembershipPushResult copyWith({
    int? added,
    int? removed,
    int? failed,
    int? stranded,
    int? compensated,
  }) {
    return PkGroupMembershipPushResult(
      added: added ?? this.added,
      removed: removed ?? this.removed,
      failed: failed ?? this.failed,
      stranded: stranded ?? this.stranded,
      compensated: compensated ?? this.compensated,
    );
  }
}
