import 'package:drift/drift.dart';
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

  Stream<List<MemberGroupEntryRow>> watchGroupEntries(String groupId) =>
      (select(memberGroupEntries)..where(
            (e) => e.groupId.equals(groupId) & e.isDeleted.equals(false),
          ))
          .watch();

  Future<int> createGroup(MemberGroupsCompanion companion) =>
      into(memberGroups).insert(companion);

  Future<void> updateGroup(String id, MemberGroupsCompanion companion) =>
      (update(memberGroups)..where((g) => g.id.equals(id))).write(companion);

  Future<void> deleteGroup(String id) async {
    // Soft-delete entries for this group
    await (update(memberGroupEntries)..where((e) => e.groupId.equals(id)))
        .write(const MemberGroupEntriesCompanion(isDeleted: Value(true)));
    // Soft-delete the group itself
    await (update(memberGroups)..where((g) => g.id.equals(id))).write(
      const MemberGroupsCompanion(isDeleted: Value(true)),
    );
  }

  // ── Entries ─────────────────────────────────────────────────────

  Future<int> createEntry(MemberGroupEntriesCompanion companion) =>
      into(memberGroupEntries).insert(companion);

  Future<void> deleteEntry(String id) =>
      (update(memberGroupEntries)..where((e) => e.id.equals(id))).write(
        const MemberGroupEntriesCompanion(isDeleted: Value(true)),
      );

  Future<void> deleteEntriesForGroup(String groupId) =>
      (update(memberGroupEntries)..where((e) => e.groupId.equals(groupId)))
          .write(const MemberGroupEntriesCompanion(isDeleted: Value(true)));

  /// Watches member counts per group in a single query.
  /// Returns a map of groupId → count.
  Stream<Map<String, int>> watchMemberCountsByGroup() {
    final query = select(memberGroupEntries)
      ..where((e) => e.isDeleted.equals(false));

    return query.watch().map((entries) {
      final counts = <String, int>{};
      for (final e in entries) {
        counts[e.groupId] = (counts[e.groupId] ?? 0) + 1;
      }
      return counts;
    });
  }

  /// Returns all active group entries across all groups.
  Stream<List<MemberGroupEntryRow>> watchAllGroupEntries() => (select(
    memberGroupEntries,
  )..where((e) => e.isDeleted.equals(false))).watch();

  /// Returns all active group entries across all groups as a future.
  Future<List<MemberGroupEntryRow>> getAllGroupEntries() => (select(
    memberGroupEntries,
  )..where((e) => e.isDeleted.equals(false))).get();

  /// Find an active entry for a specific group + member combination.
  Future<MemberGroupEntryRow?> findEntry(String groupId, String memberId) =>
      (select(memberGroupEntries)..where(
            (e) =>
                e.groupId.equals(groupId) &
                e.memberId.equals(memberId) &
                e.isDeleted.equals(false),
          ))
          .getSingleOrNull();

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

  /// Groups active PK-linked rows that still share the same PK UUID.
  Future<List<PkLinkedGroupDuplicateSet>>
  getActiveLinkedPkGroupDuplicateSets() async {
    final groups = await getAllActiveGroups();
    final grouped = <String, List<MemberGroupRow>>{};

    for (final group in groups) {
      final pkGroupUuid = group.pluralkitUuid;
      if (pkGroupUuid == null || pkGroupUuid.isEmpty) continue;
      grouped.putIfAbsent(pkGroupUuid, () => <MemberGroupRow>[]).add(group);
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
      final loserEntries =
          await (select(memberGroupEntries)..where(
                (e) =>
                    e.groupId.isIn(loserGroupIds) & e.isDeleted.equals(false),
              ))
              .get();

      var result = const PkGroupEntryRehomeResult();
      for (final entry in loserEntries) {
        final winnerEntry =
            await (select(memberGroupEntries)..where(
                  (e) =>
                      e.groupId.equals(winnerGroupId) &
                      e.memberId.equals(entry.memberId) &
                      e.isDeleted.equals(false),
                ))
                .getSingleOrNull();

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
      final impactedChildren =
          await (select(memberGroups)..where(
                (g) =>
                    g.isDeleted.equals(false) &
                    g.parentGroupId.isIn(loserGroupIds) &
                    g.id.equals(winnerGroupId).not(),
              ))
              .get();
      if (impactedChildren.isEmpty) return 0;

      await customUpdate(
        '''
        UPDATE member_groups
        SET parent_group_id = ?
        WHERE is_deleted = 0
          AND parent_group_id IN (${_placeholders(loserGroupIds.length)})
          AND id <> ?
        ''',
        variables: [
          Variable.withString(winnerGroupId),
          ...loserGroupIds.map(Variable.withString),
          Variable.withString(winnerGroupId),
        ],
        updates: {memberGroups},
      );
      return impactedChildren.length;
    });
  }

  /// Soft-delete legacy loser rows after their memberships/children are
  /// re-homed.
  Future<int> softDeleteGroupsForRepair(List<String> groupIds) {
    if (groupIds.isEmpty) return Future.value(0);

    return customUpdate(
      '''
      UPDATE member_groups
      SET
        is_deleted = 1,
        sync_suppressed = 1,
        suspected_pk_group_uuid = NULL
      WHERE id IN (${_placeholders(groupIds.length)})
        AND is_deleted = 0
      ''',
      variables: groupIds.map(Variable.withString).toList(),
      updates: {memberGroups},
    );
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
