import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/tables/members_table.dart';

part 'members_dao.g.dart';

@DriftAccessor(tables: [Members])
class MembersDao extends DatabaseAccessor<AppDatabase> with _$MembersDaoMixin {
  MembersDao(super.db);

  Future<List<Member>> getAllMembers() =>
      (select(members)
            ..where((m) => m.isDeleted.equals(false))
            ..orderBy([(m) => OrderingTerm.asc(m.displayOrder)]))
          .get();

  /// Like [getAllMembers] but includes soft-deleted tombstones. Used by
  /// the export importer to detect unique-constraint collisions on
  /// `pluralkit_uuid` / `pluralkit_id` against tombstones — the partial
  /// unique indexes `idx_members_pluralkit_uuid` /
  /// `idx_members_pluralkit_id` cover tombstones (no `is_deleted = 0`
  /// clause), so dedup off the active-only `getAllMembers` set is unsafe.
  Future<List<Member>> getAllMembersIncludingDeleted() => select(members).get();

  Stream<List<Member>> watchAllMembers() =>
      (select(members)
            ..where((m) => m.isDeleted.equals(false))
            ..orderBy([(m) => OrderingTerm.asc(m.displayOrder)]))
          .watch();

  Stream<List<Member>> watchActiveMembers() =>
      (select(members)
            ..where((m) => m.isActive.equals(true) & m.isDeleted.equals(false))
            ..orderBy([(m) => OrderingTerm.asc(m.displayOrder)]))
          .watch();

  Future<Member?> getMemberById(String id) =>
      (select(members)..where((m) => m.id.equals(id))).getSingleOrNull();

  /// Single-row read by ID, including tombstones. Repository writers use
  /// this to guard sync emission for missing/tombstoned rows. Alias for
  /// [getMemberById] — same query — provided so the patch-style update
  /// path reads as `getMemberByIdRow` consistently with peer repos
  /// (`getHabitByIdRow`, `getCompletionByIdRow`).
  Future<Member?> getMemberByIdRow(String id) => getMemberById(id);

  Stream<Member?> watchMemberById(String id) =>
      (select(members)..where((m) => m.id.equals(id))).watchSingleOrNull();

  Future<int> insertMember(MembersCompanion member) =>
      into(members).insert(member);

  /// Inserts at the end of the display order, including tombstones.
  Future<int> insertMemberAtEnd(MembersCompanion member) async {
    return transaction(() async {
      final nextOrder = await nextDisplayOrderIncludingDeleted();
      await into(
        members,
      ).insert(member.copyWith(displayOrder: Value(nextOrder)));
      return nextOrder;
    });
  }

  /// Batch-insert members in a single Drift `batch()` round-trip.
  ///
  /// Used by the SP importer's Phase 6 capture-replay path
  /// (`docs/plans/sp-import-perf-quick-wins.md`) to collapse N per-member
  /// inserts into one DAO call. Bypasses [DriftMemberRepository.createMember],
  /// so the caller is responsible for pushing a captured op tuple per row
  /// using [DriftMemberRepository.memberFields]. The SP importer pre-filters
  /// rows whose ID already exists, so plain `insertAll` (no conflict policy)
  /// is correct here — re-using the per-row `insertMember` policy.
  Future<void> batchInsertMembers(List<MembersCompanion> rows) async {
    if (rows.isEmpty) return;
    await batch((b) => b.insertAll(members, rows));
  }

  /// Bulk-update `boardLastReadAt` per (memberId, readAt) pair in a single
  /// Drift batch. The caller is responsible for preserving LWW semantics by
  /// passing only rows whose current `boardLastReadAt` is null or older than
  /// the supplied value.
  ///
  /// Phase 6 SP importer; see `docs/plans/sp-import-perf-quick-wins.md`.
  Future<void> batchUpdateBoardLastReadAt(
    Map<String, DateTime> readAtByMemberId,
  ) async {
    if (readAtByMemberId.isEmpty) return;
    await batch((b) {
      for (final entry in readAtByMemberId.entries) {
        b.update(
          members,
          MembersCompanion(boardLastReadAt: Value(entry.value)),
          where: (m) => m.id.equals(entry.key),
        );
      }
    });
  }

  /// Atomic-per-row variant: write `now` into `boardLastReadAt` only for
  /// active members whose current value is null or strictly older than
  /// `now`. The conditional `WHERE` is evaluated and the write applied as
  /// one SQL statement per row, so two concurrent callers cannot regress a
  /// newer stamp to an older one — the loser's `WHERE` excludes the row
  /// that already holds the winner's stamp.
  ///
  /// Returns the subset of `memberIds` whose row was actually updated, so
  /// the caller can emit `syncRecordUpdate` only for those members (and
  /// not waste CRDT ops on rows where the LWW guard already short-
  /// circuited the local write).
  Future<List<String>> setBoardLastReadAtIfOlder(
    List<String> memberIds,
    DateTime now,
  ) async {
    if (memberIds.isEmpty) return const [];
    final updated = <String>[];
    await transaction(() async {
      for (final memberId in memberIds) {
        final affected =
            await (update(members)..where(
                  (m) =>
                      m.id.equals(memberId) &
                      m.isDeleted.equals(false) &
                      (m.boardLastReadAt.isNull() |
                          m.boardLastReadAt.isSmallerThanValue(now)),
                ))
                .write(MembersCompanion(boardLastReadAt: Value(now)));
        if (affected > 0) updated.add(memberId);
      }
    });
    return updated;
  }

  Future<void> updateMember(MembersCompanion member) {
    assert(member.id.present, 'Member id is required for update');
    return (update(
      members,
    )..where((m) => m.id.equals(member.id.value))).write(member);
  }

  /// Update an active member by ID with a sparse companion. Returns the
  /// affected row count (0 if the row is tombstoned or missing, 1 on
  /// success). The `is_deleted = false` predicate is the tombstone
  /// guard — Drift `write` on a tombstoned row returns 0, letting the
  /// repository skip sync emission and avoid resurrection.
  Future<int> updateMemberById(String id, MembersCompanion companion) =>
      (update(members)
            ..where((m) => m.id.equals(id) & m.isDeleted.equals(false)))
          .write(companion);

  /// Bulk-update display orders in one SQL statement.
  ///
  /// Reordering can touch many rows in large systems; updating them one at a
  /// time forces repeated Drift write plumbing and makes drag/drop feel laggy.
  /// This keeps the database work to a single statement while callers still
  /// emit the corresponding sync ops per changed member.
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
      UPDATE members
      SET display_order = CASE id
        $whenClauses
        ELSE display_order
      END
      WHERE id IN ($wherePlaceholders)
      ''',
      variables: variables,
      updates: {members},
    );
  }

  Future<void> upsertMember(MembersCompanion member) =>
      into(members).insertOnConflictUpdate(member);

  /// Bulk-update `avatarImageData` for many members in a single Drift batch.
  ///
  /// Replaces N round-tripped `update(...)` calls with one batched statement.
  /// Used by the SP importer's parallel avatar phase
  /// (`sp_importer.dart:_downloadAvatars`); callers are expected to emit the
  /// matching `syncRecordUpdate` per member after the batch returns so the
  /// emission shape on the wire is unchanged.
  Future<void> batchUpdateAvatars(Map<String, Uint8List> bytesById) async {
    if (bytesById.isEmpty) return;
    await batch((b) {
      for (final entry in bytesById.entries) {
        b.update(
          members,
          MembersCompanion(avatarImageData: Value(entry.value)),
          where: (m) => m.id.equals(entry.key),
        );
      }
    });
  }

  Future<void> softDeleteMember(String id) =>
      (update(members)..where((m) => m.id.equals(id))).write(
        const MembersCompanion(isDeleted: Value(true)),
      );

  /// Tombstoned members that still carry a PK link and a delete
  /// intent stamped under some link epoch. Callers must additionally gate
  /// by `deleteIntentEpoch == state.linkEpoch` at push time — this
  /// query surfaces the candidate set only.
  Future<List<Member>> getDeletedLinkedMembers() =>
      (select(members)..where(
            (m) =>
                m.isDeleted.equals(true) &
                m.pluralkitId.isNotNull() &
                m.deleteIntentEpoch.isNotNull(),
          ))
          .get();

  /// Live local sessions for a member that still point at PK. Used
  /// by the cascade guard: if any exist when we want to push a member
  /// DELETE, we skip the member DELETE this pass to keep PK's cascade from
  /// silently deleting switches Prism still considers live.
  Future<List<FrontingSession>> _getLiveLinkedSessionsForMember(
    String memberId,
  ) =>
      (select(attachedDatabase.frontingSessions)..where(
            (s) =>
                s.memberId.equals(memberId) &
                s.isDeleted.equals(false) &
                s.pluralkitUuid.isNotNull(),
          ))
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
        ),
      );

  /// Plan 02 R1: stamp delete intent on a member tombstone. Called in the
  /// same transaction as `softDeleteMember` by the repository.
  Future<void> stampDeleteIntent(String id, int epoch) =>
      (update(members)..where((m) => m.id.equals(id))).write(
        MembersCompanion(deleteIntentEpoch: Value(epoch)),
      );

  /// Plan 02 R6: stamp the cross-device coordination timestamp. Callers
  /// should route this through `syncRecordUpdate` as well so other devices
  /// see it. The DAO-level write is the local half.
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) =>
      (update(members)..where((m) => m.id.equals(id))).write(
        MembersCompanion(deletePushStartedAt: Value(timestampMs)),
      );

  Future<List<Member>> getMembersByIds(List<String> ids) =>
      (select(members)..where((m) => m.id.isIn(ids))).get();

  Stream<List<Member>> watchMembersByIds(List<String> ids) =>
      (select(members)..where((m) => m.id.isIn(ids))).watch();

  Future<List<Member>> getSubsystemMembers(String parentId) =>
      (select(members)..where(
            (m) =>
                m.parentSystemId.equals(parentId) & m.isDeleted.equals(false),
          ))
          .get();

  Future<int> getCount() async {
    final count = countAll();
    final query = selectOnly(members)
      ..where(members.isDeleted.equals(false))
      ..addColumns([count]);
    final row = await query.getSingle();
    return row.read(count)!;
  }

  Future<int> nextDisplayOrderIncludingDeleted() async {
    final rows = await customSelect(
      'SELECT COALESCE(MAX(display_order), -1) + 1 AS next FROM members',
      readsFrom: {members},
    ).get();
    if (rows.isEmpty) return 0;
    return rows.single.read<int>('next');
  }
}
