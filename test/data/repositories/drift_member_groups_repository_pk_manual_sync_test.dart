import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/member_groups_dao.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/domain/models/member.dart' as member_domain;
import 'package:prism_plurality/domain/models/member_group.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';

class _FakeMemberRepository implements MemberRepository {
  _FakeMemberRepository(this._membersById);

  final Map<String, member_domain.Member> _membersById;

  @override
  Future<member_domain.Member?> getMemberById(String id) async {
    return _membersById[id];
  }

  @override
  Future<void> clearPluralKitLink(String id) {
    throw UnimplementedError();
  }

  @override
  Future<void> createMember(member_domain.Member member) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteMember(String id) {
    throw UnimplementedError();
  }

  @override
  Future<List<member_domain.Member>> getAllMembers() async {
    return _membersById.values.toList();
  }

  @override
  Future<int> getCount() async => _membersById.length;

  @override
  Future<List<member_domain.Member>> getDeletedLinkedMembers() {
    throw UnimplementedError();
  }

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
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) {
    throw UnimplementedError();
  }

  @override
  Future<void> updateMember(member_domain.Member member) {
    throw UnimplementedError();
  }

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

  final creates = <Map<String, Object?>>[];
  final updates = <Map<String, Object?>>[];
  final deletes = <Map<String, Object?>>[];

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

String _canonicalPkGroupEntityId(String pkGroupUuid) => 'pk-group:$pkGroupUuid';

String _deterministicPkEntryId(String pkGroupUuid, String pkMemberUuid) {
  final digest = sha256.convert(utf8.encode('$pkGroupUuid\u0000$pkMemberUuid'));
  return digest.toString().substring(0, 16);
}

Future<void> _insertPkBackedGroup(
  AppDatabase db, {
  required String id,
  required String name,
  required String pluralkitId,
  required String pluralkitUuid,
  required DateTime createdAt,
  required DateTime lastSeenFromPkAt,
  String? description,
  String? colorHex,
  int displayOrder = 0,
  int groupType = 0,
  String? filterRules,
}) async {
  await db
      .into(db.memberGroups)
      .insert(
        MemberGroupsCompanion.insert(
          id: id,
          name: name,
          description: Value(description),
          colorHex: Value(colorHex),
          displayOrder: Value(displayOrder),
          groupType: Value(groupType),
          filterRules: Value(filterRules),
          createdAt: createdAt,
          pluralkitId: Value(pluralkitId),
          pluralkitUuid: Value(pluralkitUuid),
          lastSeenFromPkAt: Value(lastSeenFromPkAt),
        ),
      );
}

Future<void> _insertPkLinkedMember(
  AppDatabase db, {
  required String id,
  required String name,
  required String pluralkitUuid,
  required DateTime createdAt,
}) async {
  await db
      .into(db.members)
      .insert(
        MembersCompanion.insert(
          id: id,
          name: name,
          createdAt: createdAt,
          pluralkitUuid: Value(pluralkitUuid),
        ),
      );
}

Future<void> _insertEntry(
  AppDatabase db, {
  required String id,
  required String groupId,
  required String memberId,
  String? pkGroupUuid,
  String? pkMemberUuid,
  bool isDeleted = false,
}) async {
  await db
      .into(db.memberGroupEntries)
      .insert(
        MemberGroupEntriesCompanion.insert(
          id: id,
          groupId: groupId,
          memberId: memberId,
          pkGroupUuid: Value(pkGroupUuid),
          pkMemberUuid: Value(pkMemberUuid),
          isDeleted: Value(isDeleted),
        ),
      );
}

Future<void> _insertPkGroupSyncAlias(
  AppDatabase db, {
  required String legacyEntityId,
  required String pkGroupUuid,
  required String canonicalEntityId,
}) async {
  await db
      .into(db.pkGroupSyncAliases)
      .insert(
        PkGroupSyncAliasesCompanion.insert(
          legacyEntityId: legacyEntityId,
          pkGroupUuid: pkGroupUuid,
          canonicalEntityId: canonicalEntityId,
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
}

domain.MemberGroup _groupModel({
  required String id,
  required String name,
  required DateTime createdAt,
  String? description,
  String? colorHex,
  int displayOrder = 0,
  int groupType = 0,
  String? filterRules,
}) {
  return domain.MemberGroup(
    id: id,
    name: name,
    description: description,
    colorHex: colorHex,
    displayOrder: displayOrder,
    groupType: groupType,
    filterRules: filterRules,
    createdAt: createdAt,
  );
}

member_domain.Member _memberModel({
  required String id,
  required String name,
  required DateTime createdAt,
  String? pluralkitUuid,
}) {
  return member_domain.Member(
    id: id,
    name: name,
    createdAt: createdAt,
    pluralkitUuid: pluralkitUuid,
  );
}

void main() {
  late AppDatabase db;
  late _FakeMemberRepository memberRepository;
  late _RecordingMemberGroupsRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    memberRepository = _FakeMemberRepository({});
    repo = _RecordingMemberGroupsRepository(
      db.memberGroupsDao,
      memberRepository,
    );
    await db.systemSettingsDao.getSettings();
    await db.systemSettingsDao.updatePkGroupSyncV2Enabled(true);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> setPkGroupSyncV2Enabled(bool value) async {
    await db.systemSettingsDao.getSettings();
    await db.systemSettingsDao.updatePkGroupSyncV2Enabled(value);
  }

  test(
    'PK-backed sync emits are held back while enablement bit is false, manual groups still emit',
    () async {
      await setPkGroupSyncV2Enabled(false);

      final createdAt = DateTime.utc(2026, 1, 1, 12, 30);
      await _insertPkBackedGroup(
        db,
        id: 'pk-group-local',
        name: 'Original name',
        pluralkitId: 'abcde',
        pluralkitUuid: 'pk-group-1',
        createdAt: createdAt,
        lastSeenFromPkAt: DateTime.utc(2026, 2, 2, 8, 15),
      );

      await repo.updateGroup(
        _groupModel(
          id: 'pk-group-local',
          name: 'Renamed locally',
          description: 'Edited in Prism',
          colorHex: '#ff00aa',
          displayOrder: 7,
          groupType: 2,
          filterRules: '{"mode":"all"}',
          createdAt: createdAt,
        ),
      );

      await repo.createGroup(
        _groupModel(id: 'manual-group-1', name: 'Manual', createdAt: createdAt),
      );

      expect(repo.updates, isEmpty);
      expect(repo.creates, hasLength(1));
      expect(repo.creates.single['entityId'], 'manual-group-1');
    },
  );

  test(
    'updateGroup emits canonical PK sync payload for PK-backed groups',
    () async {
      final createdAt = DateTime.utc(2026, 1, 1, 12, 30);
      final lastSeenFromPkAt = DateTime.utc(2026, 2, 2, 8, 15);

      await _insertPkBackedGroup(
        db,
        id: 'local-group-1',
        name: 'Original name',
        pluralkitId: 'abcde',
        pluralkitUuid: 'pk-group-1',
        createdAt: createdAt,
        lastSeenFromPkAt: lastSeenFromPkAt,
      );

      await repo.updateGroup(
        _groupModel(
          id: 'local-group-1',
          name: 'Renamed locally',
          description: 'Edited in Prism',
          colorHex: '#ff00aa',
          displayOrder: 7,
          groupType: 2,
          filterRules: '{"mode":"all"}',
          createdAt: createdAt,
        ),
      );
      final stored = await db.memberGroupsDao.getGroupById('local-group-1');

      expect(repo.updates, hasLength(1));
      expect(repo.creates, isEmpty);
      expect(stored != null, isTrue);

      final update = repo.updates.single;
      expect(update['table'], 'member_groups');
      expect(update['entityId'], _canonicalPkGroupEntityId('pk-group-1'));
      expect(
        update['entityId'],
        isNot('local-group-1'),
        reason:
            'PK-backed group edits should sync on the canonical PK entity id.',
      );
      expect(update['fields'], {
        'name': 'Renamed locally',
        'description': 'Edited in Prism',
        'color_hex': '#ff00aa',
        'emoji': null,
        'display_order': 7,
        'parent_group_id': null,
        'group_type': 2,
        'filter_rules': '{"mode":"all"}',
        'created_at': stored!.createdAt.toIso8601String(),
        'pluralkit_id': 'abcde',
        'pluralkit_uuid': 'pk-group-1',
        'last_seen_from_pk_at': stored.lastSeenFromPkAt!.toIso8601String(),
        'is_deleted': false,
      });
    },
  );

  test(
    'updateGroup emits legacy alias deletes alongside canonical PK updates',
    () async {
      final createdAt = DateTime.utc(2026, 1, 1, 12, 30);
      const pkGroupUuid = 'pk-group-1';
      final canonicalEntityId = _canonicalPkGroupEntityId(pkGroupUuid);

      await _insertPkBackedGroup(
        db,
        id: 'local-group-1',
        name: 'Original name',
        pluralkitId: 'abcde',
        pluralkitUuid: pkGroupUuid,
        createdAt: createdAt,
        lastSeenFromPkAt: DateTime.utc(2026, 2, 2, 8, 15),
      );
      await _insertPkGroupSyncAlias(
        db,
        legacyEntityId: 'legacy-group-1',
        pkGroupUuid: pkGroupUuid,
        canonicalEntityId: canonicalEntityId,
      );
      await _insertPkGroupSyncAlias(
        db,
        legacyEntityId: canonicalEntityId,
        pkGroupUuid: pkGroupUuid,
        canonicalEntityId: canonicalEntityId,
      );

      await repo.updateGroup(
        _groupModel(
          id: 'local-group-1',
          name: 'Renamed locally',
          description: 'Edited in Prism',
          colorHex: '#ff00aa',
          displayOrder: 7,
          groupType: 2,
          filterRules: '{"mode":"all"}',
          createdAt: createdAt,
        ),
      );

      expect(repo.updates, hasLength(1));
      expect(repo.updates.single['entityId'], canonicalEntityId);
      expect(repo.deletes, hasLength(1));
      expect(repo.deletes.single, {
        'table': 'member_groups',
        'entityId': 'legacy-group-1',
      });
    },
  );

  test('addMemberToGroup emits PK UUID fields and deterministic entry ids for '
      'PK-backed groups', () async {
    final createdAt = DateTime.utc(2026, 1, 1);

    await _insertPkBackedGroup(
      db,
      id: 'local-group-1',
      name: 'Core group',
      pluralkitId: 'abcde',
      pluralkitUuid: 'pk-group-1',
      createdAt: createdAt,
      lastSeenFromPkAt: DateTime.utc(2026, 2, 3),
    );
    await _insertPkLinkedMember(
      db,
      id: 'local-member-1',
      name: 'Linked member',
      pluralkitUuid: 'pk-member-1',
      createdAt: createdAt,
    );
    memberRepository = _FakeMemberRepository({
      'local-member-1': _memberModel(
        id: 'local-member-1',
        name: 'Linked member',
        createdAt: createdAt,
        pluralkitUuid: 'pk-member-1',
      ),
    });
    repo = _RecordingMemberGroupsRepository(
      db.memberGroupsDao,
      memberRepository,
    );

    await repo.addMemberToGroup(
      'local-group-1',
      'local-member-1',
      'random-local-entry-id',
    );

    expect(repo.creates, hasLength(1));
    expect(repo.updates, isEmpty);

    final create = repo.creates.single;
    final expectedEntryId = _deterministicPkEntryId(
      'pk-group-1',
      'pk-member-1',
    );

    expect(create['table'], 'member_group_entries');
    expect(create['entityId'], expectedEntryId);
    expect(
      create['entityId'],
      isNot('random-local-entry-id'),
      reason:
          'PK-backed memberships should derive a stable sync entity id from '
          'PK UUIDs.',
    );
    expect(create['fields'], {
      'group_id': 'local-group-1',
      'member_id': 'local-member-1',
      'pk_group_uuid': 'pk-group-1',
      'pk_member_uuid': 'pk-member-1',
      'is_deleted': false,
    });
  });

  test(
    'addMemberToGroup keeps local-only members in PK-backed groups local',
    () async {
      final createdAt = DateTime.utc(2026, 1, 1);

      await _insertPkBackedGroup(
        db,
        id: 'local-group-1',
        name: 'Core group',
        pluralkitId: 'abcde',
        pluralkitUuid: 'pk-group-1',
        createdAt: createdAt,
        lastSeenFromPkAt: DateTime.utc(2026, 2, 3),
      );
      memberRepository = _FakeMemberRepository({
        'local-member-1': _memberModel(
          id: 'local-member-1',
          name: 'Local member',
          createdAt: createdAt,
        ),
      });
      repo = _RecordingMemberGroupsRepository(
        db.memberGroupsDao,
        memberRepository,
      );

      await repo.addMemberToGroup(
        'local-group-1',
        'local-member-1',
        'local-only-entry',
      );

      expect(repo.creates, isEmpty);
      final stored = await db.memberGroupsDao.findEntry(
        'local-group-1',
        'local-member-1',
      );
      expect(stored, isNotNull);
      expect(stored!.id, 'local-only-entry');
    },
  );

  test(
    'emitGroupSyncState skips local-only entries in PK-backed groups',
    () async {
      final createdAt = DateTime.utc(2026, 1, 1);

      await _insertPkBackedGroup(
        db,
        id: 'local-group-1',
        name: 'Core group',
        pluralkitId: 'abcde',
        pluralkitUuid: 'pk-group-1',
        createdAt: createdAt,
        lastSeenFromPkAt: DateTime.utc(2026, 2, 3),
      );
      await _insertPkLinkedMember(
        db,
        id: 'linked-member',
        name: 'Linked member',
        pluralkitUuid: 'pk-member-1',
        createdAt: createdAt,
      );
      await db
          .into(db.members)
          .insert(
            MembersCompanion.insert(
              id: 'local-member',
              name: 'Local member',
              createdAt: createdAt,
            ),
          );
      await _insertEntry(
        db,
        id: 'linked-entry',
        groupId: 'local-group-1',
        memberId: 'linked-member',
      );
      await _insertEntry(
        db,
        id: 'local-only-entry',
        groupId: 'local-group-1',
        memberId: 'local-member',
      );
      memberRepository = _FakeMemberRepository({
        'linked-member': _memberModel(
          id: 'linked-member',
          name: 'Linked member',
          createdAt: createdAt,
          pluralkitUuid: 'pk-member-1',
        ),
        'local-member': _memberModel(
          id: 'local-member',
          name: 'Local member',
          createdAt: createdAt,
        ),
      });
      repo = _RecordingMemberGroupsRepository(
        db.memberGroupsDao,
        memberRepository,
      );

      await repo.emitGroupSyncState('local-group-1');

      expect(repo.updates, hasLength(2));
      expect(repo.updates.map((record) => record['table']).toList(), [
        'member_groups',
        'member_group_entries',
      ]);
      expect(
        repo.updates.first['entityId'],
        _canonicalPkGroupEntityId('pk-group-1'),
      );
      final entryUpdate = repo.updates.last;
      expect(
        entryUpdate['entityId'],
        _deterministicPkEntryId('pk-group-1', 'pk-member-1'),
      );
      expect(entryUpdate['fields'], {
        'group_id': 'local-group-1',
        'member_id': 'linked-member',
        'pk_group_uuid': 'pk-group-1',
        'pk_member_uuid': 'pk-member-1',
        'is_deleted': false,
      });
      expect(
        repo.updates.any((record) => record['entityId'] == 'local-only-entry'),
        isFalse,
      );
    },
  );

  test('deleteGroup emits canonical PK delete ids for PK-backed groups and '
      'memberships', () async {
    final createdAt = DateTime.utc(2026, 1, 1, 12, 30);

    await _insertPkBackedGroup(
      db,
      id: 'legacy-group-1',
      name: 'Core group',
      pluralkitId: 'abcde',
      pluralkitUuid: 'pk-group-1',
      createdAt: createdAt,
      lastSeenFromPkAt: DateTime.utc(2026, 2, 3),
    );
    await _insertPkLinkedMember(
      db,
      id: 'legacy-member-1',
      name: 'Linked member',
      pluralkitUuid: 'pk-member-1',
      createdAt: createdAt,
    );
    memberRepository = _FakeMemberRepository({
      'legacy-member-1': _memberModel(
        id: 'legacy-member-1',
        name: 'Linked member',
        createdAt: createdAt,
        pluralkitUuid: 'pk-member-1',
      ),
    });
    repo = _RecordingMemberGroupsRepository(
      db.memberGroupsDao,
      memberRepository,
    );
    await _insertEntry(
      db,
      id: 'legacy-entry-1',
      groupId: 'legacy-group-1',
      memberId: 'legacy-member-1',
      pkGroupUuid: 'pk-group-1',
      pkMemberUuid: 'pk-member-1',
    );

    await repo.deleteGroup('legacy-group-1');

    final expectedEntryId = _deterministicPkEntryId(
      'pk-group-1',
      'pk-member-1',
    );

    expect(repo.deletes, hasLength(2));
    expect(repo.deletes.map((record) => record['entityId']).toSet(), {
      expectedEntryId,
      _canonicalPkGroupEntityId('pk-group-1'),
    });
    expect(repo.deletes.map((record) => record['table']).toSet(), {
      'member_group_entries',
      'member_groups',
    });
    expect(
      repo.deletes.any((record) => record['entityId'] == 'legacy-group-1'),
      isFalse,
    );
    expect(
      repo.deletes.any((record) => record['entityId'] == 'legacy-entry-1'),
      isFalse,
    );
    expect(await db.memberGroupsDao.getAllActiveGroups(), isEmpty);
    expect(await db.memberGroupsDao.getAllGroupEntries(), isEmpty);
  });

  test(
    'deleteGroup also emits legacy alias deletes for canonical PK-backed groups',
    () async {
      final createdAt = DateTime.utc(2026, 1, 1, 12, 30);
      const pkGroupUuid = 'pk-group-1';
      final canonicalEntityId = _canonicalPkGroupEntityId(pkGroupUuid);

      await _insertPkBackedGroup(
        db,
        id: 'legacy-group-1',
        name: 'Core group',
        pluralkitId: 'abcde',
        pluralkitUuid: pkGroupUuid,
        createdAt: createdAt,
        lastSeenFromPkAt: DateTime.utc(2026, 2, 3),
      );
      await _insertPkLinkedMember(
        db,
        id: 'legacy-member-1',
        name: 'Linked member',
        pluralkitUuid: 'pk-member-1',
        createdAt: createdAt,
      );
      await _insertPkGroupSyncAlias(
        db,
        legacyEntityId: 'old-local-group-id',
        pkGroupUuid: pkGroupUuid,
        canonicalEntityId: canonicalEntityId,
      );
      await _insertPkGroupSyncAlias(
        db,
        legacyEntityId: canonicalEntityId,
        pkGroupUuid: pkGroupUuid,
        canonicalEntityId: canonicalEntityId,
      );
      memberRepository = _FakeMemberRepository({
        'legacy-member-1': _memberModel(
          id: 'legacy-member-1',
          name: 'Linked member',
          createdAt: createdAt,
          pluralkitUuid: 'pk-member-1',
        ),
      });
      repo = _RecordingMemberGroupsRepository(
        db.memberGroupsDao,
        memberRepository,
      );
      await _insertEntry(
        db,
        id: 'legacy-entry-1',
        groupId: 'legacy-group-1',
        memberId: 'legacy-member-1',
        pkGroupUuid: pkGroupUuid,
        pkMemberUuid: 'pk-member-1',
      );

      await repo.deleteGroup('legacy-group-1');

      final expectedEntryId = _deterministicPkEntryId(
        pkGroupUuid,
        'pk-member-1',
      );

      expect(repo.deletes.map((record) => record['entityId']).toSet(), {
        expectedEntryId,
        canonicalEntityId,
        'old-local-group-id',
      });
      expect(
        repo.deletes.where((record) => record['entityId'] == canonicalEntityId),
        hasLength(1),
      );
    },
  );

  test('removeMemberFromGroup emits the canonical PK-backed membership delete '
      'identity', () async {
    final createdAt = DateTime.utc(2026, 1, 1);

    await _insertPkBackedGroup(
      db,
      id: 'legacy-group-1',
      name: 'Core group',
      pluralkitId: 'abcde',
      pluralkitUuid: 'pk-group-1',
      createdAt: createdAt,
      lastSeenFromPkAt: DateTime.utc(2026, 2, 3),
    );
    await _insertPkLinkedMember(
      db,
      id: 'legacy-member-1',
      name: 'Linked member',
      pluralkitUuid: 'pk-member-1',
      createdAt: createdAt,
    );
    memberRepository = _FakeMemberRepository({
      'legacy-member-1': _memberModel(
        id: 'legacy-member-1',
        name: 'Linked member',
        createdAt: createdAt,
        pluralkitUuid: 'pk-member-1',
      ),
    });
    repo = _RecordingMemberGroupsRepository(
      db.memberGroupsDao,
      memberRepository,
    );
    await _insertEntry(
      db,
      id: 'legacy-entry-1',
      groupId: 'legacy-group-1',
      memberId: 'legacy-member-1',
      pkGroupUuid: 'pk-group-1',
      pkMemberUuid: 'pk-member-1',
    );

    await repo.removeMemberFromGroup('legacy-group-1', 'legacy-member-1');

    expect(repo.deletes, hasLength(1));
    expect(repo.deletes.single, {
      'table': 'member_group_entries',
      'entityId': _deterministicPkEntryId('pk-group-1', 'pk-member-1'),
    });
    expect(repo.deletes.single['entityId'], isNot('legacy-entry-1'));
    expect(await db.memberGroupsDao.entriesForGroup('legacy-group-1'), isEmpty);
  });

  test('removeMemberFromGroup still uses the logical PK edge when the member '
      'repository no longer resolves PK identity', () async {
    final createdAt = DateTime.utc(2026, 1, 1);

    await _insertPkBackedGroup(
      db,
      id: 'legacy-group-1',
      name: 'Core group',
      pluralkitId: 'abcde',
      pluralkitUuid: 'pk-group-1',
      createdAt: createdAt,
      lastSeenFromPkAt: DateTime.utc(2026, 2, 3),
    );
    memberRepository = _FakeMemberRepository({});
    repo = _RecordingMemberGroupsRepository(
      db.memberGroupsDao,
      memberRepository,
    );
    await _insertEntry(
      db,
      id: 'legacy-entry-1',
      groupId: 'legacy-group-1',
      memberId: 'legacy-member-1',
      pkGroupUuid: 'pk-group-1',
      pkMemberUuid: 'pk-member-1',
    );

    await repo.removeMemberFromGroup('legacy-group-1', 'legacy-member-1');

    expect(repo.deletes, hasLength(1));
    expect(repo.deletes.single, {
      'table': 'member_group_entries',
      'entityId': _deterministicPkEntryId('pk-group-1', 'pk-member-1'),
    });
  });

  test(
    'addMemberToGroup revives a tombstoned deterministic PK-backed membership '
    'row',
    () async {
      final createdAt = DateTime.utc(2026, 1, 1);
      final entryId = _deterministicPkEntryId('pk-group-1', 'pk-member-1');

      await _insertPkBackedGroup(
        db,
        id: 'legacy-group-1',
        name: 'Core group',
        pluralkitId: 'abcde',
        pluralkitUuid: 'pk-group-1',
        createdAt: createdAt,
        lastSeenFromPkAt: DateTime.utc(2026, 2, 3),
      );
      await _insertPkLinkedMember(
        db,
        id: 'legacy-member-1',
        name: 'Linked member',
        pluralkitUuid: 'pk-member-1',
        createdAt: createdAt,
      );
      memberRepository = _FakeMemberRepository({
        'legacy-member-1': _memberModel(
          id: 'legacy-member-1',
          name: 'Linked member',
          createdAt: createdAt,
          pluralkitUuid: 'pk-member-1',
        ),
      });
      repo = _RecordingMemberGroupsRepository(
        db.memberGroupsDao,
        memberRepository,
      );
      await _insertEntry(
        db,
        id: entryId,
        groupId: 'legacy-group-1',
        memberId: 'legacy-member-1',
        pkGroupUuid: 'pk-group-1',
        pkMemberUuid: 'pk-member-1',
        isDeleted: true,
      );

      await repo.addMemberToGroup(
        'legacy-group-1',
        'legacy-member-1',
        'random-local-entry-id',
      );

      expect(repo.creates, hasLength(1));
      expect(repo.creates.single['entityId'], entryId);
      expect(repo.creates.single['entityId'], isNot('random-local-entry-id'));

      final stored = await db.memberGroupsDao.findEntry(
        'legacy-group-1',
        'legacy-member-1',
      );
      expect(stored, isNotNull);
      expect(stored!.id, entryId);
      expect(stored.isDeleted, isFalse);
      expect(
        await db.memberGroupsDao.entriesForGroup('legacy-group-1'),
        hasLength(1),
      );
    },
  );

  test('promoteChildrenToRoot preserves the canonical PK-backed parent delete '
      'identity', () async {
    final createdAt = DateTime.utc(2026, 1, 1);

    await _insertPkBackedGroup(
      db,
      id: 'legacy-root',
      name: 'Root',
      pluralkitId: 'abcde',
      pluralkitUuid: 'pk-root',
      createdAt: createdAt,
      lastSeenFromPkAt: DateTime.utc(2026, 2, 3),
    );
    await _insertPkBackedGroup(
      db,
      id: 'legacy-child',
      name: 'Child',
      pluralkitId: 'vwxyz',
      pluralkitUuid: 'pk-child',
      createdAt: createdAt,
      lastSeenFromPkAt: DateTime.utc(2026, 2, 3),
    );
    await db.memberGroupsDao.updateGroup(
      'legacy-child',
      const MemberGroupsCompanion(parentGroupId: Value('legacy-root')),
    );

    await repo.promoteChildrenToRoot('legacy-root');

    expect(repo.deletes, hasLength(1));
    expect(repo.deletes.single, {
      'table': 'member_groups',
      'entityId': _canonicalPkGroupEntityId('pk-root'),
    });
    final child = await db.memberGroupsDao.getGroupById('legacy-child');
    expect(child?.parentGroupId, isNull);
  });

  test(
    'deleteGroupWithDescendants preserves canonical PK-backed delete ids for '
    'all deleted groups',
    () async {
      final createdAt = DateTime.utc(2026, 1, 1);

      await _insertPkBackedGroup(
        db,
        id: 'legacy-root',
        name: 'Root',
        pluralkitId: 'abcde',
        pluralkitUuid: 'pk-root',
        createdAt: createdAt,
        lastSeenFromPkAt: DateTime.utc(2026, 2, 3),
      );
      await _insertPkBackedGroup(
        db,
        id: 'legacy-child',
        name: 'Child',
        pluralkitId: 'vwxyz',
        pluralkitUuid: 'pk-child',
        createdAt: createdAt,
        lastSeenFromPkAt: DateTime.utc(2026, 2, 3),
      );
      await db.memberGroupsDao.updateGroup(
        'legacy-child',
        const MemberGroupsCompanion(parentGroupId: Value('legacy-root')),
      );

      await repo.deleteGroupWithDescendants('legacy-root');

      expect(repo.deletes, hasLength(2));
      expect(repo.deletes.map((record) => record['entityId']).toSet(), {
        _canonicalPkGroupEntityId('pk-root'),
        _canonicalPkGroupEntityId('pk-child'),
      });
      expect(repo.deletes.map((record) => record['table']).toSet(), {
        'member_groups',
      });
      expect(
        repo.deletes.any((record) => record['entityId'] == 'legacy-root'),
        isFalse,
      );
      expect(
        repo.deletes.any((record) => record['entityId'] == 'legacy-child'),
        isFalse,
      );
      expect(await db.memberGroupsDao.getAllActiveGroups(), isEmpty);
    },
  );
}
