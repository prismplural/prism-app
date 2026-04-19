import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/member_groups_table.dart';
import 'package:prism_plurality/core/database/tables/member_group_entries_table.dart';

part 'member_groups_dao.g.dart';

@DriftAccessor(tables: [MemberGroups, MemberGroupEntries])
class MemberGroupsDao extends DatabaseAccessor<AppDatabase>
    with _$MemberGroupsDaoMixin {
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

  Stream<List<MemberGroupRow>> watchGroupsForMember(String memberId) {
    final entryQuery = select(memberGroupEntries)
      ..where(
          (e) => e.memberId.equals(memberId) & e.isDeleted.equals(false));

    return entryQuery.watch().asyncMap((entries) async {
      if (entries.isEmpty) return <MemberGroupRow>[];
      final groupIds = entries.map((e) => e.groupId).toList();
      return (select(memberGroups)
            ..where(
                (g) => g.id.isIn(groupIds) & g.isDeleted.equals(false))
            ..orderBy([(g) => OrderingTerm.asc(g.displayOrder)]))
          .get();
    });
  }

  Stream<List<MemberGroupEntryRow>> watchGroupEntries(String groupId) =>
      (select(memberGroupEntries)
            ..where((e) =>
                e.groupId.equals(groupId) & e.isDeleted.equals(false)))
          .watch();

  Future<int> createGroup(MemberGroupsCompanion companion) =>
      into(memberGroups).insert(companion);

  Future<void> updateGroup(String id, MemberGroupsCompanion companion) =>
      (update(memberGroups)..where((g) => g.id.equals(id)))
          .write(companion);

  Future<void> deleteGroup(String id) async {
    // Soft-delete entries for this group
    await (update(memberGroupEntries)
          ..where((e) => e.groupId.equals(id)))
        .write(
            const MemberGroupEntriesCompanion(isDeleted: Value(true)));
    // Soft-delete the group itself
    await (update(memberGroups)..where((g) => g.id.equals(id)))
        .write(const MemberGroupsCompanion(isDeleted: Value(true)));
  }

  // ── Entries ─────────────────────────────────────────────────────

  Future<int> createEntry(MemberGroupEntriesCompanion companion) =>
      into(memberGroupEntries).insert(companion);

  Future<void> deleteEntry(String id) =>
      (update(memberGroupEntries)..where((e) => e.id.equals(id)))
          .write(
              const MemberGroupEntriesCompanion(isDeleted: Value(true)));

  Future<void> deleteEntriesForGroup(String groupId) =>
      (update(memberGroupEntries)
            ..where((e) => e.groupId.equals(groupId)))
          .write(
              const MemberGroupEntriesCompanion(isDeleted: Value(true)));

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
  Stream<List<MemberGroupEntryRow>> watchAllGroupEntries() =>
      (select(memberGroupEntries)
            ..where((e) => e.isDeleted.equals(false)))
          .watch();

  /// Returns all active group entries across all groups as a future.
  Future<List<MemberGroupEntryRow>> getAllGroupEntries() =>
      (select(memberGroupEntries)
            ..where((e) => e.isDeleted.equals(false)))
          .get();

  /// Find an active entry for a specific group + member combination.
  Future<MemberGroupEntryRow?> findEntry(
          String groupId, String memberId) =>
      (select(memberGroupEntries)
            ..where((e) =>
                e.groupId.equals(groupId) &
                e.memberId.equals(memberId) &
                e.isDeleted.equals(false)))
          .getSingleOrNull();

  // ── PluralKit linkage ───────────────────────────────────────────

  /// Look up an existing group by its PluralKit UUID. Identity is UUID-only
  /// (R7): PK short IDs can be recycled, so we never match on them.
  Future<MemberGroupRow?> findByPluralkitUuid(String uuid) =>
      (select(memberGroups)
            ..where((g) => g.pluralkitUuid.equals(uuid)))
          .getSingleOrNull();

  Future<List<MemberGroupRow>> getAllGroupsIncludingDeleted() =>
      select(memberGroups).get();

  Future<List<MemberGroupRow>> getAllActiveGroups() =>
      (select(memberGroups)..where((g) => g.isDeleted.equals(false))).get();

  /// Live entries for a group, without streaming.
  Future<List<MemberGroupEntryRow>> entriesForGroup(String groupId) =>
      (select(memberGroupEntries)
            ..where((e) =>
                e.groupId.equals(groupId) & e.isDeleted.equals(false)))
          .get();

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
      (update(memberGroupEntries)..where((e) => e.id.equals(id)))
          .write(const MemberGroupEntriesCompanion(isDeleted: Value(true)));

  Stream<List<MemberGroupRow>> watchChildGroups(String? parentGroupId) =>
      (select(memberGroups)
            ..where((g) => parentGroupId == null
                ? g.parentGroupId.isNull()
                : g.parentGroupId.equals(parentGroupId))
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
}
