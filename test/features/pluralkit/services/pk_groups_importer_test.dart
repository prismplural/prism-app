import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_groups_importer.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';

class _FakeMemberRepo implements MemberRepository {
  final List<domain.Member> members;
  _FakeMemberRepo(this.members);

  @override
  Future<List<domain.Member>> getAllMembers() async => members;

  @override
  Future<domain.Member?> getMemberById(String id) async => members
      .cast<domain.Member?>()
      .firstWhere((m) => m!.id == id, orElse: () => null);

  @override
  Future<List<domain.Member>> getMembersByIds(List<String> ids) async =>
      members.where((m) => ids.contains(m.id)).toList();

  @override
  Future<void> createMember(domain.Member m) async => members.add(m);
  @override
  Future<void> updateMember(domain.Member m) async {
    final i = members.indexWhere((x) => x.id == m.id);
    if (i >= 0) members[i] = m;
  }

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
}

class _NoopClient implements PluralKitClient {
  @override
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async => const [];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

  test('deterministic entry ID is stable across runs', () {
    final a = PkGroupsImporter.deriveEntryId('g-uuid', 'm-uuid');
    final b = PkGroupsImporter.deriveEntryId('g-uuid', 'm-uuid');
    expect(a, b);
    expect(a.length, 16);
    // Different inputs differ.
    expect(PkGroupsImporter.deriveEntryId('g-uuid2', 'm-uuid'), isNot(a));
  });

  test('inserts new group + memberships, preserves local emoji on insert '
      '(no PK emoji written)', () async {
    final m = _member(id: 'local-1', pkUuid: 'pk-mem-1');
    final repo = _FakeMemberRepo([m]);
    final importer = PkGroupsImporter(db: db, memberRepository: repo);

    final result = await importer.importGroups(_NoopClient(), [
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

      final result = await importer.importGroups(_NoopClient(), [
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

      await importer.importGroups(_NoopClient(), [
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
        'is_deleted',
      });
      expect(groupFields['name'], 'Core');
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

      await importer.importGroups(_NoopClient(), [
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

      final result = await importer.importGroups(_NoopClient(), [
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

    final result = await importer.importGroups(_NoopClient(), [
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

    await importer.importGroups(_NoopClient(), [
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
    final result = await importer.importGroups(_NoopClient(), [
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

      await importer.importGroups(_NoopClient(), [
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
      final r = await importer.importGroups(_NoopClient(), [
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

      await importer.importGroups(_NoopClient(), [
        const PKGroup(
          id: 'abcde',
          uuid: 'pk-g-1',
          name: 'OldCore',
          memberIds: [],
        ),
      ], overwriteMetadata: true);
      await importer.importGroups(_NoopClient(), [
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

    await importer.importGroups(_NoopClient(), [
      const PKGroup(id: 'abcde', uuid: 'pk-g-1', name: 'Core', memberIds: []),
    ], overwriteMetadata: true);
    var g = (await db.memberGroupsDao.getAllActiveGroups()).single;
    // User sets emoji locally.
    await (db.update(db.memberGroups)..where((t) => t.id.equals(g.id))).write(
      const MemberGroupsCompanion(emoji: Value('🎨')),
    );

    await importer.importGroups(_NoopClient(), [
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

      await importer.importGroups(_NoopClient(), [
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
      await importer.importGroups(_NoopClient(), [
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

    await importer.importGroups(_NoopClient(), [
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

    await importer.importGroups(_NoopClient(), [
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
      'is_deleted',
    });
    expect(groupFields['name'], 'Original');
    expect(groupFields['description'], isNull);
    expect(groupFields['color_hex'], isNull);
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

      await importer.importGroups(_NoopClient(), [
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

      await importer.importGroups(_NoopClient(), [
        const PKGroup(
          id: 'abcde',
          uuid: 'pk-g-1',
          name: 'First',
          memberIds: [],
        ),
      ], overwriteMetadata: true);
      await importer.importGroups(_NoopClient(), [
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

    await iA.importGroups(_NoopClient(), [pkGroup], overwriteMetadata: true);
    await iB.importGroups(_NoopClient(), [pkGroup], overwriteMetadata: true);

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

    final r1 = await importer.importGroups(_NoopClient(), [
      pkGroup,
    ], overwriteMetadata: true);
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

      final result = await importer.importGroups(_NoopClient(), [
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
}

class _StubClient implements PluralKitClient {
  final List<PKGroup> groups;
  _StubClient(this.groups);
  @override
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async => groups;
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
