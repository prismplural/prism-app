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

  /// Like [getAllMembers] but includes soft-deleted tombstones. Used by
  /// the export importer to detect unique-constraint collisions on
  /// `pluralkit_uuid` / `pluralkit_id` against tombstones — the partial
  /// unique indexes `idx_members_pluralkit_uuid` /
  /// `idx_members_pluralkit_id` cover tombstones (no `is_deleted = 0`
  /// clause), so dedup off the active-only `getAllMembers` set is unsafe.
  Future<List<Member>> getAllMembersIncludingDeleted() =>
      select(members).get();

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

  /// Tombstoned members that still carry a PK link and a delete
  /// intent stamped under some link epoch. Callers must additionally gate
  /// by `deleteIntentEpoch == state.linkEpoch` at push time — this
  /// query surfaces the candidate set only.
  Future<List<Member>> getDeletedLinkedMembers() => (select(members)
        ..where((m) =>
            m.isDeleted.equals(true) &
            m.pluralkitId.isNotNull() &
            m.deleteIntentEpoch.isNotNull()))
      .get();

  /// Live local sessions for a member that still point at PK. Used
  /// by the cascade guard: if any exist when we want to push a member
  /// DELETE, we skip the member DELETE this pass to keep PK's cascade from
  /// silently deleting switches Prism still considers live.
  Future<List<FrontingSession>> _getLiveLinkedSessionsForMember(
          String memberId) =>
      (select(attachedDatabase.frontingSessions)
            ..where((s) =>
                s.memberId.equals(memberId) &
                s.isDeleted.equals(false) &
                s.pluralkitUuid.isNotNull()))
          .get();

  /// Plan 02 R5 hook — convenience wrapper.
  Future<bool> hasLiveLinkedSessionsForMember(String memberId) async {
    final rows = await _getLiveLinkedSessionsForMember(memberId);
    return rows.isNotEmpty;
  }

  /// Plan 02 R3: clear the PK link on a tombstone (row stays `is_deleted = 1`).
  /// Bypasses the `is_deleted = false` filter that exists on most writers so
  /// the cleanup runs after the tombstone was written. Callers should route
  /// via the repository's `clearPluralKitLink` so a CRDT op is also emitted.
  Future<void> clearPluralKitLinkRaw(String id) =>
      (update(members)..where((m) => m.id.equals(id))).write(
          const MembersCompanion(
            pluralkitId: Value(null),
            pluralkitUuid: Value(null),
          ));

  /// Plan 02 R1: stamp delete intent on a member tombstone. Called in the
  /// same transaction as `softDeleteMember` by the repository.
  Future<void> stampDeleteIntent(String id, int epoch) =>
      (update(members)..where((m) => m.id.equals(id))).write(
          MembersCompanion(deleteIntentEpoch: Value(epoch)));

  /// Plan 02 R6: stamp the cross-device coordination timestamp. Callers
  /// should route this through `syncRecordUpdate` as well so other devices
  /// see it. The DAO-level write is the local half.
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) =>
      (update(members)..where((m) => m.id.equals(id))).write(
          MembersCompanion(deletePushStartedAt: Value(timestampMs)));

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
