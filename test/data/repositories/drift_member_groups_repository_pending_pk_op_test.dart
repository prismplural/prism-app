import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/member_groups_dao.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/domain/models/member.dart' as member_domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';

class _TestMemberGroupsDao extends MemberGroupsDao {
  _TestMemberGroupsDao(super.db);

  // PK push isn't suppressed by default in these tests; the suppression
  // path is exercised by drift_member_groups_repository_sync_suppression_test.
  final suppressedGroupIds = <String>{};

  @override
  Future<bool> isGroupSyncSuppressed(String groupId) async {
    return suppressedGroupIds.contains(groupId);
  }
}

class _RecordingRepo extends DriftMemberGroupsRepository {
  _RecordingRepo(MemberGroupsDao dao, MemberRepository memberRepository)
      : super(dao, null, memberRepository: memberRepository);

  final creates = <String>[];
  final deletes = <String>[];

  @override
  Future<void> syncRecordCreate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    creates.add('$table:$entityId');
  }

  @override
  Future<void> syncRecordDelete(String table, String entityId) async {
    deletes.add('$table:$entityId');
  }
}

class _FakeMemberRepository implements MemberRepository {
  _FakeMemberRepository(this._members);

  final List<member_domain.Member> _members;

  @override
  Future<member_domain.Member?> getMemberById(String id) async {
    for (final m in _members) {
      if (m.id == id) return m;
    }
    return null;
  }

  @override
  Future<List<member_domain.Member>> getMembersByIds(List<String> ids) async =>
      _members.where((m) => ids.contains(m.id)).toList();

  // The repository code only calls getMemberById and getMembersByIds in the
  // paths under test. Throwing on the rest keeps unintended call sites obvious.
  @override
  Future<void> clearPluralKitLink(String id) async => throw UnimplementedError();
  @override
  Future<void> createMember(member_domain.Member member) async =>
      throw UnimplementedError();
  @override
  Future<void> deleteMember(String id) async => throw UnimplementedError();
  @override
  Future<List<member_domain.Member>> getAllMembers() async =>
      throw UnimplementedError();
  @override
  Future<List<member_domain.Member>> getAllMembersIncludingDeleted() async =>
      throw UnimplementedError();
  @override
  Future<int> getCount() async => throw UnimplementedError();
  @override
  Future<List<member_domain.Member>> getDeletedLinkedMembers() async =>
      throw UnimplementedError();
  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async =>
      throw UnimplementedError();
  @override
  Future<void> updateMember(member_domain.Member member) async =>
      throw UnimplementedError();
  @override
  Future<int> updateMemberFields(
    String id,
    Map<String, dynamic> changedFields,
  ) async => throw UnimplementedError();
  @override
  Stream<List<member_domain.Member>> watchActiveMembers() =>
      throw UnimplementedError();
  @override
  Stream<List<member_domain.Member>> watchAllMembers() =>
      throw UnimplementedError();
  @override
  Stream<member_domain.Member?> watchMemberById(String id) =>
      throw UnimplementedError();
  @override
  Stream<List<member_domain.Member>> watchMembersByIds(List<String> ids) =>
      throw UnimplementedError();
  @override
  Future<({member_domain.Member member, bool wasCreated})>
      ensureUnknownSentinelMember() => throw UnimplementedError();
}

Future<void> _seedGroup(
  AppDatabase db, {
  required String id,
  String? pluralkitUuid,
}) {
  return db.into(db.memberGroups).insert(
        MemberGroupsCompanion.insert(
          id: id,
          name: id,
          createdAt: DateTime.utc(2026, 1, 1),
          pluralkitUuid: Value(pluralkitUuid),
        ),
      );
}

member_domain.Member _member({required String id, String? pluralkitUuid}) {
  return member_domain.Member(
    id: id,
    name: id,
    createdAt: DateTime.utc(2026, 1, 1),
    pluralkitUuid: pluralkitUuid,
  );
}

Future<MemberGroupEntryRow?> _findEntry(
  AppDatabase db,
  String groupId,
  String memberId,
) async {
  final rows = await (db.select(db.memberGroupEntries)
        ..where((e) => e.groupId.equals(groupId) & e.memberId.equals(memberId)))
      .get();
  if (rows.isEmpty) return null;
  return rows.single;
}

void main() {
  late AppDatabase db;
  late _TestMemberGroupsDao dao;
  late _RecordingRepo repo;

  Future<void> setupRepo({List<member_domain.Member> members = const []}) async {
    db = AppDatabase(NativeDatabase.memory());
    dao = _TestMemberGroupsDao(db);
    repo = _RecordingRepo(dao, _FakeMemberRepository([...members]));
  }

  tearDown(() async {
    await db.close();
  });

  group('addMemberToGroup pending_pk_op', () {
    test('PK group + PK member → push_add', () async {
      await setupRepo(
        members: [_member(id: 'm1', pluralkitUuid: 'pk-m1')],
      );
      await _seedGroup(db, id: 'g1', pluralkitUuid: 'pk-g1');

      await repo.addMemberToGroup('g1', 'm1', 'fresh-uuid');

      final entry = await _findEntry(db, 'g1', 'm1');
      expect(entry, isNotNull);
      expect(entry!.isDeleted, isFalse);
      expect(entry.pendingPkOp, 'push_add');
    });

    test('non-PK group → none', () async {
      await setupRepo(members: [_member(id: 'm1')]);
      await _seedGroup(db, id: 'g1');

      await repo.addMemberToGroup('g1', 'm1', 'fresh-uuid');

      final entry = await _findEntry(db, 'g1', 'm1');
      expect(entry, isNotNull);
      expect(entry!.pendingPkOp, 'none');
    });

    test('PK group + non-PK member → none (member can\'t be pushed)', () async {
      await setupRepo(members: [_member(id: 'm1')]);
      await _seedGroup(db, id: 'g1', pluralkitUuid: 'pk-g1');

      await repo.addMemberToGroup('g1', 'm1', 'fresh-uuid');

      final entry = await _findEntry(db, 'g1', 'm1');
      expect(entry!.pendingPkOp, 'none');
    });

    test(
      're-adding a soft-deleted push_remove row revives it as push_add '
      '(NOT none — see v3-patches-2 #1)',
      () async {
        await setupRepo(
          members: [_member(id: 'm1', pluralkitUuid: 'pk-m1')],
        );
        await _seedGroup(db, id: 'g1', pluralkitUuid: 'pk-g1');

        // Set up the soft-deleted push_remove tombstone. It must live at
        // the deterministic SHA id so the upsert in the revival path lands
        // on the same row.
        await repo.addMemberToGroup('g1', 'm1', 'unused-uuid');
        await repo.removeMemberFromGroup('g1', 'm1');
        final tombstone = await _findEntry(db, 'g1', 'm1');
        expect(tombstone!.isDeleted, isTrue);
        expect(tombstone.pendingPkOp, 'push_remove');

        // Re-add. The existing row is soft-deleted so findEntry returns
        // null and the upsert path runs.
        await repo.addMemberToGroup('g1', 'm1', 'unused-uuid');

        final revived = await _findEntry(db, 'g1', 'm1');
        expect(revived!.id, tombstone.id, reason: 'same canonical SHA id');
        expect(revived.isDeleted, isFalse);
        expect(
          revived.pendingPkOp,
          'push_add',
          reason: 'reviving must preserve push intent so the next push round '
              'restores PK after the remove that may have already shipped',
        );
      },
    );

    test('no-op early return when an active entry already exists', () async {
      await setupRepo(
        members: [_member(id: 'm1', pluralkitUuid: 'pk-m1')],
      );
      await _seedGroup(db, id: 'g1', pluralkitUuid: 'pk-g1');

      await repo.addMemberToGroup('g1', 'm1', 'fresh-1');
      // Second add with active row already in place. Pending stays push_add
      // (no churn — no clearance to none, no second create event).
      final createsBefore = repo.creates.length;
      await repo.addMemberToGroup('g1', 'm1', 'fresh-2');
      final entry = await _findEntry(db, 'g1', 'm1');
      expect(entry!.pendingPkOp, 'push_add');
      expect(repo.creates.length, createsBefore);
    });
  });

  group('removeMemberFromGroup pending_pk_op', () {
    test('PK-linked active entry → soft-delete + push_remove', () async {
      await setupRepo(
        members: [_member(id: 'm1', pluralkitUuid: 'pk-m1')],
      );
      await _seedGroup(db, id: 'g1', pluralkitUuid: 'pk-g1');
      await repo.addMemberToGroup('g1', 'm1', 'fresh-uuid');

      await repo.removeMemberFromGroup('g1', 'm1');

      final entry = await _findEntry(db, 'g1', 'm1');
      expect(entry, isNotNull, reason: 'NEVER hard-delete from this path');
      expect(entry!.isDeleted, isTrue);
      expect(entry.pendingPkOp, 'push_remove');
    });

    test(
      'non-PK active entry → soft-delete + none (no PK to push to)',
      () async {
        await setupRepo(members: [_member(id: 'm1')]);
        await _seedGroup(db, id: 'g1');
        await repo.addMemberToGroup('g1', 'm1', 'fresh-uuid');

        await repo.removeMemberFromGroup('g1', 'm1');

        final entry = await _findEntry(db, 'g1', 'm1');
        expect(entry!.isDeleted, isTrue);
        expect(entry.pendingPkOp, 'none');
      },
    );

    test(
      'PK-linked active entry currently with push_add intent → flip to '
      'push_remove (do NOT hard-delete; v3-patches-2 #7)',
      () async {
        await setupRepo(
          members: [_member(id: 'm1', pluralkitUuid: 'pk-m1')],
        );
        await _seedGroup(db, id: 'g1', pluralkitUuid: 'pk-g1');

        // Add: pending becomes push_add. Push hasn't run yet.
        await repo.addMemberToGroup('g1', 'm1', 'fresh-uuid');
        expect((await _findEntry(db, 'g1', 'm1'))!.pendingPkOp, 'push_add');

        // Remove. Old behavior would hard-delete since push hadn't shipped;
        // new behavior soft-deletes and queues push_remove. The orchestrator
        // will issue /members/remove which PK 4xx's not-member, then refetch
        // confirms gone, then cleanup DELETE removes the tombstone.
        await repo.removeMemberFromGroup('g1', 'm1');

        final entry = await _findEntry(db, 'g1', 'm1');
        expect(entry, isNotNull, reason: 'must NOT hard-delete');
        expect(entry!.isDeleted, isTrue);
        expect(entry.pendingPkOp, 'push_remove');
      },
    );

    test('emits Prism syncRecordDelete on PK-linked remove', () async {
      await setupRepo(
        members: [_member(id: 'm1', pluralkitUuid: 'pk-m1')],
      );
      // PK-backed sync emit is gated on pkGroupSyncV2Enabled. Enable so the
      // syncRecordDelete fires; we're testing the CRDT-emit half of the
      // remove path here, not the gate itself.
      await db.systemSettingsDao.updatePkGroupSyncV2Enabled(true);
      await _seedGroup(db, id: 'g1', pluralkitUuid: 'pk-g1');
      await repo.addMemberToGroup('g1', 'm1', 'fresh-uuid');
      repo.deletes.clear();

      await repo.removeMemberFromGroup('g1', 'm1');

      expect(repo.deletes, hasLength(1));
      expect(repo.deletes.single, startsWith('member_group_entries:'));
    });

    test('no-op when entry does not exist', () async {
      await setupRepo(members: [_member(id: 'm1')]);
      await _seedGroup(db, id: 'g1');

      await repo.removeMemberFromGroup('g1', 'm1');

      expect(repo.deletes, isEmpty);
    });
  });
}
