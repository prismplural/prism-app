// Regression test: deep PluralKit group hierarchies must survive the data
// model without depth clamping. Before this PR the UI capped interaction at
// depth 5; that cap is now removed. This test verifies that:
//   1. The importer can persist 10 PK-sourced groups to the database.
//   2. The database rows accept arbitrary parent chains (parentGroupId wiring).
//   3. GroupTreeUtils.getGroupDepth reports the correct depth (10) for the
//      resulting tree — the depth-clamping guard the UI previously relied on
//      is not present in the data layer.
//
// PluralKit's API does not carry parent-group information; the nesting
// hierarchy is a local Prism concept set after import. The test therefore
// imports the flat PK payload and then wires the parent chain via a DB
// update — exactly as Prism's group-management layer would do.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/repositories/member_repository.dart';
import 'package:prism_plurality/features/members/utils/group_tree_utils.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_groups_importer.dart';

// ---------------------------------------------------------------------------
// Minimal fake member repository — no members needed for a group-only import.
// ---------------------------------------------------------------------------

class _EmptyMemberRepo implements MemberRepository {
  @override
  Future<List<domain.Member>> getAllMembers() async => const [];

  @override
  Future<List<domain.Member>> getAllMembersIncludingDeleted() async => const [];

  @override
  Future<domain.Member?> getMemberById(String id) async => null;

  @override
  Future<List<domain.Member>> getMembersByIds(List<String> ids) async =>
      const [];

  @override
  Stream<List<domain.Member>> watchMembersByIds(List<String> ids) =>
      throw UnimplementedError();

  @override
  Future<void> createMember(domain.Member m) async {}

  @override
  Future<void> updateMember(domain.Member m) async {}

  @override
  Future<int> updateMemberFields(
    String id,
    Map<String, dynamic> changedFields,
  ) async => 0;

  @override
  Future<void> deleteMember(String id) async {}

  @override
  Stream<List<domain.Member>> watchAllMembers() => throw UnimplementedError();

  @override
  Stream<List<domain.Member>> watchActiveMembers() =>
      throw UnimplementedError();

  @override
  Stream<domain.Member?> watchMemberById(String id) =>
      throw UnimplementedError();

  @override
  Future<int> getCount() async => 0;

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

void main() {
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    // Initialise settings row so the importer's _pkGroupSyncV2Enabled() query
    // works against the in-memory database.
    await db.systemSettingsDao.getSettings();
    await db.systemSettingsDao.updatePkGroupSyncV2Enabled(false);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    '10-deep PluralKit group chain lands in DB with parent chain intact',
    () async {
      // Build 10 synthetic PK group records. PluralKit groups carry no parent
      // field — nesting is a local Prism concept established post-import.
      // We still need the import to succeed for all 10 before we can wire them.
      final pkGroups = <PKGroup>[
        for (var i = 0; i < 10; i++)
          PKGroup(
            id: 'g${i.toString().padLeft(5, '0')}', // 5-char PK short ID
            uuid: 'pk-uuid-$i',
            name: 'Group $i',
            memberIds: const [], // empty membership — no member repo needed
          ),
      ];

      final importer = PkGroupsImporter(
        db: db,
        memberRepository: _EmptyMemberRepo(),
      );

      final importResult = await importer.importGroups(pkGroups);

      // Assert all 10 groups were inserted by the importer.
      expect(importResult.groupsInserted, 10,
          reason: 'importer must persist all 10 PK groups');

      // Wire the parent chain: g1 → g0, g2 → g1, …, g9 → g8.
      // This mirrors what Prism's group-management layer does when a user
      // arranges groups into a hierarchy after (or during) a PK import.
      for (var i = 1; i < 10; i++) {
        final childLocalId = PkGroupsImporter.deriveGroupId('pk-uuid-$i');
        final parentLocalId = PkGroupsImporter.deriveGroupId('pk-uuid-${i - 1}');
        await (db.update(db.memberGroups)
              ..where((g) => g.id.equals(childLocalId)))
            .write(MemberGroupsCompanion(parentGroupId: Value(parentLocalId)));
      }

      // Read all active groups back from the database.
      final rows = await db.memberGroupsDao.getAllActiveGroups();
      expect(rows.length, 10, reason: 'all 10 imported groups must be active');

      // Convert DB rows to domain MemberGroup objects for GroupTreeUtils.
      final groups = rows.map((row) {
        return MemberGroup(
          id: row.id,
          name: row.name,
          parentGroupId: row.parentGroupId,
          createdAt: row.createdAt,
        );
      }).toList();

      // Build the in-memory tree and assert depth at the leaf node (g9).
      final leafLocalId = PkGroupsImporter.deriveGroupId('pk-uuid-9');
      final tree = GroupTreeUtils.buildGroupTree(groups);
      final depth = GroupTreeUtils.getGroupDepth(leafLocalId, tree);

      expect(depth, 10,
          reason:
              'GroupTreeUtils must report depth 10 for the leaf of a '
              'PK-imported depth-10 chain; depth was previously clamped by '
              'the UI at 5 — this regression locks in the removal of that cap');
    },
  );
}
