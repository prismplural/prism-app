import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/member_groups_table.dart';
import 'package:prism_plurality/core/database/tables/member_group_entries_table.dart';

part 'member_groups_dao.g.dart';

class PkLinkedGroupDuplicateSet {
  const PkLinkedGroupDuplicateSet({
    required this.pkGroupUuid,
    required this.groups,
  });

  final String pkGroupUuid;
  final List<MemberGroupRow> groups;
}

class PkGroupEntryRehomeResult {
  const PkGroupEntryRehomeResult({
    this.movedEntries = 0,
    this.softDeletedConflicts = 0,
  });

  final int movedEntries;
  final int softDeletedConflicts;

  PkGroupEntryRehomeResult copyWith({
    int? movedEntries,
    int? softDeletedConflicts,
  }) {
    return PkGroupEntryRehomeResult(
      movedEntries: movedEntries ?? this.movedEntries,
      softDeletedConflicts: softDeletedConflicts ?? this.softDeletedConflicts,
    );
  }
}

@DriftAccessor(tables: [MemberGroups, MemberGroupEntries])
class MemberGroupsDao extends DatabaseAccessor<AppDatabase>
    with _$MemberGroupsDaoMixin {
  static const _memberGroupsTableName = 'member_groups';
  static const _syncSuppressedColumnName = 'sync_suppressed';
  static const _lookupBatchSize = 500;

  bool? _hasSyncSuppressedColumn;

  MemberGroupsDao(super.db);

  // ── Groups ──────────────────────────────────────────────────────

  Stream<List<MemberGroupRow>> watchAllGroups() =>
      (select(memberGroups)
            ..where((g) => g.isDeleted.equals(false))
            ..orderBy([(g) => OrderingTerm.asc(g.displayOrder)]))
          .watch();

  Stream<MemberGroupRow?> watchGroupById(String id) =>
      (select(memberGroups)
            ..where((g) => g.id.equals(id) & g.isDeleted.equals(false)))
          .watchSingleOrNull();

  Future<MemberGroupRow?> getGroupById(String id) =>
      (select(memberGroups)
            ..where((g) => g.id.equals(id) & g.isDeleted.equals(false)))
          .getSingleOrNull();

  Stream<List<MemberGroupRow>> watchGroupsForMember(String memberId) {
    final entryQuery = select(memberGroupEntries)
      ..where((e) => e.memberId.equals(memberId) & e.isDeleted.equals(false));

    return entryQuery.watch().asyncMap((entries) async {
      if (entries.isEmpty) return <MemberGroupRow>[];
      final groupIds = entries.map((e) => e.groupId).toList();
      return (select(memberGroups)
            ..where((g) => g.id.isIn(groupIds) & g.isDeleted.equals(false))
            ..orderBy([(g) => OrderingTerm.asc(g.displayOrder)]))
          .get();
    });
  }

  Stream<List<MemberGroupEntryRow>> watchGroupEntries(String groupId) {
    final query =
        select(memberGroupEntries).join([
          innerJoin(
            attachedDatabase.members,
            attachedDatabase.members.id.equalsExp(memberGroupEntries.memberId) &
                attachedDatabase.members.isDeleted.equals(false),
          ),
        ])..where(
          memberGroupEntries.groupId.equals(groupId) &
              memberGroupEntries.isDeleted.equals(false),
        );

    return query.watch().map(
      (rows) => rows.map((row) => row.readTable(memberGroupEntries)).toList(),
    );
  }

  Future<int> createGroup(MemberGroupsCompanion companion) =>
      into(memberGroups).insert(companion);

  /// Batch-insert member groups in a single Drift `batch()` round-trip.
  ///
  /// Used by the SP importer's Phase 6 capture-replay path
  /// (`docs/plans/sp-import-perf-quick-wins.md`). Bypasses
  /// [DriftMemberGroupsRepository.createGroup], so the caller is responsible
  /// for pushing a captured op tuple per row using
  /// [DriftMemberGroupsRepository.groupFields].
  Future<void> batchInsertGroups(List<MemberGroupsCompanion> rows) async {
    if (rows.isEmpty) return;
    await batch((b) => b.insertAll(memberGroups, rows));
  }

  Future<void> updateGroup(String id, MemberGroupsCompanion companion) =>
      (update(memberGroups)..where((g) => g.id.equals(id))).write(companion);

  /// Bulk-update display orders in one SQL statement.
  ///
  /// Large nested systems can reorder hundreds or thousands of groups. Keeping
  /// this as one local write avoids a long chain of Drift update calls while
  /// repository code still emits per-row sync updates afterward.
  Future<void> bulkUpdateDisplayOrders(Map<String, int> displayOrders) async {
    if (displayOrders.isEmpty) return;

    final ids = displayOrders.keys.toList(growable: false);
    final whenClauses = ids.map((_) => 'WHEN ? THEN ?').join(' ');
    final wherePlaceholders = List.filled(ids.length, '?').join(', ');
    final variables = <Variable>[];

    for (final entry in displayOrders.entries) {
      variables.add(Variable.withString(entry.key));
      variables.add(Variable.withInt(entry.value));
    }
    variables.addAll(ids.map(Variable.withString));

    await customUpdate(
      '''
      UPDATE member_groups
      SET display_order = CASE id
        $whenClauses
        ELSE display_order
      END
      WHERE id IN ($wherePlaceholders)
      ''',
      variables: variables,
      updates: {memberGroups},
    );
  }

  /// Writes the pre-encoded JSON verbatim — the repository owns serialization.
  Future<int> updateGroupSortState(String groupId, String sortStateJson) =>
      (update(memberGroups)..where((g) => g.id.equals(groupId))).write(
        MemberGroupsCompanion(sortState: Value(sortStateJson)),
      );

  Future<void> deleteGroup(String id) async {
    // Soft-delete entries for this group
    await (update(memberGroupEntries)..where((e) => e.groupId.equals(id)))
        .write(const MemberGroupEntriesCompanion(isDeleted: Value(true)));
    // Soft-delete the group itself. The tombstone KEEPS its `pluralkit_uuid`
    // (M13): the partial unique index only covers active rows, so no
    // collision is possible, and nulling it made the tombstone unfindable by
    // UUID — bypassing the importer's resurrection guard for repair-linked
    // groups. Pairing bootstrap now emits the tombstone under its canonical
    // `pk-group:<uuid>` entity id, matching the original delete op.
    await (update(memberGroups)..where((g) => g.id.equals(id))).write(
      const MemberGroupsCompanion(isDeleted: Value(true)),
    );
  }

  // ── Entries ─────────────────────────────────────────────────────

  Future<int> createEntry(MemberGroupEntriesCompanion companion) =>
      into(memberGroupEntries).insert(companion);

  /// Batch-insert member-group entries in a single Drift `batch()` round-trip.
  ///
  /// Uses `insertAllOnConflictUpdate` so a re-import that hits a deterministic
  /// sha256 entry id whose prior row is soft-deleted revives it — matching
  /// the live-edit `addMemberToGroup` path which calls `upsertEntry` for
  /// PK-linked rows. Non-PK rows use random v4 ids and don't collide on
  /// re-import, so the upsert is a no-op for them.
  ///
  /// Used by the SP importer's Phase 6 capture-replay path
  /// (`docs/plans/sp-import-perf-quick-wins.md`). Bypasses
  /// [DriftMemberGroupsRepository.addMemberToGroup], so the caller is
  /// responsible for pushing a captured op tuple per row using
  /// [DriftMemberGroupsRepository.memberGroupEntryFields]. Suppressed groups
  /// and entries that can't be emitted (per `_canEmitPkBackedEntry` rules)
  /// must be excluded from the captured-tuple list by the caller.
  Future<void> batchInsertEntries(
    List<MemberGroupEntriesCompanion> rows,
  ) async {
    if (rows.isEmpty) return;
    await batch((b) => b.insertAllOnConflictUpdate(memberGroupEntries, rows));
  }

  Future<void> deleteEntry(String id) =>
      (update(memberGroupEntries)..where((e) => e.id.equals(id))).write(
        const MemberGroupEntriesCompanion(isDeleted: Value(true)),
      );

  /// Soft-delete an entry and atomically set its `pending_pk_op` intent
  /// (repository `removeMemberFromGroup`). Also refreshes the local-only
  /// `created_at` recency stamp (M15): the push retry cap measures INTENT
  /// age off this column, so without the refresh a remove queued on an old
  /// row would be "expired" the instant the user queued it.
  Future<void> softDeleteEntryWithPendingOp(
    String id, {
    required String pendingPkOp,
  }) => (update(memberGroupEntries)..where((e) => e.id.equals(id))).write(
    MemberGroupEntriesCompanion(
      isDeleted: const Value(true),
      pendingPkOp: Value(pendingPkOp),
      createdAt: Value(DateTime.now()),
    ),
  );

  /// Guarded re-tombstone for the H6c compensation: re-soft-deletes an entry
  /// a CRDT revive flipped active, but ONLY when the row still matches the
  /// expected state (same `pending_pk_op`, `is_deleted = !expectedActive`).
  /// Returns rows touched (0 or 1); 0 means a concurrent local mutation won
  /// the race — back off. Deliberately does NOT refresh `created_at`: this
  /// re-asserts an EXISTING intent, so the retry-cap clock keeps running.
  Future<int> softDeleteEntryWithPendingOpGuarded(
    String id, {
    required String pendingPkOp,
    required bool expectedActive,
  }) =>
      (update(memberGroupEntries)..where(
            (e) =>
                e.id.equals(id) &
                e.isDeleted.equals(!expectedActive) &
                e.pendingPkOp.equals(pendingPkOp),
          ))
          .write(
            MemberGroupEntriesCompanion(
              isDeleted: const Value(true),
              pendingPkOp: Value(pendingPkOp),
            ),
          );

  // ── Push orchestrator primitives (step 6) ───────────────────────────────
  // These all use guarded WHERE clauses on the row's expected state so a
  // CRDT delete or a concurrent local mutation that changes the row between
  // snapshot and apply causes the operation to MISS rather than corrupt
  // state. The orchestrator then re-reads on the next round and converges.

  /// Guarded flip of `pending_pk_op` from one value to another. Returns the
  /// number of affected rows (0 or 1). Used by the push orchestrator's:
  ///   - 204 cleanup for push_add (`from='push_add'`, `to='none'`,
  ///     `expectedIsDeleted=false`).
  ///   - pre-push CRDT compensation flips:
  ///     * push_add ∧ is_deleted=true → push_remove (the row was deleted
  ///       via CRDT after we set push_add; PK might now be wrong, queue
  ///       a remove to converge).
  ///     * push_remove ∧ is_deleted=false → push_add (CRDT created or
  ///       local revival flipped is_deleted; need to ensure PK has it).
  Future<int> flipPendingPkOpGuarded(
    String id, {
    required String from,
    required String to,
    required bool expectedIsDeleted,
  }) =>
      (update(memberGroupEntries)..where(
            (e) =>
                e.id.equals(id) &
                e.pendingPkOp.equals(from) &
                e.isDeleted.equals(expectedIsDeleted),
          ))
          .write(MemberGroupEntriesCompanion(pendingPkOp: Value(to)));

  /// Guarded hard-delete of a `push_remove` tombstone after PK confirmed
  /// the remove. Returns the number of affected rows. The WHERE clause
  /// requires `is_deleted = 1 AND pending_pk_op = 'push_remove'` so a
  /// row revived to active+push_add via concurrent re-add is preserved
  /// (the conditional misses, the row keeps its new state, the next push
  /// round handles it).
  Future<int> hardDeleteRemoveTombstoneGuarded(String id) =>
      (delete(memberGroupEntries)..where(
            (e) =>
                e.id.equals(id) &
                e.pendingPkOp.equals('push_remove') &
                e.isDeleted.equals(true),
          ))
          .go();

  /// Hard-delete soft-deleted rows for the `(groupId, memberId)` edge that are
  /// being superseded by a freshly-minted incarnation row (R1 re-add). Excludes
  /// [keepId] (the live incarnation row the caller is about to write/just wrote)
  /// and only touches `is_deleted = 1` rows, so the active row is never removed.
  ///
  /// This closes the H6c regression introduced by the incarnation split: a
  /// re-add that mints a NEW gen-N id leaves the old gen-0 row soft-deleted with
  /// its `pending_pk_op = 'push_remove'` orphaned in place. The push orchestrator
  /// iterates ALL pending rows and pushes adds before removes with no same-edge
  /// cross-row dedup, so the stale remove would fire after the fresh add and
  /// remove the member from the user's real PluralKit group despite the re-add
  /// being the latest intent. Removing the orphaned tombstone row here makes the
  /// minted live row the only pending intent for the edge. Returns the number of
  /// rows removed.
  Future<int> hardDeleteSupersededEntryRowsForEdge({
    required String groupId,
    required String memberId,
    required String keepId,
  }) =>
      (delete(memberGroupEntries)..where(
            (e) =>
                e.groupId.equals(groupId) &
                e.memberId.equals(memberId) &
                e.isDeleted.equals(true) &
                e.id.equals(keepId).not(),
          ))
          .go();

  /// Clear `pending_pk_op = 'none'` for every entry in [groupId] whose
  /// pending op is non-'none'. Used by the push orchestrator's terminal
  /// policy when a refetch returns 404 on the group (PK group is gone),
  /// or when the local group lost its PK link before push could run.
  /// Soft-deleted rows stay soft-deleted; active rows stay active. The
  /// existing reconcile no-ops on rows with pending=none and a missing
  /// PK group, so stranded rows do not cause future destructive churn.
  Future<int> clearAllPendingPkOpForGroup(String groupId) => customUpdate(
    "UPDATE member_group_entries SET pending_pk_op = 'none' "
    "WHERE group_id = ? AND pending_pk_op != 'none'",
    variables: [Variable.withString(groupId)],
    updates: {memberGroupEntries},
  );

  /// Flip a peer-originated entry tombstone's `pending_pk_op` to `push_remove`
  /// so the PK-token device converges PluralKit to the user's cross-device
  /// removal (F06, absorbing-tombstone-revive-holes). Guarded to
  /// `is_deleted = 1 AND pending_pk_op = 'none'`: only a SYNCED tombstone (the
  /// local-only `pending_pk_op` arrives as the default 'none' on a peer's
  /// remove) is adopted, so this never clobbers an in-flight local intent
  /// (`push_add`/`push_remove`) or revives an active row. Returns the number of
  /// rows touched (0 or 1); a 0 means the row was active or already carried a
  /// pending op, and the caller leaves it alone.
  ///
  /// Also refreshes the local-only `created_at` recency stamp, exactly as
  /// [softDeleteEntryWithPendingOp] does (wave-3 verifier issue 1, 2026-06 PK
  /// audit M15): this call SETS a new intent on a row that carried none, so the
  /// push orchestrator's age-based retry cap must clock the intent from the
  /// moment of adoption. The F06 sweep adopts tombstones whose apply-stamp is
  /// commonly far older than `PkGroupsImporter.pushRetryMaxAge` (applied
  /// pre-upgrade, or while PK pull was offline) — the precise already-diverged
  /// install this fix exists to converge. Without the refresh that intent is
  /// born expired, so the first non-environmental 4xx on the remove push routes
  /// it through `_isPushCandidateExpired -> hardDeleteRemoveTombstoneGuarded`
  /// and terminally drops the convergence intent with zero retry budget, and
  /// PluralKit keeps the removed member forever.
  Future<int> markEntryPushRemoveGuarded(String id) =>
      (update(memberGroupEntries)..where(
            (e) =>
                e.id.equals(id) &
                e.isDeleted.equals(true) &
                e.pendingPkOp.equals('none'),
          ))
          .write(
            MemberGroupEntriesCompanion(
              pendingPkOp: const Value('push_remove'),
              createdAt: Value(DateTime.now()),
            ),
          );

  Future<void> deleteEntriesForGroup(String groupId) =>
      (update(memberGroupEntries)..where((e) => e.groupId.equals(groupId)))
          .write(const MemberGroupEntriesCompanion(isDeleted: Value(true)));

  /// Watches member counts per group in a single query.
  /// Returns a map of groupId → count.
  Stream<Map<String, int>> watchMemberCountsByGroup() {
    return watchAllGroupEntries().map((entries) {
      final counts = <String, int>{};
      for (final e in entries) {
        counts[e.groupId] = (counts[e.groupId] ?? 0) + 1;
      }
      return counts;
    });
  }

  /// Returns all active group entries across all groups.
  Stream<List<MemberGroupEntryRow>> watchAllGroupEntries() {
    final query = select(memberGroupEntries).join([
      innerJoin(
        attachedDatabase.members,
        attachedDatabase.members.id.equalsExp(memberGroupEntries.memberId) &
            attachedDatabase.members.isDeleted.equals(false),
      ),
    ])..where(memberGroupEntries.isDeleted.equals(false));

    return query.watch().map(
      (rows) => rows.map((row) => row.readTable(memberGroupEntries)).toList(),
    );
  }

  /// Returns all active group entries across all groups as a future.
  Future<List<MemberGroupEntryRow>> getAllGroupEntries() async {
    final query = select(memberGroupEntries).join([
      innerJoin(
        attachedDatabase.members,
        attachedDatabase.members.id.equalsExp(memberGroupEntries.memberId) &
            attachedDatabase.members.isDeleted.equals(false),
      ),
    ])..where(memberGroupEntries.isDeleted.equals(false));

    final rows = await query.get();
    return rows.map((row) => row.readTable(memberGroupEntries)).toList();
  }

  Future<Map<String, int>> activeEntryCountsByGroupId() async {
    final rows = await customSelect(
      '''
      SELECT group_id, COUNT(*) AS entry_count
      FROM member_group_entries
      WHERE is_deleted = 0
      GROUP BY group_id
      ''',
      readsFrom: {memberGroupEntries},
    ).get();

    return {
      for (final row in rows)
        row.read<String>('group_id'): row.read<int>('entry_count'),
    };
  }

  Future<Map<String, Set<String>>> activePkMemberUuidsByGroupId() async {
    final rows = await customSelect(
      '''
      SELECT group_id, pk_member_uuid
      FROM member_group_entries
      WHERE is_deleted = 0
        AND pk_member_uuid IS NOT NULL
        AND pk_member_uuid != ''
      ''',
      readsFrom: {memberGroupEntries},
    ).get();

    final grouped = <String, Set<String>>{};
    for (final row in rows) {
      grouped
          .putIfAbsent(row.read<String>('group_id'), () => <String>{})
          .add(row.read<String>('pk_member_uuid'));
    }
    return grouped;
  }

  Future<Map<String, Set<String>>> activePkMemberUuidsByGroupIds(
    Iterable<String> groupIds,
  ) async {
    final ids = groupIds.toSet().toList(growable: false);
    if (ids.isEmpty) return const <String, Set<String>>{};

    final grouped = <String, Set<String>>{};
    for (var start = 0; start < ids.length; start += _lookupBatchSize) {
      final end = start + _lookupBatchSize > ids.length
          ? ids.length
          : start + _lookupBatchSize;
      final batch = ids.sublist(start, end);
      final rows = await customSelect(
        '''
        SELECT group_id, pk_member_uuid
        FROM member_group_entries
        WHERE is_deleted = 0
          AND group_id IN (${_placeholders(batch.length)})
          AND pk_member_uuid IS NOT NULL
          AND pk_member_uuid != ''
        ''',
        variables: batch.map(Variable.withString).toList(),
        readsFrom: {memberGroupEntries},
      ).get();

      for (final row in rows) {
        grouped
            .putIfAbsent(row.read<String>('group_id'), () => <String>{})
            .add(row.read<String>('pk_member_uuid'));
      }
    }
    return grouped;
  }

  Future<Map<String, Set<String>>> activeLocalOnlyMemberIdsByGroupIds(
    Iterable<String> groupIds,
  ) async {
    final ids = groupIds.toSet().toList(growable: false);
    if (ids.isEmpty) return const <String, Set<String>>{};

    final grouped = <String, Set<String>>{};
    for (var start = 0; start < ids.length; start += _lookupBatchSize) {
      final end = start + _lookupBatchSize > ids.length
          ? ids.length
          : start + _lookupBatchSize;
      final batch = ids.sublist(start, end);
      final rows = await customSelect(
        '''
        SELECT group_id, member_id
        FROM member_group_entries
        WHERE is_deleted = 0
          AND group_id IN (${_placeholders(batch.length)})
          AND (pk_member_uuid IS NULL OR pk_member_uuid = '')
        ''',
        variables: batch.map(Variable.withString).toList(),
        readsFrom: {memberGroupEntries},
      ).get();

      for (final row in rows) {
        grouped
            .putIfAbsent(row.read<String>('group_id'), () => <String>{})
            .add(row.read<String>('member_id'));
      }
    }
    return grouped;
  }

  /// Find an active entry for a specific group + member combination.
  Future<MemberGroupEntryRow?> findEntry(String groupId, String memberId) =>
      (select(memberGroupEntries)..where(
            (e) =>
                e.groupId.equals(groupId) &
                e.memberId.equals(memberId) &
                e.isDeleted.equals(false),
          ))
          .getSingleOrNull();

  /// Active membership entries for a member across all groups.
  Future<List<MemberGroupEntryRow>> activeEntriesForMember(String memberId) =>
      (select(memberGroupEntries)..where(
            (e) => e.memberId.equals(memberId) & e.isDeleted.equals(false),
          ))
          .get();

  /// Read entries for [groupId] that the PK reconcile pass needs to see:
  /// active rows AND soft-deleted rows that still have a pending PK op
  /// queued ('push_remove' tombstones the user wants pushed to PK on the
  /// next sync). The vanilla [entriesForGroup] filters `is_deleted = true`
  /// out, hiding `push_remove` rows from reconcile and letting the insert
  /// branch revive them when PK still reports the member.
  ///
  /// SUPERSEDED for reconcile by [entriesForGroupIncludingDeleted] (F06): this
  /// filter still hides peer-originated tombstones (`is_deleted = 1` with the
  /// local-only `pending_pk_op` at its synced default `'none'`), which the
  /// insert branch then blind-revives. The reconcile pass reads the full list
  /// instead — do NOT reintroduce this method on that path.
  @visibleForTesting
  Future<List<MemberGroupEntryRow>> entriesForGroupForReconcile(
    String groupId,
  ) =>
      (select(memberGroupEntries)..where(
            (e) =>
                e.groupId.equals(groupId) &
                (e.isDeleted.equals(false) |
                    e.pendingPkOp.equals('none').not()),
          ))
          .get();

  /// Read EVERY entry for [groupId], including peer-originated tombstones
  /// ([entriesForGroupForReconcile] minus the `pending_pk_op` filter). F06
  /// (absorbing-tombstone-revive-holes): a tombstone that arrived via CRDT sync
  /// from a peer carries the local-only `pending_pk_op` default `'none'`, so
  /// the reconcile filter hides it and the insert branch blind-revives the
  /// burned deterministic id. The reconcile pass now classifies removals and
  /// inserts over this full list so a peer's removal is honored (the gate
  /// decides skip-vs-revive), never silently un-deleted.
  Future<List<MemberGroupEntryRow>> entriesForGroupIncludingDeleted(
    String groupId,
  ) => (select(memberGroupEntries)
        ..where((e) => e.groupId.equals(groupId)))
      .get();

  /// Read EVERY entry across all groups, including tombstones. The membership
  /// joins of [getAllGroupEntries] would hide rows whose member is itself
  /// deleted; the absorbing-tombstone-revive detector (R6) needs the raw rows so
  /// it can re-derive each row's current incarnation id and compare it against
  /// the engine's `field_versions`. Read-only; no membership filtering.
  Future<List<MemberGroupEntryRow>> getAllEntriesIncludingDeleted() =>
      select(memberGroupEntries).get();

  /// Read every entry with a non-`'none'` pending PK op queued, regardless
  /// of `is_deleted` state. The push orchestrator buckets these by
  /// `(groupPkUuid, op)` and pushes to PK. `push_remove` rows are
  /// soft-deleted by construction; `push_add` rows should be active but
  /// can become soft-deleted via a CRDT delete from another device — the
  /// orchestrator's pre-push validation handles that contradiction.
  Future<List<MemberGroupEntryRow>> entriesWithPendingPkOp() => (select(
    memberGroupEntries,
  )..where((e) => e.pendingPkOp.equals('none').not())).get();

  // ── PluralKit linkage ───────────────────────────────────────────

  /// Look up an existing group by its PluralKit UUID. Identity is UUID-only
  /// (R7): PK short IDs can be recycled, so we never match on them.
  Future<MemberGroupRow?> findByPluralkitUuid(String uuid) async {
    final rows =
        await (select(memberGroups)..where(
              (g) => g.pluralkitUuid.equals(uuid) & g.isDeleted.equals(false),
            ))
            .get();
    if (rows.isEmpty) return null;

    final sorted = [...rows]..sort(_compareActivePkLookupRows);
    return sorted.first;
  }

  Future<MemberGroupRow?> findByPluralkitUuidIncludingDeleted(
    String uuid,
  ) async {
    final rows = await (select(
      memberGroups,
    )..where((g) => g.pluralkitUuid.equals(uuid))).get();
    if (rows.isEmpty) return null;

    final sorted = [...rows]
      ..sort((left, right) {
        if (left.isDeleted != right.isDeleted) {
          return left.isDeleted ? 1 : -1;
        }
        return _compareActivePkLookupRows(left, right);
      });
    return sorted.first;
  }

  Future<List<MemberGroupRow>> getAllGroupsIncludingDeleted() =>
      select(memberGroups).get();

  /// Look up a group by primary-key id INCLUDING tombstoned rows. Primary
  /// lookup for the importer's M13 resurrection guard, and the only one that
  /// catches LEGACY tombstones whose uuid was nulled by the pre-fix
  /// deleteGroup.
  Future<MemberGroupRow?> getGroupByIdIncludingDeleted(String id) =>
      (select(memberGroups)..where((g) => g.id.equals(id))).getSingleOrNull();

  Future<List<MemberGroupRow>> getAllActiveGroups() =>
      (select(memberGroups)..where((g) => g.isDeleted.equals(false))).get();

  /// Backfill missing PK UUID references on active membership rows using the
  /// currently linked local group/member records.
  ///
  /// This is safe to re-run; existing non-empty PK UUID fields are preserved.
  Future<int> backfillActiveEntryPkReferences() {
    return customUpdate(
      '''
      UPDATE member_group_entries
      SET
        pk_group_uuid = COALESCE(
          NULLIF(pk_group_uuid, ''),
          (
            SELECT g.pluralkit_uuid
            FROM member_groups g
            WHERE g.id = member_group_entries.group_id
              AND g.is_deleted = 0
              AND g.pluralkit_uuid IS NOT NULL
              AND g.pluralkit_uuid <> ''
            LIMIT 1
          )
        ),
        pk_member_uuid = COALESCE(
          NULLIF(pk_member_uuid, ''),
          (
            SELECT m.pluralkit_uuid
            FROM members m
            WHERE m.id = member_group_entries.member_id
              AND m.is_deleted = 0
              AND m.pluralkit_uuid IS NOT NULL
              AND m.pluralkit_uuid <> ''
            LIMIT 1
          )
        )
      WHERE is_deleted = 0
        AND (
          (
            NULLIF(pk_group_uuid, '') IS NULL
            AND EXISTS (
              SELECT 1
              FROM member_groups g
              WHERE g.id = member_group_entries.group_id
                AND g.is_deleted = 0
                AND g.pluralkit_uuid IS NOT NULL
                AND g.pluralkit_uuid <> ''
            )
          )
          OR (
            NULLIF(pk_member_uuid, '') IS NULL
            AND EXISTS (
              SELECT 1
              FROM members m
              WHERE m.id = member_group_entries.member_id
                AND m.is_deleted = 0
                AND m.pluralkit_uuid IS NOT NULL
                AND m.pluralkit_uuid <> ''
            )
          )
        )
      ''',
      updates: {memberGroupEntries},
    );
  }

  /// Canonicalizes PK-backed entry IDs by rewriting each active row whose
  /// `pk_group_uuid` + `pk_member_uuid` are set onto the deterministic
  /// `sha256(pkGroupUuid || 0x00 || pkMemberUuid)[:16]` hash the sync layer
  /// already emits. Reviving tombstones under the canonical id when a
  /// matching tombstoned row already exists.
  ///
  /// Idempotent: rows whose `id` already equals the canonical hash are left
  /// alone. Rows without both PK UUIDs set are skipped (non-PK entries).
  ///
  /// Algorithm per row:
  /// 1. Compute `canonical = sha256(pkGroupUuid || 0x00 || pkMemberUuid)[:16]`.
  /// 2. If `id == canonical` skip.
  /// 3. If a tombstoned row (`is_deleted = 1`) already exists under
  ///    `canonical`: promote that tombstone (set `is_deleted = 0` and sync
  ///    the group/member onto the logical edge) and soft-delete the legacy
  ///    active row.
  /// 4. Otherwise rewrite the legacy row's `id` to `canonical`.
  ///
  /// Wrapped in a transaction so repair sees an atomic before/after state
  /// if any row fails mid-pass.
  Future<
    ({int rewritten, int revivedTombstones, int softDeletedLegacyConflicts})
  >
  canonicalizePkBackedEntryIds() {
    return transaction(() async {
      var rewritten = 0;
      var revivedTombstones = 0;
      var softDeletedLegacyConflicts = 0;

      // Scope to active PK-backed entries. Order by id so repeated runs
      // process rows in the same sequence when multiple legacy rows map to
      // the same canonical edge.
      final candidates =
          await (select(memberGroupEntries)
                ..where(
                  (e) =>
                      e.isDeleted.equals(false) &
                      e.pkGroupUuid.isNotNull() &
                      e.pkMemberUuid.isNotNull(),
                )
                ..orderBy([(e) => OrderingTerm.asc(e.id)]))
              .get();

      final idsToLoad = <String>{};
      final canonicalIdsByEntryId = <String, String>{};
      for (final entry in candidates) {
        final pkGroupUuid = entry.pkGroupUuid;
        final pkMemberUuid = entry.pkMemberUuid;
        if (pkGroupUuid == null ||
            pkGroupUuid.isEmpty ||
            pkMemberUuid == null ||
            pkMemberUuid.isEmpty) {
          continue;
        }
        final canonical = _canonicalPkEntryId(pkGroupUuid, pkMemberUuid);
        canonicalIdsByEntryId[entry.id] = canonical;
        idsToLoad
          ..add(entry.id)
          ..add(canonical);
      }

      final byId = <String, MemberGroupEntryRow>{};
      final legacySoftDeleteIds = <String>[];
      final canonicalRevivals =
          <({String id, MemberGroupEntriesCompanion companion})>[];
      final idRewrites = <({String from, String to})>[];
      final idsList = idsToLoad.toList(growable: false);
      for (var start = 0; start < idsList.length; start += _lookupBatchSize) {
        final end = start + _lookupBatchSize > idsList.length
            ? idsList.length
            : start + _lookupBatchSize;
        final batch = idsList.sublist(start, end);
        if (batch.isEmpty) continue;
        final existingRows = await (select(
          memberGroupEntries,
        )..where((e) => e.id.isIn(batch))).get();
        for (final row in existingRows) {
          byId[row.id] = row;
        }
      }

      for (final entry in candidates) {
        final pkGroupUuid = entry.pkGroupUuid;
        final pkMemberUuid = entry.pkMemberUuid;
        if (pkGroupUuid == null ||
            pkGroupUuid.isEmpty ||
            pkMemberUuid == null ||
            pkMemberUuid.isEmpty) {
          continue;
        }

        final canonical = canonicalIdsByEntryId[entry.id]!;
        if (entry.id == canonical) continue;

        final canonicalRow = byId[canonical];

        if (canonicalRow != null && canonicalRow.isDeleted) {
          // Soft-delete the legacy active row first so the partial unique
          // index on (group_id, member_id) WHERE is_deleted = 0 is clear,
          // then revive the tombstoned canonical row onto the logical edge.
          legacySoftDeleteIds.add(entry.id);
          canonicalRevivals.add((
            id: canonical,
            companion: MemberGroupEntriesCompanion(
              groupId: Value(entry.groupId),
              memberId: Value(entry.memberId),
              pkGroupUuid: Value(pkGroupUuid),
              pkMemberUuid: Value(pkMemberUuid),
              isDeleted: const Value(false),
            ),
          ));
          revivedTombstones++;
          softDeletedLegacyConflicts++;
          byId[entry.id] = entry.copyWith(isDeleted: true);
          byId[canonical] = canonicalRow.copyWith(
            groupId: entry.groupId,
            memberId: entry.memberId,
            pkGroupUuid: Value(pkGroupUuid),
            pkMemberUuid: Value(pkMemberUuid),
            isDeleted: false,
          );
          continue;
        }

        if (canonicalRow != null && !canonicalRow.isDeleted) {
          if (canonicalRow.pkGroupUuid == pkGroupUuid &&
              canonicalRow.pkMemberUuid == pkMemberUuid) {
            // The logical edge already has an active canonical row. Keep the
            // canonical row and soft-delete this legacy duplicate so future
            // canonical updates/deletes target the surviving row.
            legacySoftDeleteIds.add(entry.id);
            softDeletedLegacyConflicts++;
            byId[entry.id] = entry.copyWith(isDeleted: true);
          }
          continue;
        }

        // Primary-key rewrite. SQLite permits `UPDATE ... SET id = ?`; the
        // member_group_entries table declares no foreign keys, so this is
        // safe. `member_groups` tables never join on entry ids either.
        idRewrites.add((from: entry.id, to: canonical));
        rewritten++;
        byId
          ..remove(entry.id)
          ..[canonical] = entry.copyWith(id: canonical);
      }

      await _applyCanonicalEntryMutations(
        legacySoftDeleteIds: legacySoftDeleteIds,
        canonicalRevivals: canonicalRevivals,
        idRewrites: idRewrites,
      );

      return (
        rewritten: rewritten,
        revivedTombstones: revivedTombstones,
        softDeletedLegacyConflicts: softDeletedLegacyConflicts,
      );
    });
  }

  Future<void> _applyCanonicalEntryMutations({
    required List<String> legacySoftDeleteIds,
    required List<({String id, MemberGroupEntriesCompanion companion})>
    canonicalRevivals,
    required List<({String from, String to})> idRewrites,
  }) async {
    if (legacySoftDeleteIds.isNotEmpty) {
      await batch((batch) {
        for (final id in legacySoftDeleteIds) {
          batch.update(
            memberGroupEntries,
            const MemberGroupEntriesCompanion(isDeleted: Value(true)),
            where: (entry) => entry.id.equals(id),
          );
        }
      });
    }

    if (canonicalRevivals.isNotEmpty) {
      await batch((batch) {
        for (final revival in canonicalRevivals) {
          batch.update(
            memberGroupEntries,
            revival.companion,
            where: (entry) => entry.id.equals(revival.id),
          );
        }
      });
    }

    for (final rewrite in idRewrites) {
      await customUpdate(
        'UPDATE member_group_entries SET id = ? WHERE id = ?',
        variables: [
          Variable.withString(rewrite.to),
          Variable.withString(rewrite.from),
        ],
        updates: {memberGroupEntries},
      );
    }
  }

  static String _canonicalPkEntryId(String pkGroupUuid, String pkMemberUuid) {
    final joined = '$pkGroupUuid\x00$pkMemberUuid';
    final digest = sha256.convert(utf8.encode(joined));
    return digest.toString().substring(0, 16);
  }

  /// Groups active PK-linked rows that still share the same PK UUID.
  Future<List<PkLinkedGroupDuplicateSet>>
  getActiveLinkedPkGroupDuplicateSets() async {
    final duplicateUuidRows = await customSelect(
      '''
      SELECT pluralkit_uuid
      FROM member_groups
      WHERE is_deleted = 0
        AND pluralkit_uuid IS NOT NULL
        AND pluralkit_uuid != ''
      GROUP BY pluralkit_uuid
      HAVING COUNT(*) > 1
      ''',
      readsFrom: {memberGroups},
    ).get();
    if (duplicateUuidRows.isEmpty) return const <PkLinkedGroupDuplicateSet>[];

    final duplicateUuids = duplicateUuidRows
        .map((row) => row.read<String>('pluralkit_uuid'))
        .toList(growable: false);
    final grouped = <String, List<MemberGroupRow>>{};

    for (
      var start = 0;
      start < duplicateUuids.length;
      start += _lookupBatchSize
    ) {
      final end = start + _lookupBatchSize > duplicateUuids.length
          ? duplicateUuids.length
          : start + _lookupBatchSize;
      final batch = duplicateUuids.sublist(start, end);
      if (batch.isEmpty) continue;

      final groups =
          await (select(memberGroups)..where(
                (g) => g.isDeleted.equals(false) & g.pluralkitUuid.isIn(batch),
              ))
              .get();
      for (final group in groups) {
        final pkGroupUuid = group.pluralkitUuid;
        if (pkGroupUuid == null || pkGroupUuid.isEmpty) continue;
        grouped.putIfAbsent(pkGroupUuid, () => <MemberGroupRow>[]).add(group);
      }
    }

    final duplicates = <PkLinkedGroupDuplicateSet>[];
    for (final entry in grouped.entries) {
      if (entry.value.length < 2) continue;
      entry.value.sort(_compareGroupRowsForRepair);
      duplicates.add(
        PkLinkedGroupDuplicateSet(pkGroupUuid: entry.key, groups: entry.value),
      );
    }
    duplicates.sort((a, b) => a.pkGroupUuid.compareTo(b.pkGroupUuid));
    return duplicates;
  }

  /// Re-home active membership rows from loser groups onto the chosen winner.
  ///
  /// Conflicting duplicate memberships are soft-deleted on the loser row after
  /// opportunistically filling missing PK UUID references on the winner row.
  Future<PkGroupEntryRehomeResult> rehomeEntriesToWinner({
    required String winnerGroupId,
    required List<String> loserGroupIds,
    required String canonicalPkGroupUuid,
  }) async {
    if (loserGroupIds.isEmpty) {
      return const PkGroupEntryRehomeResult();
    }

    return transaction(() async {
      final loserEntries = <MemberGroupEntryRow>[];
      for (
        var start = 0;
        start < loserGroupIds.length;
        start += _lookupBatchSize
      ) {
        final end = start + _lookupBatchSize > loserGroupIds.length
            ? loserGroupIds.length
            : start + _lookupBatchSize;
        final batch = loserGroupIds.sublist(start, end);
        if (batch.isEmpty) continue;
        loserEntries.addAll(
          await (select(memberGroupEntries)..where(
                (e) => e.groupId.isIn(batch) & e.isDeleted.equals(false),
              ))
              .get(),
        );
      }
      if (loserEntries.isEmpty) return const PkGroupEntryRehomeResult();

      final memberIds = {
        for (final entry in loserEntries) entry.memberId,
      }.toList(growable: false);
      final winnerEntriesByMemberId = <String, MemberGroupEntryRow>{};
      for (var start = 0; start < memberIds.length; start += _lookupBatchSize) {
        final end = start + _lookupBatchSize > memberIds.length
            ? memberIds.length
            : start + _lookupBatchSize;
        final batch = memberIds.sublist(start, end);
        if (batch.isEmpty) continue;
        final winnerEntries =
            await (select(memberGroupEntries)..where(
                  (e) =>
                      e.groupId.equals(winnerGroupId) &
                      e.memberId.isIn(batch) &
                      e.isDeleted.equals(false),
                ))
                .get();
        for (final entry in winnerEntries) {
          winnerEntriesByMemberId[entry.memberId] = entry;
        }
      }

      var result = const PkGroupEntryRehomeResult();
      for (final entry in loserEntries) {
        final winnerEntry = winnerEntriesByMemberId[entry.memberId];

        if (winnerEntry != null) {
          final mergedPkMemberUuid = _coalesceNullableNonEmpty(
            winnerEntry.pkMemberUuid,
            entry.pkMemberUuid,
          );
          await (update(
            memberGroupEntries,
          )..where((e) => e.id.equals(winnerEntry.id))).write(
            MemberGroupEntriesCompanion(
              pkGroupUuid: Value(
                _coalesceNonEmpty(
                  winnerEntry.pkGroupUuid,
                  canonicalPkGroupUuid,
                ),
              ),
              pkMemberUuid: mergedPkMemberUuid == null
                  ? const Value.absent()
                  : Value(mergedPkMemberUuid),
            ),
          );
          await (update(memberGroupEntries)
                ..where((e) => e.id.equals(entry.id)))
              .write(const MemberGroupEntriesCompanion(isDeleted: Value(true)));
          result = result.copyWith(
            softDeletedConflicts: result.softDeletedConflicts + 1,
          );
          continue;
        }

        await (update(
          memberGroupEntries,
        )..where((e) => e.id.equals(entry.id))).write(
          MemberGroupEntriesCompanion(
            groupId: Value(winnerGroupId),
            pkGroupUuid: Value(
              _coalesceNonEmpty(entry.pkGroupUuid, canonicalPkGroupUuid),
            ),
          ),
        );
        winnerEntriesByMemberId[entry.memberId] = entry.copyWith(
          groupId: winnerGroupId,
          pkGroupUuid: Value(
            _coalesceNonEmpty(entry.pkGroupUuid, canonicalPkGroupUuid),
          ),
        );
        result = result.copyWith(movedEntries: result.movedEntries + 1);
      }

      return result;
    });
  }

  /// Re-home active child-group references that currently point at loser rows.
  ///
  /// The winner row itself is excluded so we never create a self-parent loop.
  Future<int> rehomeParentReferencesToWinner({
    required String winnerGroupId,
    required List<String> loserGroupIds,
  }) async {
    if (loserGroupIds.isEmpty) return Future.value(0);

    return transaction(() async {
      var rehomed = 0;
      for (
        var start = 0;
        start < loserGroupIds.length;
        start += _lookupBatchSize
      ) {
        final end = start + _lookupBatchSize > loserGroupIds.length
            ? loserGroupIds.length
            : start + _lookupBatchSize;
        final batch = loserGroupIds.sublist(start, end);
        if (batch.isEmpty) continue;

        rehomed += await customUpdate(
          '''
          UPDATE member_groups
          SET parent_group_id = ?
          WHERE is_deleted = 0
            AND parent_group_id IN (${_placeholders(batch.length)})
            AND id <> ?
          ''',
          variables: [
            Variable.withString(winnerGroupId),
            ...batch.map(Variable.withString),
            Variable.withString(winnerGroupId),
          ],
          updates: {memberGroups},
        );
      }
      return rehomed;
    });
  }

  /// Soft-delete legacy loser rows after their memberships/children are
  /// re-homed.
  Future<int> softDeleteGroupsForRepair(List<String> groupIds) async {
    if (groupIds.isEmpty) return Future.value(0);

    var deleted = 0;
    for (var start = 0; start < groupIds.length; start += _lookupBatchSize) {
      final end = start + _lookupBatchSize > groupIds.length
          ? groupIds.length
          : start + _lookupBatchSize;
      final batch = groupIds.sublist(start, end);
      if (batch.isEmpty) continue;

      deleted += await customUpdate(
        '''
        UPDATE member_groups
        SET
          is_deleted = 1,
          sync_suppressed = 1,
          suspected_pk_group_uuid = NULL
        WHERE id IN (${_placeholders(batch.length)})
          AND is_deleted = 0
        ''',
        variables: batch.map(Variable.withString).toList(),
        updates: {memberGroups},
      );
    }
    return deleted;
  }

  /// Mark active plain groups as local-only until the user reviews them.
  Future<int> markGroupsSuppressedForReview({
    required List<String> groupIds,
    required String suspectedPkGroupUuid,
  }) {
    if (groupIds.isEmpty) return Future.value(0);

    return customUpdate(
      '''
      UPDATE member_groups
      SET
        sync_suppressed = 1,
        suspected_pk_group_uuid = ?
      WHERE id IN (${_placeholders(groupIds.length)})
        AND is_deleted = 0
      ''',
      variables: [
        Variable.withString(suspectedPkGroupUuid),
        ...groupIds.map(Variable.withString),
      ],
      updates: {memberGroups},
    );
  }

  Future<List<MemberGroupRow>> getGroupsPendingPkReview() =>
      (select(memberGroups)
            ..where(
              (g) =>
                  g.isDeleted.equals(false) &
                  g.suspectedPkGroupUuid.isNotNull(),
            )
            ..orderBy([(g) => OrderingTerm.asc(g.displayOrder)]))
          .get();

  /// Clears a PK review item and restores the group to normal sync.
  Future<int> dismissGroupsFromPkReview(List<String> groupIds) {
    if (groupIds.isEmpty) return Future.value(0);

    return customUpdate(
      '''
      UPDATE member_groups
      SET
        sync_suppressed = 0,
        suspected_pk_group_uuid = NULL
      WHERE id IN (${_placeholders(groupIds.length)})
        AND is_deleted = 0
      ''',
      variables: groupIds.map(Variable.withString).toList(),
      updates: {memberGroups},
    );
  }

  /// Keeps the row out of the review queue but leaves it suppressed locally.
  Future<int> keepGroupsLocalOnly(List<String> groupIds) {
    if (groupIds.isEmpty) return Future.value(0);

    return customUpdate(
      '''
      UPDATE member_groups
      SET suspected_pk_group_uuid = NULL
      WHERE id IN (${_placeholders(groupIds.length)})
        AND is_deleted = 0
      ''',
      variables: groupIds.map(Variable.withString).toList(),
      updates: {memberGroups},
    );
  }

  /// Converts a reviewed group into the canonical PK-linked row when needed.
  Future<void> linkGroupToPluralkitUuid({
    required String groupId,
    required String pluralkitUuid,
  }) async {
    await (update(memberGroups)..where((g) => g.id.equals(groupId))).write(
      MemberGroupsCompanion(
        syncSuppressed: const Value(false),
        suspectedPkGroupUuid: const Value(null),
        pluralkitUuid: Value(pluralkitUuid),
      ),
    );
  }

  /// Returns whether the group row is currently flagged to stay local-only.
  ///
  /// The `sync_suppressed` column is still landing across the schema in this
  /// workspace, so older builds of the table may not have it yet. In that
  /// case we treat every group as syncable.
  Future<bool> isGroupSyncSuppressed(String groupId) async {
    if (!await _supportsSyncSuppression()) return false;

    final rows = await customSelect(
      '''
      SELECT COALESCE($_syncSuppressedColumnName, 0) AS $_syncSuppressedColumnName
      FROM $_memberGroupsTableName
      WHERE id = ?
      LIMIT 1
      ''',
      variables: [Variable.withString(groupId)],
    ).get();

    if (rows.isEmpty) return false;

    final rawValue = attachedDatabase.typeMapping.read(
      DriftSqlType.bool,
      rows.single.data[_syncSuppressedColumnName],
    );
    return rawValue ?? false;
  }

  /// Live entries for a group, without streaming.
  Future<List<MemberGroupEntryRow>> entriesForGroup(String groupId) => (select(
    memberGroupEntries,
  )..where((e) => e.groupId.equals(groupId) & e.isDeleted.equals(false))).get();

  /// Insert-or-update a member group row. Used by the PK group importer to
  /// persist metadata updates; membership is reconciled via [upsertEntry] /
  /// [softDeleteEntry].
  Future<void> upsertGroup(MemberGroupsCompanion c) =>
      into(memberGroups).insertOnConflictUpdate(c);

  /// Insert-or-update a membership entry. The caller is responsible for
  /// choosing the primary key (deterministic sha256 for PK-originated entries,
  /// see plan R6). Re-activates a soft-deleted entry on conflict.
  Future<void> upsertEntry(MemberGroupEntriesCompanion c) =>
      into(memberGroupEntries).insertOnConflictUpdate(c);

  /// Soft-delete a membership entry by id.
  Future<void> softDeleteEntry(String id) =>
      (update(memberGroupEntries)..where((e) => e.id.equals(id))).write(
        const MemberGroupEntriesCompanion(isDeleted: Value(true)),
      );

  Future<List<MemberGroupRow>> getDirectChildrenOf(String parentGroupId) =>
      (select(memberGroups)
            ..where((g) => g.parentGroupId.equals(parentGroupId))
            ..where((g) => g.isDeleted.equals(false)))
          .get();

  Stream<List<MemberGroupRow>> watchChildGroups(String? parentGroupId) =>
      (select(memberGroups)
            ..where(
              (g) => parentGroupId == null
                  ? g.parentGroupId.isNull()
                  : g.parentGroupId.equals(parentGroupId),
            )
            ..where((g) => g.isDeleted.equals(false))
            ..orderBy([(g) => OrderingTerm.asc(g.displayOrder)]))
          .watch();

  /// Next `display_order` scoped to siblings sharing the same [parentGroupId].
  /// Returns 0 when no siblings exist.
  Future<int> nextDisplayOrder(String? parentGroupId) async {
    final sql = parentGroupId == null
        ? 'SELECT COALESCE(MAX(display_order), -1) + 1 AS next FROM member_groups WHERE is_deleted = 0 AND parent_group_id IS NULL'
        : 'SELECT COALESCE(MAX(display_order), -1) + 1 AS next FROM member_groups WHERE is_deleted = 0 AND parent_group_id = ?';
    final rows = await customSelect(
      sql,
      variables: parentGroupId != null
          ? [Variable.withString(parentGroupId)]
          : [],
    ).get();
    if (rows.isEmpty) return 0;
    return rows.single.read<int>('next');
  }

  Future<bool> _supportsSyncSuppression() async {
    final cached = _hasSyncSuppressedColumn;
    if (cached != null) return cached;

    final rows = await customSelect(
      'PRAGMA table_info($_memberGroupsTableName)',
    ).get();
    final hasColumn = rows.any(
      (row) => row.data['name'] == _syncSuppressedColumnName,
    );
    _hasSyncSuppressedColumn = hasColumn;
    return hasColumn;
  }

  static int _compareGroupRowsForRepair(
    MemberGroupRow left,
    MemberGroupRow right,
  ) {
    final createdAtCompare = left.createdAt.compareTo(right.createdAt);
    if (createdAtCompare != 0) return createdAtCompare;
    return left.id.compareTo(right.id);
  }

  static int _compareActivePkLookupRows(
    MemberGroupRow left,
    MemberGroupRow right,
  ) {
    if (left.syncSuppressed != right.syncSuppressed) {
      return left.syncSuppressed ? 1 : -1;
    }

    if (left.lastSeenFromPkAt != null && right.lastSeenFromPkAt == null) {
      return -1;
    }
    if (left.lastSeenFromPkAt == null && right.lastSeenFromPkAt != null) {
      return 1;
    }
    if (left.lastSeenFromPkAt != null && right.lastSeenFromPkAt != null) {
      final seenCompare = right.lastSeenFromPkAt!.compareTo(
        left.lastSeenFromPkAt!,
      );
      if (seenCompare != 0) return seenCompare;
    }

    final createdAtCompare = left.createdAt.compareTo(right.createdAt);
    if (createdAtCompare != 0) return createdAtCompare;
    return left.id.compareTo(right.id);
  }

  static String _coalesceNonEmpty(String? primary, String fallback) {
    if (primary != null && primary.isNotEmpty) return primary;
    return fallback;
  }

  static String? _coalesceNullableNonEmpty(String? primary, String? fallback) {
    if (primary != null && primary.isNotEmpty) return primary;
    if (fallback != null && fallback.isNotEmpty) return fallback;
    return null;
  }

  static String _placeholders(int count) => List.filled(count, '?').join(', ');
}
