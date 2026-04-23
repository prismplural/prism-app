import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';

MemberGroupsCompanion _group({
  required String id,
  required DateTime createdAt,
  String? pluralkitUuid,
  String? parentGroupId,
}) => MemberGroupsCompanion.insert(
  id: id,
  name: id,
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
            _group(
              id: 'group-linked',
              createdAt: DateTime(2024, 1, 1),
              pluralkitUuid: 'pk-group-1',
            ),
          );
      await db
          .into(db.members)
          .insert(
            _member(
              id: 'member-linked',
              name: 'Alice',
              pluralkitUuid: 'pk-member-1',
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            _entry(
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
          _member(id: 'member-a', name: 'Alice', pluralkitUuid: 'pk-member-a'),
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
            createdAt: DateTime(2024, 1, 1),
            pluralkitUuid: 'pk-group-1',
          ),
        );
    await db
        .into(db.memberGroups)
        .insert(
          _group(
            id: 'loser',
            createdAt: DateTime(2024, 1, 2),
            pluralkitUuid: 'pk-group-1',
          ),
        );
    await db
        .into(db.memberGroups)
        .insert(
          _group(
            id: 'child',
            createdAt: DateTime(2024, 1, 3),
            parentGroupId: 'loser',
          ),
        );

    await db
        .into(db.memberGroupEntries)
        .insert(
          _entry(id: 'winner-entry-a', groupId: 'winner', memberId: 'member-a'),
        );
    await db
        .into(db.memberGroupEntries)
        .insert(
          _entry(
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
          _entry(
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

  test('markGroupsSuppressedForReview is idempotent and queryable', () async {
    await db
        .into(db.memberGroups)
        .insert(_group(id: 'plain-group', createdAt: DateTime(2024, 1, 1)));

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
