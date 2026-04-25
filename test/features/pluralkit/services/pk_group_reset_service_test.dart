import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/member_groups_dao.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/domain/models/member.dart' as member_domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_reset_service.dart';

import '../../../helpers/pk_fixtures.dart';

class _FakeMemberRepository implements MemberRepository {
  _FakeMemberRepository(this._membersById);

  final Map<String, member_domain.Member> _membersById;

  @override
  Future<member_domain.Member?> getMemberById(String id) async =>
      _membersById[id];

  @override
  Future<List<member_domain.Member>> getMembersByIds(List<String> ids) async {
    return ids
        .map((id) => _membersById[id])
        .whereType<member_domain.Member>()
        .toList();
  }

  @override
  Stream<List<member_domain.Member>> watchMembersByIds(List<String> ids) =>
      throw UnimplementedError();

  @override
  Future<List<member_domain.Member>> getAllMembers() async {
    return _membersById.values.toList();
  }

  @override
  Future<void> clearPluralKitLink(String id) async {}

  @override
  Future<void> createMember(member_domain.Member member) async {}

  @override
  Future<void> deleteMember(String id) async {}

  @override
  Future<int> getCount() async => _membersById.length;

  @override
  Future<List<member_domain.Member>> getDeletedLinkedMembers() async =>
      const [];

  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async {}

  @override
  Future<void> updateMember(member_domain.Member member) async {}

  @override
  Stream<List<member_domain.Member>> watchActiveMembers() async* {
    yield _membersById.values.toList();
  }

  @override
  Stream<List<member_domain.Member>> watchAllMembers() async* {
    yield _membersById.values.toList();
  }

  @override
  Stream<member_domain.Member?> watchMemberById(String id) async* {
    yield _membersById[id];
  }
}

class _RecordingMemberGroupsRepository extends DriftMemberGroupsRepository {
  _RecordingMemberGroupsRepository(
    MemberGroupsDao dao,
    MemberRepository memberRepository,
  ) : super(dao, null, memberRepository: memberRepository);

  final updates = <Map<String, Object?>>[];
  final deletes = <Map<String, Object?>>[];

  @override
  Future<void> syncRecordUpdate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    updates.add({
      'table': table,
      'entityId': entityId,
      'fields': Map<String, dynamic>.from(fields),
    });
  }

  @override
  Future<void> syncRecordDelete(String table, String entityId) async {
    deletes.add({'table': table, 'entityId': entityId});
  }
}

member_domain.Member _member({
  required String id,
  required String name,
  required String? pluralkitUuid,
}) {
  return member_domain.Member(
    id: id,
    name: name,
    createdAt: DateTime.utc(2024, 1, 1),
    pluralkitUuid: pluralkitUuid,
  );
}

MemberGroupsCompanion _group({
  required String id,
  required String name,
  required DateTime createdAt,
  String? parentGroupId,
  String? pluralkitUuid,
  bool syncSuppressed = false,
  String? suspectedPkGroupUuid,
}) => pkFixtureGroup(
      id: id,
      name: name,
      createdAt: createdAt,
      parentGroupId: parentGroupId,
      pluralkitUuid: pluralkitUuid,
      syncSuppressed: syncSuppressed,
      suspectedPkGroupUuid: suspectedPkGroupUuid,
    );

MemberGroupEntriesCompanion _entry({
  required String id,
  required String groupId,
  required String memberId,
  String? pkGroupUuid,
  String? pkMemberUuid,
}) => pkFixtureEntry(
      id: id,
      groupId: groupId,
      memberId: memberId,
      pkGroupUuid: pkGroupUuid,
      pkMemberUuid: pkMemberUuid,
    );

PkGroupEntryDeferredSyncOpsCompanion _deferredOp({
  required String id,
  required String entityId,
}) {
  return PkGroupEntryDeferredSyncOpsCompanion.insert(
    id: id,
    entityType: 'member_group_entries',
    entityId: entityId,
    fieldsJson: '{}',
    reason: 'waiting for refs',
    createdAt: DateTime.utc(2026, 4, 23),
  );
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test(
    'reset removes PK-linked and suppressed groups, promotes manual children, and clears deferred ops',
    () async {
      await db
          .into(db.members)
          .insert(
            MembersCompanion.insert(
              id: 'member-a',
              name: 'Alice',
              createdAt: DateTime.utc(2024, 1, 1),
              pluralkitUuid: const Value('pk-member-a'),
            ),
          );
      await db
          .into(db.members)
          .insert(
            MembersCompanion.insert(
              id: 'member-b',
              name: 'Bob',
              createdAt: DateTime.utc(2024, 1, 1),
            ),
          );

      await db
          .into(db.memberGroups)
          .insert(
            _group(
              id: 'pk-root',
              name: 'PK Root',
              createdAt: DateTime.utc(2024, 1, 1),
              pluralkitUuid: 'pk-group-root',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            _group(
              id: 'pk-child',
              name: 'PK Child',
              createdAt: DateTime.utc(2024, 1, 2),
              parentGroupId: 'pk-root',
              pluralkitUuid: 'pk-group-child',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            _group(
              id: 'suppressed',
              name: 'Suppressed Copy',
              createdAt: DateTime.utc(2024, 1, 3),
              syncSuppressed: true,
              suspectedPkGroupUuid: 'pk-group-root',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            _group(
              id: 'local-child',
              name: 'Local Child',
              createdAt: DateTime.utc(2024, 1, 4),
              parentGroupId: 'pk-root',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            _group(
              id: 'local-grandchild',
              name: 'Local Grandchild',
              createdAt: DateTime.utc(2024, 1, 5),
              parentGroupId: 'pk-child',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            _group(
              id: 'manual-root',
              name: 'Manual Root',
              createdAt: DateTime.utc(2024, 1, 6),
            ),
          );

      await db
          .into(db.memberGroupEntries)
          .insert(
            _entry(
              id: 'root-entry',
              groupId: 'pk-root',
              memberId: 'member-a',
              pkGroupUuid: 'pk-group-root',
              pkMemberUuid: 'pk-member-a',
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            _entry(
              id: 'child-entry',
              groupId: 'pk-child',
              memberId: 'member-a',
              pkGroupUuid: 'pk-group-child',
              pkMemberUuid: 'pk-member-a',
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            _entry(
              id: 'suppressed-entry',
              groupId: 'suppressed',
              memberId: 'member-b',
            ),
          );

      await db.pkGroupEntryDeferredSyncOpsDao.upsert(
        _deferredOp(id: 'deferred-1', entityId: 'root-entry'),
      );
      await db.pkGroupEntryDeferredSyncOpsDao.upsert(
        _deferredOp(id: 'deferred-2', entityId: 'suppressed-entry'),
      );

      final repository = _RecordingMemberGroupsRepository(
        db.memberGroupsDao,
        _FakeMemberRepository({
          'member-a': _member(
            id: 'member-a',
            name: 'Alice',
            pluralkitUuid: 'pk-member-a',
          ),
          'member-b': _member(id: 'member-b', name: 'Bob', pluralkitUuid: null),
        }),
      );
      final service = PkGroupResetService(
        db: db,
        memberGroupsRepository: repository,
      );

      final result = await service.resetPkGroupsOnly();

      expect(result.groupsReset, 3);
      expect(result.promotedChildGroups, 2);
      expect(result.deferredOpsCleared, 2);

      final activeGroups = await db.memberGroupsDao.getAllActiveGroups();
      expect(activeGroups.map((group) => group.id).toSet(), {
        'local-child',
        'local-grandchild',
        'manual-root',
      });

      final promotedChild = await db.memberGroupsDao.getGroupById(
        'local-child',
      );
      final promotedGrandchild = await db.memberGroupsDao.getGroupById(
        'local-grandchild',
      );
      expect(promotedChild?.parentGroupId, isNull);
      expect(promotedGrandchild?.parentGroupId, isNull);

      final deletedPkRoot = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('pk-root'))).getSingle();
      final deletedSuppressed = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('suppressed'))).getSingle();
      expect(deletedPkRoot.isDeleted, isTrue);
      expect(deletedSuppressed.isDeleted, isTrue);

      expect(await db.pkGroupEntryDeferredSyncOpsDao.getAll(), isEmpty);

      expect(repository.updates.map((op) => op['entityId']).toSet(), {
        'local-child',
        'local-grandchild',
      });
      expect(
        repository.deletes.map((op) => op['entityId']).toSet(),
        {'suppressed-entry', 'suppressed'},
      );
    },
  );

  test(
    'reset preserves manual groups and still clears lingering deferred PK ops',
    () async {
      await db
          .into(db.memberGroups)
          .insert(
            _group(
              id: 'manual-root',
              name: 'Manual Root',
              createdAt: DateTime.utc(2024, 1, 1),
            ),
          );
      await db.pkGroupEntryDeferredSyncOpsDao.upsert(
        _deferredOp(id: 'deferred-1', entityId: 'legacy-entry'),
      );

      final repository = _RecordingMemberGroupsRepository(
        db.memberGroupsDao,
        _FakeMemberRepository(const {}),
      );
      final service = PkGroupResetService(
        db: db,
        memberGroupsRepository: repository,
      );

      final result = await service.resetPkGroupsOnly();

      expect(result.groupsReset, 0);
      expect(result.promotedChildGroups, 0);
      expect(result.deferredOpsCleared, 1);
      expect(
        (await db.memberGroupsDao.getAllActiveGroups()).map(
          (group) => group.id,
        ),
        ['manual-root'],
      );
      expect(repository.updates, isEmpty);
      expect(repository.deletes, isEmpty);
      expect(await db.pkGroupEntryDeferredSyncOpsDao.getAll(), isEmpty);
    },
  );
}
