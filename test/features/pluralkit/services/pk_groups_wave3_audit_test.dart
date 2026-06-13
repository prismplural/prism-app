// Regression tests for the 2026-06 PK sync audit, GROUPS surface: H6a
// push-before-reconcile, H6b recency grace, M13 resurrection guard, M14a/b
// emit hygiene, M15a/c terminal-cleanup gating, and the M15 retry cap.
// Each test is written to FAIL against the pre-fix importer.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_groups_importer.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';

import '../../../helpers/pk_fixtures.dart';

// ── Fakes ──────────────────────────────────────────────────────────────────

class _FakeMemberRepo implements MemberRepository {
  _FakeMemberRepo(this.members);
  final List<domain.Member> members;

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
  Future<int> getCount() async => members.length;

  // Unused by these tests.
  @override
  Future<void> clearPluralKitLink(String id) async => throw UnimplementedError();
  @override
  Future<void> createMember(domain.Member m) async => throw UnimplementedError();
  @override
  Future<void> deleteMember(String id) async => throw UnimplementedError();
  @override
  Future<List<domain.Member>> getDeletedLinkedMembers() async =>
      throw UnimplementedError();
  @override
  Future<void> stampDeletePushStartedAt(String id, int t) async =>
      throw UnimplementedError();
  @override
  Future<void> updateMember(domain.Member m) async => throw UnimplementedError();
  @override
  Future<int> updateMemberFields(String id, Map<String, dynamic> f) async =>
      throw UnimplementedError();
  @override
  Future<int> applyPluralKitLink(String id, Map<String, dynamic> p) async =>
      throw UnimplementedError();
  @override
  Future<int> recordPluralKitIdentity(String id, Map<String, dynamic> p) async =>
      throw UnimplementedError();
  @override
  Future<int> excludePluralKitSync(String id) async =>
      throw UnimplementedError();
  @override
  Future<int> resumePluralKitSync(String id) async => throw UnimplementedError();
  @override
  Stream<List<domain.Member>> watchActiveMembers() => throw UnimplementedError();
  @override
  Stream<List<domain.Member>> watchAllMembers() => throw UnimplementedError();
  @override
  Stream<domain.Member?> watchMemberById(String id) =>
      throw UnimplementedError();
  @override
  Stream<List<domain.Member>> watchMembersByIds(List<String> ids) =>
      throw UnimplementedError();
  @override
  Future<({domain.Member member, bool wasCreated})>
  ensureUnknownSentinelMember() => throw UnimplementedError();
}

/// Programmable PK client: records calls; canned per-method responses; tracks
/// the ORDER in which membership endpoints vs getGroups were hit (for H6a).
class _ProgrammableClient implements PluralKitClient {
  final List<({String groupRef, List<String> refs})> addCalls = [];
  final List<({String groupRef, List<String> refs})> removeCalls = [];
  final List<String> getMembersCalls = [];
  final List<String> callOrder = [];

  final List<Object> addResponses = [];
  final List<Object> removeResponses = [];
  final Map<String, Object> getMembersResponses = {};

  // For H6a: what getGroups returns, evaluated lazily so a test can assert PK
  // already reflects a pushed intent by the time pull reads it.
  List<PKGroup> Function()? groupsProvider;

  @override
  Future<void> addMembersToGroup(String groupRef, List<String> refs) async {
    callOrder.add('add');
    addCalls.add((groupRef: groupRef, refs: refs));
    final next = addResponses.isEmpty ? null : addResponses.removeAt(0);
    if (next is Exception) throw next;
  }

  @override
  Future<void> removeMembersFromGroup(String groupRef, List<String> refs) async {
    callOrder.add('remove');
    removeCalls.add((groupRef: groupRef, refs: refs));
    final next = removeResponses.isEmpty ? null : removeResponses.removeAt(0);
    if (next is Exception) throw next;
  }

  @override
  Future<List<String>> getGroupMembers(String groupRef) async {
    getMembersCalls.add(groupRef);
    final response = getMembersResponses[groupRef];
    if (response is Exception) throw response;
    if (response is List<String>) return response;
    return const <String>[];
  }

  @override
  Future<List<PKGroup>> getGroups({bool withMembers = true}) async {
    callOrder.add('getGroups');
    return groupsProvider?.call() ?? const <PKGroup>[];
  }

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

// ── Helpers ──────────────────────────────────────────────────────────────────

domain.Member _member(String id, {String? pkUuid, bool excluded = false}) =>
    domain.Member(
      id: id,
      name: id,
      createdAt: DateTime.utc(2026, 1, 1),
      pluralkitUuid: pkUuid,
      pluralkitSyncIgnored: excluded,
    );

Future<void> _seedGroup(
  AppDatabase db, {
  required String id,
  String? pkUuid,
  String? pkId,
  bool isDeleted = false,
  DateTime? lastSeen,
}) {
  return db.into(db.memberGroups).insert(
        MemberGroupsCompanion.insert(
          id: id,
          name: id,
          createdAt: DateTime.utc(2026, 1, 1),
          pluralkitUuid: Value(pkUuid),
          pluralkitId: Value(pkId),
          isDeleted: Value(isDeleted),
          lastSeenFromPkAt: Value(lastSeen),
        ),
      );
}

Future<void> _seedEntry(
  AppDatabase db, {
  required String id,
  required String groupId,
  required String memberId,
  String? pkGroupUuid,
  String? pkMemberUuid,
  bool isDeleted = false,
  String pendingPkOp = 'none',
  DateTime? createdAt,
}) {
  return db.into(db.memberGroupEntries).insert(
        MemberGroupEntriesCompanion.insert(
          id: id,
          groupId: groupId,
          memberId: memberId,
          pkGroupUuid: Value(pkGroupUuid),
          pkMemberUuid: Value(pkMemberUuid),
          isDeleted: Value(isDeleted),
          pendingPkOp: Value(pendingPkOp),
          createdAt: Value(createdAt),
        ),
      );
}

Future<MemberGroupEntryRow?> _findEntry(AppDatabase db, String id) async {
  final rows = await (db.select(db.memberGroupEntries)
        ..where((e) => e.id.equals(id)))
      .get();
  return rows.isEmpty ? null : rows.single;
}

void main() {
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    await db.systemSettingsDao.getSettings();
    await db.systemSettingsDao.updatePkGroupSyncV2Enabled(true);
  });

  tearDown(() => db.close());

  // ── H6a ────────────────────────────────────────────────────────────────
  group('H6a push-before-reconcile ordering', () {
    test('pushPendingGroupOps runs BEFORE getGroups when pushClient supplied',
        () async {
      final repo = _FakeMemberRepo([_member('m1', pkUuid: 'pk-m1')]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);
      await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1', pkId: 'gid');
      // A locally-added entry queued for push.
      await _seedEntry(
        db,
        id: 'e1',
        groupId: 'g1',
        memberId: 'm1',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-m1',
        pendingPkOp: 'push_add',
      );

      final client = _ProgrammableClient()
        ..groupsProvider = () => const [
              PKGroup(
                id: 'gid',
                uuid: 'pk-g1',
                name: 'g1',
                // PK already reflects the add because push ran first.
                memberIds: ['pk-m1'],
              ),
            ];

      await importer.importGroups(
        [
          const PKGroup(
            id: 'gid',
            uuid: 'pk-g1',
            name: 'g1',
            memberIds: ['pk-m1'],
          ),
        ],
        direction: PkSyncDirection.bidirectional,
        pushClient: client,
      );

      // The add POST must precede the importer's own getGroups would-be call —
      // here the orchestrator's refetch is unneeded (204) so we assert the add
      // happened and pending was cleared (drained to PK before reconcile).
      expect(client.addCalls, hasLength(1));
      expect(client.callOrder.first, 'add',
          reason: 'push must run before pull reconcile (H6a)');
      expect((await _findEntry(db, 'e1'))!.pendingPkOp, 'none');
    });

    test('a push failure does NOT abort the pull (failure isolation)',
        () async {
      final repo = _FakeMemberRepo([_member('m1', pkUuid: 'pk-m1')]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);
      await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1', pkId: 'gid');
      await _seedEntry(
        db,
        id: 'e1',
        groupId: 'g1',
        memberId: 'm1',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-m1',
        pendingPkOp: 'push_add',
      );

      final client = _ProgrammableClient();
      // Push 5xx + refetch 5xx → push leaves pending; must not throw out.
      client.addResponses.add(const PluralKitApiError(500, 'boom'));

      // Pull brings in a brand-new group; the import must still apply it.
      final result = await importer.importGroups(
        [
          const PKGroup(
            id: 'g2id',
            uuid: 'pk-g2',
            name: 'NewGroup',
            memberIds: [],
          ),
        ],
        direction: PkSyncDirection.bidirectional,
        pushClient: client,
      );

      expect(result.groupsInserted, 1,
          reason: 'a push failure must not abort the pull (H6a)');
      // The failing add intent stays pending for the next round.
      expect((await _findEntry(db, 'e1'))!.pendingPkOp, 'push_add');
    });
  });

  // ── H6b ────────────────────────────────────────────────────────────────
  group('H6b removal recency grace', () {
    test('a RECENT entry omitted by PK is NOT reconcile-deleted', () async {
      final repo = _FakeMemberRepo([_member('m1', pkUuid: 'pk-m1')]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);
      await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
      // Fresh entry (created now), pending=none, PK-linked. PK's authoritative
      // set below omits it — pre-fix this soft-deletes; post-fix grace protects.
      await _seedEntry(
        db,
        id: 'e1',
        groupId: 'g1',
        memberId: 'm1',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-m1',
        createdAt: DateTime.now(),
      );

      final result = await importer.importGroups([
        const PKGroup(id: 'g1id', uuid: 'pk-g1', name: 'g1', memberIds: []),
      ]);

      expect(result.entriesRemoved, 0);
      expect(result.entriesSkippedRecent, 1);
      expect((await _findEntry(db, 'e1'))!.isDeleted, isFalse);
    });

    test('an OLD entry omitted by PK IS reconcile-deleted', () async {
      final repo = _FakeMemberRepo([_member('m1', pkUuid: 'pk-m1')]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);
      await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
      await _seedEntry(
        db,
        id: 'e1',
        groupId: 'g1',
        memberId: 'm1',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-m1',
        createdAt: DateTime.now()
            .subtract(PkGroupsImporter.removalRecencyGrace * 2),
      );

      final result = await importer.importGroups([
        const PKGroup(id: 'g1id', uuid: 'pk-g1', name: 'g1', memberIds: []),
      ]);

      expect(result.entriesRemoved, 1);
      expect(result.entriesSkippedRecent, 0);
      expect((await _findEntry(db, 'e1'))!.isDeleted, isTrue);
    });

    test('a NULL created_at (pre-column row) is treated as eligible',
        () async {
      final repo = _FakeMemberRepo([_member('m1', pkUuid: 'pk-m1')]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);
      await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
      await _seedEntry(
        db,
        id: 'e1',
        groupId: 'g1',
        memberId: 'm1',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-m1',
        createdAt: null,
      );
      // Force created_at NULL (seed clientDefault would otherwise stamp it).
      await db.customStatement(
        'UPDATE member_group_entries SET created_at = NULL WHERE id = ?',
        ['e1'],
      );

      final result = await importer.importGroups([
        const PKGroup(id: 'g1id', uuid: 'pk-g1', name: 'g1', memberIds: []),
      ]);

      expect(result.entriesRemoved, 1,
          reason: 'missing stamp must not permanently leak a PK membership');
    });
  });

  // ── M13 ──────────────────────────────────────────────────────────────────
  group('M13 deleted group not resurrected', () {
    test('a user-deleted PK group (deterministic-id tombstone) is preserved',
        () async {
      final repo = _FakeMemberRepo([_member('m1', pkUuid: 'pk-m1')]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);

      // Simulate the deleteGroup outcome: deterministic id tombstone with the
      // pluralkit_uuid NULLED (exactly what member_groups_dao.deleteGroup does).
      final deterministicId = PkGroupsImporter.deriveGroupId('pk-g1');
      await _seedGroup(db, id: deterministicId, pkUuid: null, isDeleted: true);

      final result = await importer.importGroups([
        const PKGroup(
          id: 'gid',
          uuid: 'pk-g1',
          name: 'Resurrected?',
          memberIds: ['pk-m1'],
        ),
      ], overwriteMetadata: true);

      expect(result.groupsInserted, 0);
      expect(result.groupsPreservedAsDeletedTombstone, 1);
      // The group stays deleted; no entry was re-created.
      final active = await db.memberGroupsDao.getAllActiveGroups();
      expect(active, isEmpty,
          reason: 'a user-deleted PK group must not resurrect on pull (M13)');
      final entries = await (db.select(db.memberGroupEntries)).get();
      expect(entries, isEmpty,
          reason: 'entries of a deleted group must not be re-created (M13)');
    });

    test('a fresh (no tombstone) PK group still imports normally', () async {
      final repo = _FakeMemberRepo([_member('m1', pkUuid: 'pk-m1')]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);

      final result = await importer.importGroups([
        const PKGroup(
          id: 'gid',
          uuid: 'pk-g1',
          name: 'Fresh',
          memberIds: ['pk-m1'],
        ),
      ], overwriteMetadata: true);

      expect(result.groupsInserted, 1);
      expect(result.groupsPreservedAsDeletedTombstone, 0);
    });
  });

  // ── M14a ──────────────────────────────────────────────────────────────────
  group('M14a no-emit-when-unchanged + last_seen rate limit', () {
    test('unchanged group on a rapid second pull emits NO update', () async {
      final updates = <Map<String, Object?>>[];
      final repo = _FakeMemberRepo([]);
      final importer = PkGroupsImporter(
        db: db,
        memberRepository: repo,
        recordCreateOverride: (t, e, f) async {},
        recordUpdateOverride: (table, entityId, fields) async {
          updates.add({'table': table, 'fields': {...fields}});
        },
        recordDeleteOverride: (t, e) async {},
      );

      const group = PKGroup(id: 'gid', uuid: 'pk-g1', name: 'g', memberIds: []);
      await importer.importGroups([group], overwriteMetadata: true);
      updates.clear();

      // Immediate second pull, no identity change, no metadata change.
      await importer.importGroups([group], overwriteMetadata: false);

      final groupUpdates =
          updates.where((u) => u['table'] == 'member_groups').toList();
      expect(groupUpdates, isEmpty,
          reason: 'M14a: unchanged group must not churn an update every pull');
    });

    test('a stale (>24h) last_seen DOES refresh + emit a lone heartbeat',
        () async {
      final updates = <Map<String, Object?>>[];
      final repo = _FakeMemberRepo([]);
      final importer = PkGroupsImporter(
        db: db,
        memberRepository: repo,
        recordCreateOverride: (t, e, f) async {},
        recordUpdateOverride: (table, entityId, fields) async {
          updates.add({'table': table, 'fields': {...fields}});
        },
        recordDeleteOverride: (t, e) async {},
      );

      // Seed an existing group whose last_seen is 25h old and matching PK
      // identity (no identity change), so only the heartbeat is due.
      await _seedGroup(
        db,
        id: PkGroupsImporter.deriveGroupId('pk-g1'),
        pkUuid: 'pk-g1',
        pkId: 'gid',
        lastSeen: DateTime.now().subtract(const Duration(hours: 25)),
      );

      await importer.importGroups([
        const PKGroup(id: 'gid', uuid: 'pk-g1', name: 'g', memberIds: []),
      ], overwriteMetadata: false);

      final groupUpdates =
          updates.where((u) => u['table'] == 'member_groups').toList();
      expect(groupUpdates, hasLength(1));
      expect((groupUpdates.single['fields'] as Map).keys,
          contains('last_seen_from_pk_at'));
    });
  });

  // ── M14b ──────────────────────────────────────────────────────────────────
  group('M14b legacy alias emitted-once-then-cleaned', () {
    test('a legacy alias delete is emitted once, then the alias row is gone',
        () async {
      final deletes = <String>[];
      final repo = _FakeMemberRepo([]);
      final importer = PkGroupsImporter(
        db: db,
        memberRepository: repo,
        recordCreateOverride: (t, e, f) async {},
        recordUpdateOverride: (t, e, f) async {},
        recordDeleteOverride: (table, entityId) async {
          deletes.add('$table:$entityId');
        },
      );

      // Existing PK-linked group + a legacy alias pointing at it.
      await _seedGroup(
        db,
        id: PkGroupsImporter.deriveGroupId('pk-g1'),
        pkUuid: 'pk-g1',
        pkId: 'gid',
        lastSeen: DateTime.now().subtract(const Duration(hours: 25)),
      );
      await db.pkGroupSyncAliasesDao.upsertAlias(
        legacyEntityId: 'legacy-entity-1',
        pkGroupUuid: 'pk-g1',
        canonicalEntityId: 'pk-group:pk-g1',
      );

      // First pull (last_seen due → emits an update → triggers alias deletes).
      await importer.importGroups([
        const PKGroup(id: 'gid', uuid: 'pk-g1', name: 'g', memberIds: []),
      ], overwriteMetadata: false);

      expect(deletes, contains('member_groups:legacy-entity-1'));
      // Alias row deleted, so it cannot be re-emitted.
      final remaining =
          await db.pkGroupSyncAliasesDao.getByPkGroupUuid('pk-g1');
      expect(remaining, isEmpty);

      // Second pull (force another due update) must NOT re-emit the delete.
      deletes.clear();
      await db
          .update(db.memberGroups)
          .write(
            MemberGroupsCompanion(
              lastSeenFromPkAt: Value(
                DateTime.now().subtract(const Duration(hours: 25)),
              ),
            ),
          );
      await importer.importGroups([
        const PKGroup(id: 'gid', uuid: 'pk-g1', name: 'g', memberIds: []),
      ], overwriteMetadata: false);

      expect(
        deletes.where((d) => d.contains('legacy-entity-1')),
        isEmpty,
        reason: 'M14b: a cleaned alias delete must not re-emit forever',
      );
    });
  });

  // ── F25 ─────────────────────────────────────────────────────────────────
  group('F25 self/active alias-delete emission is guarded and purged', () {
    test(
        'a planted self-alias for the deterministic pk-group-<uuid> id emits NO '
        'delete and the alias row is purged; a genuine loser alias still emits',
        () async {
      final deletes = <String>[];
      final repo = _FakeMemberRepo([]);
      final importer = PkGroupsImporter(
        db: db,
        memberRepository: repo,
        recordCreateOverride: (t, e, f) async {},
        recordUpdateOverride: (t, e, f) async {},
        recordDeleteOverride: (table, entityId) async {
          deletes.add('$table:$entityId');
        },
      );

      // The active local group row lives under the importer's deterministic
      // hyphen-form id `pk-group-<uuid>` — the same id is every importing
      // device's own active row across the fleet.
      final selfId = PkGroupsImporter.deriveGroupId('pk-g1');
      await _seedGroup(
        db,
        id: selfId,
        pkUuid: 'pk-g1',
        pkId: 'gid',
        lastSeen: DateTime.now().subtract(const Duration(hours: 25)),
      );
      // Poison: a stale self-alias pointing the deterministic id at this uuid.
      await db.pkGroupSyncAliasesDao.upsertAlias(
        legacyEntityId: selfId,
        pkGroupUuid: 'pk-g1',
        canonicalEntityId: 'pk-group:pk-g1',
      );
      // A genuine loser alias: a random id that is NOT an active local row.
      await db.pkGroupSyncAliasesDao.upsertAlias(
        legacyEntityId: 'loser-entity-1',
        pkGroupUuid: 'pk-g1',
        canonicalEntityId: 'pk-group:pk-g1',
      );

      // Due update (last_seen 25h old) drives the alias-delete emitter.
      await importer.importGroups([
        const PKGroup(id: 'gid', uuid: 'pk-g1', name: 'g', memberIds: []),
      ], overwriteMetadata: false);

      // The self-id delete must NOT be emitted (it would tombstone peers' and
      // this device's own active row), and the poisoned alias is purged so the
      // emitter loop terminates.
      expect(
        deletes.where((d) => d.contains(selfId)),
        isEmpty,
        reason: 'F25: never emit a delete for the deterministic self-id',
      );
      expect(
        await db.pkGroupSyncAliasesDao.getByLegacyEntityId(selfId),
        isNull,
        reason: 'F25: a forbidden self-alias is purged on sight',
      );

      // The genuine loser alias still gets its one delete (convergence).
      expect(deletes, contains('member_groups:loser-entity-1'));
    });
  });

  // ── M14c ──────────────────────────────────────────────────────────────────
  // (M14c dismissal memory lives in pk_group_repair_service_test additions.)

  // ── M15a ──────────────────────────────────────────────────────────────────
  group('M15a 404 terminal cleanup gated on code 20004', () {
    test('a bare 404 (no code 20004) on refetch keeps intents (transient)',
        () async {
      final repo = _FakeMemberRepo([_member('m1', pkUuid: 'pk-m1')]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);
      await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
      await _seedEntry(
        db,
        id: 'e1',
        groupId: 'g1',
        memberId: 'm1',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-m1',
        pendingPkOp: 'push_add',
        createdAt: DateTime.now(),
      );

      final client = _ProgrammableClient();
      client.addResponses.add(const PluralKitApiError(400, 'bad'));
      // Refetch 404 WITHOUT code 20004 → transient, keep pending.
      client.getMembersResponses['pk-g1'] =
          const PluralKitApiError(404, 'proxy hiccup');

      final result = await importer.pushPendingGroupOps(
        client,
        PkSyncDirection.bidirectional,
      );

      expect(result.stranded, 0,
          reason: 'a bare 404 must NOT be treated as group-gone (M15a)');
      expect((await _findEntry(db, 'e1'))!.pendingPkOp, 'push_add',
          reason: 'intent kept for retry on a transient 404 (M15a)');
      expect(result.failed, 1);
    });

    test('a 404 WITH code 20004 on refetch triggers terminal cleanup',
        () async {
      final repo = _FakeMemberRepo([_member('m1', pkUuid: 'pk-m1')]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);
      await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
      await _seedEntry(
        db,
        id: 'e1',
        groupId: 'g1',
        memberId: 'm1',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-m1',
        pendingPkOp: 'push_add',
        createdAt: DateTime.now(),
      );

      final client = _ProgrammableClient();
      client.addResponses.add(const PluralKitApiError(404, 'gone'));
      client.getMembersResponses['pk-g1'] =
          const PluralKitApiError(404, 'group gone', code: 20004);

      final result = await importer.pushPendingGroupOps(
        client,
        PkSyncDirection.bidirectional,
      );

      expect(result.stranded, 1);
      expect((await _findEntry(db, 'e1'))!.pendingPkOp, 'none');
    });
  });

  // ── M15 retry cap ─────────────────────────────────────────────────────────
  group('M15 age-based retry cap', () {
    test('a push_add older than pushRetryMaxAge that keeps 4xx-failing is '
        'marked terminal, not retried forever', () async {
      final repo = _FakeMemberRepo([_member('m1', pkUuid: 'pk-m1')]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);
      await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
      await _seedEntry(
        db,
        id: 'e1',
        groupId: 'g1',
        memberId: 'm1',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-m1',
        pendingPkOp: 'push_add',
        // Older than the cap.
        createdAt:
            DateTime.now().subtract(PkGroupsImporter.pushRetryMaxAge * 2),
      );

      final client = _ProgrammableClient();
      client.addResponses.add(const PluralKitApiError(400, 'validation'));
      // Refetch succeeds but does NOT list the member → would otherwise stay
      // pending forever. Past the cap, it is given up on.
      client.getMembersResponses['pk-g1'] = const <String>[];

      final result = await importer.pushPendingGroupOps(
        client,
        PkSyncDirection.bidirectional,
      );

      expect(result.terminallyFailed, 1);
      expect((await _findEntry(db, 'e1'))!.pendingPkOp, 'none',
          reason: 'past-cap intent must stop churning (M15)');
    });

    test('a YOUNG failing push_add stays pending (not yet capped)', () async {
      final repo = _FakeMemberRepo([_member('m1', pkUuid: 'pk-m1')]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);
      await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
      await _seedEntry(
        db,
        id: 'e1',
        groupId: 'g1',
        memberId: 'm1',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-m1',
        pendingPkOp: 'push_add',
        createdAt: DateTime.now(),
      );

      final client = _ProgrammableClient();
      client.addResponses.add(const PluralKitApiError(400, 'validation'));
      client.getMembersResponses['pk-g1'] = const <String>[];

      final result = await importer.pushPendingGroupOps(
        client,
        PkSyncDirection.bidirectional,
      );

      expect(result.terminallyFailed, 0);
      expect(result.failed, 1);
      expect((await _findEntry(db, 'e1'))!.pendingPkOp, 'push_add');
    });
  });

  // ── M15c ──────────────────────────────────────────────────────────────────
  group('M15c poisoned bulk-add ref isolation', () {
    test('a 20003-named bad ref is dropped while the valid ref proceeds',
        () async {
      final repo = _FakeMemberRepo([
        _member('m1', pkUuid: 'pk-good'),
        _member('m2', pkUuid: 'pk-bad'),
      ]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);
      await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
      await _seedEntry(
        db,
        id: 'eGood',
        groupId: 'g1',
        memberId: 'm1',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-good',
        pendingPkOp: 'push_add',
        createdAt: DateTime.now(),
      );
      await _seedEntry(
        db,
        id: 'eBad',
        groupId: 'g1',
        memberId: 'm2',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-bad',
        pendingPkOp: 'push_add',
        createdAt: DateTime.now(),
      );

      final client = _ProgrammableClient();
      // First bulk add (both refs) → atomic 404 20003 naming the bad ref.
      client.addResponses.add(
        const PluralKitApiError(
          404,
          'Member "pk-bad" not found',
          code: 20003,
        ),
      );
      // Retry with the survivor (pk-good) succeeds (204 default).

      final result = await importer.pushPendingGroupOps(
        client,
        PkSyncDirection.bidirectional,
      );

      // The bad ref dropped terminally; the good ref pushed and cleared.
      expect(result.terminallyFailed, 1);
      expect(result.added, 1);
      expect((await _findEntry(db, 'eBad'))!.pendingPkOp, 'none',
          reason: 'poisoned ref intent dropped (M15c)');
      expect((await _findEntry(db, 'eGood'))!.pendingPkOp, 'none',
          reason: 'valid ref still pushed despite the poisoned sibling (M15c)');
      // Two add calls: the failing batch, then the survivor-only retry.
      expect(client.addCalls, hasLength(2));
      expect(client.addCalls.last.refs, ['pk-good']);
    });
  });

  // ── Verifier issue 1: auth/rate-limit must never reach the refetch/cap ──
  group('issue 1: 401/429 keep intents pending regardless of age', () {
    test('401 on the add POST: stale push_add untouched, no refetch, no cap',
        () async {
      final repo = _FakeMemberRepo([_member('m1', pkUuid: 'pk-m1')]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);
      await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
      await _seedEntry(
        db,
        id: 'e1',
        groupId: 'g1',
        memberId: 'm1',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-m1',
        pendingPkOp: 'push_add',
        // WAY past the retry cap — pre-fix, the 401 entered the 4xx
        // refetch path, the refetch 401'd the same way, and the cap
        // terminal-dropped this intent on a routine token rotation.
        createdAt:
            DateTime.now().subtract(PkGroupsImporter.pushRetryMaxAge * 3),
      );

      final client = _ProgrammableClient();
      client.addResponses.add(const PluralKitAuthError());

      final result = await importer.pushPendingGroupOps(
        client,
        PkSyncDirection.bidirectional,
      );

      expect(result.terminallyFailed, 0,
          reason: 'auth failure is environmental — never consumes the cap');
      expect(result.failed, 1);
      expect(client.getMembersCalls, isEmpty,
          reason: '401 must not trigger the refetch (same token would 401)');
      expect((await _findEntry(db, 'e1'))!.pendingPkOp, 'push_add');
    });

    test('429 on the remove POST: stale push_remove tombstone untouched',
        () async {
      final repo = _FakeMemberRepo([_member('m1', pkUuid: 'pk-m1')]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);
      await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
      await _seedEntry(
        db,
        id: 'e1',
        groupId: 'g1',
        memberId: 'm1',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-m1',
        pendingPkOp: 'push_remove',
        isDeleted: true,
        createdAt:
            DateTime.now().subtract(PkGroupsImporter.pushRetryMaxAge * 3),
      );

      final client = _ProgrammableClient();
      client.removeResponses.add(const PluralKitRateLimitError());

      final result = await importer.pushPendingGroupOps(
        client,
        PkSyncDirection.bidirectional,
      );

      // Pre-fix: cap hard-deleted the tombstone → next pull re-imported the
      // member → user's remove silently reverted fleet-wide.
      expect(result.terminallyFailed, 0);
      expect(result.removed, 0);
      expect(client.getMembersCalls, isEmpty);
      final row = await _findEntry(db, 'e1');
      expect(row, isNotNull,
          reason: '429 must never hard-delete a push_remove tombstone');
      expect(row!.isDeleted, isTrue);
      expect(row.pendingPkOp, 'push_remove');
    });

    test('401 on the REFETCH (after a generic 4xx POST) also bypasses the cap',
        () async {
      final repo = _FakeMemberRepo([_member('m1', pkUuid: 'pk-m1')]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);
      await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
      await _seedEntry(
        db,
        id: 'e1',
        groupId: 'g1',
        memberId: 'm1',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-m1',
        pendingPkOp: 'push_remove',
        isDeleted: true,
        createdAt:
            DateTime.now().subtract(PkGroupsImporter.pushRetryMaxAge * 3),
      );

      final client = _ProgrammableClient();
      client.removeResponses.add(const PluralKitApiError(400, 'bad'));
      client.getMembersResponses['pk-g1'] = const PluralKitAuthError();

      final result = await importer.pushPendingGroupOps(
        client,
        PkSyncDirection.bidirectional,
      );

      expect(result.terminallyFailed, 0);
      expect(result.failed, 1);
      final row = await _findEntry(db, 'e1');
      expect(row, isNotNull);
      expect(row!.pendingPkOp, 'push_remove');
    });
  });

  // ── Verifier issue 1(ii): the cap measures INTENT age, not row age ──────
  group('issue 1: intent-age semantics for the retry cap', () {
    test('a fresh REMOVE of an old row is NOT expired '
        '(softDeleteEntryWithPendingOp refreshes the recency stamp)',
        () async {
      final repo = _FakeMemberRepo([_member('m1', pkUuid: 'pk-m1')]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);
      await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
      // Steady-state membership: the row has existed far longer than the cap.
      await _seedEntry(
        db,
        id: 'e1',
        groupId: 'g1',
        memberId: 'm1',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-m1',
        createdAt:
            DateTime.now().subtract(PkGroupsImporter.pushRetryMaxAge * 3),
      );

      // The user removes it NOW — the DAO method the repository's
      // removeMemberFromGroup uses must refresh the stamp so the intent is
      // measured from the remove, not from row creation.
      await db.memberGroupsDao.softDeleteEntryWithPendingOp(
        'e1',
        pendingPkOp: 'push_remove',
      );

      final stamped = await _findEntry(db, 'e1');
      expect(
        stamped!.createdAt!.isAfter(
          DateTime.now().subtract(const Duration(minutes: 1)),
        ),
        isTrue,
        reason: 'setting a pending op must refresh the recency stamp',
      );

      // First push attempt fails with a generic 4xx and the refetch still
      // lists the member — pre-fix(intent-age) this was instantly "expired"
      // and the tombstone hard-deleted on the FIRST failure.
      final client = _ProgrammableClient();
      client.removeResponses.add(const PluralKitApiError(400, 'flaky'));
      client.getMembersResponses['pk-g1'] = ['pk-m1'];

      final result = await importer.pushPendingGroupOps(
        client,
        PkSyncDirection.bidirectional,
      );

      expect(result.terminallyFailed, 0,
          reason: 'a fresh remove intent must not be age-capped');
      expect(result.failed, 1);
      final row = await _findEntry(db, 'e1');
      expect(row, isNotNull);
      expect(row!.isDeleted, isTrue);
      expect(row.pendingPkOp, 'push_remove');
    });

    test('a genuinely stale push_remove intent still caps', () async {
      final repo = _FakeMemberRepo([_member('m1', pkUuid: 'pk-m1')]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);
      await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
      // The INTENT itself is old: tombstone seeded directly with a stale
      // stamp (nothing refreshed it since the remove was queued).
      await _seedEntry(
        db,
        id: 'e1',
        groupId: 'g1',
        memberId: 'm1',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-m1',
        pendingPkOp: 'push_remove',
        isDeleted: true,
        createdAt:
            DateTime.now().subtract(PkGroupsImporter.pushRetryMaxAge * 2),
      );

      final client = _ProgrammableClient();
      client.removeResponses.add(const PluralKitApiError(400, 'persistent'));
      client.getMembersResponses['pk-g1'] = ['pk-m1'];

      final result = await importer.pushPendingGroupOps(
        client,
        PkSyncDirection.bidirectional,
      );

      expect(result.terminallyFailed, 1);
      expect(await _findEntry(db, 'e1'), isNull,
          reason: 'past-cap remove intent is given up on (M15 cap intact)');
    });
  });

  // ── Verifier issue 2: CRDT revive refreshes the recency stamp ───────────
  group('issue 2: apply-onto-tombstone restamps created_at', () {
    test('a revive apply gets a fresh stamp and the H6b grace protects it',
        () async {
      // Real member row — the adapter resolves pk_member_uuid against the DB.
      await db.into(db.members).insert(
            pkFixtureMember(id: 'm1', name: 'M1', pluralkitUuid: 'pk-m1'),
          );
      await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
      // Old local tombstone for the (pk-g1, pk-m1) edge — e.g. an earlier
      // reconcile-removal. Stamp far in the past.
      final entryId = PkGroupsImporter.deriveEntryId('pk-g1', 'pk-m1');
      await _seedEntry(
        db,
        id: entryId,
        groupId: 'g1',
        memberId: 'm1',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-m1',
        isDeleted: true,
        createdAt: DateTime.now()
            .subtract(PkGroupsImporter.removalRecencyGrace * 4),
      );

      // Peer B re-adds → emits a CREATE under the deterministic id. Apply it
      // here (device A). Drift's clientDefault fires only on true INSERTs;
      // pre-fix this revive kept the ORIGINAL stamp, so A's next pull (PK
      // still missing the member — B hasn't pushed yet) reconcile-deleted
      // the revive and destroyed B's unpushed push_add (scenario A).
      final entriesEntity = buildSyncAdapterWithCompletion(db)
          .adapter
          .entities
          .singleWhere((e) => e.tableName == 'member_group_entries');
      final before = DateTime.now().subtract(const Duration(seconds: 5));
      await entriesEntity.applyFields(entryId, {
        'group_id': 'g1',
        'member_id': 'm1',
        'pk_group_uuid': 'pk-g1',
        'pk_member_uuid': 'pk-m1',
        'is_deleted': false,
      });

      final revived = await _findEntry(db, entryId);
      expect(revived, isNotNull);
      expect(revived!.isDeleted, isFalse);
      expect(revived.createdAt, isNotNull);
      expect(revived.createdAt!.isAfter(before), isTrue,
          reason: 'apply onto an existing tombstone must restamp created_at');

      // And the grace now protects the revived row against the next pull.
      final repo = _FakeMemberRepo([_member('m1', pkUuid: 'pk-m1')]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);
      final result = await importer.importGroups([
        // PK does not list the member yet (peer B hasn't pushed).
        const PKGroup(id: 'gid', uuid: 'pk-g1', name: 'g1', memberIds: []),
      ]);

      expect(result.entriesRemoved, 0);
      expect(result.entriesSkippedRecent, 1);
      expect((await _findEntry(db, entryId))!.isDeleted, isFalse,
          reason: 'H6b grace must protect the freshly-revived entry');
    });
  });

  // ── Verifier issue 3: uuid-keeping tombstones block resurrection ─────────
  group('issue 3: repair-linked (non-deterministic id) deletion preserved',
      () {
    test('deleteGroup keeps the uuid; the next pull does not resurrect',
        () async {
      final repo = _FakeMemberRepo([_member('m1', pkUuid: 'pk-m1')]);
      final importer = PkGroupsImporter(db: db, memberRepository: repo);

      // A group adopted under its ORIGINAL row id (repair's
      // linkGroupToPluralkitUuid path) — NOT the deterministic pk-group-<uuid>
      // id, so the deterministic-id tombstone lookup alone cannot see it.
      await _seedGroup(db, id: 'my-original-group', pkUuid: 'pk-g1');
      await _seedEntry(
        db,
        id: 'e1',
        groupId: 'my-original-group',
        memberId: 'm1',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-m1',
      );

      // User deletes it through the real DAO path.
      await db.memberGroupsDao.deleteGroup('my-original-group');

      final tombstone = await db.memberGroupsDao
          .getGroupByIdIncludingDeleted('my-original-group');
      expect(tombstone!.isDeleted, isTrue);
      expect(tombstone.pluralkitUuid, 'pk-g1',
          reason: 'deleteGroup must KEEP the uuid for guard findability');

      // Next pull still lists the group on PK — must NOT resurrect.
      final result = await importer.importGroups([
        const PKGroup(
          id: 'gid',
          uuid: 'pk-g1',
          name: 'Resurrected?',
          memberIds: ['pk-m1'],
        ),
      ], overwriteMetadata: true);

      expect(result.groupsInserted, 0);
      expect(result.groupsPreservedAsDeletedTombstone, 1);
      expect(await db.memberGroupsDao.getAllActiveGroups(), isEmpty);
      // The entry tombstone is untouched — not revived, not duplicated.
      final entry = await _findEntry(db, 'e1');
      expect(entry!.isDeleted, isTrue);
      final allEntries = await (db.select(db.memberGroupEntries)).get();
      expect(allEntries, hasLength(1));
    });
  });
}
