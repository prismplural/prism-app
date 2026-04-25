import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/member_groups_dao.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/domain/models/member.dart' as member_domain;
import 'package:prism_plurality/domain/models/member_group.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';

class _TestMemberGroupsDao extends MemberGroupsDao {
  _TestMemberGroupsDao(super.db);

  final suppressedGroupIds = <String>{};

  @override
  Future<bool> isGroupSyncSuppressed(String groupId) async {
    return suppressedGroupIds.contains(groupId);
  }
}

class _RecordingMemberGroupsRepository extends DriftMemberGroupsRepository {
  _RecordingMemberGroupsRepository(
    MemberGroupsDao dao,
    MemberRepository memberRepository,
  ) : super(dao, null, memberRepository: memberRepository);

  final creates = <Map<String, Object?>>[];
  final updates = <Map<String, Object?>>[];
  final deletes = <Map<String, String>>[];

  @override
  Future<void> syncRecordCreate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    creates.add({
      'table': table,
      'entityId': entityId,
      'fields': Map<String, dynamic>.from(fields),
    });
  }

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

class _FakeMemberRepository implements MemberRepository {
  _FakeMemberRepository({List<member_domain.Member>? members})
    : _members = members ?? <member_domain.Member>[];

  final List<member_domain.Member> _members;

  @override
  Future<void> clearPluralKitLink(String id) async {}

  @override
  Future<void> createMember(member_domain.Member member) async {
    _members.add(member);
  }

  @override
  Future<void> deleteMember(String id) async {
    _members.removeWhere((member) => member.id == id);
  }

  @override
  Future<List<member_domain.Member>> getAllMembers() async => _members;

  @override
  Future<int> getCount() async => _members.length;

  @override
  Future<List<member_domain.Member>> getDeletedLinkedMembers() async =>
      const [];

  @override
  Future<member_domain.Member?> getMemberById(String id) async {
    for (final member in _members) {
      if (member.id == id) return member;
    }
    return null;
  }

  @override
  Future<List<member_domain.Member>> getMembersByIds(List<String> ids) async =>
      _members.where((member) => ids.contains(member.id)).toList();

  @override
  Stream<List<member_domain.Member>> watchMembersByIds(List<String> ids) =>
      throw UnimplementedError();

  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async {}

  @override
  Future<void> updateMember(member_domain.Member member) async {
    final index = _members.indexWhere((existing) => existing.id == member.id);
    if (index >= 0) {
      _members[index] = member;
    }
  }

  @override
  Stream<List<member_domain.Member>> watchActiveMembers() =>
      throw UnimplementedError();

  @override
  Stream<List<member_domain.Member>> watchAllMembers() =>
      throw UnimplementedError();

  @override
  Stream<member_domain.Member?> watchMemberById(String id) =>
      throw UnimplementedError();
}

domain.MemberGroup _groupModel({
  required String id,
  String? name,
  String? parentGroupId,
}) => domain.MemberGroup(
  id: id,
  name: name ?? id,
  parentGroupId: parentGroupId,
  createdAt: DateTime.utc(2026, 1, 1),
);

Future<void> _insertGroup(
  AppDatabase db, {
  required String id,
  bool syncSuppressed = false,
}) async {
  await db
      .into(db.memberGroups)
      .insert(
        MemberGroupsCompanion.insert(
          id: id,
          name: id,
          createdAt: DateTime.utc(2026, 1, 1),
          syncSuppressed: Value(syncSuppressed),
        ),
      );
}

Future<void> _insertEntry(
  AppDatabase db, {
  required String id,
  required String groupId,
  required String memberId,
}) {
  return db
      .into(db.memberGroupEntries)
      .insert(
        MemberGroupEntriesCompanion.insert(
          id: id,
          groupId: groupId,
          memberId: memberId,
        ),
      );
}

void main() {
  late AppDatabase db;
  late _TestMemberGroupsDao dao;
  late _RecordingMemberGroupsRepository repo;
  late _FakeMemberRepository memberRepository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = _TestMemberGroupsDao(db);
    memberRepository = _FakeMemberRepository();
    repo = _RecordingMemberGroupsRepository(dao, memberRepository);
  });

  tearDown(() async {
    await db.close();
  });

  test('dao reads sync_suppressed from persisted group rows', () async {
    await _insertGroup(db, id: 'suppressed-group', syncSuppressed: true);
    await _insertGroup(db, id: 'normal-group');

    expect(
      await db.memberGroupsDao.isGroupSyncSuppressed('suppressed-group'),
      isTrue,
    );
    expect(
      await db.memberGroupsDao.isGroupSyncSuppressed('normal-group'),
      isFalse,
    );
  });

  test(
    'createGroup skips outgoing sync create for sync_suppressed groups',
    () async {
      dao.suppressedGroupIds.add('pk-local-only');

      await repo.createGroup(_groupModel(id: 'pk-local-only'));

      expect(repo.creates, isEmpty);
      final stored = await db.memberGroupsDao.getAllActiveGroups();
      expect(stored.map((group) => group.id), ['pk-local-only']);
    },
  );

  test('createGroup still emits when sync_suppressed is false', () async {
    await repo.createGroup(_groupModel(id: 'normal-group'));

    expect(repo.creates, hasLength(1));
    final create = repo.creates.single;
    expect(create['table'], 'member_groups');
    expect(create['entityId'], 'normal-group');
    expect(create['fields'], isA<Map<String, dynamic>>());

    final fields = create['fields']! as Map<String, dynamic>;
    expect(fields['name'], 'normal-group');
    expect(fields['description'], null);
    expect(fields['color_hex'], null);
    expect(fields['emoji'], null);
    expect(fields['display_order'], 0);
    expect(fields['parent_group_id'], null);
    expect(fields['group_type'], 0);
    expect(fields['filter_rules'], null);
    expect(fields['pluralkit_id'], null);
    expect(fields['pluralkit_uuid'], null);
    expect(fields['last_seen_from_pk_at'], null);
    expect(fields['is_deleted'], false);
    expect(
      DateTime.parse(
        fields['created_at']! as String,
      ).toUtc().isAtSameMomentAs(DateTime.utc(2026, 1, 1)),
      isTrue,
    );
  });

  test(
    'updateGroup skips outgoing sync update for sync_suppressed groups',
    () async {
      dao.suppressedGroupIds.add('suppressed-group');
      await _insertGroup(db, id: 'suppressed-group');

      await repo.updateGroup(
        _groupModel(id: 'suppressed-group', name: 'Renamed locally'),
      );

      expect(repo.updates, isEmpty);
      final stored = await db.memberGroupsDao
          .watchGroupById('suppressed-group')
          .first;
      expect(stored?.name, 'Renamed locally');
    },
  );

  test(
    'deleteGroup skips outgoing group and membership deletes when suppressed',
    () async {
      dao.suppressedGroupIds.add('suppressed-group');
      await _insertGroup(db, id: 'suppressed-group');
      await _insertEntry(
        db,
        id: 'entry-1',
        groupId: 'suppressed-group',
        memberId: 'member-1',
      );

      await repo.deleteGroup('suppressed-group');

      expect(repo.deletes, isEmpty);
      final activeGroups = await db.memberGroupsDao.getAllActiveGroups();
      expect(activeGroups, isEmpty);
      final activeEntries = await db.memberGroupsDao.entriesForGroup(
        'suppressed-group',
      );
      expect(activeEntries, isEmpty);
    },
  );

  test(
    'membership emits are skipped when the parent group is suppressed',
    () async {
      dao.suppressedGroupIds.add('suppressed-group');
      await _insertGroup(db, id: 'suppressed-group');

      await repo.addMemberToGroup('suppressed-group', 'member-1', 'entry-1');
      await repo.removeMemberFromGroup('suppressed-group', 'member-1');

      expect(repo.creates, isEmpty);
      expect(repo.deletes, isEmpty);
      final activeEntries = await db.memberGroupsDao.entriesForGroup(
        'suppressed-group',
      );
      expect(activeEntries, isEmpty);
    },
  );
}
