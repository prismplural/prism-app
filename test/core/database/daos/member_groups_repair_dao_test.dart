import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';

import '../../../helpers/pk_fixtures.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test(
    'backfillActiveEntryPkReferences fills missing PK UUIDs only once',
    () async {
      await db
          .into(db.memberGroups)
          .insert(
            pkFixtureGroup(
              id: 'group-linked',
              createdAt: DateTime(2024, 1, 1),
              pluralkitUuid: 'pk-group-1',
            ),
          );
      await db
          .into(db.members)
          .insert(
            pkFixtureMember(
              id: 'member-linked',
              name: 'Alice',
              pluralkitUuid: 'pk-member-1',
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            pkFixtureEntry(
              id: 'entry-1',
              groupId: 'group-linked',
              memberId: 'member-linked',
            ),
          );

      final firstPass = await db.memberGroupsDao
          .backfillActiveEntryPkReferences();
      expect(firstPass, 1);

      final entry = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals('entry-1'))).getSingle();
      expect(entry.pkGroupUuid, 'pk-group-1');
      expect(entry.pkMemberUuid, 'pk-member-1');

      final secondPass = await db.memberGroupsDao
          .backfillActiveEntryPkReferences();
      expect(secondPass, 0);
    },
  );

  test('duplicate linked PK groups can be rehomed deterministically', () async {
    await db.customStatement('DROP INDEX idx_member_groups_pluralkit_uuid');

    await db
        .into(db.members)
        .insert(
          pkFixtureMember(id: 'member-a', name: 'Alice', pluralkitUuid: 'pk-member-a'),
        );
    await db
        .into(db.members)
        .insert(
          pkFixtureMember(id: 'member-b', name: 'Bob', pluralkitUuid: 'pk-member-b'),
        );

    await db
        .into(db.memberGroups)
        .insert(
          pkFixtureGroup(
            id: 'winner',
            createdAt: DateTime(2024, 1, 1),
            pluralkitUuid: 'pk-group-1',
          ),
        );
    await db
        .into(db.memberGroups)
        .insert(
          pkFixtureGroup(
            id: 'loser',
            createdAt: DateTime(2024, 1, 2),
            pluralkitUuid: 'pk-group-1',
          ),
        );
    await db
        .into(db.memberGroups)
        .insert(
          pkFixtureGroup(
            id: 'child',
            createdAt: DateTime(2024, 1, 3),
            parentGroupId: 'loser',
          ),
        );

    await db
        .into(db.memberGroupEntries)
        .insert(
          pkFixtureEntry(id: 'winner-entry-a', groupId: 'winner', memberId: 'member-a'),
        );
    await db
        .into(db.memberGroupEntries)
        .insert(
          pkFixtureEntry(
            id: 'loser-entry-a',
            groupId: 'loser',
            memberId: 'member-a',
            pkGroupUuid: 'pk-group-1',
            pkMemberUuid: 'pk-member-a',
          ),
        );
    await db
        .into(db.memberGroupEntries)
        .insert(
          pkFixtureEntry(
            id: 'loser-entry-b',
            groupId: 'loser',
            memberId: 'member-b',
            pkMemberUuid: 'pk-member-b',
          ),
        );

    final duplicateSets = await db.memberGroupsDao
        .getActiveLinkedPkGroupDuplicateSets();
    expect(duplicateSets, hasLength(1));
    expect(duplicateSets.single.groups.map((group) => group.id), [
      'winner',
      'loser',
    ]);

    final rehomedParents = await db.memberGroupsDao
        .rehomeParentReferencesToWinner(
          winnerGroupId: 'winner',
          loserGroupIds: const ['loser'],
        );
    expect(rehomedParents, 1);

    final rehomeResult = await db.memberGroupsDao.rehomeEntriesToWinner(
      winnerGroupId: 'winner',
      loserGroupIds: const ['loser'],
      canonicalPkGroupUuid: 'pk-group-1',
    );
    expect(rehomeResult.movedEntries, 1);
    expect(rehomeResult.softDeletedConflicts, 1);

    final softDeleted = await db.memberGroupsDao.softDeleteGroupsForRepair(
      const ['loser'],
    );
    expect(softDeleted, 1);

    final child = await (db.select(
      db.memberGroups,
    )..where((t) => t.id.equals('child'))).getSingle();
    expect(child.parentGroupId, 'winner');

    final winnerEntry = await (db.select(
      db.memberGroupEntries,
    )..where((t) => t.id.equals('winner-entry-a'))).getSingle();
    expect(winnerEntry.pkGroupUuid, 'pk-group-1');
    expect(winnerEntry.pkMemberUuid, 'pk-member-a');

    final movedEntry = await (db.select(
      db.memberGroupEntries,
    )..where((t) => t.id.equals('loser-entry-b'))).getSingle();
    expect(movedEntry.groupId, 'winner');
    expect(movedEntry.pkGroupUuid, 'pk-group-1');
    expect(movedEntry.pkMemberUuid, 'pk-member-b');
    expect(movedEntry.isDeleted, isFalse);

    final deletedConflict = await (db.select(
      db.memberGroupEntries,
    )..where((t) => t.id.equals('loser-entry-a'))).getSingle();
    expect(deletedConflict.isDeleted, isTrue);

    final deletedGroup = await (db.select(
      db.memberGroups,
    )..where((t) => t.id.equals('loser'))).getSingle();
    expect(deletedGroup.isDeleted, isTrue);
    expect(deletedGroup.syncSuppressed, isTrue);
  });

  test(
    'rehomeEntriesToWinner treats earlier moved entries as winner conflicts',
    () async {
      await db
          .into(db.memberGroups)
          .insert(pkFixtureGroup(id: 'winner', createdAt: DateTime(2024, 1, 1)));
      await db
          .into(db.memberGroups)
          .insert(pkFixtureGroup(id: 'loser-a', createdAt: DateTime(2024, 1, 2)));
      await db
          .into(db.memberGroups)
          .insert(pkFixtureGroup(id: 'loser-b', createdAt: DateTime(2024, 1, 3)));
      await db.into(db.members).insert(pkFixtureMember(id: 'member-a', name: 'Alice'));

      await db
          .into(db.memberGroupEntries)
          .insert(
            pkFixtureEntry(
              id: 'entry-a',
              groupId: 'loser-a',
              memberId: 'member-a',
              pkMemberUuid: 'pk-member-a',
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            pkFixtureEntry(
              id: 'entry-b',
              groupId: 'loser-b',
              memberId: 'member-a',
              pkMemberUuid: 'pk-member-a',
            ),
          );

      final result = await db.memberGroupsDao.rehomeEntriesToWinner(
        winnerGroupId: 'winner',
        loserGroupIds: const ['loser-a', 'loser-b'],
        canonicalPkGroupUuid: 'pk-group-1',
      );

      expect(result.movedEntries, 1);
      expect(result.softDeletedConflicts, 1);

      final active = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.isDeleted.equals(false))).get();
      expect(active, hasLength(1));
      expect(active.single.groupId, 'winner');
      expect(active.single.memberId, 'member-a');
    },
  );

  test(
    'aggregate repair helpers avoid materializing full entry rows',
    () async {
      await db
          .into(db.memberGroupEntries)
          .insert(
            pkFixtureEntry(
              id: 'entry-a',
              groupId: 'group-a',
              memberId: 'member-a',
              pkMemberUuid: 'pk-member-a',
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            pkFixtureEntry(
              id: 'entry-b',
              groupId: 'group-a',
              memberId: 'member-b',
              pkMemberUuid: 'pk-member-b',
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            pkFixtureEntry(id: 'entry-c', groupId: 'group-b', memberId: 'member-c'),
          );

      final counts = await db.memberGroupsDao.activeEntryCountsByGroupId();
      expect(counts, {'group-a': 2, 'group-b': 1});

      final pkMembers = await db.memberGroupsDao.activePkMemberUuidsByGroupId();
      expect(pkMembers, {
        'group-a': {'pk-member-a', 'pk-member-b'},
      });
    },
  );

  test('duplicate group repair operations batch large loser sets', () async {
    await db.customStatement('DROP INDEX idx_member_groups_pluralkit_uuid');

    const loserCount = 1200;

    await db
        .into(db.memberGroups)
        .insert(pkFixtureGroup(id: 'winner', createdAt: DateTime(2024, 1, 1)));
    await db
        .into(db.members)
        .insert(pkFixtureMember(id: 'member-shared', name: 'Shared'));

    final loserIds = <String>[];
    for (var i = 0; i < loserCount; i++) {
      final loserId = 'loser-$i';
      loserIds.add(loserId);
      await db
          .into(db.memberGroups)
          .insert(
            pkFixtureGroup(
              id: loserId,
              createdAt: DateTime(2024, 1, 2),
              pluralkitUuid: 'pk-group-1',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            pkFixtureGroup(
              id: 'child-$i',
              createdAt: DateTime(2024, 1, 3),
              parentGroupId: loserId,
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            pkFixtureEntry(
              id: 'entry-$i',
              groupId: loserId,
              memberId: 'member-$i',
              pkMemberUuid: 'pk-member-$i',
            ),
          );
    }

    final rehomeResult = await db.memberGroupsDao.rehomeEntriesToWinner(
      winnerGroupId: 'winner',
      loserGroupIds: loserIds,
      canonicalPkGroupUuid: 'pk-group-1',
    );
    expect(rehomeResult.movedEntries, loserCount);
    expect(rehomeResult.softDeletedConflicts, 0);

    final rehomedParents = await db.memberGroupsDao
        .rehomeParentReferencesToWinner(
          winnerGroupId: 'winner',
          loserGroupIds: loserIds,
        );
    expect(rehomedParents, loserCount);

    final softDeleted = await db.memberGroupsDao.softDeleteGroupsForRepair(
      loserIds,
    );
    expect(softDeleted, loserCount);

    final activeLosers = await (db.select(
      db.memberGroups,
    )..where((t) => t.id.like('loser-%') & t.isDeleted.equals(false))).get();
    expect(activeLosers, isEmpty);

    final activeEntries =
        await (db.select(db.memberGroupEntries)..where(
              (t) => t.groupId.equals('winner') & t.isDeleted.equals(false),
            ))
            .get();
    expect(activeEntries, hasLength(loserCount));
  });

  test('markGroupsSuppressedForReview is idempotent and queryable', () async {
    await db
        .into(db.memberGroups)
        .insert(pkFixtureGroup(id: 'plain-group', createdAt: DateTime(2024, 1, 1)));

    final firstPass = await db.memberGroupsDao.markGroupsSuppressedForReview(
      groupIds: const ['plain-group'],
      suspectedPkGroupUuid: 'pk-group-1',
    );
    final secondPass = await db.memberGroupsDao.markGroupsSuppressedForReview(
      groupIds: const ['plain-group'],
      suspectedPkGroupUuid: 'pk-group-1',
    );

    expect(firstPass, 1);
    expect(secondPass, 1);

    final pending = await db.memberGroupsDao.getGroupsPendingPkReview();
    expect(pending.map((group) => group.id), ['plain-group']);
    expect(pending.single.syncSuppressed, isTrue);
    expect(pending.single.suspectedPkGroupUuid, 'pk-group-1');
  });
}
