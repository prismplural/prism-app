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
    test(
      'BOTH stored entry.pkMemberUuid and current member.pluralkitUuid empty '
      '→ stranded (genuine no-link case)',
      () async {
        // The orchestrator prefers entry.pkMemberUuid (snapshot) and falls
        // back to current member.pluralkitUuid (later review [P2] fix). The
        // stranded branch only fires when neither source has a UUID — i.e.
        // a row with no stored snapshot AND a local member that's never
        // been linked to PK (or had its link cleared). Otherwise we have
        // enough to push.
        buildImporter([_member('m1')]); // current: no pkUuid
        await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
        await _seedEntry(
          db,
          id: 'e1',
          groupId: 'g1',
          memberId: 'm1',
          pkGroupUuid: 'pk-g1',
          // Stored: also no pkMemberUuid. Genuinely orphaned edge.
          pkMemberUuid: null,
          pendingPkOp: 'push_add',
        );

        final result = await importer.pushPendingGroupOps(
          client,
          PkSyncDirection.bidirectional,
        );

        expect(result.stranded, 1);
        expect(client.addCalls, isEmpty);
        expect((await _findEntry(db, 'e1'))!.pendingPkOp, 'none');
      },
    );

    test('group lost PK link AND no stored snapshot → stranded', () async {
      buildImporter([_member('m1', pkUuid: 'pk-m1')]);
      await _seedGroup(db, id: 'g1'); // no pkUuid
      await _seedEntry(
        db,
        id: 'e1',
        groupId: 'g1',
        memberId: 'm1',
        pkGroupUuid: null, // stored snapshot also missing
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

    test(
      'current member lost PK link but entry has stored snapshot → STILL '
      'pushes (the historical edge is preserved)',
      () async {
        // Companion to the [P2] regression test in the "stored vs current"
        // group: with a stored UUID, an unlinked current member doesn't
        // strand — we know what to push.
        buildImporter([_member('m1')]); // current: unlinked
        await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
        await _seedEntry(
          db,
          id: 'e1',
          groupId: 'g1',
          memberId: 'm1',
          pkGroupUuid: 'pk-g1',
          pkMemberUuid: 'pk-stored', // snapshot survives the unlink
          pendingPkOp: 'push_add',
        );

        await importer.pushPendingGroupOps(
          client,
          PkSyncDirection.bidirectional,
        );

        expect(client.addCalls.single.refs, ['pk-stored']);
        expect((await _findEntry(db, 'e1'))!.pendingPkOp, 'none');
      },
    );
  });

  group('pushPendingGroupOps stored vs current PK UUIDs', () {
    test(
      'push_remove uses entry.pkMemberUuid (snapshot) NOT current member.pluralkitUuid '
      '— so a relink mid-pending does not delete the wrong PK member',
      () async {
        // Reproduces the implementation-review [P2] regression:
        // 1. User added member-with-pk-A to group → entry stored pkMemberUuid=pk-A.
        // 2. User removed → push_remove queued.
        // 3. Before push runs, user relinks member to pk-B locally.
        // 4. Push must call /members/remove with pk-A (the entry's snapshot),
        //    NOT pk-B (the current member.pluralkitUuid). Otherwise pk-A is
        //    stranded in the PK group permanently.
        buildImporter([_member('m1', pkUuid: 'pk-B')]); // RELINKED to B
        await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
        await _seedEntry(
          db,
          id: 'e1',
          groupId: 'g1',
          memberId: 'm1',
          pkGroupUuid: 'pk-g1',
          pkMemberUuid: 'pk-A', // entry snapshot from BEFORE the relink
          pendingPkOp: 'push_remove',
          isDeleted: true,
        );

        await importer.pushPendingGroupOps(
          client,
          PkSyncDirection.bidirectional,
        );

        // Wire body must contain pk-A, not pk-B.
        expect(client.removeCalls, hasLength(1));
        expect(client.removeCalls.single.refs, ['pk-A']);
      },
    );

    test(
      'push_add uses entry.pkMemberUuid snapshot when set, falls back to '
      'current member.pluralkitUuid when entry has empty stored UUID',
      () async {
        // Two entries: one with stored UUID (must use stored), one without
        // any stored UUID at all (must fall back to current). Both push to
        // the same group so we get a single bucket with two distinct refs.
        buildImporter([
          _member('m1', pkUuid: 'pk-m1-current'),
          _member('m2', pkUuid: 'pk-m2-current'),
        ]);
        await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
        await _seedEntry(
          db,
          id: 'eStored',
          groupId: 'g1',
          memberId: 'm1',
          pkGroupUuid: 'pk-g1',
          pkMemberUuid: 'pk-m1-stored', // stored set, current differs
          pendingPkOp: 'push_add',
        );
        await _seedEntry(
          db,
          id: 'eFallback',
          groupId: 'g1',
          memberId: 'm2',
          pkGroupUuid: 'pk-g1',
          pkMemberUuid: null, // no stored snapshot — must fall back
          pendingPkOp: 'push_add',
        );

        await importer.pushPendingGroupOps(
          client,
          PkSyncDirection.bidirectional,
        );

        expect(client.addCalls, hasLength(1));
        // Set comparison because bucket order isn't guaranteed.
        expect(
          client.addCalls.single.refs.toSet(),
          {'pk-m1-stored', 'pk-m2-current'},
          reason: 'stored entry uses stored UUID; fallback entry uses '
              "the current member's pluralkitUuid",
        );
      },
    );
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

    test(
      'PK group 404 affects BOTH push_add and push_remove buckets in the '
      'same group → push_remove tombstones still hard-delete cleanly even '
      'when the add bucket runs first (2nd-pass review [P3])',
      () async {
        // Same gone group has both kinds of pending. Buckets are processed
        // add-first (per implementation), so the add bucket's 404 path
        // would clear push_remove pending first → the later remove bucket's
        // guarded DELETE would miss → zombie. The shared terminal-cleanup
        // helper hard-deletes push_remove tombstones BEFORE clearing.
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

        client.addResponses
            .add(const PluralKitApiError(404, 'group not found'));
        client.removeResponses
            .add(const PluralKitApiError(404, 'group not found'));
        // Both refetches hit the same group, both 404.
        client.getMembersResponses['pk-g1'] =
            const PluralKitApiError(404, 'group gone');

        await importer.pushPendingGroupOps(
          client,
          PkSyncDirection.bidirectional,
        );

        // The push_remove tombstone must be hard-deleted regardless of
        // which bucket ran first. Without the cross-bucket fix, the row
        // would be left as soft-deleted-pending=none zombie.
        expect(await _findEntry(db, 'eRem'), isNull,
            reason: 'tombstone must be hard-deleted, not stranded as zombie');
        // The push_add row stays active (gone PK group, no destructive
        // local action), pending cleared.
        final addRow = await _findEntry(db, 'eAdd');
        expect(addRow, isNotNull);
        expect(addRow!.isDeleted, isFalse);
        expect(addRow.pendingPkOp, 'none');
      },
    );

    test(
      'PK group 404 during REMOVE-bucket refetch → hard-delete the tombstone '
      'AND clear any other pending in the group (later review [P3] order fix)',
      () async {
        // Seed two pending rows in the same PK group: one push_remove (the
        // bucket we are pushing) and one push_add (an unrelated row that
        // group-404 should also clear pending on).
        buildImporter([
          _member('m1', pkUuid: 'pk-m1'),
          _member('m2', pkUuid: 'pk-m2'),
        ]);
        await _seedGroup(db, id: 'g1', pkUuid: 'pk-g1');
        await _seedEntry(
          db,
          id: 'eRemove',
          groupId: 'g1',
          memberId: 'm1',
          pkGroupUuid: 'pk-g1',
          pkMemberUuid: 'pk-m1',
          pendingPkOp: 'push_remove',
          isDeleted: true,
        );
        await _seedEntry(
          db,
          id: 'eAddCohabit',
          groupId: 'g1',
          memberId: 'm2',
          pkGroupUuid: 'pk-g1',
          pkMemberUuid: 'pk-m2',
          pendingPkOp: 'push_add',
        );
        // Force the remove POST to 4xx and the refetch to 404. Any add
        // POSTs in this run must not interfere.
        client.removeResponses.add(const PluralKitApiError(404, 'not found'));
        client.getMembersResponses['pk-g1'] =
            const PluralKitApiError(404, 'group gone');

        final result = await importer.pushPendingGroupOps(
          client,
          PkSyncDirection.bidirectional,
        );

        // Pre-fix bug: clearAllPendingPkOpForGroup ran first, wiping the
        // push_remove value the guarded DELETE matches on, so DELETE missed
        // and removed=0 with the row left as a soft-deleted zombie.
        // Post-fix: DELETE runs first (still push_remove ∧ is_deleted=true),
        // THEN clearAllPendingPkOpForGroup tidies the rest.
        expect(result.removed, 1);
        expect(await _findEntry(db, 'eRemove'), isNull,
            reason: 'tombstone must be hard-deleted, not stranded');
        // The cohabit push_add row had its pending cleared by the
        // clear-all step (group is gone, can't push to it).
        final cohabit = await _findEntry(db, 'eAddCohabit');
        expect(cohabit!.pendingPkOp, 'none');
      },
    );
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
