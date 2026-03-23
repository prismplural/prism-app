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

  /// Find an active entry for a specific group + member combination.
  Future<MemberGroupEntryRow?> findEntry(
          String groupId, String memberId) =>
      (select(memberGroupEntries)
            ..where((e) =>
                e.groupId.equals(groupId) &
                e.memberId.equals(memberId) &
                e.isDeleted.equals(false)))
          .getSingleOrNull();
}
