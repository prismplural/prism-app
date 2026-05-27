import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_repair_run_gate.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_groups_importer.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeMemberRepo implements MemberRepository {
  final List<domain.Member> members;
  _FakeMemberRepo(this.members);

  @override
  Future<List<domain.Member>> getAllMembers() async => members;

  @override
  Future<List<domain.Member>> getAllMembersIncludingDeleted() async => members;

  @override
  Future<domain.Member?> getMemberById(String id) async => members
      .cast<domain.Member?>()
      .firstWhere((m) => m!.id == id, orElse: () => null);

  @override
  Future<List<domain.Member>> getMembersByIds(List<String> ids) async =>
      members.where((m) => ids.contains(m.id)).toList();

  @override
  Stream<List<domain.Member>> watchMembersByIds(List<String> ids) =>
      throw UnimplementedError();

  @override
  Future<void> createMember(domain.Member m) async => members.add(m);
  @override
  Future<void> updateMember(domain.Member m) async {
    final i = members.indexWhere((x) => x.id == m.id);
    if (i >= 0) members[i] = m;
  }

  @override
  Future<int> updateMemberFields(
    String id,
    Map<String, dynamic> changedFields,
  ) async => throw UnimplementedError();

  // Stub: not exercised by this test file.
  @override
  Future<int> applyPluralKitLink(String id, Map<String, dynamic> patch) async =>
      throw UnimplementedError();

  // Stub: not exercised by this test file.
  @override
  Future<int> recordPluralKitIdentity(
    String id,
    Map<String, dynamic> patch,
  ) async => throw UnimplementedError();

  // Stub: not exercised by this test file.
  @override
  Future<int> excludePluralKitSync(String id) async => throw UnimplementedError();

  // Stub: not exercised by this test file.
  @override
  Future<int> resumePluralKitSync(String id) async => throw UnimplementedError();

  @override
  Future<void> deleteMember(String id) async =>
      members.removeWhere((m) => m.id == id);

  @override
  Stream<List<domain.Member>> watchAllMembers() => throw UnimplementedError();
  @override
  Stream<List<domain.Member>> watchActiveMembers() =>
      throw UnimplementedError();
  @override
  Stream<domain.Member?> watchMemberById(String id) =>
      throw UnimplementedError();
  @override
  Future<int> getCount() async => members.length;

  @override
  Future<List<domain.Member>> getDeletedLinkedMembers() async => const [];
  @override
  Future<void> clearPluralKitLink(String id) async {}
  @override
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async {}
  @override
  Future<({domain.Member member, bool wasCreated})>
  ensureUnknownSentinelMember() => throw UnimplementedError();
}

domain.Member _member({required String id, String? pkUuid, String? pkId}) =>
    domain.Member(
      id: id,
      name: id,
      emoji: '❔',
      createdAt: DateTime.utc(2026, 1, 1),
      pluralkitUuid: pkUuid,
      pluralkitId: pkId,
    );

void main() {
  late AppDatabase db;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
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

  Future<void> insertPkGroupSyncAlias({
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

  Future<void> insertGroup({required String id, String? pkUuid}) async {
    await db
        .into(db.memberGroups)
        .insert(
          MemberGroupsCompanion.insert(
            id: id,
            name: id,
            createdAt: DateTime.utc(2026, 1, 1),
            pluralkitUuid: Value(pkUuid),
          ),
        );
  }

  Future<void> insertEntry({
    required String id,
    required String groupId,
    required String memberId,
    String? pkGroupUuid,
    String? pkMemberUuid,
    bool isDeleted = false,
    String pendingPkOp = 'none',
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
            pendingPkOp: Value(pendingPkOp),
          ),
        );
  }

  test('deterministic entry ID is stable across runs', () {
    final a = PkGroupsImporter.deriveEntryId('g-uuid', 'm-uuid');
    final b = PkGroupsImporter.deriveEntryId('g-uuid', 'm-uuid');
    expect(a, b);
    expect(a.length, 16);
    // Different inputs differ.
    expect(PkGroupsImporter.deriveEntryId('g-uuid2', 'm-uuid'), isNot(a));
  });

  test(
    'import marks automatic repair gate dirty after PK membership changes',
    () async {
      final repo = _FakeMemberRepo([
        _member(id: 'local-1', pkUuid: 'pk-mem-1'),
      ]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);

      await importer.importGroups([
        const PKGroup(
          id: 'abcde',
          uuid: 'pk-g-1',
          name: 'Core',
          memberIds: ['pk-mem-1'],
        ),
      ]);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(PkGroupRepairRunGate.dirtyKey), isTrue);
    },
  );

  group('previewPendingGroupMembershipRemovals', () {
    test('counts only valid pending push_remove tombstones', () async {
      await insertGroup(id: 'group-fallback', pkUuid: 'pk-group-fallback');
      await insertGroup(id: 'group-missing-link');
      await insertGroup(id: 'group-valid-add', pkUuid: 'pk-group-add');
      final repo = _FakeMemberRepo([
        _member(id: 'member-fallback', pkUuid: 'pk-member-fallback'),
        _member(id: 'member-active-remove', pkUuid: 'pk-member-active'),
        _member(id: 'member-add-deleted', pkUuid: 'pk-member-add-deleted'),
        _member(id: 'member-add-active', pkUuid: 'pk-member-add-active'),
      ]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);

      await insertEntry(
        id: 'stored-remove',
        groupId: 'missing-group',
        memberId: 'missing-member',
        pkGroupUuid: 'pk-group-stored',
        pkMemberUuid: 'pk-member-stored',
        isDeleted: true,
        pendingPkOp: 'push_remove',
      );
      await insertEntry(
        id: 'fallback-remove',
        groupId: 'group-fallback',
        memberId: 'member-fallback',
        isDeleted: true,
        pendingPkOp: 'push_remove',
      );
      await insertEntry(
        id: 'missing-link-remove',
        groupId: 'group-missing-link',
        memberId: 'member-missing-link',
        isDeleted: true,
        pendingPkOp: 'push_remove',
      );
      await insertEntry(
        id: 'active-remove',
        groupId: 'group-fallback',
        memberId: 'member-active-remove',
        isDeleted: false,
        pendingPkOp: 'push_remove',
      );
      await insertEntry(
        id: 'deleted-add',
        groupId: 'group-valid-add',
        memberId: 'member-add-deleted',
        isDeleted: true,
        pendingPkOp: 'push_add',
      );
      await insertEntry(
        id: 'active-add',
        groupId: 'group-valid-add',
        memberId: 'member-add-active',
        isDeleted: false,
        pendingPkOp: 'push_add',
      );

      final preview = await importer.previewPendingGroupMembershipRemovals();

      expect(preview.toRemove, 2);
      expect(
        preview.skipped,
        3,
        reason:
            'missing links and compensation cases are skipped; active push_add '
            'is not destructive and is ignored',
      );
    });

    test('does not mutate pending group membership rows', () async {
      await insertGroup(id: 'group-1', pkUuid: 'pk-group-1');
      final repo = _FakeMemberRepo([
        _member(id: 'member-1', pkUuid: 'pk-member-1'),
        _member(id: 'member-2', pkUuid: 'pk-member-2'),
      ]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);

      await insertEntry(
        id: 'remove',
        groupId: 'group-1',
        memberId: 'member-1',
        isDeleted: true,
        pendingPkOp: 'push_remove',
      );
      await insertEntry(
        id: 'compensate',
        groupId: 'group-1',
        memberId: 'member-2',
        isDeleted: false,
        pendingPkOp: 'push_remove',
      );
      await insertEntry(
        id: 'strand',
        groupId: 'missing-group',
        memberId: 'missing-member',
        isDeleted: true,
        pendingPkOp: 'push_remove',
      );

      final before = await db.memberGroupsDao.entriesWithPendingPkOp();

      final preview = await importer.previewPendingGroupMembershipRemovals();

      expect(preview.toRemove, 1);
      expect(preview.skipped, 2);
      final after = await db.memberGroupsDao.entriesWithPendingPkOp();
      expect(after, before);
    });
  });

  test('inserts new group + memberships, preserves local emoji on insert '
      '(no PK emoji written)', () async {
    final m = _member(id: 'local-1', pkUuid: 'pk-mem-1');
    final repo = _FakeMemberRepo([m]);
    final importer = PkGroupsImporter(db: db, memberRepository: repo);

    final result = await importer.importGroups([
      const PKGroup(
        id: 'abcde',
        uuid: 'pk-g-1',
        name: 'Core',
        description: 'A group',
        color: 'ff00aa',
        memberIds: ['pk-mem-1'],
      ),
    ], overwriteMetadata: true);
    expect(result.groupsInserted, 1);
    expect(result.entriesInserted, 1);

    final groups = await db.memberGroupsDao.getAllActiveGroups();
    expect(groups, hasLength(1));
    expect(groups.single.pluralkitUuid, 'pk-g-1');
    expect(groups.single.pluralkitId, 'abcde');
    expect(groups.single.emoji, isNull, reason: 'Never write emoji on PK pull');
    expect(groups.single.colorHex, '#ff00aa');
    expect(groups.single.lastSeenFromPkAt, isNotNull);

    final entries = await db.memberGroupsDao.entriesForGroup(groups.single.id);
    expect(entries, hasLength(1));
    expect(entries.single.memberId, 'local-1');
    expect(entries.single.pkGroupUuid, 'pk-g-1');
    expect(entries.single.pkMemberUuid, 'pk-mem-1');
  });

  test(
    're-imports a PK group when a deleted tombstone has the same UUID',
    () async {
      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: 'deleted-local-group',
              name: 'Deleted',
              createdAt: DateTime.utc(2024, 1, 1),
              isDeleted: const Value(true),
              pluralkitUuid: const Value('pk-g-1'),
            ),
          );

      final repo = _FakeMemberRepo([
        _member(id: 'local-1', pkUuid: 'pk-mem-1'),
      ]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);

      final result = await importer.importGroups([
        const PKGroup(
          id: 'abcde',
          uuid: 'pk-g-1',
          name: 'Core',
          memberIds: ['pk-mem-1'],
        ),
      ], overwriteMetadata: true);

      expect(result.groupsInserted, 1);
      final active = await db.memberGroupsDao.findByPluralkitUuid('pk-g-1');
      expect(active, isNotNull);
      expect(active!.id, PkGroupsImporter.deriveGroupId('pk-g-1'));
      expect(active.isDeleted, isFalse);
    },
  );

  test(
    'emits sync create payloads for imported groups and memberships',
    () async {
      await setPkGroupSyncV2Enabled(true);
      final creates = <Map<String, Object?>>[];
      final updates = <Map<String, Object?>>[];
      final deletes = <Map<String, String>>[];
      final repo = _FakeMemberRepo([
        _member(id: 'local-1', pkUuid: 'pk-mem-1'),
      ]);
      final importer = PkGroupsImporter(
        db: db,
        memberRepository: repo,
        recordCreateOverride: (table, entityId, fields) async {
          creates.add({
            'table': table,
            'entityId': entityId,
            'fields': Map<String, dynamic>.from(fields),
          });
        },
        recordUpdateOverride: (table, entityId, fields) async {
          updates.add({
            'table': table,
            'entityId': entityId,
            'fields': Map<String, dynamic>.from(fields),
          });
        },
        recordDeleteOverride: (table, entityId) async {
          deletes.add({'table': table, 'entityId': entityId});
        },
      );

      await importer.importGroups([
        const PKGroup(
          id: 'abcde',
          uuid: 'pk-g-1',
          name: 'Core',
          description: 'A group',
          color: 'ff00aa',
          memberIds: ['pk-mem-1'],
        ),
      ], overwriteMetadata: true);

      expect(updates, isEmpty);
      expect(deletes, isEmpty);

      final groupCreate = creates.singleWhere(
        (call) => call['table'] == 'member_groups',
      );
      final groupFields = groupCreate['fields']! as Map<String, dynamic>;
      expect(
        groupCreate['entityId'],
        PkGroupsImporter.deriveGroupSyncEntityId('pk-g-1'),
      );
      expect(groupFields.keys.toSet(), {
        'name',
        'description',
        'color_hex',
        'emoji',
        'display_order',
        'parent_group_id',
        'group_type',
        'filter_rules',
        'created_at',
        'pluralkit_id',
        'pluralkit_uuid',
        'last_seen_from_pk_at',
        'sort_state',
        'is_deleted',
      });
      expect(groupFields['name'], 'Core');
      expect(groupFields['sort_state'], '{"mode":0,"order":[]}');
      expect(groupFields['description'], 'A group');
      expect(groupFields['color_hex'], '#ff00aa');
      expect(groupFields['pluralkit_id'], 'abcde');
      expect(groupFields['pluralkit_uuid'], 'pk-g-1');
      expect(groupFields['is_deleted'], isFalse);

      final entryCreate = creates.singleWhere(
        (call) => call['table'] == 'member_group_entries',
      );
      final entryFields = entryCreate['fields']! as Map<String, dynamic>;
      expect(
        entryCreate['entityId'],
        PkGroupsImporter.deriveEntryId('pk-g-1', 'pk-mem-1'),
      );
      expect(entryFields, {
        'group_id': PkGroupsImporter.deriveGroupId('pk-g-1'),
        'member_id': 'local-1',
        'pk_group_uuid': 'pk-g-1',
        'pk_member_uuid': 'pk-mem-1',
        'is_deleted': false,
      });
    },
  );

  test(
    'emits legacy alias deletes alongside canonical group creates',
    () async {
      final creates = <Map<String, Object?>>[];
      final updates = <Map<String, Object?>>[];
      final deletes = <Map<String, String>>[];
      const pkGroupUuid = 'pk-g-1';
      final canonicalEntityId = PkGroupsImporter.deriveGroupSyncEntityId(
        pkGroupUuid,
      );
      await insertPkGroupSyncAlias(
        legacyEntityId: 'legacy-group-1',
        pkGroupUuid: pkGroupUuid,
        canonicalEntityId: canonicalEntityId,
      );
      await insertPkGroupSyncAlias(
        legacyEntityId: canonicalEntityId,
        pkGroupUuid: pkGroupUuid,
        canonicalEntityId: canonicalEntityId,
      );
      final importer = PkGroupsImporter(
        db: db,
        memberRepository: _FakeMemberRepo(const []),
        recordCreateOverride: (table, entityId, fields) async {
          creates.add({
            'table': table,
            'entityId': entityId,
            'fields': Map<String, dynamic>.from(fields),
          });
        },
        recordUpdateOverride: (table, entityId, fields) async {
          updates.add({
            'table': table,
            'entityId': entityId,
            'fields': Map<String, dynamic>.from(fields),
          });
        },
        recordDeleteOverride: (table, entityId) async {
          deletes.add({'table': table, 'entityId': entityId});
        },
      );

      await importer.importGroups([
        const PKGroup(
          id: 'abcde',
          uuid: pkGroupUuid,
          name: 'Core',
          memberIds: [],
        ),
      ], overwriteMetadata: true);

      expect(updates, isEmpty);
      expect(
        creates.singleWhere(
          (call) => call['table'] == 'member_groups',
        )['entityId'],
        canonicalEntityId,
      );
      expect(deletes, [
        {'table': 'member_groups', 'entityId': 'legacy-group-1'},
      ]);
    },
  );

  test(
    'holds back PK-backed sync emits while enablement bit is false',
    () async {
      await setPkGroupSyncV2Enabled(false);
      final creates = <Map<String, Object?>>[];
      final updates = <Map<String, Object?>>[];
      final deletes = <Map<String, String>>[];
      final repo = _FakeMemberRepo([
        _member(id: 'local-1', pkUuid: 'pk-mem-1'),
      ]);
      final importer = PkGroupsImporter(
        db: db,
        memberRepository: repo,
        recordCreateOverride: (table, entityId, fields) async {
          creates.add({
            'table': table,
            'entityId': entityId,
            'fields': Map<String, dynamic>.from(fields),
          });
        },
        recordUpdateOverride: (table, entityId, fields) async {
          updates.add({
            'table': table,
            'entityId': entityId,
            'fields': Map<String, dynamic>.from(fields),
          });
        },
        recordDeleteOverride: (table, entityId) async {
          deletes.add({'table': table, 'entityId': entityId});
        },
      );

      final result = await importer.importGroups([
        const PKGroup(
          id: 'abcde',
          uuid: 'pk-g-1',
          name: 'Core',
          description: 'A group',
          color: 'ff00aa',
          memberIds: ['pk-mem-1'],
        ),
      ], overwriteMetadata: true);

      expect(result.groupsInserted, 1);
      expect(result.entriesInserted, 1);
      expect(creates, isEmpty);
      expect(updates, isEmpty);
      expect(deletes, isEmpty);
      final groups = await db.memberGroupsDao.getAllActiveGroups();
      expect(groups, hasLength(1));
      expect(groups.single.pluralkitUuid, 'pk-g-1');
      expect(
        await db.memberGroupsDao.entriesForGroup(groups.single.id),
        hasLength(1),
      );
    },
  );

  test('authoritative-set diff: unresolved PK member is deferred, NOT '
      'used to drop other entries', () async {
    // Local has member A linked. PK group authoritative set is {A, B} where
    // B is not yet linked locally. We expect A inserted, B deferred. No drops.
    final repo = _FakeMemberRepo([_member(id: 'local-A', pkUuid: 'pk-A')]);
    final importer = PkGroupsImporter(db: db, memberRepository: repo);

    final result = await importer.importGroups([
      const PKGroup(
        id: 'abcde',
        uuid: 'pk-g-1',
        name: 'Core',
        memberIds: ['pk-A', 'pk-B'],
      ),
    ], overwriteMetadata: true);
    expect(result.entriesInserted, 1);
    expect(result.entriesDeferred, 1);
    expect(result.entriesRemoved, 0);
  });

  test('memberIds null → no removals applied (unknown)', () async {
    // Seed: group has local entry already.
    final repo = _FakeMemberRepo([_member(id: 'local-A', pkUuid: 'pk-A')]);
    final importer = PkGroupsImporter(db: db, memberRepository: repo);

    await importer.importGroups([
      const PKGroup(
        id: 'abcde',
        uuid: 'pk-g-1',
        name: 'Core',
        memberIds: ['pk-A'],
      ),
    ], overwriteMetadata: true);
    final initialGroups = await db.memberGroupsDao.getAllActiveGroups();
    final localGroupId = initialGroups.single.id;

    // Second pull: memberIds = null (unknown).
    final result = await importer.importGroups([
      const PKGroup(id: 'abcde', uuid: 'pk-g-1', name: 'Core', memberIds: null),
    ], overwriteMetadata: false);
    expect(result.groupsWithUnknownMembership, 1);
    expect(result.entriesRemoved, 0);

    final entries = await db.memberGroupsDao.entriesForGroup(localGroupId);
    expect(entries, hasLength(1), reason: 'Entry preserved on unknown pull');
  });

  test(
    'removed on PK: entry soft-deleted when PK no longer lists member',
    () async {
      final repo = _FakeMemberRepo([
        _member(id: 'local-A', pkUuid: 'pk-A'),
        _member(id: 'local-B', pkUuid: 'pk-B'),
      ]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);

      await importer.importGroups([
        const PKGroup(
          id: 'abcde',
          uuid: 'pk-g-1',
          name: 'Core',
          memberIds: ['pk-A', 'pk-B'],
        ),
      ], overwriteMetadata: true);
      final g = (await db.memberGroupsDao.getAllActiveGroups()).single;
      var entries = await db.memberGroupsDao.entriesForGroup(g.id);
      expect(entries, hasLength(2));

      // Re-import with only A; B should be removed.
      final r = await importer.importGroups([
        const PKGroup(
          id: 'abcde',
          uuid: 'pk-g-1',
          name: 'Core',
          memberIds: ['pk-A'],
        ),
      ], overwriteMetadata: false);
      expect(r.entriesRemoved, 1);
      entries = await db.memberGroupsDao.entriesForGroup(g.id);
      expect(entries.map((e) => e.memberId).toList(), ['local-A']);
    },
  );

  test(
    'identity via UUID only: same short ID, different UUID → two rows',
    () async {
      final repo = _FakeMemberRepo([]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);

      await importer.importGroups([
        const PKGroup(
          id: 'abcde',
          uuid: 'pk-g-1',
          name: 'OldCore',
          memberIds: [],
        ),
      ], overwriteMetadata: true);
      await importer.importGroups([
        const PKGroup(
          // Same 5-char, but different UUID (e.g. recycled).
          id: 'abcde',
          uuid: 'pk-g-2-different',
          name: 'NewCore',
          memberIds: [],
        ),
      ], overwriteMetadata: true);
      final all = await db.memberGroupsDao.getAllActiveGroups();
      expect(
        all,
        hasLength(2),
        reason: 'UUID-only identity must not merge groups with recycled IDs',
      );
    },
  );

  test('preserves local emoji on subsequent pull', () async {
    final repo = _FakeMemberRepo([]);
    final importer = PkGroupsImporter(db: db, memberRepository: repo);

    await importer.importGroups([
      const PKGroup(id: 'abcde', uuid: 'pk-g-1', name: 'Core', memberIds: []),
    ], overwriteMetadata: true);
    var g = (await db.memberGroupsDao.getAllActiveGroups()).single;
    // User sets emoji locally.
    await (db.update(db.memberGroups)..where((t) => t.id.equals(g.id))).write(
      const MemberGroupsCompanion(emoji: Value('🎨')),
    );

    await importer.importGroups([
      const PKGroup(id: 'abcde', uuid: 'pk-g-1', name: 'Core', memberIds: []),
    ], overwriteMetadata: true);
    g = (await db.memberGroupsDao.getAllActiveGroups()).single;
    expect(
      g.emoji,
      '🎨',
      reason: 'PK pull must never clobber the locally-set emoji (R8)',
    );
  });

  test(
    'metadata preserved on background sync (overwriteMetadata=false)',
    () async {
      final repo = _FakeMemberRepo([]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);

      await importer.importGroups([
        const PKGroup(
          id: 'abcde',
          uuid: 'pk-g-1',
          name: 'OriginalName',
          description: 'orig',
          color: 'aabbcc',
          memberIds: [],
        ),
      ], overwriteMetadata: true);
      var g = (await db.memberGroupsDao.getAllActiveGroups()).single;
      // User renames locally.
      await (db.update(db.memberGroups)..where((t) => t.id.equals(g.id))).write(
        const MemberGroupsCompanion(
          name: Value('MyLocalName'),
          description: Value('my desc'),
          colorHex: Value('#000000'),
        ),
      );

      // Background sync — PK has different values.
      await importer.importGroups([
        const PKGroup(
          id: 'abcde',
          uuid: 'pk-g-1',
          name: 'PKName',
          description: 'pk desc',
          color: 'ffffff',
          memberIds: [],
        ),
      ], overwriteMetadata: false);
      g = (await db.memberGroupsDao.getAllActiveGroups()).single;
      expect(g.name, 'MyLocalName');
      expect(g.description, 'my desc');
      expect(g.colorHex, '#000000');
    },
  );

  test('background sync only updates PK linkage fields and deletes removed '
      'memberships', () async {
    final creates = <Map<String, Object?>>[];
    final updates = <Map<String, Object?>>[];
    final deletes = <Map<String, String>>[];
    final repo = _FakeMemberRepo([
      _member(id: 'local-A', pkUuid: 'pk-A'),
      _member(id: 'local-B', pkUuid: 'pk-B'),
    ]);
    final importer = PkGroupsImporter(
      db: db,
      memberRepository: repo,
      recordCreateOverride: (table, entityId, fields) async {
        creates.add({
          'table': table,
          'entityId': entityId,
          'fields': Map<String, dynamic>.from(fields),
        });
      },
      recordUpdateOverride: (table, entityId, fields) async {
        updates.add({
          'table': table,
          'entityId': entityId,
          'fields': Map<String, dynamic>.from(fields),
        });
      },
      recordDeleteOverride: (table, entityId) async {
        deletes.add({'table': table, 'entityId': entityId});
      },
    );

    await importer.importGroups([
      const PKGroup(
        id: 'abcde',
        uuid: 'pk-g-1',
        name: 'Original',
        memberIds: ['pk-A', 'pk-B'],
      ),
    ], overwriteMetadata: true);

    creates.clear();
    updates.clear();
    deletes.clear();

    await importer.importGroups([
      const PKGroup(
        id: 'abcde',
        uuid: 'pk-g-1',
        name: 'ShouldNotOverwrite',
        description: 'ignored',
        color: 'ffffff',
        memberIds: ['pk-A'],
      ),
    ], overwriteMetadata: false);

    expect(creates, isEmpty);

    final groupUpdate = updates.singleWhere(
      (call) => call['table'] == 'member_groups',
    );
    final groupFields = groupUpdate['fields']! as Map<String, dynamic>;
    expect(
      groupUpdate['entityId'],
      PkGroupsImporter.deriveGroupSyncEntityId('pk-g-1'),
    );
    // overwriteMetadata: false → only the three PK-linkage columns.
    // Narrow patch, no `is_deleted` — see `lib/data/sync/field_diff.dart`.
    expect(groupFields.keys.toSet(), {
      'last_seen_from_pk_at',
      'pluralkit_id',
      'pluralkit_uuid',
    });
    expect(groupFields['pluralkit_id'], 'abcde');
    expect(groupFields['pluralkit_uuid'], 'pk-g-1');

    expect(
      deletes.map((call) => '${call['table']}:${call['entityId']}').toList(),
      contains(
        'member_group_entries:'
        '${PkGroupsImporter.deriveEntryId('pk-g-1', 'pk-B')}',
      ),
    );
  });

  test(
    'emits legacy alias deletes alongside canonical group updates',
    () async {
      final creates = <Map<String, Object?>>[];
      final updates = <Map<String, Object?>>[];
      final deletes = <Map<String, String>>[];
      const pkGroupUuid = 'pk-g-1';
      final canonicalEntityId = PkGroupsImporter.deriveGroupSyncEntityId(
        pkGroupUuid,
      );
      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: PkGroupsImporter.deriveGroupId(pkGroupUuid),
              name: 'Existing Core',
              createdAt: DateTime.utc(2026, 1, 1),
              pluralkitId: const Value('abcde'),
              pluralkitUuid: const Value(pkGroupUuid),
              lastSeenFromPkAt: Value(DateTime.utc(2026, 1, 2)),
            ),
          );
      await insertPkGroupSyncAlias(
        legacyEntityId: 'legacy-group-1',
        pkGroupUuid: pkGroupUuid,
        canonicalEntityId: canonicalEntityId,
      );
      await insertPkGroupSyncAlias(
        legacyEntityId: canonicalEntityId,
        pkGroupUuid: pkGroupUuid,
        canonicalEntityId: canonicalEntityId,
      );
      final importer = PkGroupsImporter(
        db: db,
        memberRepository: _FakeMemberRepo(const []),
        recordCreateOverride: (table, entityId, fields) async {
          creates.add({
            'table': table,
            'entityId': entityId,
            'fields': Map<String, dynamic>.from(fields),
          });
        },
        recordUpdateOverride: (table, entityId, fields) async {
          updates.add({
            'table': table,
            'entityId': entityId,
            'fields': Map<String, dynamic>.from(fields),
          });
        },
        recordDeleteOverride: (table, entityId) async {
          deletes.add({'table': table, 'entityId': entityId});
        },
      );

      await importer.importGroups([
        const PKGroup(
          id: 'abcde',
          uuid: pkGroupUuid,
          name: 'Updated Core',
          description: 'Updated description',
          color: 'ff00aa',
          memberIds: [],
        ),
      ], overwriteMetadata: true);

      expect(creates, isEmpty);
      expect(
        updates.singleWhere(
          (call) => call['table'] == 'member_groups',
        )['entityId'],
        canonicalEntityId,
      );
      expect(deletes, [
        {'table': 'member_groups', 'entityId': 'legacy-group-1'},
      ]);
    },
  );

  test(
    'metadata overwritten on explicit import (overwriteMetadata=true)',
    () async {
      final repo = _FakeMemberRepo([]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);

      await importer.importGroups([
        const PKGroup(
          id: 'abcde',
          uuid: 'pk-g-1',
          name: 'First',
          memberIds: [],
        ),
      ], overwriteMetadata: true);
      await importer.importGroups([
        const PKGroup(
          id: 'abcde',
          uuid: 'pk-g-1',
          name: 'Second',
          description: 'desc2',
          color: '112233',
          memberIds: [],
        ),
      ], overwriteMetadata: true);
      final g = (await db.memberGroupsDao.getAllActiveGroups()).single;
      expect(g.name, 'Second');
      expect(g.description, 'desc2');
      expect(g.colorHex, '#112233');
    },
  );

  test('deterministic entry ID across two simulated devices', () async {
    final previousMultipleDbWarningSetting =
        driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases =
          previousMultipleDbWarningSetting;
    });

    // Two DBs import the same PK group/member; entry IDs must match.
    final dbA = AppDatabase(NativeDatabase.memory());
    final dbB = AppDatabase(NativeDatabase.memory());
    addTearDown(dbA.close);
    addTearDown(dbB.close);

    final repoA = _FakeMemberRepo([_member(id: 'local-A-abc', pkUuid: 'pk-A')]);
    final repoB = _FakeMemberRepo([
      // Different local UUID for the same PK member (devices can choose
      // their own local UUIDs independently).
      _member(id: 'local-A-xyz', pkUuid: 'pk-A'),
    ]);

    final iA = PkGroupsImporter(db: dbA, memberRepository: repoA);
    final iB = PkGroupsImporter(db: dbB, memberRepository: repoB);

    const pkGroup = PKGroup(
      id: 'abcde',
      uuid: 'pk-g-1',
      name: 'Core',
      memberIds: ['pk-A'],
    );

    await iA.importGroups([pkGroup], overwriteMetadata: true);
    await iB.importGroups([pkGroup], overwriteMetadata: true);

    final gA = (await dbA.memberGroupsDao.getAllActiveGroups()).single;
    final gB = (await dbB.memberGroupsDao.getAllActiveGroups()).single;

    final eA = (await dbA.memberGroupsDao.entriesForGroup(gA.id)).single;
    final eB = (await dbB.memberGroupsDao.entriesForGroup(gB.id)).single;

    expect(
      gA.id,
      gB.id,
      reason: 'Group IDs must be deterministic across devices',
    );
    expect(gA.id, PkGroupsImporter.deriveGroupId('pk-g-1'));
    expect(
      eA.id,
      eB.id,
      reason: 'Entry IDs must be deterministic across devices (R6)',
    );
  });

  test('reattribute inserts previously-deferred members without removing '
      'anything', () async {
    // First pull: member B not yet linked locally → entry deferred.
    final members = [_member(id: 'local-A', pkUuid: 'pk-A')];
    final repo = _FakeMemberRepo(members);
    final creates = <Map<String, Object?>>[];
    final updates = <Map<String, Object?>>[];
    final importer = PkGroupsImporter(
      db: db,
      memberRepository: repo,
      recordCreateOverride: (table, entityId, fields) async {
        creates.add({
          'table': table,
          'entityId': entityId,
          'fields': Map<String, dynamic>.from(fields),
        });
      },
      recordUpdateOverride: (table, entityId, fields) async {
        updates.add({
          'table': table,
          'entityId': entityId,
          'fields': Map<String, dynamic>.from(fields),
        });
      },
    );

    const pkGroup = PKGroup(
      id: 'abcde',
      uuid: 'pk-g-1',
      name: 'Core',
      memberIds: ['pk-A', 'pk-B'],
    );

    final r1 = await importer.importGroups([pkGroup], overwriteMetadata: true);
    expect(r1.entriesDeferred, 1);
    expect(r1.entriesInserted, 1);

    // Link member B locally.
    members.add(_member(id: 'local-B', pkUuid: 'pk-B'));

    // Reattribute — insert-only. We need a client that returns pkGroup.
    final r2 = await importer.reattribute(_StubClient([pkGroup]));
    expect(r2.entriesInserted, 1);

    final g = (await db.memberGroupsDao.getAllActiveGroups()).single;
    final entries = await db.memberGroupsDao.entriesForGroup(g.id);
    expect(entries.map((e) => e.memberId).toSet(), {'local-A', 'local-B'});
    final reattributedSyncCreate = creates.singleWhere(
      (call) =>
          call['table'] == 'member_group_entries' &&
          call['entityId'] == PkGroupsImporter.deriveEntryId('pk-g-1', 'pk-B'),
    );
    expect(updates, isEmpty);
    expect(reattributedSyncCreate['fields'], {
      'group_id': g.id,
      'member_id': 'local-B',
      'pk_group_uuid': 'pk-g-1',
      'pk_member_uuid': 'pk-B',
      'is_deleted': false,
    });
  });

  test(
    'ignores soft-deleted loser rows when looking up PK-linked groups',
    () async {
      final repo = _FakeMemberRepo([]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);

      await db.customStatement('DROP INDEX idx_member_groups_pluralkit_uuid');
      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: 'deleted-loser',
              name: 'Old deleted row',
              createdAt: DateTime.utc(2026, 1, 1),
              pluralkitUuid: const Value('pk-g-1'),
              isDeleted: const Value(true),
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: 'active-winner',
              name: 'Active winner',
              createdAt: DateTime.utc(2026, 1, 2),
              pluralkitUuid: const Value('pk-g-1'),
            ),
          );

      final result = await importer.importGroups([
        const PKGroup(
          id: 'abcde',
          uuid: 'pk-g-1',
          name: 'Fresh PK name',
          memberIds: [],
        ),
      ], overwriteMetadata: true);

      expect(result.groupsUpdated, 1);

      final active = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('active-winner'))).getSingle();
      final deleted = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('deleted-loser'))).getSingle();
      expect(active.name, 'Fresh PK name');
      expect(deleted.name, 'Old deleted row');
    },
  );

  // Step 4 tests live in a separate function so they can share the same
  // setUp/tearDown db lifecycle without duplicating fixture wiring.
  _stepFourTests(getDb: () => db);
}

class _StubClient implements PluralKitClient {
  final List<PKGroup> groups;
  _StubClient(this.groups);
  @override
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async => groups;
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ─── Step 4: pending_pk_op-aware reconcile tests ────────────────────────────
// All tests below cover the new behavior introduced by step 4 of
// docs/plans/pk-group-membership-push.md: the reconcile pass respects
// pending_pk_op and the direction param gates the whole pull pass.

void _stepFourTests({required AppDatabase Function() getDb}) {
  group('step 4: pending_pk_op-aware reconcile', () {
    test(
      'preserves push_add row whose member is NOT in PK authoritative set',
      () async {
        final db = getDb();
        final localMember = _member(id: 'local-1', pkUuid: 'pk-mem-1');
        final repo = _FakeMemberRepo([localMember]);
        final importer = PkGroupsImporter(db: db, memberRepository: repo);

        // First: import the group with the member to seed local state.
        await importer.importGroups([
          const PKGroup(
            id: 'g1',
            uuid: 'pk-g-1',
            name: 'Group',
            memberIds: ['pk-mem-1'],
          ),
        ]);

        // Mark the local entry as push_add (simulating: user just added
        // again locally and we expect the push orchestrator to push it).
        // We directly write the column since the importer's insert path
        // sets pending=none for pull-side inserts.
        await db.customStatement(
          'UPDATE member_group_entries '
          "SET pending_pk_op = 'push_add' "
          'WHERE group_id = (SELECT id FROM member_groups '
          "WHERE pluralkit_uuid = 'pk-g-1') AND member_id = 'local-1'",
        );

        // Second import: PK now reports the group has NO members. Old
        // behavior would soft-delete the local row (the original data-loss
        // bug). New behavior: skip the soft-delete because pending_pk_op
        // = push_add says local owns this row.
        final result = await importer.importGroups([
          const PKGroup(id: 'g1', uuid: 'pk-g-1', name: 'Group', memberIds: []),
        ]);

        expect(
          result.entriesRemoved,
          0,
          reason: 'push_add row must NOT be soft-deleted by reconcile',
        );

        final row = await (db.select(
          db.memberGroupEntries,
        )..where((e) => e.memberId.equals('local-1'))).getSingle();
        expect(row.isDeleted, isFalse);
        expect(row.pendingPkOp, 'push_add');
      },
    );

    test('does NOT re-insert PK member that has a soft-deleted push_remove '
        'tombstone locally', () async {
      final db = getDb();
      final localMember = _member(id: 'local-1', pkUuid: 'pk-mem-1');
      final repo = _FakeMemberRepo([localMember]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);

      // First: import with the member present (seed the row).
      await importer.importGroups([
        const PKGroup(
          id: 'g1',
          uuid: 'pk-g-1',
          name: 'Group',
          memberIds: ['pk-mem-1'],
        ),
      ]);

      // Locally remove + queue push_remove (the tombstone state).
      await db.customStatement(
        'UPDATE member_group_entries '
        "SET is_deleted = 1, pending_pk_op = 'push_remove' "
        "WHERE member_id = 'local-1'",
      );

      // Re-import: PK still has the member. Old behavior (insert path
      // checked only active rows) would re-insert. New behavior: skip
      // because pending_pk_op = push_remove says local wants them gone.
      await importer.importGroups([
        const PKGroup(
          id: 'g1',
          uuid: 'pk-g-1',
          name: 'Group',
          memberIds: ['pk-mem-1'],
        ),
      ]);

      final row = await (db.select(
        db.memberGroupEntries,
      )..where((e) => e.memberId.equals('local-1'))).getSingle();
      expect(
        row.isDeleted,
        isTrue,
        reason: 'tombstone must remain; orchestrator handles the push',
      );
      expect(row.pendingPkOp, 'push_remove');
    });

    test('still soft-deletes pending=none entries when PK drops the member '
        '(existing destructive behavior preserved for synced rows)', () async {
      final db = getDb();
      final localMember = _member(id: 'local-1', pkUuid: 'pk-mem-1');
      final repo = _FakeMemberRepo([localMember]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);

      await importer.importGroups([
        const PKGroup(
          id: 'g1',
          uuid: 'pk-g-1',
          name: 'Group',
          memberIds: ['pk-mem-1'],
        ),
      ]);

      // PK drops the member. Local row has pending=none (was synced from PK
      // originally). Reconcile must soft-delete it — that's the legitimate
      // PK-as-source-of-truth case the user signed up for.
      final result = await importer.importGroups([
        const PKGroup(id: 'g1', uuid: 'pk-g-1', name: 'Group', memberIds: []),
      ]);

      expect(result.entriesRemoved, 1);
      final row = await (db.select(
        db.memberGroupEntries,
      )..where((e) => e.memberId.equals('local-1'))).getSingle();
      expect(row.isDeleted, isTrue);
    });

    test(
      'direction without pull bails: no metadata writes, no inserts',
      () async {
        final db = getDb();
        final repo = _FakeMemberRepo([
          _member(id: 'local-1', pkUuid: 'pk-mem-1'),
        ]);
        final importer = PkGroupsImporter(db: db, memberRepository: repo);

        final result = await importer.importGroups([
          const PKGroup(
            id: 'g1',
            uuid: 'pk-g-1',
            name: 'Group',
            memberIds: ['pk-mem-1'],
          ),
        ], direction: PkSyncDirection.pushOnly);

        expect(result.groupsObserved, 0);
        expect(result.groupsInserted, 0);
        expect(result.entriesInserted, 0);

        // Confirm DB is empty — no group, no entry.
        final groups = await (db.select(db.memberGroups)).get();
        expect(groups, isEmpty);
      },
    );

    // Regression: per-field LWW stamped a fresh HLC on `is_deleted: false`
    // in the membership-revive update emit, which could resurrect a row a
    // peer had concurrently deleted. Same shape as commit 94f5d950 for
    // member_groups, which missed member_group_entries. Uses the
    // installCaptureSinkForTesting pattern (not the constructor-level
    // recordUpdateOverride) so the emit goes through the real
    // SyncRecordMixin pipeline — the override pattern would replace it
    // wholesale and miss any regression in the dispatch layer itself.
    test(
      'PK membership revive update does NOT carry is_deleted '
      '(regression: per-field LWW resurrection of soft-deleted entries)',
      () async {
        final db = getDb();
        // Seed: PK-backed group + a soft-deleted entry for member-1. The
        // tombstone's id MUST match the deterministic id the importer
        // derives — that's how `existedBefore == true` triggers the revive
        // (update) emit path.
        const pkGroupUuid = 'pk-g-revive';
        const pkMemberUuid = 'pk-mem-revive';
        final groupId = PkGroupsImporter.deriveGroupId(pkGroupUuid);
        final entryId = PkGroupsImporter.deriveEntryId(
          pkGroupUuid,
          pkMemberUuid,
        );

        await db
            .into(db.memberGroups)
            .insert(
              MemberGroupsCompanion.insert(
                id: groupId,
                name: 'Revive',
                createdAt: DateTime.utc(2026, 1, 1),
                pluralkitUuid: const Value(pkGroupUuid),
              ),
            );
        // Seed as a soft-deleted push_add tombstone — that's the scenario
        // where `entriesForGroupForReconcile` returns the row AND the
        // reconcile path falls through to the revive (`existedBefore=true`)
        // emit branch. (push_remove tombstones are filtered out by the
        // pendingRemovalMemberIds skip; active rows are skipped by the
        // existingActiveMemberIds check.)
        await db
            .into(db.memberGroupEntries)
            .insert(
              MemberGroupEntriesCompanion.insert(
                id: entryId,
                groupId: groupId,
                memberId: 'local-revive',
                pkGroupUuid: const Value(pkGroupUuid),
                pkMemberUuid: const Value(pkMemberUuid),
                isDeleted: const Value(true),
                pendingPkOp: const Value('push_add'),
              ),
            );

        final repo = _FakeMemberRepo([
          _member(id: 'local-revive', pkUuid: pkMemberUuid),
        ]);
        final importer = PkGroupsImporter(db: db, memberRepository: repo);

        final captured = <CapturedSyncOp>[];
        SyncRecordMixin.installCaptureSinkForTesting(captured.add);
        addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

        await importer.importGroups([
          const PKGroup(
            id: 'gabcd',
            uuid: pkGroupUuid,
            name: 'Revive',
            memberIds: [pkMemberUuid],
          ),
        ]);

        // Filter to the entry's sync ops (the group emits its own).
        final entryOps = captured
            .where(
              (op) =>
                  op.table == 'member_group_entries' &&
                  op.entityId == entryId,
            )
            .toList();
        expect(
          entryOps,
          hasLength(1),
          reason: 'Exactly one membership emit per reconciled entry.',
        );

        final op = entryOps.single;
        // The fix is satisfied by EITHER (a) emitting a create on the
        // revive branch OR (b) emitting an update whose patch does not
        // carry is_deleted. Accept both shapes; reject only the buggy
        // "update with is_deleted: false" emit.
        if (op.opType == SyncRecordOpType.update) {
          expect(
            op.fields.containsKey('is_deleted'),
            isFalse,
            reason:
                'Update patch must not carry is_deleted on the revive '
                'path — per-field LWW would stamp a fresh HLC and '
                'resurrect a row a peer concurrently deleted (same bug '
                'fixed for member_groups in commit 94f5d950).',
          );
        } else {
          expect(op.opType, SyncRecordOpType.create);
        }
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────────
  // PR 2 — sync_ignored guard at allMembers fetch (Part 1.5).
  //
  // Both importGroups and reattribute filter excluded locals at the
  // allMembers fetch so downstream uses (the pkUuidToLocalMemberId map AND
  // the remove path in _reconcileMembership) only see non-excluded.
  // ─────────────────────────────────────────────────────────────────────────

  group('PR 2: importGroups skips excluded locals', () {
    test('excluded local does not appear in the pkUuidToLocalMemberId map '
        '(no insert into the group membership)', () async {
      final db = getDb();
      final excluded = domain.Member(
        id: 'local-excluded',
        name: 'Excluded',
        emoji: '?',
        createdAt: DateTime.utc(2026),
        pluralkitUuid: 'pk-mem-excluded',
        pluralkitId: 'eee01',
        pluralkitSyncIgnored: true,
      );
      final active = _member(id: 'local-active', pkUuid: 'pk-mem-active');
      final repo = _FakeMemberRepo([excluded, active]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);

      await importer.importGroups([
        const PKGroup(
          id: 'gabcd',
          uuid: 'pk-g-1',
          name: 'Group',
          memberIds: ['pk-mem-excluded', 'pk-mem-active'],
        ),
      ]);

      final groups = await db.memberGroupsDao.getAllActiveGroups();
      expect(groups, hasLength(1));
      final entries = await db.memberGroupsDao.entriesForGroup(
        groups.single.id,
      );
      // Only the non-excluded local is associated. The excluded member's
      // PK UUID is deferred (treated as unresolved) because the filter
      // dropped it before the map build.
      final memberIds = entries.map((e) => e.memberId).toSet();
      expect(memberIds, {'local-active'});
    });

    test('excluded local is not on the remove-path either: existing entry '
        'for the excluded member stays put when PK omits the corresponding '
        'PK UUID', () async {
      final db = getDb();
      // Seed: existing group + entry for the excluded local.
      await db.into(db.memberGroups).insert(
            MemberGroupsCompanion.insert(
              id: 'g-local',
              name: 'g-local',
              createdAt: DateTime.utc(2026, 1, 1),
              pluralkitUuid: const Value('pk-g-1'),
            ),
          );
      await db.into(db.memberGroupEntries).insert(
            MemberGroupEntriesCompanion.insert(
              id: 'e-1',
              groupId: 'g-local',
              memberId: 'local-excluded',
              pkGroupUuid: const Value('pk-g-1'),
              pkMemberUuid: const Value('pk-mem-excluded'),
            ),
          );

      final excluded = domain.Member(
        id: 'local-excluded',
        name: 'Excluded',
        emoji: '?',
        createdAt: DateTime.utc(2026),
        pluralkitUuid: 'pk-mem-excluded',
        pluralkitId: 'eee01',
        pluralkitSyncIgnored: true,
      );
      final repo = _FakeMemberRepo([excluded]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);

      // PK now reports the group with NO members. The remove path would
      // normally tombstone the existing entry — but the excluded local is
      // filtered out at the fetch so the remove path never considers it.
      await importer.importGroups([
        const PKGroup(
          id: 'gabcd',
          uuid: 'pk-g-1',
          name: 'Group',
          memberIds: [],
        ),
      ]);

      final entry = await (db.select(
        db.memberGroupEntries,
      )..where((e) => e.id.equals('e-1'))).getSingle();
      expect(
        entry.isDeleted,
        isFalse,
        reason: 'remove path must not touch entries for excluded locals',
      );
    });
  });

  group('PR 2: reattribute skips excluded locals', () {
    test('does not insert membership for an excluded local even when PK '
        'lists their UUID', () async {
      final db = getDb();
      // Seed: existing group, no entries yet.
      await db.into(db.memberGroups).insert(
            MemberGroupsCompanion.insert(
              id: 'g-local',
              name: 'g-local',
              createdAt: DateTime.utc(2026, 1, 1),
              pluralkitUuid: const Value('pk-g-1'),
            ),
          );

      final excluded = domain.Member(
        id: 'local-excluded',
        name: 'Excluded',
        emoji: '?',
        createdAt: DateTime.utc(2026),
        pluralkitUuid: 'pk-mem-excluded',
        pluralkitId: 'eee01',
        pluralkitSyncIgnored: true,
      );
      final active = _member(id: 'local-active', pkUuid: 'pk-mem-active');
      final repo = _FakeMemberRepo([excluded, active]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);

      final client = _ReattributeFakeClient([
        const PKGroup(
          id: 'gabcd',
          uuid: 'pk-g-1',
          name: 'Group',
          memberIds: ['pk-mem-excluded', 'pk-mem-active'],
        ),
      ]);

      await importer.reattribute(client);

      final entries = await db.memberGroupsDao.entriesForGroup('g-local');
      final memberIds = entries.map((e) => e.memberId).toSet();
      expect(memberIds, {'local-active'},
          reason: 'excluded local must not be reattributed to the group');
    });
  });
}

/// Minimal PluralKitClient stub for reattribute tests — only getGroups is
/// invoked, everything else throws.
class _ReattributeFakeClient implements PluralKitClient {
  _ReattributeFakeClient(this._groups);
  final List<PKGroup> _groups;

  @override
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async => _groups;

  @override
  String get currentToken => 'fake';

  @override
  void dispose() {}

  @override
  Future<PKMember> createMember(Map<String, dynamic> data) =>
      throw UnimplementedError();
  @override
  Future<PKMember> updateMember(String id, Map<String, dynamic> data) =>
      throw UnimplementedError();
  @override
  Future<PKSwitch> createSwitch(
    List<String> memberIds, {
    DateTime? timestamp,
  }) => throw UnimplementedError();
  @override
  Future<PKSwitch> updateSwitch(
    String switchId, {
    required DateTime timestamp,
  }) => throw UnimplementedError();
  @override
  Future<PKSwitch> updateSwitchMembers(
    String switchId,
    List<String> memberIds,
  ) => throw UnimplementedError();
  @override
  Future<void> deleteSwitch(String switchId) => throw UnimplementedError();
  @override
  Future<PKSystem> getSystem() => throw UnimplementedError();
  @override
  Future<List<PKMember>> getMembers() => throw UnimplementedError();
  @override
  Future<PKMember> getMember(String memberRef) => throw UnimplementedError();
  @override
  Future<List<PKSwitch>> getSwitches({DateTime? before, int limit = 100}) =>
      throw UnimplementedError();
  @override
  Future<void> deleteMember(String id) => throw UnimplementedError();
  @override
  Future<List<int>> downloadBytes(String url) => throw UnimplementedError();
  @override
  Future<List<String>> getGroupMembers(String groupRef) async => const [];
  @override
  Future<void> addMembersToGroup(
    String groupRef,
    List<String> memberRefs,
  ) async => throw UnimplementedError();
  @override
  Future<void> removeMembersFromGroup(
    String groupRef,
    List<String> memberRefs,
  ) async => throw UnimplementedError();
  @override
  Future<PKSwitch?> getCurrentFronters() => throw UnimplementedError();
}
