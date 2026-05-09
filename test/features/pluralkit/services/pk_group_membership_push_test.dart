// Tests for the PK group-membership push orchestrator (step 6 of
// docs/plans/pk-group-membership-push.md).
//
// These cover the orchestrator's full state machine: pre-push validation
// with CRDT compensation, stale-link terminal policy, bucketed POSTs,
// guarded 204 cleanup, 4xx refetch-and-compare, and PK 404 group policy.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_groups_importer.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';

class _FakeMemberRepo implements MemberRepository {
  _FakeMemberRepo(this.members);
  final List<domain.Member> members;

  @override
  Future<domain.Member?> getMemberById(String id) async {
    for (final m in members) {
      if (m.id == id) return m;
    }
    return null;
  }

  @override
  Future<List<domain.Member>> getMembersByIds(List<String> ids) async =>
      members.where((m) => ids.contains(m.id)).toList();

  @override
  Future<List<domain.Member>> getAllMembers() async => members;
  @override
  Future<List<domain.Member>> getAllMembersIncludingDeleted() async => members;
  @override
  Future<int> getCount() async => members.length;

  // Intentionally unimplemented — orchestrator never calls these in tests.
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
  Future<void> stampDeletePushStartedAt(String id, int timestampMs) async =>
      throw UnimplementedError();
  @override
  Future<void> updateMember(domain.Member m) async => throw UnimplementedError();
  @override
  Stream<List<domain.Member>> watchActiveMembers() => throw UnimplementedError();
  @override
  Stream<List<domain.Member>> watchAllMembers() => throw UnimplementedError();
  @override
  Stream<domain.Member?> watchMemberById(String id) => throw UnimplementedError();
  @override
  Stream<List<domain.Member>> watchMembersByIds(List<String> ids) =>
      throw UnimplementedError();
  @override
  Future<({domain.Member member, bool wasCreated})> ensureUnknownSentinelMember() =>
      throw UnimplementedError();
}

/// Programmable PluralKit client. Each method records its calls so tests can
/// assert wire shape; canned responses can be wired per method via setters.
class _ProgrammableClient implements PluralKitClient {
  final List<({String groupRef, List<String> refs})> addCalls = [];
  final List<({String groupRef, List<String> refs})> removeCalls = [];
  final List<String> getMembersCalls = [];

  /// Default: 204. Override per call by mutating the queue.
  final List<Object> addResponses = [];
  final List<Object> removeResponses = [];
  final Map<String, Object> getMembersResponses = {};

  @override
  Future<void> addMembersToGroup(String groupRef, List<String> refs) async {
    addCalls.add((groupRef: groupRef, refs: refs));
    final next =
        addResponses.isEmpty ? null : addResponses.removeAt(0);
    if (next is Exception) throw next;
  }

  @override
  Future<void> removeMembersFromGroup(
    String groupRef,
    List<String> refs,
  ) async {
    removeCalls.add((groupRef: groupRef, refs: refs));
    final next =
        removeResponses.isEmpty ? null : removeResponses.removeAt(0);
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
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

domain.Member _member(String id, {String? pkUuid}) => domain.Member(
      id: id,
      name: id,
      createdAt: DateTime.utc(2026, 1, 1),
      pluralkitUuid: pkUuid,
    );

Future<void> _seedGroup(
  AppDatabase db, {
  required String id,
  String? pkUuid,
}) {
  return db.into(db.memberGroups).insert(
        MemberGroupsCompanion.insert(
          id: id,
          name: id,
          createdAt: DateTime.utc(2026, 1, 1),
          pluralkitUuid: Value(pkUuid),
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
  required String pendingPkOp,
  bool isDeleted = false,
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
        ),
      );
}

Future<MemberGroupEntryRow?> _findEntry(
  AppDatabase db,
  String entryId,
) async {
  final rows =
      await (db.select(db.memberGroupEntries)..where((e) => e.id.equals(entryId)))
          .get();
  return rows.isEmpty ? null : rows.single;
}

void main() {
  late AppDatabase db;
  late PkGroupsImporter importer;
  late _ProgrammableClient client;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    client = _ProgrammableClient();
  });

  tearDown(() async {
    await db.close();
  });

  void buildImporter(List<domain.Member> members) {
    importer = PkGroupsImporter(
      db: db,
      memberRepository: _FakeMemberRepo(members),
    );
  }

  group('pushPendingGroupOps direction gating', () {
    test('pullOnly direction returns empty result and makes no PK calls',
        () async {
      buildImporter([_member('m1', pkUuid: 'pk-m1')]);
      await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
      await _seedEntry(
        db,
        id: 'e1',
        groupId: 'g1',
        memberId: 'm1',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-m1',
        pendingPkOp: 'push_add',
      );

      final result = await importer.pushPendingGroupOps(
        client,
        PkSyncDirection.pullOnly,
      );

      expect(result.added, 0);
      expect(client.addCalls, isEmpty);
      // Pending row must be untouched.
      final entry = await _findEntry(db, 'e1');
      expect(entry!.pendingPkOp, 'push_add');
    });

    test('disabled direction returns empty', () async {
      buildImporter([]);
      final result = await importer.pushPendingGroupOps(
        client,
        PkSyncDirection.disabled,
      );
      expect(result.added, 0);
      expect(result.removed, 0);
      expect(client.addCalls, isEmpty);
    });
  });

  group('pushPendingGroupOps push_add bucket', () {
    test('204 → guarded UPDATE clears pending; member is added to PK',
        () async {
      buildImporter([
        _member('m1', pkUuid: 'pk-m1'),
        _member('m2', pkUuid: 'pk-m2'),
      ]);
      await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
      await _seedEntry(
        db,
        id: 'e1',
        groupId: 'g1',
        memberId: 'm1',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-m1',
        pendingPkOp: 'push_add',
      );
      await _seedEntry(
        db,
        id: 'e2',
        groupId: 'g1',
        memberId: 'm2',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-m2',
        pendingPkOp: 'push_add',
      );

      final result = await importer.pushPendingGroupOps(
        client,
        PkSyncDirection.bidirectional,
      );

      expect(result.added, 2);
      expect(client.addCalls, hasLength(1));
      expect(client.addCalls.single.groupRef, 'pk-g1');
      expect(client.addCalls.single.refs.toSet(), {'pk-m1', 'pk-m2'});

      // Both entries cleaned up to pending=none.
      expect((await _findEntry(db, 'e1'))!.pendingPkOp, 'none');
      expect((await _findEntry(db, 'e2'))!.pendingPkOp, 'none');
    });

    test(
      '4xx + refetch shows member NOW in PK → cleanup as if 204',
      () async {
        buildImporter([_member('m1', pkUuid: 'pk-m1')]);
        await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
        await _seedEntry(
          db,
          id: 'e1',
          groupId: 'g1',
          memberId: 'm1',
          pkGroupUuid: 'pk-g1',
          pkMemberUuid: 'pk-m1',
          pendingPkOp: 'push_add',
        );

        client.addResponses.add(const PluralKitApiError(400, 'bad request'));
        client.getMembersResponses['pk-g1'] = ['pk-m1'];

        final result = await importer.pushPendingGroupOps(
          client,
          PkSyncDirection.bidirectional,
        );

        expect(result.added, 1);
        expect(result.failed, 0);
        expect((await _findEntry(db, 'e1'))!.pendingPkOp, 'none');
      },
    );

    test(
      '4xx + refetch shows member NOT in PK → leave pending; per-entry failure',
      () async {
        buildImporter([_member('m1', pkUuid: 'pk-m1')]);
        await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
        await _seedEntry(
          db,
          id: 'e1',
          groupId: 'g1',
          memberId: 'm1',
          pkGroupUuid: 'pk-g1',
          pkMemberUuid: 'pk-m1',
          pendingPkOp: 'push_add',
        );

        client.addResponses.add(const PluralKitApiError(400, 'bad request'));
        client.getMembersResponses['pk-g1'] = const <String>[]; // not present

        final result = await importer.pushPendingGroupOps(
          client,
          PkSyncDirection.bidirectional,
        );

        expect(result.added, 0);
        expect(result.failed, 1);
        // Group-absence does NOT terminally clear push_add (cleanup-pass [P2]).
        expect((await _findEntry(db, 'e1'))!.pendingPkOp, 'push_add');
      },
    );

    test('5xx → leave pending; per-entry failure', () async {
      buildImporter([_member('m1', pkUuid: 'pk-m1')]);
      await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
      await _seedEntry(
        db,
        id: 'e1',
        groupId: 'g1',
        memberId: 'm1',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-m1',
        pendingPkOp: 'push_add',
      );

      client.addResponses.add(const PluralKitApiError(500, 'server error'));

      final result = await importer.pushPendingGroupOps(
        client,
        PkSyncDirection.bidirectional,
      );

      expect(result.failed, 1);
      // Refetch must NOT have happened — 5xx isn't 4xx.
      expect(client.getMembersCalls, isEmpty);
      expect((await _findEntry(db, 'e1'))!.pendingPkOp, 'push_add');
    });
  });

  group('pushPendingGroupOps push_remove bucket', () {
    test('204 → guarded DELETE removes the soft-deleted tombstone', () async {
      buildImporter([_member('m1', pkUuid: 'pk-m1')]);
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
      );

      final result = await importer.pushPendingGroupOps(
        client,
        PkSyncDirection.bidirectional,
      );

      expect(result.removed, 1);
      expect(client.removeCalls, hasLength(1));
      expect(client.removeCalls.single.refs, ['pk-m1']);
      // Row hard-deleted — gone from DB.
      expect(await _findEntry(db, 'e1'), isNull);
    });

    test(
      '4xx + refetch confirms member not in PK → DELETE (desired remove '
      'satisfied)',
      () async {
        buildImporter([_member('m1', pkUuid: 'pk-m1')]);
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
        );

        client.removeResponses
            .add(const PluralKitApiError(400, 'not member'));
        client.getMembersResponses['pk-g1'] = const <String>[];

        final result = await importer.pushPendingGroupOps(
          client,
          PkSyncDirection.bidirectional,
        );

        expect(result.removed, 1);
        expect(await _findEntry(db, 'e1'), isNull);
      },
    );
  });

  group('pushPendingGroupOps pre-push compensation', () {
    test(
      'push_add ∧ is_deleted=1 → flips to push_remove, no PK call this round',
      () async {
        buildImporter([_member('m1', pkUuid: 'pk-m1')]);
        await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
        // CRDT delete from another device flipped is_deleted to true while
        // pending_pk_op stayed push_add. Orchestrator must compensate.
        await _seedEntry(
          db,
          id: 'e1',
          groupId: 'g1',
          memberId: 'm1',
          pkGroupUuid: 'pk-g1',
          pkMemberUuid: 'pk-m1',
          pendingPkOp: 'push_add',
          isDeleted: true,
        );

        final result = await importer.pushPendingGroupOps(
          client,
          PkSyncDirection.bidirectional,
        );

        expect(result.compensated, 1);
        expect(client.addCalls, isEmpty);
        expect(client.removeCalls, isEmpty);

        final entry = await _findEntry(db, 'e1');
        expect(entry!.pendingPkOp, 'push_remove');
        expect(entry.isDeleted, isTrue);
      },
    );

    test(
      'push_remove ∧ is_deleted=0 → flips to push_add, no PK call this round',
      () async {
        buildImporter([_member('m1', pkUuid: 'pk-m1')]);
        await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
        await _seedEntry(
          db,
          id: 'e1',
          groupId: 'g1',
          memberId: 'm1',
          pkGroupUuid: 'pk-g1',
          pkMemberUuid: 'pk-m1',
          pendingPkOp: 'push_remove',
          isDeleted: false,
        );

        final result = await importer.pushPendingGroupOps(
          client,
          PkSyncDirection.bidirectional,
        );

        expect(result.compensated, 1);
        expect(client.addCalls, isEmpty);

        final entry = await _findEntry(db, 'e1');
        expect(entry!.pendingPkOp, 'push_add');
        expect(entry.isDeleted, isFalse);
      },
    );
  });

  group('pushPendingGroupOps stale-link policy', () {
    test('member lost PK link → pending cleared, no PK call', () async {
      buildImporter([_member('m1')]); // no pkUuid
      await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
      await _seedEntry(
        db,
        id: 'e1',
        groupId: 'g1',
        memberId: 'm1',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-m1',
        pendingPkOp: 'push_add',
      );

      final result = await importer.pushPendingGroupOps(
        client,
        PkSyncDirection.bidirectional,
      );

      expect(result.stranded, 1);
      expect(client.addCalls, isEmpty);
      expect((await _findEntry(db, 'e1'))!.pendingPkOp, 'none');
    });

    test('group lost PK link → pending cleared, no PK call', () async {
      buildImporter([_member('m1', pkUuid: 'pk-m1')]);
      await _seedGroup(db, id: 'g1'); // no pkUuid
      await _seedEntry(
        db,
        id: 'e1',
        groupId: 'g1',
        memberId: 'm1',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-m1',
        pendingPkOp: 'push_add',
      );

      final result = await importer.pushPendingGroupOps(
        client,
        PkSyncDirection.bidirectional,
      );

      expect(result.stranded, 1);
      expect(client.addCalls, isEmpty);
      expect((await _findEntry(db, 'e1'))!.pendingPkOp, 'none');
    });
  });

  group('pushPendingGroupOps refetch 404', () {
    test('PK group 404 during refetch → clear all pending in group',
        () async {
      buildImporter([_member('m1', pkUuid: 'pk-m1')]);
      await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
      await _seedEntry(
        db,
        id: 'e1',
        groupId: 'g1',
        memberId: 'm1',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-m1',
        pendingPkOp: 'push_add',
      );

      client.addResponses.add(const PluralKitApiError(404, 'not found'));
      client.getMembersResponses['pk-g1'] =
          const PluralKitApiError(404, 'group gone');

      final result = await importer.pushPendingGroupOps(
        client,
        PkSyncDirection.bidirectional,
      );

      expect(result.stranded, 1);
      expect((await _findEntry(db, 'e1'))!.pendingPkOp, 'none');
    });
  });

  group('pushPendingGroupOps mutex', () {
    test('parallel calls share a single in-flight push', () async {
      buildImporter([_member('m1', pkUuid: 'pk-m1')]);
      await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
      await _seedEntry(
        db,
        id: 'e1',
        groupId: 'g1',
        memberId: 'm1',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-m1',
        pendingPkOp: 'push_add',
      );

      final f1 =
          importer.pushPendingGroupOps(client, PkSyncDirection.bidirectional);
      final f2 =
          importer.pushPendingGroupOps(client, PkSyncDirection.bidirectional);
      final r1 = await f1;
      final r2 = await f2;

      // Same Future (same result instance).
      expect(identical(r1, r2), isTrue);
      // Exactly one HTTP call despite two callers.
      expect(client.addCalls, hasLength(1));
    });
  });

  group('pushPendingGroupOps mixed batch', () {
    test('one group with both push_add and push_remove → two PK calls',
        () async {
      buildImporter([
        _member('m1', pkUuid: 'pk-m1'),
        _member('m2', pkUuid: 'pk-m2'),
      ]);
      await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
      await _seedEntry(
        db,
        id: 'eAdd',
        groupId: 'g1',
        memberId: 'm1',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-m1',
        pendingPkOp: 'push_add',
      );
      await _seedEntry(
        db,
        id: 'eRem',
        groupId: 'g1',
        memberId: 'm2',
        pkGroupUuid: 'pk-g1',
        pkMemberUuid: 'pk-m2',
        pendingPkOp: 'push_remove',
        isDeleted: true,
      );

      final result = await importer.pushPendingGroupOps(
        client,
        PkSyncDirection.bidirectional,
      );

      expect(result.added, 1);
      expect(result.removed, 1);
      expect(client.addCalls, hasLength(1));
      expect(client.removeCalls, hasLength(1));
      expect(await _findEntry(db, 'eRem'), isNull);
      expect((await _findEntry(db, 'eAdd'))!.pendingPkOp, 'none');
    });
  });
}
