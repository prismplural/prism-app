import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/members_table.dart';

part 'members_dao.g.dart';

@DriftAccessor(tables: [Members])
class MembersDao extends DatabaseAccessor<AppDatabase> with _$MembersDaoMixin {
  MembersDao(super.db);

  Future<List<Member>> getAllMembers() => (select(members)
        ..where((m) => m.isDeleted.equals(false))
        ..orderBy([(m) => OrderingTerm.asc(m.displayOrder)]))
      .get();

  Stream<List<Member>> watchAllMembers() => (select(members)
        ..where((m) => m.isDeleted.equals(false))
        ..orderBy([(m) => OrderingTerm.asc(m.displayOrder)]))
      .watch();

  Stream<List<Member>> watchActiveMembers() => (select(members)
        ..where(
            (m) => m.isActive.equals(true) & m.isDeleted.equals(false))
        ..orderBy([(m) => OrderingTerm.asc(m.displayOrder)]))
      .watch();

  Future<Member?> getMemberById(String id) =>
      (select(members)..where((m) => m.id.equals(id))).getSingleOrNull();

  Stream<Member?> watchMemberById(String id) =>
      (select(members)..where((m) => m.id.equals(id))).watchSingleOrNull();

  Future<int> insertMember(MembersCompanion member) =>
      into(members).insert(member);

  Future<void> updateMember(MembersCompanion member) {
    assert(member.id.present, 'Member id is required for update');
    return (update(members)..where((m) => m.id.equals(member.id.value)))
        .write(member);
  }

  Future<void> upsertMember(MembersCompanion member) =>
      into(members).insertOnConflictUpdate(member);

  Future<void> softDeleteMember(String id) =>
      (update(members)..where((m) => m.id.equals(id))).write(
          const MembersCompanion(isDeleted: Value(true)));

  Future<List<Member>> getMembersByIds(List<String> ids) =>
      (select(members)..where((m) => m.id.isIn(ids))).get();

  Future<List<Member>> getSubsystemMembers(String parentId) =>
      (select(members)
            ..where((m) =>
                m.parentSystemId.equals(parentId) &
                m.isDeleted.equals(false)))
          .get();

  Future<int> getCount() async {
    final count = countAll();
    final query = selectOnly(members)
      ..where(members.isDeleted.equals(false))
      ..addColumns([count]);
    final row = await query.getSingle();
    return row.read(count)!;
  }
}
