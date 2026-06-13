import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/pk_incarnation_ids.dart';
import 'package:prism_plurality/core/sync/tombstone_gate.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
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

/// A [TombstoneGate] reporting exactly [tombstonedIds] as is_deleted=true (the
/// Rust field_versions source of truth); every other id reads as live. Used by
/// the F06 tests to drive the drain-path-physical-delete case where no local
/// soft-deleted row exists but the engine still holds the tombstone.
TombstoneGate _gateTombstoning(Set<String> tombstonedIds) {
  return TombstoneGate((table, entityId, field) async {
    if (field != 'is_deleted') return null;
    return tombstonedIds.contains(entityId) ? 'true' : null;
  });
}

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

  // H6b: the removal-reconcile recency grace protects entries
  // younger than `removalRecencyGrace` (48h). Removal tests that create an
  // entry then expect it dropped on a later pull must first age the entry past
  // the window — the steady-state case (a stable membership later removed on
  // PK). This sets EVERY entry's local `created_at` to well before the grace
  // cutoff so the destructive pass treats them as eligible.
  Future<void> ageAllEntriesPastGrace() async {
    final ancient = DateTime.now().subtract(
      PkGroupsImporter.removalRecencyGrace * 2,
    );
    await db
        .update(db.memberGroupEntries)
        .write(MemberGroupEntriesCompanion(createdAt: Value(ancient)));
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
    'import does not mark the decommissioned PK repair run gate (S3)',
    () async {
      // S3 (pk-identity-alias-coherence): the PK group repair auto-run was
      // decommissioned, so the importer no longer marks the now-deleted
      // PkGroupRepairRunGate dirty. Assert the legacy prefs key stays unset
      // after a membership-changing import.
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
      expect(prefs.getBool('pk_group_repair.dirty'), isNull);
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
    'M13/issue 3 + F15: a BACKGROUND pull over a deleted tombstone that KEPT '
    'its UUID (non-deterministic row id) skips re-import — user deletion is '
    'preserved',
    () async {
      // CONTRACT INVERSION (2026-06 PK audit wave-3 verifier issue 3): this
      // test previously asserted the opposite — that a uuid-bearing tombstone
      // is happily bypassed and the group re-imported under the deterministic
      // id. That bypass was the resurrection vector for groups adopted under
      // their ORIGINAL row id (repair's linkGroupToPluralkitUuid, pre-
      // deterministic imports), whose deletion the deterministic-id guard
      // alone cannot see. deleteGroup now keeps the uuid on the tombstone,
      // and the importer consults findByPluralkitUuidIncludingDeleted.
      //
      // F15 (absorbing-tombstone-revive-holes): a BACKGROUND pull
      // (overwriteMetadata=false) honors the deletion and skips. An explicit
      // re-import revives instead (separate test below).
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
      ]);

      expect(result.groupsInserted, 0);
      expect(result.groupsPreservedAsDeletedTombstone, 1);
      expect(result.groupsSkippedTombstoned, 1);
      expect(await db.memberGroupsDao.findByPluralkitUuid('pk-g-1'), isNull);
      // No entries materialized for the preserved-deleted group.
      final entries = await (db.select(db.memberGroupEntries)).get();
      expect(entries, isEmpty);
    },
  );

  test(
    'F15: an EXPLICIT re-import over a Drift tombstone revives under a fresh '
    'group incarnation id — one create under the new id, alias recorded',
    () async {
      await setPkGroupSyncV2Enabled(true);
      // A user-deleted group tombstone under its deterministic row id. The gate
      // reports the canonical gen-0 entity as burned (Rust field_versions),
      // matching the absorbing-delete state of every peer.
      const groupUuid = 'pk-g-1';
      final localRowId = PkGroupsImporter.deriveGroupId(groupUuid);
      final canonicalId = PkGroupsImporter.deriveGroupSyncEntityId(groupUuid);
      final gen1Id = deriveGroupIncarnationEntityId(groupUuid, 1);
      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: localRowId,
              name: 'Deleted',
              createdAt: DateTime.utc(2024, 1, 1),
              isDeleted: const Value(true),
              pluralkitUuid: const Value(groupUuid),
            ),
          );

      final creates = <Map<String, Object?>>[];
      final updates = <Map<String, Object?>>[];
      final deletes = <Map<String, String>>[];
      final repo = _FakeMemberRepo([
        _member(id: 'local-1', pkUuid: 'pk-mem-1'),
      ]);
      final importer = PkGroupsImporter(
        db: db,
        memberRepository: repo,
        tombstoneGate: _gateTombstoning({canonicalId}),
        recordCreateOverride: (table, entityId, fields) async {
          creates.add({'table': table, 'entityId': entityId});
        },
        recordUpdateOverride: (table, entityId, fields) async {
          updates.add({'table': table, 'entityId': entityId});
        },
        recordDeleteOverride: (table, entityId) async {
          deletes.add({'table': table, 'entityId': entityId});
        },
      );

      final result = await importer.importGroups([
        const PKGroup(
          id: 'abcde',
          uuid: groupUuid,
          name: 'Core',
          memberIds: ['pk-mem-1'],
        ),
      ], overwriteMetadata: true);

      // Revived, not skipped.
      expect(result.groupsInserted, 1);
      expect(result.groupsSkippedTombstoned, 0);
      expect(result.groupsPreservedAsDeletedTombstone, 0);

      // Local row revived in place at the bumped incarnation generation.
      final revived = await db.memberGroupsDao.findByPluralkitUuid(groupUuid);
      expect(revived, isNotNull);
      expect(revived!.id, localRowId);
      expect(revived.isDeleted, isFalse);
      expect(revived.syncGeneration, 1);

      // Exactly one group create, under the gen-1 incarnation id — never the
      // burned canonical id — and no delete/update for the group.
      final groupCreates = creates
          .where((c) => c['table'] == 'member_groups')
          .toList();
      expect(groupCreates, hasLength(1));
      expect(groupCreates.single['entityId'], gen1Id);
      expect(
        deletes.where((d) => d['table'] == 'member_groups'),
        isEmpty,
      );
      expect(
        creates.any((c) => c['entityId'] == canonicalId),
        isFalse,
        reason: 'the burned canonical id must never be re-created',
      );

      // The incarnation id is recorded as an alias for the canonical uuid.
      final alias = await db.pkGroupSyncAliasesDao.getByLegacyEntityId(gen1Id);
      expect(alias, isNotNull);
      expect(alias!.pkGroupUuid, groupUuid);
      expect(alias.canonicalEntityId, canonicalId);

      // Membership reconcile ran under the revived row. Only the GROUP entity
      // was burned here (the entry's gen-0 sha is not in the gate's tombstone
      // set), so the entry inserts live at gen 0 — exactly one entry create.
      final entryCreates = creates
          .where((c) => c['table'] == 'member_group_entries')
          .toList();
      expect(entryCreates, hasLength(1));
      expect(
        entryCreates.single['entityId'],
        PkGroupsImporter.deriveEntryId(groupUuid, 'pk-mem-1'),
      );
    },
  );

  test(
    'F15 remote-tombstone variant: a group tombstoned in the engine '
    '(field_versions only, no Drift evidence) is skipped on a background pull',
    () async {
      await setPkGroupSyncV2Enabled(true);
      // The drain path hard-deleted the local Drift row (or a pre-fix
      // deleteGroup nulled its uuid), so neither the deterministic-id lookup
      // nor the uuid lookup finds a tombstone — the engine's field_versions are
      // the ONLY surviving evidence. The gate must still block the blind-revive.
      const groupUuid = 'pk-g-1';
      final canonicalId = PkGroupsImporter.deriveGroupSyncEntityId(groupUuid);

      final creates = <Map<String, Object?>>[];
      final repo = _FakeMemberRepo([
        _member(id: 'local-1', pkUuid: 'pk-mem-1'),
      ]);
      final importer = PkGroupsImporter(
        db: db,
        memberRepository: repo,
        tombstoneGate: _gateTombstoning({canonicalId}),
        recordCreateOverride: (table, entityId, fields) async {
          creates.add({'table': table, 'entityId': entityId});
        },
      );

      final result = await importer.importGroups([
        const PKGroup(
          id: 'abcde',
          uuid: groupUuid,
          name: 'Core',
          memberIds: ['pk-mem-1'],
        ),
      ]);

      expect(result.groupsInserted, 0);
      expect(result.groupsSkippedTombstoned, 1);
      // FFI-only: no Drift soft-deleted row, so the Drift-evidence subcounter
      // stays 0.
      expect(result.groupsPreservedAsDeletedTombstone, 0);
      expect(await db.memberGroupsDao.findByPluralkitUuid(groupUuid), isNull);
      expect(creates, isEmpty);
    },
  );

  test(
    'F15 blocker: a pull AFTER an explicit revive never tombstones the minted '
    'incarnation — the update targets the live gen-1 id and the alias survives',
    () async {
      await setPkGroupSyncV2Enabled(true);
      // A user-deleted group tombstone; the gate burns the gen-0 canonical id,
      // so the first explicit re-import revives the row at gen 1 and records the
      // `pk-group-g1:<uuid>` incarnation as an alias. The bug: the very next
      // emit-worthy pull (a second explicit re-import, or the 24h heartbeat /
      // identity change on a background pull) took the update branch, emitted
      // the alias-delete keyed only against the gen-0 canonical id, dropped the
      // alias row, and so tombstoned the freshly minted incarnation fleet-wide.
      const groupUuid = 'pk-g-1';
      final localRowId = PkGroupsImporter.deriveGroupId(groupUuid);
      final canonicalId = PkGroupsImporter.deriveGroupSyncEntityId(groupUuid);
      final gen1Id = deriveGroupIncarnationEntityId(groupUuid, 1);
      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: localRowId,
              name: 'Deleted',
              createdAt: DateTime.utc(2024, 1, 1),
              isDeleted: const Value(true),
              pluralkitUuid: const Value(groupUuid),
            ),
          );

      final creates = <Map<String, Object?>>[];
      final updates = <Map<String, Object?>>[];
      final deletes = <Map<String, String>>[];
      final repo = _FakeMemberRepo([
        _member(id: 'local-1', pkUuid: 'pk-mem-1'),
      ]);
      final importer = PkGroupsImporter(
        db: db,
        memberRepository: repo,
        tombstoneGate: _gateTombstoning({canonicalId}),
        recordCreateOverride: (table, entityId, fields) async {
          creates.add({'table': table, 'entityId': entityId});
        },
        recordUpdateOverride: (table, entityId, fields) async {
          updates.add({'table': table, 'entityId': entityId});
        },
        recordDeleteOverride: (table, entityId) async {
          deletes.add({'table': table, 'entityId': entityId});
        },
      );

      const group = PKGroup(
        id: 'abcde',
        uuid: groupUuid,
        name: 'Core',
        memberIds: ['pk-mem-1'],
      );

      // Pass 1: explicit re-import revives under the gen-1 incarnation.
      final first = await importer.importGroups([group], overwriteMetadata: true);
      expect(first.groupsInserted, 1);
      final aliasAfterRevive = await db.pkGroupSyncAliasesDao.getByLegacyEntityId(
        gen1Id,
      );
      expect(aliasAfterRevive, isNotNull);

      creates.clear();
      updates.clear();
      deletes.clear();

      // Pass 2: a SUBSEQUENT pull. The row is now active at gen 1, so this hits
      // the existing-row update branch (overwriteMetadata forces a metadata
      // emit). It must NOT delete the gen-1 incarnation and must target the
      // live id.
      final second = await importer.importGroups(
        [group],
        overwriteMetadata: true,
      );
      expect(second.groupsInserted, 0);
      expect(second.groupsUpdated, 1);

      // The update is emitted under the LIVE incarnation id, never the burned
      // canonical id.
      final groupUpdates = updates
          .where((u) => u['table'] == 'member_groups')
          .toList();
      expect(groupUpdates, hasLength(1));
      expect(groupUpdates.single['entityId'], gen1Id);

      // No delete is emitted for the group's live incarnation (or the canonical
      // id) — the alias-delete bookkeeping must exclude the row's own
      // incarnation.
      expect(
        deletes.where(
          (d) =>
              d['table'] == 'member_groups' &&
              (d['entityId'] == gen1Id || d['entityId'] == canonicalId),
        ),
        isEmpty,
        reason:
            'the minted incarnation (and the canonical id) must never be a '
            'legacy-alias delete target',
      );

      // The incarnation alias row survives the pull, so the row keeps resolving.
      final aliasAfterPull = await db.pkGroupSyncAliasesDao.getByLegacyEntityId(
        gen1Id,
      );
      expect(aliasAfterPull, isNotNull);

      // The local row is still alive at gen 1 (no revive-then-delete flap).
      final row = await db.memberGroupsDao.findByPluralkitUuid(groupUuid);
      expect(row, isNotNull);
      expect(row!.isDeleted, isFalse);
      expect(row.syncGeneration, 1);
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

      // Age the entries past the H6b grace window so the removal reconcile is
      // eligible (steady-state membership later dropped on PK).
      await ageAllEntriesPastGrace();

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

    // Age the seeded entries past the H6b grace window so the membership
    // removal below is eligible.
    await ageAllEntriesPastGrace();

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

    // M14a: an immediate second pull with no identity
    // change, no metadata overwrite, and a last_seen heartbeat that is NOT yet
    // due (< 24h) must emit NO member_groups update — the pre-fix code churned
    // one out every pull. The membership delete still flows.
    final groupUpdates = updates
        .where((call) => call['table'] == 'member_groups')
        .toList();
    expect(
      groupUpdates,
      isEmpty,
      reason: 'unchanged group on rapid second pull must not emit an update',
    );

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

  // ─────────────────────────────────────────────────────────────────────────
  // F06 (absorbing-tombstone-revive-holes): PK membership reconcile is
  // tombstone-aware. A peer's cross-device removal arrives as a soft-deleted
  // entry with pending_pk_op='none' (the local-only column defaults to 'none'
  // on a synced tombstone) and/or as a Rust is_deleted tombstone after the
  // drain path physically deleted the local row. Blind-reviving the burned
  // deterministic id emits a create every peer silently drops. The importer
  // now: (background pull) honors the removal and skips, optionally flipping
  // the local tombstone to push_remove under the cohort gate; (explicit user
  // re-import) revives under a freshly-minted incarnation id.
  group('F06: tombstone-aware membership reconcile', () {
    const pkGroupUuid = 'pk-g-f06';
    const pkMemberUuid = 'pk-mem-f06';
    final groupLocalId = PkGroupsImporter.deriveGroupId(pkGroupUuid);
    final gen0EntryId = PkGroupsImporter.deriveEntryId(
      pkGroupUuid,
      pkMemberUuid,
    );
    const pkGroup = PKGroup(
      id: 'gf06',
      uuid: pkGroupUuid,
      name: 'F06',
      memberIds: [pkMemberUuid],
    );

    test(
      'background pull over a peer tombstone (gate-tombstoned) performs no '
      'upsert/emit, reports entriesSkippedTombstoned=1, and flips the local '
      'tombstone to push_remove under the cohort gate',
      () async {
        await setPkGroupSyncV2Enabled(true);
        await insertGroup(id: groupLocalId, pkUuid: pkGroupUuid);
        // Peer-originated tombstone: soft-deleted, pending_pk_op='none'.
        await insertEntry(
          id: gen0EntryId,
          groupId: groupLocalId,
          memberId: 'local-f06',
          pkGroupUuid: pkGroupUuid,
          pkMemberUuid: pkMemberUuid,
          isDeleted: true,
          pendingPkOp: 'none',
        );

        final creates = <Map<String, Object?>>[];
        final updates = <Map<String, Object?>>[];
        final deletes = <Map<String, Object?>>[];
        final importer = PkGroupsImporter(
          db: db,
          memberRepository: _FakeMemberRepo([
            _member(id: 'local-f06', pkUuid: pkMemberUuid),
          ]),
          // Gate reports the gen-0 id as tombstoned (Rust field_versions),
          // covering the drain-physical-delete case too.
          tombstoneGate: _gateTombstoning({gen0EntryId}),
          recordCreateOverride: (table, entityId, fields) async =>
              creates.add({'table': table, 'entityId': entityId}),
          recordUpdateOverride: (table, entityId, fields) async =>
              updates.add({'table': table, 'entityId': entityId}),
          recordDeleteOverride: (table, entityId) async =>
              deletes.add({'table': table, 'entityId': entityId}),
        );

        // Background pull (overwriteMetadata defaults to false).
        final result = await importer.importGroups([pkGroup]);

        expect(result.entriesSkippedTombstoned, 1);
        expect(result.entriesInserted, 0);
        // No entry op of any kind — the tombstone is honored.
        expect(
          creates.where((c) => c['table'] == 'member_group_entries'),
          isEmpty,
        );
        expect(
          updates.where((u) => u['table'] == 'member_group_entries'),
          isEmpty,
        );
        expect(
          deletes.where((d) => d['table'] == 'member_group_entries'),
          isEmpty,
        );
        // Row stays soft-deleted; pending flipped to push_remove (cohort gate
        // on) so the PK-token device converges PluralKit to the removal.
        final row = await (db.select(
          db.memberGroupEntries,
        )..where((e) => e.id.equals(gen0EntryId))).getSingle();
        expect(row.isDeleted, isTrue);
        expect(row.pendingPkOp, 'push_remove');
      },
    );

    test(
      'background pull does NOT flip pending to push_remove when the cohort '
      'gate (pkGroupSyncV2Enabled) is off',
      () async {
        await setPkGroupSyncV2Enabled(false);
        await insertGroup(id: groupLocalId, pkUuid: pkGroupUuid);
        await insertEntry(
          id: gen0EntryId,
          groupId: groupLocalId,
          memberId: 'local-f06',
          pkGroupUuid: pkGroupUuid,
          pkMemberUuid: pkMemberUuid,
          isDeleted: true,
          pendingPkOp: 'none',
        );

        final importer = PkGroupsImporter(
          db: db,
          memberRepository: _FakeMemberRepo([
            _member(id: 'local-f06', pkUuid: pkMemberUuid),
          ]),
          tombstoneGate: _gateTombstoning({gen0EntryId}),
        );

        final result = await importer.importGroups([pkGroup]);

        expect(result.entriesSkippedTombstoned, 1);
        final row = await (db.select(
          db.memberGroupEntries,
        )..where((e) => e.id.equals(gen0EntryId))).getSingle();
        expect(row.isDeleted, isTrue);
        expect(
          row.pendingPkOp,
          'none',
          reason: 'push_remove adoption is behind the pkGroupSyncV2 gate',
        );
      },
    );

    test(
      'explicit user re-import revives under a freshly-minted incarnation: '
      'generation bumped, exactly one create under the gen1 sha id',
      () async {
        await setPkGroupSyncV2Enabled(true);
        await insertGroup(id: groupLocalId, pkUuid: pkGroupUuid);
        // Local tombstone at the gen-0 id AND the gate reports it burned.
        await insertEntry(
          id: gen0EntryId,
          groupId: groupLocalId,
          memberId: 'local-f06',
          pkGroupUuid: pkGroupUuid,
          pkMemberUuid: pkMemberUuid,
          isDeleted: true,
          pendingPkOp: 'none',
        );

        final creates = <Map<String, Object?>>[];
        final updates = <Map<String, Object?>>[];
        final importer = PkGroupsImporter(
          db: db,
          memberRepository: _FakeMemberRepo([
            _member(id: 'local-f06', pkUuid: pkMemberUuid),
          ]),
          tombstoneGate: _gateTombstoning({gen0EntryId}),
          recordCreateOverride: (table, entityId, fields) async => creates.add({
            'table': table,
            'entityId': entityId,
            'fields': Map<String, dynamic>.from(fields),
          }),
          recordUpdateOverride: (table, entityId, fields) async =>
              updates.add({'table': table, 'entityId': entityId}),
        );

        // Explicit re-import => overwriteMetadata: true.
        final result = await importer.importGroups(
          [pkGroup],
          overwriteMetadata: true,
        );

        // Not counted as a skipped tombstone — it was revived.
        expect(result.entriesSkippedTombstoned, 0);
        expect(result.entriesInserted, 1);

        final gen1Id = deriveEntryIncarnationEntityId(
          pkGroupUuid,
          pkMemberUuid,
          1,
        )!;
        // Exactly one entry create, under the gen-1 incarnation id.
        final entryCreates = creates
            .where((c) => c['table'] == 'member_group_entries')
            .toList();
        expect(entryCreates, hasLength(1));
        expect(entryCreates.single['entityId'], gen1Id);
        // No entry UPDATE (revive under a fresh id is always a create).
        expect(
          updates.where((u) => u['table'] == 'member_group_entries'),
          isEmpty,
        );
        // The revived row carries sync_generation=1 and is live.
        final revived = await (db.select(
          db.memberGroupEntries,
        )..where((e) => e.id.equals(gen1Id))).getSingle();
        expect(revived.syncGeneration, 1);
        expect(revived.isDeleted, isFalse);
        // The superseded gen-0 tombstone row is hard-deleted so no stale push
        // intent races the fresh revive (R1/H6c composition).
        final gen0Rows = await (db.select(
          db.memberGroupEntries,
        )..where((e) => e.id.equals(gen0EntryId))).get();
        expect(gen0Rows, isEmpty);
      },
    );

    test(
      'locally-originated push_remove tombstone still skips insert '
      '(regression — no revive, no skip-count, no push_remove churn)',
      () async {
        await setPkGroupSyncV2Enabled(true);
        await insertGroup(id: groupLocalId, pkUuid: pkGroupUuid);
        // A push_remove tombstone is the user's own queued removal — handled
        // by the pendingRemovalMemberIds skip BEFORE the gate, so it is not an
        // F06 tombstone-skip and its pending op is left untouched.
        await insertEntry(
          id: gen0EntryId,
          groupId: groupLocalId,
          memberId: 'local-f06',
          pkGroupUuid: pkGroupUuid,
          pkMemberUuid: pkMemberUuid,
          isDeleted: true,
          pendingPkOp: 'push_remove',
        );

        final creates = <Map<String, Object?>>[];
        final importer = PkGroupsImporter(
          db: db,
          memberRepository: _FakeMemberRepo([
            _member(id: 'local-f06', pkUuid: pkMemberUuid),
          ]),
          recordCreateOverride: (table, entityId, fields) async =>
              creates.add({'table': table, 'entityId': entityId}),
        );

        final result = await importer.importGroups([pkGroup]);

        expect(result.entriesInserted, 0);
        expect(
          result.entriesSkippedTombstoned,
          0,
          reason: 'the push_remove skip is the pre-existing pending-op skip, '
              'not an F06 tombstone skip',
        );
        expect(
          creates.where((c) => c['table'] == 'member_group_entries'),
          isEmpty,
        );
        final row = await (db.select(
          db.memberGroupEntries,
        )..where((e) => e.id.equals(gen0EntryId))).getSingle();
        expect(row.pendingPkOp, 'push_remove');
      },
    );

    test(
      'gen-0 revive of an existing (non-tombstoned) row emits an UPDATE that '
      'OMITS is_deleted (94f5d950-shape per-field-LWW guard regression pin)',
      () async {
        // existedBefore=true update branch: an ACTIVE gen-0 row already sits at
        // the id, keyed to a different local member, when PK re-maps the
        // pkMemberUuid to local-f06. Classification routes this to a plain
        // gen-0 insert plan with existedBefore=true (live row at gen0Id, member
        // not yet active), so _emitMembershipSync takes the UPDATE branch — and
        // that patch must keep stripping is_deleted so per-field LWW can't stamp
        // is_deleted:false over a peer's concurrent delete.
        await setPkGroupSyncV2Enabled(true);
        await insertGroup(id: groupLocalId, pkUuid: pkGroupUuid);
        await insertEntry(
          id: gen0EntryId,
          groupId: groupLocalId,
          memberId: 'other-member',
          pkGroupUuid: pkGroupUuid,
          pkMemberUuid: pkMemberUuid,
        );

        final creates = <Map<String, Object?>>[];
        final updates = <Map<String, Object?>>[];
        final importer = PkGroupsImporter(
          db: db,
          memberRepository: _FakeMemberRepo([
            _member(id: 'local-f06', pkUuid: pkMemberUuid),
          ]),
          recordCreateOverride: (table, entityId, fields) async => creates.add({
            'table': table,
            'entityId': entityId,
            'fields': Map<String, dynamic>.from(fields),
          }),
          recordUpdateOverride: (table, entityId, fields) async => updates.add({
            'table': table,
            'entityId': entityId,
            'fields': Map<String, dynamic>.from(fields),
          }),
        );

        await importer.importGroups([pkGroup]);

        final entryUpdate = updates.singleWhere(
          (u) => u['table'] == 'member_group_entries',
          orElse: () => throw StateError(
            'expected a member_group_entries UPDATE on the existedBefore branch',
          ),
        );
        expect(
          (entryUpdate['fields'] as Map).containsKey('is_deleted'),
          isFalse,
          reason: 'the revive UPDATE patch must omit is_deleted so per-field '
              'LWW cannot resurrect a peer-deleted row',
        );
        // The update path is a revive, not a create.
        expect(
          creates.where((c) => c['table'] == 'member_group_entries'),
          isEmpty,
        );
      },
    );
  });
  _stepFourTests(getDb: () => db);
}

class _StubClient implements PluralKitClient {
  @override
  Future<PKSwitch> getSwitch(String switchRef) =>
      throw UnimplementedError();
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

      // H6b: age the entry past the removal grace window so
      // the steady-state "PK dropped this member" destructive path is eligible.
      await db
          .update(db.memberGroupEntries)
          .write(
            MemberGroupEntriesCompanion(
              createdAt: Value(
                DateTime.now().subtract(
                  PkGroupsImporter.removalRecencyGrace * 2,
                ),
              ),
            ),
          );

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

    // F06 (absorbing-tombstone-revive-holes): a soft-deleted entry at the
    // deterministic id is a tombstone — reviving it in place can never
    // propagate (the sender strips is_deleted=false; peers drop every op on
    // the tombstoned entity). A background pull must NOT blind-revive it; the
    // old behavior emitted a phantom revive that was silently dropped fleet-
    // wide, leaving the member alive only on the PK-token device. The fix
    // skips the insert/emit entirely on background pull. (Was previously a
    // per-field-LWW-on-revive regression test; F06 supersedes it because the
    // revive itself is now gone on background pull.) Uses the real
    // SyncRecordMixin capture pipeline, not the constructor override.
    test(
      'background pull does NOT revive a soft-deleted entry at the '
      'deterministic id (F06 honors the tombstone, emits nothing)',
      () async {
        final db = getDb();
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
        // Soft-deleted entry at the deterministic id — a local tombstone the
        // gate-less importer treats as burned.
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

        // No membership op at all — the tombstone is honored.
        final entryOps = captured
            .where((op) => op.table == 'member_group_entries')
            .toList();
        expect(
          entryOps,
          isEmpty,
          reason: 'Background pull must not emit a revive of a tombstoned '
              'entry id (F06).',
        );
        // Row stays soft-deleted.
        final row = await (db.select(
          db.memberGroupEntries,
        )..where((e) => e.id.equals(entryId))).getSingle();
        expect(row.isDeleted, isTrue);
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
  @override
  Future<PKSwitch> getSwitch(String switchRef) =>
      throw UnimplementedError();
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
