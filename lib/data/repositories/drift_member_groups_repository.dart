import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/pk_alias_guards.dart';
import 'package:prism_plurality/core/sync/pk_incarnation_ids.dart';
import 'package:prism_plurality/core/sync/tombstone_gate.dart';
import 'package:prism_plurality/shared/utils/avatar_normalizer.dart';
import 'package:prism_plurality/core/database/daos/member_groups_dao.dart';
import 'package:prism_plurality/data/mappers/member_group_mapper.dart';
import 'package:prism_plurality/data/mappers/member_group_entry_mapper.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/data/sync/field_diff.dart';
import 'package:prism_plurality/data/utils/sync_datetime.dart';
import 'package:prism_plurality/domain/models/group_sort_mode.dart';
import 'package:prism_plurality/domain/models/group_sort_state.dart';
import 'package:prism_plurality/domain/models/member.dart' as member_domain;
import 'package:prism_plurality/domain/models/member_group.dart' as domain;
import 'package:prism_plurality/domain/models/member_group_entry.dart'
    as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/domain/repositories/member_groups_repository.dart';
import 'package:prism_plurality/domain/repositories/snapshot_apply_result.dart';

class DriftMemberGroupsRepository
    with SyncRecordMixin
    implements MemberGroupsRepository {
  final MemberGroupsDao _dao;
  final MemberRepository _memberRepository;
  final ffi.PrismSyncHandle? _syncHandle;

  /// Engine-backed view of absorbing-tombstone state for sanctioned revive.
  /// Built from [_syncHandle]; `null` when no handle is wired (pre-pairing /
  /// most unit tests), in which case the re-add path keeps the legacy gen-0 id.
  /// Overridable so fakes can drive the mint loop in tests.
  final TombstoneGate? _tombstoneGate;

  @override
  ffi.PrismSyncHandle? get syncHandle => _syncHandle;

  static const _groupTable = 'member_groups';
  static const _entryTable = 'member_group_entries';

  DriftMemberGroupsRepository(
    this._dao,
    this._syncHandle, {
    MemberRepository? memberRepository,
    @visibleForTesting TombstoneGate? tombstoneGate,
  }) : _memberRepository = memberRepository ?? const _NoopMemberRepository(),
       _tombstoneGate =
           tombstoneGate ?? TombstoneGate.forHandle(_syncHandle);

  @override
  Stream<List<domain.MemberGroup>> watchAllGroups() {
    return _dao.watchAllGroups().map(
      (rows) => rows.map(MemberGroupMapper.toDomain).toList(),
    );
  }

  @override
  Future<List<domain.MemberGroup>> getAllGroups() async {
    final rows = await _dao.getAllActiveGroups();
    return rows.map(MemberGroupMapper.toDomain).toList();
  }

  @override
  Stream<domain.MemberGroup?> watchGroupById(String id) {
    return _dao
        .watchGroupById(id)
        .map((row) => row != null ? MemberGroupMapper.toDomain(row) : null);
  }

  @override
  Stream<List<domain.MemberGroup>> watchGroupsForMember(String memberId) {
    return _dao
        .watchGroupsForMember(memberId)
        .map((rows) => rows.map(MemberGroupMapper.toDomain).toList());
  }

  @override
  Stream<List<domain.MemberGroupEntry>> watchGroupEntries(String groupId) {
    return _dao
        .watchGroupEntries(groupId)
        .map((rows) => rows.map(MemberGroupEntryMapper.toDomain).toList());
  }

  @override
  Stream<List<domain.MemberGroupEntry>> watchAllGroupEntries() {
    return _dao.watchAllGroupEntries().map(
      (rows) => rows.map(MemberGroupEntryMapper.toDomain).toList(),
    );
  }

  @override
  Future<List<domain.MemberGroupEntry>> getAllGroupEntries() async {
    final rows = await _dao.getAllGroupEntries();
    return rows.map(MemberGroupEntryMapper.toDomain).toList();
  }

  @override
  Stream<Map<String, int>> watchMemberCountsByGroup() {
    return _dao.watchMemberCountsByGroup();
  }

  @override
  Future<void> createGroup(domain.MemberGroup group) async {
    final normalized = _normalizeGroup(group);
    final displayOrder = await _dao.nextDisplayOrder(normalized.parentGroupId);
    final withOrder = normalized.copyWith(displayOrder: displayOrder);
    final companion = MemberGroupMapper.toCompanion(withOrder);
    await _dao.createGroup(companion);
    final stored = await _requireGroupRow(withOrder.id);
    await _syncGroupCreateIfAllowed(stored);
  }

  @override
  Future<void> updateGroup(domain.MemberGroup group) async {
    final normalized = _normalizeGroup(group);
    // Read BEFORE the DAO write so the diff sees the pre-update state. The
    // DAO's `updateGroup` does NOT filter active rows (member_groups_dao.dart
    // :117), so the `existingRow.isDeleted` guard is load-bearing: without
    // it, a stale caller could resurrect a tombstoned group.
    final existingRow = await _dao.getGroupById(normalized.id);
    if (existingRow == null || existingRow.isDeleted) return;

    final changedFields = diffSyncFields(
      _groupFieldsFromRow(existingRow),
      _groupDomainFields(normalized),
    );
    if (changedFields.isEmpty) return;

    final companion = _partialGroupCompanion(changedFields);
    await _dao.updateGroup(normalized.id, companion);

    // Preserve the existing PK-link gating + suppression + legacy alias
    // emission semantics. We must re-read the row because
    // `_groupEntityId(stored)` / `_syncLegacyPkGroupAliasDeletes(stored)`
    // need post-write group identity (e.g. if a future writer ever flips
    // pluralkit_uuid here). For now this is functionally equivalent to using
    // `existingRow` since the patch never touches PK columns, but the
    // re-read keeps the helper contract stable.
    final stored = await _requireGroupRow(normalized.id);
    if (await _dao.isGroupSyncSuppressed(stored.id)) return;
    if (!await _shouldEmitPkBackedGroupSync(stored)) return;
    await syncRecordUpdate(_groupTable, _groupEntityId(stored), changedFields);
    await _syncLegacyPkGroupAliasDeletes(stored);
  }

  @override
  Future<void> reorderGroups(List<domain.MemberGroup> groups) async {
    final changedGroups = <domain.MemberGroup>[];
    final displayOrders = <String, int>{};

    for (var i = 0; i < groups.length; i++) {
      final group = groups[i];
      if (group.displayOrder == i) continue;
      final updated = group.copyWith(displayOrder: i);
      changedGroups.add(updated);
      displayOrders[updated.id] = i;
    }

    if (changedGroups.isEmpty) return;

    await _dao.bulkUpdateDisplayOrders(displayOrders);
    for (final group in changedGroups) {
      final stored = await _dao.getGroupById(group.id);
      if (stored == null) continue;
      await _syncGroupUpdateIfAllowed(stored, {
        'display_order': group.displayOrder,
      });
    }
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    // Fetch entries before the delete so we can emit ops for them.
    final entries = await _dao.entriesForGroup(groupId);
    final group = await _dao.getGroupById(groupId);
    final groupEntityId = _groupEntityId(group, fallbackId: groupId);
    final membersById = <String, member_domain.Member>{};
    for (final member in await _memberRepository.getMembersByIds(
      entries.map((entry) => entry.memberId).toSet().toList(),
    )) {
      membersById[member.id] = member;
    }
    final isSuppressed = await _dao.isGroupSyncSuppressed(groupId);
    await _dao.deleteGroup(groupId);
    if (isSuppressed) return;
    if (!await _shouldEmitPkBackedGroupSync(group)) return;
    final entryEntityIds = [
      for (final entry in entries)
        _entryEntityIdForDelete(
          group: group,
          entry: entry,
          member: membersById[entry.memberId],
        ),
    ];
    // Entry tombstones (coalesced) before the group tombstone, so peers see
    // child deletes before the parent — the single group delete gets a later
    // HLC than the bulk entry batch.
    await syncRecordDeleteMulti(_entryTable, entryEntityIds);
    await syncRecordDelete(_groupTable, groupEntityId);
    await _syncLegacyPkGroupAliasDeletes(group);
  }

  @override
  Future<void> promoteChildrenToRoot(String groupId) async {
    final group = await _dao.getGroupById(groupId);
    final groupEntityId = _groupEntityId(group, fallbackId: groupId);
    final children = await _dao.getDirectChildrenOf(groupId);
    final promotedModels = children.map((child) {
      return MemberGroupMapper.toDomain(child).copyWith(parentGroupId: null);
    }).toList();
    final entries = await _dao.entriesForGroup(groupId);
    final membersById = <String, member_domain.Member>{};
    for (final member in await _memberRepository.getMembersByIds(
      entries.map((entry) => entry.memberId).toSet().toList(),
    )) {
      membersById[member.id] = member;
    }
    final isDeletedGroupSuppressed = await _dao.isGroupSyncSuppressed(groupId);

    await _dao.transaction(() async {
      for (final promoted in promotedModels) {
        await _dao.updateGroup(
          promoted.id,
          MemberGroupMapper.toCompanion(promoted),
        );
      }
      await _dao.deleteGroup(groupId);
    });

    for (final promoted in promotedModels) {
      final stored = await _requireGroupRow(promoted.id);
      await _syncGroupUpdateIfAllowed(stored, const <String, dynamic>{
        'parent_group_id': null,
      });
    }
    if (isDeletedGroupSuppressed) return;
    if (!await _shouldEmitPkBackedGroupSync(group)) return;
    final entryEntityIds = [
      for (final entry in entries)
        _entryEntityIdForDelete(
          group: group,
          entry: entry,
          member: membersById[entry.memberId],
        ),
    ];
    // Entry tombstones (coalesced) before the group tombstone, so peers see
    // child deletes before the parent — the single group delete gets a later
    // HLC than the bulk entry batch.
    await syncRecordDeleteMulti(_entryTable, entryEntityIds);
    await syncRecordDelete(_groupTable, groupEntityId);
    await _syncLegacyPkGroupAliasDeletes(group);
  }

  @override
  Future<void> deleteGroupWithDescendants(String groupId) async {
    // BFS to collect all descendant IDs (max 3 levels, so at most ~100 groups).
    final allGroups = await _dao.getAllActiveGroups();
    final byParent = <String, List<String>>{};
    for (final g in allGroups) {
      if (g.parentGroupId != null) {
        byParent.putIfAbsent(g.parentGroupId!, () => []).add(g.id);
      }
    }
    final toDelete = <String>{};
    final queue = [groupId];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      toDelete.add(current);
      queue.addAll(
        (byParent[current] ?? []).where((id) => !toDelete.contains(id)),
      );
    }

    // Pre-fetch entries for sync ops before the transaction deletes them.
    final entriesByGroup = <String, List<domain.MemberGroupEntry>>{};
    final groupRowsById = <String, MemberGroupRow?>{};
    final suppressedByGroup = <String, bool>{};
    final membersById = <String, member_domain.Member>{};
    for (final id in toDelete) {
      entriesByGroup[id] = (await _dao.entriesForGroup(
        id,
      )).map(MemberGroupEntryMapper.toDomain).toList();
      groupRowsById[id] = await _dao.getGroupById(id);
      suppressedByGroup[id] = await _dao.isGroupSyncSuppressed(id);
    }
    final memberIds = entriesByGroup.values
        .expand((entries) => entries.map((entry) => entry.memberId))
        .toSet()
        .toList();
    for (final member in await _memberRepository.getMembersByIds(memberIds)) {
      membersById[member.id] = member;
    }

    await _dao.transaction(() async {
      for (final id in toDelete) {
        await _dao.deleteGroup(id);
      }
    });

    for (final id in toDelete) {
      if (suppressedByGroup[id] ?? false) continue;
      if (!await _shouldEmitPkBackedGroupSync(groupRowsById[id])) continue;
      final entryEntityIds = <String>[
        for (final entry in entriesByGroup[id] ?? [])
          _entryEntityIdForDelete(
            group: groupRowsById[id],
            entry: entry,
            member: membersById[entry.memberId],
          ),
      ];
      await syncRecordDeleteMulti(_entryTable, entryEntityIds);
      await syncRecordDelete(
        _groupTable,
        _groupEntityId(groupRowsById[id], fallbackId: id),
      );
      await _syncLegacyPkGroupAliasDeletes(groupRowsById[id]);
    }
  }

  @override
  Future<void> addMemberToGroup(
    String groupId,
    String memberId,
    String entryId,
  ) async {
    final existing = await _dao.findEntry(groupId, memberId);
    if (existing != null) return;
    final group = await _requireGroupRow(groupId);
    final member = await _memberRepository.getMemberById(memberId);
    // PK push intent (step 3 of docs/plans/pk-group-membership-push.md): a
    // PK-linked add (both group AND member have PK UUIDs) sets push_add so
    // the orchestrator pushes it to PluralKit on the next sync. For
    // non-PK-linked entries, pending_pk_op stays 'none' (nothing to push).
    final isPkLinked =
        (group.pluralkitUuid ?? '').isNotEmpty &&
        (member?.pluralkitUuid ?? '').isNotEmpty;
    final pendingPkOp = isPkLinked ? 'push_add' : 'none';

    // Sanctioned revive: for a PK-linked re-add, the deterministic gen-0 sha id
    // may be a peer tombstone burned in the CRDT — reviving it in place can
    // never propagate (sender strips is_deleted=false, peers drop every op on
    // the tombstoned entity). Consult the engine's tombstone state (the gate's
    // read is source of truth even when the pruner hard-deleted the local row)
    // and mint the lowest live incarnation id. A fresh add with no tombstone
    // resolves to gen 0 (legacy id, unchanged). Non-PK entries use the random
    // fallback id and skip the gate. Gate/mint reads run BEFORE the
    // transaction; the create is emitted after commit.
    final minted = isPkLinked
        ? await _mintEntryIncarnation(
            pkGroupUuid: group.pluralkitUuid,
            pkMemberUuid: member?.pluralkitUuid,
            fallbackId: entryId,
          )
        : MintedIncarnation(generation: 0, entityId: entryId);
    final resolvedEntryId = minted.entityId;
    final companion = MemberGroupEntriesCompanion(
      id: Value(resolvedEntryId),
      groupId: Value(groupId),
      memberId: Value(memberId),
      pkGroupUuid: Value(group.pluralkitUuid),
      pkMemberUuid: Value(member?.pluralkitUuid),
      isDeleted: const Value(false),
      pendingPkOp: Value(pendingPkOp),
      syncGeneration: Value(minted.generation),
      // Local-only recency stamp: "row creation or latest local membership
      // mutation". Must be EXPLICIT here — the upsertEntry revive path below is
      // an insertOnConflictUpdate whose DO UPDATE writes only the companion, so
      // `clientDefault` would NOT fire and a revived tombstone would keep its
      // stale stamp, instantly "expiring" the fresh push_add under the
      // age-based retry cap (and dropping it from the removal grace).
      createdAt: Value(DateTime.now()),
    );

    // Entry insert + parent sort_state update in one transaction so a mid-
    // flight exception rolls both back. The two are independent sync
    // records (read path tolerates partial peer arrival), emitted after
    // commit.
    MemberGroupEntryRow? stored;
    bool parentOrderChanged = false;
    await _dao.transaction(() async {
      if (isPkLinked) {
        // upsertEntry on the resolved incarnation id either inserts the fresh
        // gen-N row or revives a prior soft-deleted row at this exact id (a
        // tombstone with pending_pk_op=push_remove that is NOT burned in the
        // CRDT). The companion's push_add intent overwrites whatever pending
        // was queued — the user's revival intent wins, and the next push round
        // restores the member to PK regardless of whether the prior remove
        // already shipped.
        await _dao.upsertEntry(companion);
        if (minted.generation > 0) {
          // Minting a NEW incarnation id (gen>0) leaves the burned gen-(N-1)
          // row soft-deleted with its `pending_pk_op='push_remove'` orphaned —
          // the upsert above wrote the NEW id, so it never reached that stale
          // row. The push orchestrator pushes all add buckets before all remove
          // buckets with no same-edge cross-row dedup, so the stale remove would
          // fire AFTER this fresh add and remove the member from the user's real
          // PluralKit group despite the re-add being the latest intent.
          // Hard-delete the superseded same-edge soft-deleted rows so the minted
          // live row is the only pending intent.
          await _dao.hardDeleteSupersededEntryRowsForEdge(
            groupId: groupId,
            memberId: memberId,
            keepId: resolvedEntryId,
          );
        }
      } else {
        await _dao.createEntry(companion);
      }
      stored = await _dao.findEntry(groupId, memberId);
      if (stored != null) {
        parentOrderChanged = await _appendEntryToManualOrder(group, stored!.id);
      }
    });

    final committedEntry = stored;
    if (committedEntry == null) return;
    await _syncEntryCreateIfAllowed(committedEntry, member: member);
    if (parentOrderChanged) {
      await _emitGroupSortStateUpdateIfAllowed(group.id);
    }
  }

  @override
  Future<void> removeMemberFromGroup(String groupId, String memberId) async {
    final entry = await _dao.findEntry(groupId, memberId);
    if (entry == null) return;
    final group = await _dao.getGroupById(groupId);
    if (group == null) return;
    final member = await _memberRepository.getMemberById(memberId);
    // PK push intent (step 3 of docs/plans/pk-group-membership-push.md): a
    // remove on a PK-linked entry queues push_remove so the orchestrator
    // tells PluralKit on the next sync. For non-PK rows, pending stays 'none'.
    // We always SOFT-delete (never hard-delete from this path); the orchestrator
    // hard-deletes via guarded DELETE after a successful PK push. This is the
    // TOCTOU-safe path: if a push_add for this row was already in flight, the
    // soft-delete-with-push_remove queues a compensating remove that converges
    // PK to the user's current intent regardless of when the in-flight add
    // returned.
    final isPkLinked =
        (group.pluralkitUuid ?? '').isNotEmpty &&
        (member?.pluralkitUuid ?? '').isNotEmpty;
    final entryEntityId = _entryEntityIdForDelete(
      group: group,
      entry: entry,
      member: member,
    );
    final isSuppressed = await _dao.isGroupSyncSuppressed(groupId);

    // Tombstone + manualOrder prune in one transaction; sync emits after.
    bool parentOrderChanged = false;
    await _dao.transaction(() async {
      await _dao.softDeleteEntryWithPendingOp(
        entry.id,
        pendingPkOp: isPkLinked ? 'push_remove' : 'none',
      );
      parentOrderChanged = await _removeEntryFromManualOrder(group, entry.id);
    });

    if (parentOrderChanged) {
      await _emitGroupSortStateUpdateIfAllowed(group.id);
    }
    if (isSuppressed) return;
    if (!await _shouldEmitPkBackedGroupSync(group)) return;
    await syncRecordDelete(_entryTable, entryEntityId);
  }

  @override
  Future<void> emitGroupSyncState(String groupId) async {
    final group = await _dao.getGroupById(groupId);
    if (group == null) return;
    // Intentionally bypass `isGroupSyncSuppressed` — callers invoke this after
    // clearing review flags, and the goal is precisely to re-broadcast the
    // current state so accumulated local edits reach peers.
    if (!await _shouldEmitPkBackedGroupSync(group)) return;
    await syncRecordUpdate(
      _groupTable,
      _groupEntityId(group),
      _groupFields(group),
    );
    final entries = await _dao.entriesForGroup(groupId);
    final memberIds = entries.map((entry) => entry.memberId).toSet().toList();
    final membersById = <String, member_domain.Member>{};
    for (final member in await _memberRepository.getMembersByIds(memberIds)) {
      membersById[member.id] = member;
    }
    for (final entry in entries) {
      final member = membersById[entry.memberId];
      if (!_canEmitPkBackedEntry(entry, group: group, member: member)) {
        continue;
      }
      await syncRecordUpdate(
        _entryTable,
        _entryEntityIdFromStoredEntry(entry, group: group, member: member),
        _entryFields(entry, group: group, member: member),
      );
    }
  }

  @override
  Future<SnapshotApplyResult> setGroupManualOrderSnapshot(
    String groupId,
    List<String> orderedEntryIds,
  ) async {
    final liveEntries = await _dao.entriesForGroup(groupId);
    final liveIds = liveEntries.map((e) => e.id).toSet();
    final suppliedIds = orderedEntryIds.toSet();

    final droppedIds = orderedEntryIds
        .where((id) => !liveIds.contains(id))
        .toList();
    final appendedIds =
        liveIds.where((id) => !suppliedIds.contains(id)).toList()..sort();

    // Stable dedupe of the supplied permutation (first occurrence wins).
    // Duplicates in the input must NOT round-trip through the stored column
    // — even if the read path dedupes for display, the raw list ships on
    // the wire to peers. Track duplicates so we can flag the call as
    // recovered (only exact permutations return `applied`).
    final seen = <String>{};
    final retainedSupplied = <String>[];
    final duplicateIds = <String>[];
    for (final id in orderedEntryIds) {
      if (!liveIds.contains(id)) continue; // dropped, handled above
      if (seen.add(id)) {
        retainedSupplied.add(id);
      } else {
        duplicateIds.add(id);
      }
    }
    final finalOrder = [...retainedSupplied, ...appendedIds];

    final newState = GroupSortState(
      mode: GroupSortMode.manual,
      manualOrder: finalOrder,
    );
    final encoded = MemberGroupMapper.encodeSortStateForColumn(newState);
    await _dao.updateGroupSortState(groupId, encoded);

    final row = await _dao.getGroupById(groupId);
    if (row != null) {
      await _syncGroupUpdateIfAllowed(row, <String, dynamic>{
        'sort_state': sanitizeSortStateForEmission(
          row.sortState,
          contextId: row.id,
        ),
      });
    }

    // Duplicates surfaced via `droppedIds` (shared recovery indicator).
    if (droppedIds.isEmpty && appendedIds.isEmpty && duplicateIds.isEmpty) {
      return const SnapshotApplyResult.applied();
    }
    return SnapshotApplyResult.recovered(
      droppedIds: [...droppedIds, ...duplicateIds],
      appendedIds: appendedIds,
    );
  }

  @override
  Future<void> setGroupSortMode(String groupId, GroupSortMode mode) async {
    final row = await _dao.getGroupById(groupId);
    if (row == null) return;

    // Corrupt-JSON fallback drops prior manualOrder; apply-time validation
    // should keep this from happening in practice.
    final current =
        tryDecodeSortState(row.sortState) ?? GroupSortState.manualEmpty;
    final newState = current.copyWith(mode: mode);
    final encoded = MemberGroupMapper.encodeSortStateForColumn(newState);
    await _dao.updateGroupSortState(groupId, encoded);

    final refreshed = await _dao.getGroupById(groupId);
    if (refreshed != null) {
      await _syncGroupUpdateIfAllowed(refreshed, <String, dynamic>{
        'sort_state': sanitizeSortStateForEmission(
          refreshed.sortState,
          contextId: refreshed.id,
        ),
      });
    }
  }

  /// No-op outside manual mode. Must run inside `_dao.transaction(...)` —
  /// caller pairs this with the entry insert. Returns `true` if the column
  /// changed (caller emits the parent sync update after commit).
  Future<bool> _appendEntryToManualOrder(
    MemberGroupRow group,
    String entryId,
  ) async {
    final current = tryDecodeSortState(group.sortState);
    if (current == null || !current.isManual) return false;
    if (current.manualOrder.contains(entryId)) return false;

    final newState = current.copyWith(
      manualOrder: [...current.manualOrder, entryId],
    );
    final encoded = MemberGroupMapper.encodeSortStateForColumn(newState);
    await _dao.updateGroupSortState(group.id, encoded);
    return true;
  }

  /// Mirrors [_appendEntryToManualOrder]. The `isManual` guard matters:
  /// [setGroupSortMode] preserves `manualOrder` across sorted-mode flips,
  /// so pruning in sorted mode would destroy that and emit a stray update.
  Future<bool> _removeEntryFromManualOrder(
    MemberGroupRow group,
    String entryId,
  ) async {
    final current = tryDecodeSortState(group.sortState);
    if (current == null || !current.isManual) return false;
    if (!current.manualOrder.contains(entryId)) return false;

    final newOrder = current.manualOrder
        .where((id) => id != entryId)
        .toList(growable: false);
    final newState = current.copyWith(manualOrder: newOrder);
    final encoded = MemberGroupMapper.encodeSortStateForColumn(newState);
    await _dao.updateGroupSortState(group.id, encoded);
    return true;
  }

  /// Re-reads [groupId] and emits a `{sort_state}` patch after a local
  /// sort_state mutation. Honors suppression + PK gating.
  Future<void> _emitGroupSortStateUpdateIfAllowed(String groupId) async {
    final refreshed = await _dao.getGroupById(groupId);
    if (refreshed == null) return;
    await _syncGroupUpdateIfAllowed(refreshed, <String, dynamic>{
      'sort_state': sanitizeSortStateForEmission(
        refreshed.sortState,
        contextId: refreshed.id,
      ),
    });
  }

  Future<void> _syncGroupCreateIfAllowed(MemberGroupRow group) async {
    if (await _dao.isGroupSyncSuppressed(group.id)) return;
    if (!await _shouldEmitPkBackedGroupSync(group)) return;
    await syncRecordCreate(
      _groupTable,
      _groupEntityId(group),
      _groupFields(group),
    );
    await _syncLegacyPkGroupAliasDeletes(group);
  }

  /// Emit a narrow `member_groups` sync update. Honors suppression + PK
  /// gating + legacy alias emission. `is_deleted` belongs to
  /// [syncRecordDelete] / [syncRecordCreate]; see `lib/data/sync/field_diff.dart`.
  Future<void> _syncGroupUpdateIfAllowed(
    MemberGroupRow group,
    Map<String, dynamic> changedFields,
  ) async {
    assert(
      !changedFields.containsKey('is_deleted'),
      'is_deleted must not appear in a member_groups update patch',
    );
    if (changedFields.isEmpty) return;
    if (await _dao.isGroupSyncSuppressed(group.id)) return;
    if (!await _shouldEmitPkBackedGroupSync(group)) return;
    await syncRecordUpdate(_groupTable, _groupEntityId(group), changedFields);
    await _syncLegacyPkGroupAliasDeletes(group);
  }

  Future<void> _syncEntryCreateIfAllowed(
    MemberGroupEntryRow entry, {
    member_domain.Member? member,
  }) async {
    if (await _dao.isGroupSyncSuppressed(entry.groupId)) return;
    final resolvedMember =
        member ?? await _memberRepository.getMemberById(entry.memberId);
    final group = await _requireGroupRow(entry.groupId);
    if (!await _shouldEmitPkBackedGroupSync(group)) return;
    if (!_canEmitPkBackedEntry(entry, group: group, member: resolvedMember)) {
      return;
    }
    await syncRecordCreate(
      _entryTable,
      _entryEntityIdFromStoredEntry(
        entry,
        group: group,
        member: resolvedMember,
      ),
      _entryFields(entry, group: group, member: resolvedMember),
    );
  }

  Future<bool> _shouldEmitPkBackedGroupSync(MemberGroupRow? group) async {
    final pkUuid = group?.pluralkitUuid;
    if (pkUuid == null || pkUuid.isEmpty) return true;
    final settings = await _dao.attachedDatabase.systemSettingsDao
        .getSettings();
    return settings.pkGroupSyncV2Enabled;
  }

  bool _canEmitPkBackedEntry(
    MemberGroupEntryRow entry, {
    required MemberGroupRow group,
    required member_domain.Member? member,
  }) {
    final pkGroupUuid = (entry.pkGroupUuid ?? group.pluralkitUuid ?? '').trim();
    if (pkGroupUuid.isEmpty) return true;

    final pkMemberUuid = (entry.pkMemberUuid ?? member?.pluralkitUuid ?? '')
        .trim();
    return pkMemberUuid.isNotEmpty;
  }

  Future<void> _syncLegacyPkGroupAliasDeletes(MemberGroupRow? group) async {
    final pkGroupUuid = (group?.pluralkitUuid ?? '').trim();
    if (group == null || pkGroupUuid.isEmpty) return;
    final db = _dao.attachedDatabase;
    final canonicalEntityId = _groupEntityId(group);
    final aliases = await db.pkGroupSyncAliasesDao.getByPkGroupUuid(pkGroupUuid);
    final legacyEntityIds = <String>{};
    for (final alias in aliases) {
      final legacyEntityId = alias.legacyEntityId.trim();
      if (legacyEntityId.isEmpty || legacyEntityId == canonicalEntityId) {
        continue;
      }
      // Emitter guard: never emit a delete for an id that is the deterministic
      // hyphen-form self-id ('pk-group-<uuid>') or that matches any active local
      // member_groups row — emitting it would hard-delete a peer's (or this
      // device's own) live PK-group row. On a forbidden alias, PURGE the
      // poisoned row so the recurring re-kill loop terminates.
      if (await isForbiddenAliasTarget(
        db,
        _groupTable,
        legacyEntityId,
        pkGroupUuid,
      )) {
        await db.pkGroupSyncAliasesDao.deleteByLegacyEntityId(
          alias.legacyEntityId,
        );
        continue;
      }
      legacyEntityIds.add(legacyEntityId);
    }
    for (final legacyEntityId in legacyEntityIds) {
      await syncRecordDelete(_groupTable, legacyEntityId);
    }
  }

  domain.MemberGroup _normalizeGroup(domain.MemberGroup group) {
    final normalizedAvatar = AvatarNormalizer.normalize(group.avatarImageData);
    if (normalizedAvatar == group.avatarImageData) {
      return group;
    }
    return group.copyWith(avatarImageData: normalizedAvatar);
  }

  Future<MemberGroupRow> _requireGroupRow(String id) async {
    final row = await _dao.getGroupById(id);
    if (row == null) {
      throw StateError('Missing member group row $id');
    }
    return row;
  }

  String _groupEntityId(MemberGroupRow? group, {String? fallbackId}) {
    final pkUuid = group?.pluralkitUuid;
    if (pkUuid != null && pkUuid.isNotEmpty) {
      // Emit/delete against the row's live incarnation id so a revived group
      // (sync_generation>=1) never targets the burned legacy 'pk-group:<uuid>'
      // entity that peers tombstoned. gen0 is byte-identical to the legacy id.
      return deriveGroupIncarnationEntityId(pkUuid, group?.syncGeneration ?? 0);
    }
    if (group != null) return group.id;
    if (fallbackId != null) return fallbackId;
    throw StateError('Missing member group identity');
  }

  /// Mint the lowest live entry incarnation for the `(pkGroupUuid,
  /// pkMemberUuid)` edge via [TombstoneGate], or fall back to gen 0 when no gate
  /// is wired or the edge isn't PK-backed. The returned generation is persisted
  /// onto the row's `sync_generation` so emit/delete sites target the live id.
  Future<MintedIncarnation> _mintEntryIncarnation({
    required String? pkGroupUuid,
    required String? pkMemberUuid,
    required String fallbackId,
  }) async {
    final gate = _tombstoneGate;
    final gen0Id = deriveEntryIncarnationEntityId(pkGroupUuid, pkMemberUuid, 0);
    // Non-PK edge (no deterministic id) or no engine to consult: keep the
    // legacy gen-0 behavior.
    if (gate == null || gen0Id == null) {
      return MintedIncarnation(generation: 0, entityId: gen0Id ?? fallbackId);
    }
    return gate.mintLiveEntityId(
      _entryTable,
      (gen) =>
          deriveEntryIncarnationEntityId(pkGroupUuid, pkMemberUuid, gen) ??
          fallbackId,
    );
  }

  String _entryEntityIdFromStoredEntry(
    MemberGroupEntryRow entry, {
    required MemberGroupRow group,
    required member_domain.Member? member,
  }) {
    return _entryEntityIdFromPkRefs(
      pkGroupUuid: entry.pkGroupUuid ?? group.pluralkitUuid,
      pkMemberUuid: entry.pkMemberUuid ?? member?.pluralkitUuid,
      fallbackId: entry.id,
      // The row's stored incarnation: emit/delete target its live id, not the
      // burned gen0 sha.
      generation: entry.syncGeneration,
    );
  }

  String _entryEntityIdFromPkRefs({
    required String? pkGroupUuid,
    required String? pkMemberUuid,
    required String fallbackId,
    int generation = 0,
  }) {
    return deriveEntryIncarnationEntityId(
          pkGroupUuid,
          pkMemberUuid,
          generation,
        ) ??
        fallbackId;
  }

  String _entryEntityIdForDelete({
    required MemberGroupRow? group,
    required MemberGroupEntryRow entry,
    required member_domain.Member? member,
  }) {
    if (group == null) return entry.id;
    return _entryEntityIdFromStoredEntry(entry, group: group, member: member);
  }

  /// Visible-for-testing: builds the group field map this repository hands to
  /// the Rust sync engine for create/update. Exposed so a regression test can
  /// pin every emitted DateTime as Z-suffixed UTC.
  @visibleForTesting
  Map<String, dynamic> debugGroupFields(MemberGroupRow row) =>
      _groupFields(row);

  Map<String, dynamic> _groupFields(MemberGroupRow row) => groupFields(row);

  /// "Previous" side of the [updateGroup] diff: builds a field map from the
  /// stored row over the columns [updateGroup] is allowed to write.
  ///
  /// The PK-link columns (`pluralkit_id`, `pluralkit_uuid`,
  /// `last_seen_from_pk_at`) and `is_deleted` are intentionally omitted on
  /// both sides of the diff — `updateGroup` never touches them, and the
  /// domain object does not carry them. Including them here would make
  /// unchanged PK columns look like null-clears against
  /// [_groupDomainFields].
  ///
  /// `sort_state` passes through the stored string verbatim. The to-domain
  /// helper encodes the structured `GroupSortState` via
  /// [MemberGroupMapper.encodeSortStateForColumn]; for a clean stored row
  /// the round-trip is byte-equal, so an unchanged group diffs empty.
  Map<String, dynamic> _groupFieldsFromRow(MemberGroupRow row) {
    return {
      'name': row.name,
      'description': row.description,
      'color_hex': row.colorHex,
      'emoji': row.emoji,
      'avatar_image_data': row.avatarImageData != null
          ? base64Encode(row.avatarImageData!)
          : null,
      'display_order': row.displayOrder,
      'parent_group_id': row.parentGroupId,
      'group_type': row.groupType,
      'filter_rules': row.filterRules,
      'created_at': toSyncUtc(row.createdAt),
      'sort_state': row.sortState,
      'is_deleted': row.isDeleted,
    };
  }

  /// "Next" side of the [updateGroup] diff: builds a field map from the
  /// domain [domain.MemberGroup] over the same columns as
  /// [_groupFieldsFromRow]. Mirrors what [MemberGroupMapper.toCompanion]
  /// would write.
  Map<String, dynamic> _groupDomainFields(domain.MemberGroup g) {
    return {
      'name': g.name,
      'description': g.description,
      'color_hex': g.colorHex,
      'emoji': g.emoji,
      'avatar_image_data': g.avatarImageData != null
          ? base64Encode(g.avatarImageData!)
          : null,
      'display_order': g.displayOrder,
      'parent_group_id': g.parentGroupId,
      'group_type': g.groupType,
      'filter_rules': g.filterRules,
      'created_at': toSyncUtc(g.createdAt),
      'sort_state': MemberGroupMapper.encodeSortStateForColumn(g.sortState),
      'is_deleted': false,
    };
  }

  /// Build a sparse [MemberGroupsCompanion] from a patch map produced by
  /// [diffSyncFields]. Unmentioned keys stay [Value.absent]. Only the
  /// columns [updateGroup] is allowed to write are represented here —
  /// PK-link columns and `is_deleted` are deliberately omitted to keep the
  /// repository's tombstone/PK semantics owned by their dedicated methods.
  MemberGroupsCompanion _partialGroupCompanion(Map<String, dynamic> fields) {
    return MemberGroupsCompanion(
      name: fields.containsKey('name')
          ? Value(fields['name'] as String)
          : const Value.absent(),
      description: fields.containsKey('description')
          ? Value(fields['description'] as String?)
          : const Value.absent(),
      colorHex: fields.containsKey('color_hex')
          ? Value(fields['color_hex'] as String?)
          : const Value.absent(),
      emoji: fields.containsKey('emoji')
          ? Value(fields['emoji'] as String?)
          : const Value.absent(),
      avatarImageData: fields.containsKey('avatar_image_data')
          ? Value(
              fields['avatar_image_data'] == null
                  ? null
                  : base64Decode(fields['avatar_image_data'] as String),
            )
          : const Value.absent(),
      displayOrder: fields.containsKey('display_order')
          ? Value(fields['display_order'] as int)
          : const Value.absent(),
      parentGroupId: fields.containsKey('parent_group_id')
          ? Value(fields['parent_group_id'] as String?)
          : const Value.absent(),
      groupType: fields.containsKey('group_type')
          ? Value(fields['group_type'] as int)
          : const Value.absent(),
      filterRules: fields.containsKey('filter_rules')
          ? Value(fields['filter_rules'] as String?)
          : const Value.absent(),
      createdAt: fields.containsKey('created_at')
          ? Value(parseSyncDateTime(fields['created_at']))
          : const Value.absent(),
      sortState: fields.containsKey('sort_state')
          ? Value(fields['sort_state'] as String)
          : const Value.absent(),
    );
  }

  /// Field-map builder for member-group sync emissions.
  ///
  /// Public so the Phase 6 batch capture path in `sp_importer.dart` can
  /// construct byte-identical `fields` payloads when it bypasses
  /// `createGroup()` for the bulk insert. See
  /// `docs/plans/sp-import-perf-quick-wins.md` (Phase 5 "Field-map reuse").
  static Map<String, dynamic> groupFields(MemberGroupRow row) {
    return {
      'name': row.name,
      'description': row.description,
      'color_hex': row.colorHex,
      'emoji': row.emoji,
      'avatar_image_data': row.avatarImageData != null
          ? base64Encode(row.avatarImageData!)
          : null,
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

  Map<String, dynamic> _entryFields(
    MemberGroupEntryRow entry, {
    required MemberGroupRow group,
    required member_domain.Member? member,
  }) => memberGroupEntryFields(entry, group: group, member: member);

  /// Field-map builder for member-group-entry sync emissions.
  ///
  /// Public so the Phase 6 batch-membership capture path in
  /// `sp_importer.dart` can construct byte-identical `fields` payloads when
  /// it bypasses `addMemberToGroup()` for the bulk insert. See
  /// `docs/plans/sp-import-perf-quick-wins.md` (Phase 5 "Field-map reuse",
  /// and the Phase 6 `addMemberToGroup` parity-test scenarios that gate the
  /// bulk path).
  static Map<String, dynamic> memberGroupEntryFields(
    MemberGroupEntryRow entry, {
    required MemberGroupRow group,
    required member_domain.Member? member,
  }) {
    final pkGroupUuid = entry.pkGroupUuid ?? group.pluralkitUuid;
    final pkMemberUuid = entry.pkMemberUuid ?? member?.pluralkitUuid;
    return {
      'group_id': entry.groupId,
      'member_id': entry.memberId,
      if ((pkGroupUuid ?? '').isNotEmpty) 'pk_group_uuid': pkGroupUuid,
      if ((pkMemberUuid ?? '').isNotEmpty) 'pk_member_uuid': pkMemberUuid,
      'is_deleted': entry.isDeleted,
    };
  }
}

class _NoopMemberRepository implements MemberRepository {
  const _NoopMemberRepository();

  @override
  Future<void> clearPluralKitLink(String id) async {}

  @override
  Future<void> createMember(member_domain.Member member) async {}

  @override
  Future<List<member_domain.Member>> getAllMembersIncludingDeleted() async =>
      const [];

  @override
  Future<void> deleteMember(String id) async {}

  @override
  Future<List<member_domain.Member>> getAllMembers() async => const [];

  @override
  Future<int> getCount() async => 0;

  @override
  Future<List<member_domain.Member>> getDeletedLinkedMembers() async =>
      const [];

  @override
  Future<member_domain.Member?> getMemberById(String id) async => null;

  @override
  Future<List<member_domain.Member>> getMembersByIds(List<String> ids) async =>
      const [];

  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async {}

  @override
  Future<void> updateMember(member_domain.Member member) async {}

  @override
  Future<int> updateMemberFields(
    String id,
    Map<String, dynamic> changedFields,
  ) async => 0;

  @override
  Future<int> applyPluralKitLink(String id, Map<String, dynamic> patch) async =>
      0;

  @override
  Future<int> recordPluralKitIdentity(
    String id,
    Map<String, dynamic> patch,
  ) async => 0;

  @override
  Future<int> excludePluralKitSync(String id) async => 0;

  @override
  Future<int> resumePluralKitSync(String id) async => 0;

  @override
  Stream<List<member_domain.Member>> watchActiveMembers() =>
      const Stream.empty();

  @override
  Stream<List<member_domain.Member>> watchAllMembers() => const Stream.empty();

  @override
  Stream<member_domain.Member?> watchMemberById(String id) =>
      const Stream.empty();

  @override
  Stream<List<member_domain.Member>> watchMembersByIds(List<String> ids) =>
      const Stream.empty();

  @override
  Future<({member_domain.Member member, bool wasCreated})>
  ensureUnknownSentinelMember() => throw UnsupportedError(
    '_NoopMemberRepository does not support ensureUnknownSentinelMember',
  );
}
