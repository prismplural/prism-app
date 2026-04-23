import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/pk_group_sync_aliases_dao.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_repair_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

MemberGroupsCompanion _group({
  required String id,
  required String name,
  required DateTime createdAt,
  String? pluralkitUuid,
  String? parentGroupId,
}) => MemberGroupsCompanion.insert(
  id: id,
  name: name,
  createdAt: createdAt,
  displayOrder: const Value(0),
  parentGroupId: Value(parentGroupId),
  pluralkitUuid: Value(pluralkitUuid),
);

MembersCompanion _member({
  required String id,
  required String name,
  String? pluralkitUuid,
}) => MembersCompanion.insert(
  id: id,
  name: name,
  createdAt: DateTime(2024, 1, 1),
  pluralkitUuid: Value(pluralkitUuid),
);

MemberGroupEntriesCompanion _entry({
  required String id,
  required String groupId,
  required String memberId,
  String? pkGroupUuid,
  String? pkMemberUuid,
}) => MemberGroupEntriesCompanion.insert(
  id: id,
  groupId: groupId,
  memberId: memberId,
  pkGroupUuid: Value(pkGroupUuid),
  pkMemberUuid: Value(pkMemberUuid),
);

class _ThrowingAliasesDao extends PkGroupSyncAliasesDao {
  _ThrowingAliasesDao(super.db);

  @override
  Future<void> upsertAlias({
    required String legacyEntityId,
    required String pkGroupUuid,
    required String canonicalEntityId,
  }) async {
    throw StateError('alias write failed');
  }
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test(
    'run without token backfills and merges linked duplicate PK groups',
    () async {
      await db.customStatement('DROP INDEX idx_member_groups_pluralkit_uuid');

      await db
          .into(db.members)
          .insert(
            _member(
              id: 'member-a',
              name: 'Alice',
              pluralkitUuid: 'pk-member-a',
            ),
          );
      await db
          .into(db.members)
          .insert(
            _member(id: 'member-b', name: 'Bob', pluralkitUuid: 'pk-member-b'),
          );

      await db
          .into(db.memberGroups)
          .insert(
            _group(
              id: 'winner',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 1),
              pluralkitUuid: 'pk-group-1',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            _group(
              id: 'loser',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 2),
              pluralkitUuid: 'pk-group-1',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            _group(
              id: 'child',
              name: 'Child',
              createdAt: DateTime(2024, 1, 3),
              parentGroupId: 'loser',
            ),
          );

      await db
          .into(db.memberGroupEntries)
          .insert(
            _entry(id: 'winner-a', groupId: 'winner', memberId: 'member-a'),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            _entry(
              id: 'loser-a',
              groupId: 'loser',
              memberId: 'member-a',
              pkGroupUuid: 'pk-group-1',
              pkMemberUuid: 'pk-member-a',
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            _entry(id: 'loser-b', groupId: 'loser', memberId: 'member-b'),
          );

      var fetchCalls = 0;
      final service = PkGroupRepairService(
        memberGroupsDao: db.memberGroupsDao,
        aliasesDao: db.pkGroupSyncAliasesDao,
        hasRepairToken: ({String? token}) async => false,
        fetchRepairReferenceData: ({String? token}) async {
          fetchCalls++;
          throw StateError('unexpected fetch');
        },
      );

      final report = await service.run(allowStoredToken: false);

      expect(fetchCalls, 0);
      expect(report.referenceMode, PkGroupRepairReferenceMode.none);
      expect(report.backfilledEntries, 2);
      expect(report.duplicateSetsMerged, 1);
      expect(report.duplicateGroupsSoftDeleted, 1);
      expect(report.parentReferencesRehomed, 0);
      expect(report.entriesRehomed, 0);
      expect(report.entryConflictsSoftDeleted, 1);
      expect(report.aliasesRecorded, 1);
      expect(report.pendingReviewCount, 0);

      final aliases = await db.pkGroupSyncAliasesDao.getByPkGroupUuid(
        'pk-group-1',
      );
      expect(aliases, hasLength(1));
      expect(aliases.single.legacyEntityId, 'winner');
      expect(aliases.single.canonicalEntityId, 'pk-group:pk-group-1');

      final child = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('child'))).getSingle();
      expect(child.parentGroupId, 'loser');

      final survivingPrimaryEntry = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals('loser-a'))).getSingle();
      expect(survivingPrimaryEntry.pkGroupUuid, 'pk-group-1');
      expect(survivingPrimaryEntry.pkMemberUuid, 'pk-member-a');

      final survivingSecondaryEntry = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals('loser-b'))).getSingle();
      expect(survivingSecondaryEntry.groupId, 'loser');
      expect(survivingSecondaryEntry.pkGroupUuid, 'pk-group-1');
      expect(survivingSecondaryEntry.pkMemberUuid, 'pk-member-b');

      final deletedGroup = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('winner'))).getSingle();
      expect(deletedGroup.isDeleted, isTrue);
    },
  );

  test(
    'provided token reference data suppresses exact ambiguous plain group copy',
    () async {
      await db
          .into(db.members)
          .insert(
            _member(
              id: 'member-a',
              name: 'Alice',
              pluralkitUuid: 'pk-member-a',
            ),
          );
      await db
          .into(db.members)
          .insert(
            _member(id: 'member-b', name: 'Bob', pluralkitUuid: 'pk-member-b'),
          );
      await db
          .into(db.memberGroups)
          .insert(
            _group(
              id: 'plain-group',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 1),
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            _entry(
              id: 'plain-a',
              groupId: 'plain-group',
              memberId: 'member-a',
              pkMemberUuid: 'pk-member-a',
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            _entry(
              id: 'plain-b',
              groupId: 'plain-group',
              memberId: 'member-b',
              pkMemberUuid: 'pk-member-b',
            ),
          );

      final service = PkGroupRepairService(
        memberGroupsDao: db.memberGroupsDao,
        aliasesDao: db.pkGroupSyncAliasesDao,
        hasRepairToken: ({String? token}) async => token != null,
        fetchRepairReferenceData: ({String? token}) async {
          expect(token, 'provided-token');
          return const PkRepairReferenceData(
            system: PKSystem(id: 'system-1', name: 'Test'),
            members: [
              PKMember(id: 'm1', uuid: 'pk-member-a', name: 'Alice'),
              PKMember(id: 'm2', uuid: 'pk-member-b', name: 'Bob'),
            ],
            groups: [
              PKGroup(
                id: 'g1',
                uuid: 'pk-group-1',
                name: 'Cluster',
                memberIds: ['pk-member-a', 'pk-member-b'],
              ),
            ],
          );
        },
      );

      final report = await service.run(token: 'provided-token');

      expect(report.referenceMode, PkGroupRepairReferenceMode.providedToken);
      expect(report.ambiguousGroupsSuppressed, 1);
      expect(report.pendingReviewCount, 1);

      final group = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('plain-group'))).getSingle();
      expect(group.syncSuppressed, isTrue);
      expect(group.suspectedPkGroupUuid, 'pk-group-1');
    },
  );

  test(
    'import-only local repair still restores directly linked rows and flags reconnect guidance',
    () async {
      await db
          .into(db.members)
          .insert(
            _member(
              id: 'member-a',
              name: 'Alice',
              pluralkitUuid: 'pk-member-a',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            _group(
              id: 'imported-group',
              name: 'Imported Cluster',
              createdAt: DateTime(2024, 1, 1),
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            _entry(
              id: 'imported-entry',
              groupId: 'imported-group',
              memberId: 'member-a',
              pkGroupUuid: 'pk-group-1',
            ),
          );

      var fetchCalls = 0;
      final service = PkGroupRepairService(
        memberGroupsDao: db.memberGroupsDao,
        aliasesDao: db.pkGroupSyncAliasesDao,
        hasRepairToken: ({String? token}) async => false,
        fetchRepairReferenceData: ({String? token}) async {
          fetchCalls++;
          throw StateError('unexpected fetch');
        },
      );

      final report = await service.run(allowStoredToken: false);

      expect(fetchCalls, 0);
      expect(report.referenceMode, PkGroupRepairReferenceMode.none);
      expect(report.backfilledEntries, 1);
      expect(report.requiresReconnectForMissingPkGroupIdentity, isTrue);

      final entry = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals('imported-entry'))).getSingle();
      expect(entry.pkGroupUuid, 'pk-group-1');
      expect(entry.pkMemberUuid, 'pk-member-a');
    },
  );

  test(
    'stored-token lookup failure does not trigger the import-only reconnect flag',
    () async {
      await db
          .into(db.members)
          .insert(
            _member(
              id: 'member-a',
              name: 'Alice',
              pluralkitUuid: 'pk-member-a',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            _group(
              id: 'imported-group',
              name: 'Imported Cluster',
              createdAt: DateTime(2024, 1, 1),
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            _entry(
              id: 'imported-entry',
              groupId: 'imported-group',
              memberId: 'member-a',
              pkGroupUuid: 'pk-group-1',
            ),
          );

      final service = PkGroupRepairService(
        memberGroupsDao: db.memberGroupsDao,
        aliasesDao: db.pkGroupSyncAliasesDao,
        hasRepairToken: ({String? token}) async => true,
        fetchRepairReferenceData: ({String? token}) async {
          throw StateError('bad token');
        },
      );

      final report = await service.run();

      expect(report.referenceMode, PkGroupRepairReferenceMode.none);
      expect(report.referenceError, contains('bad token'));
      expect(report.backfilledEntries, 1);
      expect(report.requiresReconnectForMissingPkGroupIdentity, isFalse);
    },
  );

  test(
    'review actions clear or retain suppression state as requested',
    () async {
      await db
          .into(db.memberGroups)
          .insert(
            _group(
              id: 'plain-group',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 1),
            ),
          );

      final service = PkGroupRepairService(
        memberGroupsDao: db.memberGroupsDao,
        aliasesDao: db.pkGroupSyncAliasesDao,
        hasRepairToken: ({String? token}) async => false,
        fetchRepairReferenceData: ({String? token}) async {
          throw StateError('unexpected fetch');
        },
      );

      await db.memberGroupsDao.markGroupsSuppressedForReview(
        groupIds: const ['plain-group'],
        suspectedPkGroupUuid: 'pk-group-1',
      );

      await service.keepReviewItemsLocalOnly(['plain-group']);
      var group = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('plain-group'))).getSingle();
      expect(group.syncSuppressed, isTrue);
      expect(group.suspectedPkGroupUuid, null);
      expect(await service.getPendingReviewCount(), 0);

      await db.memberGroupsDao.markGroupsSuppressedForReview(
        groupIds: const ['plain-group'],
        suspectedPkGroupUuid: 'pk-group-1',
      );
      await service.dismissReviewItems(['plain-group']);
      group = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('plain-group'))).getSingle();
      expect(group.syncSuppressed, isFalse);
      expect(group.suspectedPkGroupUuid, null);
      expect(await service.getPendingReviewCount(), 0);
    },
  );

  test(
    'merge review item into canonical rehomes rows into the PK-backed winner',
    () async {
      await db
          .into(db.members)
          .insert(
            _member(
              id: 'member-a',
              name: 'Alice',
              pluralkitUuid: 'pk-member-a',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            _group(
              id: 'canonical',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 1),
              pluralkitUuid: 'pk-group-1',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            _group(
              id: 'review',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 2),
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            _group(
              id: 'child',
              name: 'Child',
              createdAt: DateTime(2024, 1, 3),
              parentGroupId: 'review',
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            _entry(id: 'review-entry', groupId: 'review', memberId: 'member-a'),
          );
      await db.memberGroupsDao.markGroupsSuppressedForReview(
        groupIds: const ['review'],
        suspectedPkGroupUuid: 'pk-group-1',
      );

      final service = PkGroupRepairService(
        memberGroupsDao: db.memberGroupsDao,
        aliasesDao: db.pkGroupSyncAliasesDao,
        hasRepairToken: ({String? token}) async => false,
        fetchRepairReferenceData: ({String? token}) async {
          throw StateError('unexpected fetch');
        },
      );

      await service.mergeReviewItemIntoCanonical('review');

      final canonical = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('canonical'))).getSingle();
      expect(canonical.isDeleted, isFalse);
      expect(canonical.pluralkitUuid, 'pk-group-1');

      final child = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('child'))).getSingle();
      expect(child.parentGroupId, 'canonical');

      final movedEntry = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals('review-entry'))).getSingle();
      expect(movedEntry.groupId, 'canonical');
      expect(movedEntry.pkGroupUuid, 'pk-group-1');

      final review = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('review'))).getSingle();
      expect(review.isDeleted, isTrue);
      expect(review.syncSuppressed, isTrue);
      expect(review.suspectedPkGroupUuid, null);

      final aliases = await db.pkGroupSyncAliasesDao.getByPkGroupUuid(
        'pk-group-1',
      );
      expect(aliases, hasLength(1));
      expect(aliases.single.legacyEntityId, 'review');
    },
  );

  test(
    'stored-token fetch failure falls back to local repair and records warning',
    () async {
      await db
          .into(db.memberGroups)
          .insert(
            _group(
              id: 'linked-group',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 1),
              pluralkitUuid: 'pk-group-1',
            ),
          );
      await db
          .into(db.members)
          .insert(
            _member(
              id: 'linked-member',
              name: 'Alice',
              pluralkitUuid: 'pk-member-1',
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            _entry(
              id: 'linked-entry',
              groupId: 'linked-group',
              memberId: 'linked-member',
            ),
          );

      var fetchCalls = 0;
      final service = PkGroupRepairService(
        memberGroupsDao: db.memberGroupsDao,
        aliasesDao: db.pkGroupSyncAliasesDao,
        hasRepairToken: ({String? token}) async => true,
        fetchRepairReferenceData: ({String? token}) async {
          fetchCalls++;
          throw StateError('bad token');
        },
      );

      final report = await service.run();

      expect(fetchCalls, 1);
      expect(report.referenceMode, PkGroupRepairReferenceMode.none);
      expect(report.referenceError, contains('bad token'));
      expect(report.backfilledEntries, 1);
    },
  );

  test(
    'repair rolls back duplicate merge changes when a later step fails',
    () async {
      await db.customStatement('DROP INDEX idx_member_groups_pluralkit_uuid');

      await db
          .into(db.members)
          .insert(
            _member(
              id: 'member-a',
              name: 'Alice',
              pluralkitUuid: 'pk-member-a',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            _group(
              id: 'winner',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 1),
              pluralkitUuid: 'pk-group-1',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            _group(
              id: 'loser',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 2),
              pluralkitUuid: 'pk-group-1',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            _group(
              id: 'child',
              name: 'Child',
              createdAt: DateTime(2024, 1, 3),
              parentGroupId: 'loser',
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            _entry(
              id: 'loser-entry',
              groupId: 'loser',
              memberId: 'member-a',
              pkGroupUuid: 'pk-group-1',
              pkMemberUuid: 'pk-member-a',
            ),
          );

      final service = PkGroupRepairService(
        memberGroupsDao: db.memberGroupsDao,
        aliasesDao: _ThrowingAliasesDao(db),
        hasRepairToken: ({String? token}) async => false,
        fetchRepairReferenceData: ({String? token}) async {
          throw StateError('unexpected fetch');
        },
      );

      try {
        await service.run(allowStoredToken: false);
        fail('Expected repair to fail when alias writes throw');
      } on StateError catch (error) {
        expect(error.message, 'alias write failed');
      }

      final child = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('child'))).getSingle();
      expect(child.parentGroupId, 'loser');

      final loserEntry = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals('loser-entry'))).getSingle();
      expect(loserEntry.groupId, 'loser');
      expect(loserEntry.isDeleted, isFalse);

      final loserGroup = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('loser'))).getSingle();
      expect(loserGroup.isDeleted, isFalse);

      final aliases = await db.pkGroupSyncAliasesDao.getByPkGroupUuid(
        'pk-group-1',
      );
      expect(aliases, isEmpty);
    },
  );
}
