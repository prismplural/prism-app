/// Integration test: PluralKit group-membership bidirectional push against
/// the live PK API.
///
/// Excluded from CI. Run manually with a PluralKit token in PK_TOKEN:
///   PK_TOKEN=your-token flutter test --tags integration \
///     test/features/pluralkit/services/pk_group_membership_push_integration_test.dart
///
/// The test hits the live PluralKit API — use a dedicated test account.
///
/// What this covers (gap from unit tests against fakes):
///   * The wire body shape — raw JSON array, not {"members": [...]} — actually
///     accepted by PluralKit and produces 204.
///   * The orchestrator's full pipeline against real network timing, real PK
///     rate limits, and real PK group/member state.
///   * The reporter's bug end-to-end: queue a local push_add → run the
///     orchestrator → verify PK contains the member afterwards.
///
/// Safety:
///   * If PK_TOKEN is unset, every test is skipped.
///   * Each test cleans up after itself (removes any members it added back to
///     PK groups). A teardownAll restores the test group to its pre-test
///     membership as a belt-and-suspenders pass.
@Tags(['integration'])
library;

import 'dart:io' show Platform;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_groups_importer.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_client.dart';

String? get _tokenOrNull {
  final env = Platform.environment['PK_TOKEN'];
  if (env == null || env.trim().isEmpty) return null;
  return env;
}

String get _token => _tokenOrNull!;

bool get _skipAll => _tokenOrNull == null;

String get _skipReason =>
    'PK_TOKEN env var not set — skipping live PluralKit integration tests';

void main() {
  group(
    'PluralKit group membership push — live API',
    () {
      late AppDatabase db;
      late PluralKitClient client;
      // Discovered at setup: the test group + its baseline members.
      late String testGroupUuid;
      late Set<String> baselineGroupMembers;
      late List<String> allMemberUuids;

      setUpAll(() async {
        client = PluralKitClient(token: _token, httpClient: http.Client());
        // Discover state of the test account.
        final groups = await client.getGroups(withMembers: true);
        if (groups.isEmpty) {
          throw StateError(
            'Test PK account has no groups. These tests need at least one '
            'group to add/remove members from.',
          );
        }
        testGroupUuid = groups.first.uuid;
        baselineGroupMembers = (groups.first.memberIds ?? const <String>[]).toSet();
        final allMembers = await client.getMembers();
        allMemberUuids = allMembers.map((m) => m.uuid).toList();
        if (allMemberUuids.length < 2) {
          throw StateError(
            'Test PK account needs at least 2 members. Has ${allMemberUuids.length}.',
          );
        }
      });

      setUp(() {
        db = AppDatabase(NativeDatabase.memory());
      });

      tearDown(() async {
        await db.close();
        // Restore baseline membership after each test, regardless of what the
        // test did. If any test left non-baseline members in the group, this
        // removes them.
        try {
          final current =
              (await client.getGroupMembers(testGroupUuid)).toSet();
          final extras = current.difference(baselineGroupMembers).toList();
          if (extras.isNotEmpty) {
            await client.removeMembersFromGroup(testGroupUuid, extras);
          }
          final missing = baselineGroupMembers.difference(current).toList();
          if (missing.isNotEmpty) {
            await client.addMembersToGroup(testGroupUuid, missing);
          }
        } catch (_) {
          // Best-effort cleanup.
        }
      });

      tearDownAll(() async {
        client.dispose();
      });

      // ─── Wire-shape sanity (the v1 plan's [P1] body-shape assumption) ────

      test(
        'addMembersToGroup with a raw JSON array body produces 204 and the '
        'member appears in PK\'s group listing',
        () async {
          // Pick a member NOT already in the group.
          final candidate = allMemberUuids.firstWhere(
            (uuid) => !baselineGroupMembers.contains(uuid),
            orElse: () => throw StateError(
              'No member outside baseline available for add test',
            ),
          );

          await client.addMembersToGroup(testGroupUuid, [candidate]);

          final after =
              (await client.getGroupMembers(testGroupUuid)).toSet();
          expect(after, contains(candidate));
        },
        timeout: const Timeout(Duration(minutes: 1)),
        skip: _skipAll ? _skipReason : false,
      );

      test(
        'removeMembersFromGroup with raw JSON array body produces 204 and '
        'the member disappears from PK\'s group listing',
        () async {
          final candidate = allMemberUuids.firstWhere(
            (uuid) => !baselineGroupMembers.contains(uuid),
            orElse: () => throw StateError('No spare member'),
          );

          // Setup: add then remove.
          await client.addMembersToGroup(testGroupUuid, [candidate]);
          await client.removeMembersFromGroup(testGroupUuid, [candidate]);

          final after =
              (await client.getGroupMembers(testGroupUuid)).toSet();
          expect(after, isNot(contains(candidate)));
        },
        timeout: const Timeout(Duration(minutes: 1)),
        skip: _skipAll ? _skipReason : false,
      );

      // ─── End-to-end orchestrator (the reporter's bug) ───────────────────

      test(
        'pushPendingGroupOps drains a push_add intent to PK end-to-end '
        '(reporter bug repro: local add reaches PluralKit)',
        () async {
          final candidate = allMemberUuids.firstWhere(
            (uuid) => !baselineGroupMembers.contains(uuid),
            orElse: () => throw StateError('No spare member'),
          );

          // Set up local DB to mirror what would exist after pull-then-add:
          // a PK-linked group, a PK-linked member, and a pending push_add
          // entry queued by the repository.
          final memberRepo = DriftMemberRepository(db.membersDao, null);
          final group = await _seedLocalGroup(
            db,
            id: 'local-group-1',
            pkUuid: testGroupUuid,
          );
          final member = await _seedLocalMember(
            memberRepo,
            id: 'local-member-1',
            pkUuid: candidate,
          );
          await _seedPendingEntry(
            db,
            id: 'pending-1',
            groupId: group,
            memberId: member,
            pkGroupUuid: testGroupUuid,
            pkMemberUuid: candidate,
            pendingPkOp: 'push_add',
            isDeleted: false,
          );

          final importer = PkGroupsImporter(
            db: db,
            memberRepository: memberRepo,
          );

          final result = await importer.pushPendingGroupOps(
            client,
            PkSyncDirection.bidirectional,
          );

          expect(result.added, 1,
              reason: 'orchestrator should report one successful add');
          expect(result.failed, 0);

          // PK side: the member is now in the group.
          final after =
              (await client.getGroupMembers(testGroupUuid)).toSet();
          expect(after, contains(candidate),
              reason: 'reporter\'s bug regression: local push_add must reach PK');

          // Local side: pending cleared to none, row still active.
          final stored =
              (await db.select(db.memberGroupEntries).get()).single;
          expect(stored.pendingPkOp, 'none');
          expect(stored.isDeleted, isFalse);
        },
        timeout: const Timeout(Duration(minutes: 1)),
        skip: _skipAll ? _skipReason : false,
      );

      test(
        'pushPendingGroupOps drains a push_remove intent to PK end-to-end',
        () async {
          final candidate = allMemberUuids.firstWhere(
            (uuid) => !baselineGroupMembers.contains(uuid),
            orElse: () => throw StateError('No spare member'),
          );

          // Pre-seed: actually add the member to PK so we have something
          // real to remove.
          await client.addMembersToGroup(testGroupUuid, [candidate]);

          final memberRepo = DriftMemberRepository(db.membersDao, null);
          final group = await _seedLocalGroup(
            db,
            id: 'local-group-1',
            pkUuid: testGroupUuid,
          );
          final member = await _seedLocalMember(
            memberRepo,
            id: 'local-member-1',
            pkUuid: candidate,
          );
          await _seedPendingEntry(
            db,
            id: 'pending-rem-1',
            groupId: group,
            memberId: member,
            pkGroupUuid: testGroupUuid,
            pkMemberUuid: candidate,
            pendingPkOp: 'push_remove',
            isDeleted: true, // soft-deleted tombstone
          );

          final importer = PkGroupsImporter(
            db: db,
            memberRepository: memberRepo,
          );

          final result = await importer.pushPendingGroupOps(
            client,
            PkSyncDirection.bidirectional,
          );

          expect(result.removed, 1,
              reason: 'orchestrator should report one successful remove');
          expect(result.failed, 0);

          // PK side: member gone.
          final after =
              (await client.getGroupMembers(testGroupUuid)).toSet();
          expect(after, isNot(contains(candidate)));

          // Local side: row hard-deleted.
          final remaining = await db.select(db.memberGroupEntries).get();
          expect(remaining, isEmpty,
              reason: 'guarded DELETE should hard-remove the tombstone');
        },
        timeout: const Timeout(Duration(minutes: 1)),
        skip: _skipAll ? _skipReason : false,
      );

      test(
        'second pushPendingGroupOps after success is a no-op '
        '(idempotent — pending was cleared on first run)',
        () async {
          final candidate = allMemberUuids.firstWhere(
            (uuid) => !baselineGroupMembers.contains(uuid),
            orElse: () => throw StateError('No spare member'),
          );

          final memberRepo = DriftMemberRepository(db.membersDao, null);
          final group = await _seedLocalGroup(
            db,
            id: 'local-group-1',
            pkUuid: testGroupUuid,
          );
          final member = await _seedLocalMember(
            memberRepo,
            id: 'local-member-1',
            pkUuid: candidate,
          );
          await _seedPendingEntry(
            db,
            id: 'pending-idem-1',
            groupId: group,
            memberId: member,
            pkGroupUuid: testGroupUuid,
            pkMemberUuid: candidate,
            pendingPkOp: 'push_add',
            isDeleted: false,
          );

          final importer = PkGroupsImporter(
            db: db,
            memberRepository: memberRepo,
          );

          final r1 = await importer.pushPendingGroupOps(
            client,
            PkSyncDirection.bidirectional,
          );
          expect(r1.added, 1);

          // Second run: no pending rows, should issue zero PK calls and
          // return an empty result.
          final r2 = await importer.pushPendingGroupOps(
            client,
            PkSyncDirection.bidirectional,
          );
          expect(r2.added, 0);
          expect(r2.removed, 0);
          expect(r2.failed, 0);
        },
        timeout: const Timeout(Duration(minutes: 1)),
        skip: _skipAll ? _skipReason : false,
      );
    },
    skip: _skipAll ? _skipReason : false,
  );
}

// ─── Helpers ──────────────────────────────────────────────────────────────

Future<String> _seedLocalGroup(
  AppDatabase db, {
  required String id,
  required String pkUuid,
}) async {
  await db.into(db.memberGroups).insert(
        MemberGroupsCompanion.insert(
          id: id,
          name: id,
          createdAt: DateTime.utc(2026, 1, 1),
          pluralkitUuid: Value(pkUuid),
        ),
      );
  return id;
}

Future<String> _seedLocalMember(
  MemberRepository repo,
  {required String id, required String pkUuid}) async {
  await repo.createMember(
    domain.Member(
      id: id,
      name: id,
      createdAt: DateTime.utc(2026, 1, 1),
      pluralkitUuid: pkUuid,
    ),
  );
  return id;
}

Future<void> _seedPendingEntry(
  AppDatabase db, {
  required String id,
  required String groupId,
  required String memberId,
  required String pkGroupUuid,
  required String pkMemberUuid,
  required String pendingPkOp,
  required bool isDeleted,
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
