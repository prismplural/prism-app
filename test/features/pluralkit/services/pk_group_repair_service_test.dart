import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/daos/pk_group_sync_aliases_dao.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_repair_service.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';

import '../../../helpers/pk_fixtures.dart';

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

  test('provided token wins over stored token access', () async {
    final capturedTokens = <String?>[];
    final service = PkGroupRepairService(
      memberGroupsDao: db.memberGroupsDao,
      aliasesDao: db.pkGroupSyncAliasesDao,
      hasRepairToken: ({String? token}) async {
        throw StateError('stored token should not be checked');
      },
      fetchRepairReferenceData: ({String? token}) async {
        capturedTokens.add(token);
        return const PkRepairReferenceData(
          system: PKSystem(id: 'system-1', name: 'Test'),
          members: [],
          groups: [],
        );
      },
    );

    final report = await service.run(
      token: 'provided-token',
      allowStoredToken: true,
    );

    expect(report.referenceMode, PkGroupRepairReferenceMode.providedToken);
    expect(capturedTokens, ['provided-token']);
  });

  test(
    'run without token backfills and merges linked duplicate PK groups',
    () async {
      await db.customStatement('DROP INDEX idx_member_groups_pluralkit_uuid');

      await db
          .into(db.members)
          .insert(
            pkFixtureMember(
              id: 'member-a',
              name: 'Alice',
              pluralkitUuid: 'pk-member-a',
            ),
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
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 1),
              pluralkitUuid: 'pk-group-1',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            pkFixtureGroup(
              id: 'loser',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 2),
              pluralkitUuid: 'pk-group-1',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            pkFixtureGroup(
              id: 'child',
              name: 'Child',
              createdAt: DateTime(2024, 1, 3),
              parentGroupId: 'loser',
            ),
          );

      await db
          .into(db.memberGroupEntries)
          .insert(
            pkFixtureEntry(id: 'winner-a', groupId: 'winner', memberId: 'member-a'),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            pkFixtureEntry(
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
            pkFixtureEntry(id: 'loser-b', groupId: 'loser', memberId: 'member-b'),
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
      expect(report.entryConflictsSoftDeleted, 0);
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

      // The backfill + canonicalization pass rewrites legacy entry ids
      // onto the deterministic sha256 hash, so look up the rehomed rows by
      // (group_id, member_id) rather than by the seeded legacy id.
      final canonicalLoserA = pkFixtureCanonicalEntryId('pk-group-1', 'pk-member-a');
      final canonicalLoserB = pkFixtureCanonicalEntryId('pk-group-1', 'pk-member-b');

      final survivingPrimaryEntry = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals(canonicalLoserA))).getSingle();
      expect(survivingPrimaryEntry.pkGroupUuid, 'pk-group-1');
      expect(survivingPrimaryEntry.pkMemberUuid, 'pk-member-a');

      final survivingSecondaryEntry = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals(canonicalLoserB))).getSingle();
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
            pkFixtureMember(
              id: 'member-a',
              name: 'Alice',
              pluralkitUuid: 'pk-member-a',
            ),
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
              id: 'plain-group',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 1),
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            pkFixtureEntry(
              id: 'plain-a',
              groupId: 'plain-group',
              memberId: 'member-a',
              pkMemberUuid: 'pk-member-a',
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            pkFixtureEntry(
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
                description: 'Live PK description',
                color: '44AAFF',
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

      final reviewItems = await service.getPendingReviewItems();
      expect(reviewItems, hasLength(1));
      expect(reviewItems.single.candidateName, 'Cluster');
      expect(reviewItems.single.candidateDescription, 'Live PK description');
      expect(reviewItems.single.candidateColorHex, '#44AAFF');
      expect(
        reviewItems.single.sharedPkMemberUuids,
        containsAll(['pk-member-a', 'pk-member-b']),
      );
      expect(reviewItems.single.extraLocalMemberIds, isEmpty);
      expect(reviewItems.single.onlyInCandidateMemberUuids, isEmpty);

      final localOnlyReport = await service.run(allowStoredToken: false);
      expect(localOnlyReport.referenceMode, PkGroupRepairReferenceMode.none);

      final localOnlyReviewItems = await service.getPendingReviewItems();
      expect(localOnlyReviewItems, hasLength(1));
      expect(localOnlyReviewItems.single.candidateName, null);
      expect(localOnlyReviewItems.single.hasCandidateComparison, isFalse);
    },
  );

  test(
    'token-backed repair picks duplicate whose memberships match live PK data',
    () async {
      await db.customStatement('DROP INDEX idx_member_groups_pluralkit_uuid');

      final members = <MembersCompanion>[
        pkFixtureMember(
          id: 'wrong-a',
          name: 'Wrong A',
          pluralkitUuid: 'pk-member-wrong-a',
        ),
        pkFixtureMember(
          id: 'wrong-b',
          name: 'Wrong B',
          pluralkitUuid: 'pk-member-wrong-b',
        ),
        pkFixtureMember(
          id: 'match-a',
          name: 'Match A',
          pluralkitUuid: 'pk-member-match-a',
        ),
        pkFixtureMember(
          id: 'match-b',
          name: 'Match B',
          pluralkitUuid: 'pk-member-match-b',
        ),
        pkFixtureMember(
          id: 'match-c',
          name: 'Match C',
          pluralkitUuid: 'pk-member-match-c',
        ),
        pkFixtureMember(id: 'local-a', name: 'Local A'),
        pkFixtureMember(id: 'local-b', name: 'Local B'),
        pkFixtureMember(id: 'local-c', name: 'Local C'),
      ];
      for (final member in members) {
        await db.into(db.members).insert(member);
      }

      await db
          .into(db.memberGroups)
          .insert(
            pkFixtureGroup(
              id: 'entry-count-winner',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 1),
              pluralkitUuid: 'pk-group-1',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            pkFixtureGroup(
              id: 'live-match-winner',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 2),
              pluralkitUuid: 'pk-group-1',
            ),
          );

      final entries = <MemberGroupEntriesCompanion>[
        pkFixtureEntry(
          id: 'wrong-a-entry',
          groupId: 'entry-count-winner',
          memberId: 'wrong-a',
          pkGroupUuid: 'pk-group-1',
          pkMemberUuid: 'pk-member-wrong-a',
        ),
        pkFixtureEntry(
          id: 'wrong-b-entry',
          groupId: 'entry-count-winner',
          memberId: 'wrong-b',
          pkGroupUuid: 'pk-group-1',
          pkMemberUuid: 'pk-member-wrong-b',
        ),
        pkFixtureEntry(
          id: 'local-a-entry',
          groupId: 'entry-count-winner',
          memberId: 'local-a',
        ),
        pkFixtureEntry(
          id: 'local-b-entry',
          groupId: 'entry-count-winner',
          memberId: 'local-b',
        ),
        pkFixtureEntry(
          id: 'local-c-entry',
          groupId: 'entry-count-winner',
          memberId: 'local-c',
        ),
        pkFixtureEntry(
          id: 'match-a-entry',
          groupId: 'live-match-winner',
          memberId: 'match-a',
          pkGroupUuid: 'pk-group-1',
          pkMemberUuid: 'pk-member-match-a',
        ),
        pkFixtureEntry(
          id: 'match-b-entry',
          groupId: 'live-match-winner',
          memberId: 'match-b',
          pkGroupUuid: 'pk-group-1',
          pkMemberUuid: 'pk-member-match-b',
        ),
        pkFixtureEntry(
          id: 'match-c-entry',
          groupId: 'live-match-winner',
          memberId: 'match-c',
          pkGroupUuid: 'pk-group-1',
          pkMemberUuid: 'pk-member-match-c',
        ),
      ];
      for (final entry in entries) {
        await db.into(db.memberGroupEntries).insert(entry);
      }

      final service = PkGroupRepairService(
        memberGroupsDao: db.memberGroupsDao,
        aliasesDao: db.pkGroupSyncAliasesDao,
        hasRepairToken: ({String? token}) async => token != null,
        fetchRepairReferenceData: ({String? token}) async {
          expect(token, 'provided-token');
          return const PkRepairReferenceData(
            system: PKSystem(id: 'system-1', name: 'Test'),
            members: [
              PKMember(id: 'ma', uuid: 'pk-member-match-a', name: 'Match A'),
              PKMember(id: 'mb', uuid: 'pk-member-match-b', name: 'Match B'),
              PKMember(id: 'mc', uuid: 'pk-member-match-c', name: 'Match C'),
            ],
            groups: [
              PKGroup(
                id: 'g1',
                uuid: 'pk-group-1',
                name: 'Cluster',
                memberIds: [
                  'pk-member-match-a',
                  'pk-member-match-b',
                  'pk-member-match-c',
                ],
              ),
            ],
          );
        },
      );

      final report = await service.run(token: 'provided-token');

      expect(report.duplicateSetsMerged, 1);

      final liveMatchWinner = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('live-match-winner'))).getSingle();
      expect(liveMatchWinner.isDeleted, isFalse);

      final entryCountWinner = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('entry-count-winner'))).getSingle();
      expect(entryCountWinner.isDeleted, isTrue);

      final aliases = await db.pkGroupSyncAliasesDao.getByPkGroupUuid(
        'pk-group-1',
      );
      expect(aliases.single.legacyEntityId, 'entry-count-winner');
    },
  );

  test(
    'lastSeenFromPkAt ordering wins when membership match and entry count tie',
    () async {
      await db.customStatement('DROP INDEX idx_member_groups_pluralkit_uuid');

      await db
          .into(db.memberGroups)
          .insert(
            pkFixtureGroup(
              id: 'older-seen',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 1),
              pluralkitUuid: 'pk-group-1',
              lastSeenFromPkAt: DateTime(2024, 1, 2),
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            pkFixtureGroup(
              id: 'newer-seen',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 3),
              pluralkitUuid: 'pk-group-1',
              lastSeenFromPkAt: DateTime(2024, 1, 4),
            ),
          );

      final service = PkGroupRepairService(
        memberGroupsDao: db.memberGroupsDao,
        aliasesDao: db.pkGroupSyncAliasesDao,
        hasRepairToken: ({String? token}) async => token != null,
        fetchRepairReferenceData: ({String? token}) async {
          return const PkRepairReferenceData(
            system: PKSystem(id: 'system-1', name: 'Test'),
            members: [],
            groups: [
              PKGroup(
                id: 'g1',
                uuid: 'pk-group-1',
                name: 'Cluster',
                memberIds: [],
              ),
            ],
          );
        },
      );

      final report = await service.run(token: 'provided-token');

      expect(report.duplicateSetsMerged, 1);

      final newerSeen = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('newer-seen'))).getSingle();
      expect(newerSeen.isDeleted, isFalse);

      final olderSeen = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('older-seen'))).getSingle();
      expect(olderSeen.isDeleted, isTrue);
    },
  );

  test(
    'token-backed repair keeps exact live-match row and rehomes local extras',
    () async {
      await db.customStatement('DROP INDEX idx_member_groups_pluralkit_uuid');

      final members = <MembersCompanion>[
        pkFixtureMember(id: 'member-a', name: 'Alice', pluralkitUuid: 'pk-member-a'),
        pkFixtureMember(id: 'member-b', name: 'Bob', pluralkitUuid: 'pk-member-b'),
        pkFixtureMember(id: 'member-c', name: 'Charlie', pluralkitUuid: 'pk-member-c'),
        pkFixtureMember(id: 'local-extra', name: 'Local Extra'),
      ];
      for (final member in members) {
        await db.into(db.members).insert(member);
      }

      await db
          .into(db.memberGroups)
          .insert(
            pkFixtureGroup(
              id: 'exact-live-match',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 1),
              pluralkitUuid: 'pk-group-1',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            pkFixtureGroup(
              id: 'same-pk-plus-local',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 2),
              pluralkitUuid: 'pk-group-1',
            ),
          );

      final entries = <MemberGroupEntriesCompanion>[
        pkFixtureEntry(
          id: 'exact-a',
          groupId: 'exact-live-match',
          memberId: 'member-a',
          pkGroupUuid: 'stale-exact-group-ref',
          pkMemberUuid: 'pk-member-a',
        ),
        pkFixtureEntry(
          id: 'exact-b',
          groupId: 'exact-live-match',
          memberId: 'member-b',
          pkGroupUuid: 'stale-exact-group-ref',
          pkMemberUuid: 'pk-member-b',
        ),
        pkFixtureEntry(
          id: 'exact-c',
          groupId: 'exact-live-match',
          memberId: 'member-c',
          pkGroupUuid: 'stale-exact-group-ref',
          pkMemberUuid: 'pk-member-c',
        ),
        pkFixtureEntry(
          id: 'extra-a',
          groupId: 'same-pk-plus-local',
          memberId: 'member-a',
          pkGroupUuid: 'stale-extra-group-ref',
          pkMemberUuid: 'pk-member-a',
        ),
        pkFixtureEntry(
          id: 'extra-b',
          groupId: 'same-pk-plus-local',
          memberId: 'member-b',
          pkGroupUuid: 'stale-extra-group-ref',
          pkMemberUuid: 'pk-member-b',
        ),
        pkFixtureEntry(
          id: 'extra-c',
          groupId: 'same-pk-plus-local',
          memberId: 'member-c',
          pkGroupUuid: 'stale-extra-group-ref',
          pkMemberUuid: 'pk-member-c',
        ),
        pkFixtureEntry(
          id: 'local-extra-entry',
          groupId: 'same-pk-plus-local',
          memberId: 'local-extra',
        ),
      ];
      for (final entry in entries) {
        await db.into(db.memberGroupEntries).insert(entry);
      }

      final service = PkGroupRepairService(
        memberGroupsDao: db.memberGroupsDao,
        aliasesDao: db.pkGroupSyncAliasesDao,
        hasRepairToken: ({String? token}) async => token != null,
        fetchRepairReferenceData: ({String? token}) async {
          return const PkRepairReferenceData(
            system: PKSystem(id: 'system-1', name: 'Test'),
            members: [
              PKMember(id: 'm1', uuid: 'pk-member-a', name: 'Alice'),
              PKMember(id: 'm2', uuid: 'pk-member-b', name: 'Bob'),
              PKMember(id: 'm3', uuid: 'pk-member-c', name: 'Charlie'),
            ],
            groups: [
              PKGroup(
                id: 'g1',
                uuid: 'pk-group-1',
                name: 'Cluster',
                memberIds: ['pk-member-a', 'pk-member-b', 'pk-member-c'],
              ),
            ],
          );
        },
      );

      final report = await service.run(token: 'provided-token');

      expect(report.duplicateSetsMerged, 1);
      expect(report.entriesRehomed, 1);
      expect(report.entryConflictsSoftDeleted, 3);

      final exactGroup = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('exact-live-match'))).getSingle();
      expect(exactGroup.isDeleted, isFalse);

      final extraGroup = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('same-pk-plus-local'))).getSingle();
      expect(extraGroup.isDeleted, isTrue);

      final localExtra = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.memberId.equals('local-extra'))).getSingle();
      expect(localExtra.groupId, 'exact-live-match');
      expect(localExtra.isDeleted, isFalse);
      expect(localExtra.pkGroupUuid, 'pk-group-1');
      expect(localExtra.pkMemberUuid, null);
    },
  );

  test(
    'exact-match suppression rejects plain group with extra local-only members',
    () async {
      final members = <MembersCompanion>[
        pkFixtureMember(id: 'member-a', name: 'Alice', pluralkitUuid: 'pk-member-a'),
        pkFixtureMember(id: 'member-b', name: 'Bob', pluralkitUuid: 'pk-member-b'),
        pkFixtureMember(id: 'member-c', name: 'Charlie', pluralkitUuid: 'pk-member-c'),
        pkFixtureMember(id: 'local-a', name: 'Local A'),
        pkFixtureMember(id: 'local-b', name: 'Local B'),
      ];
      for (final member in members) {
        await db.into(db.members).insert(member);
      }

      await db
          .into(db.memberGroups)
          .insert(
            pkFixtureGroup(
              id: 'plain-group',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 1),
            ),
          );

      final entries = <MemberGroupEntriesCompanion>[
        pkFixtureEntry(
          id: 'plain-a',
          groupId: 'plain-group',
          memberId: 'member-a',
          pkMemberUuid: 'pk-member-a',
        ),
        pkFixtureEntry(
          id: 'plain-b',
          groupId: 'plain-group',
          memberId: 'member-b',
          pkMemberUuid: 'pk-member-b',
        ),
        pkFixtureEntry(
          id: 'plain-c',
          groupId: 'plain-group',
          memberId: 'member-c',
          pkMemberUuid: 'pk-member-c',
        ),
        pkFixtureEntry(
          id: 'plain-local-a',
          groupId: 'plain-group',
          memberId: 'local-a',
        ),
        pkFixtureEntry(
          id: 'plain-local-b',
          groupId: 'plain-group',
          memberId: 'local-b',
        ),
      ];
      for (final entry in entries) {
        await db.into(db.memberGroupEntries).insert(entry);
      }

      final service = PkGroupRepairService(
        memberGroupsDao: db.memberGroupsDao,
        aliasesDao: db.pkGroupSyncAliasesDao,
        hasRepairToken: ({String? token}) async => token != null,
        fetchRepairReferenceData: ({String? token}) async {
          return const PkRepairReferenceData(
            system: PKSystem(id: 'system-1', name: 'Test'),
            members: [
              PKMember(id: 'm1', uuid: 'pk-member-a', name: 'Alice'),
              PKMember(id: 'm2', uuid: 'pk-member-b', name: 'Bob'),
              PKMember(id: 'm3', uuid: 'pk-member-c', name: 'Charlie'),
            ],
            groups: [
              PKGroup(
                id: 'g1',
                uuid: 'pk-group-1',
                name: 'Cluster',
                memberIds: ['pk-member-a', 'pk-member-b', 'pk-member-c'],
              ),
            ],
          );
        },
      );

      final report = await service.run(token: 'provided-token');

      expect(report.ambiguousGroupsSuppressed, 0);
      expect(report.pendingReviewCount, 0);

      final group = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('plain-group'))).getSingle();
      expect(group.syncSuppressed, isFalse);
      expect(group.suspectedPkGroupUuid, null);
    },
  );

  test(
    'import-only local repair still restores directly linked rows and flags reconnect guidance',
    () async {
      await db
          .into(db.members)
          .insert(
            pkFixtureMember(
              id: 'member-a',
              name: 'Alice',
              pluralkitUuid: 'pk-member-a',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            pkFixtureGroup(
              id: 'imported-group',
              name: 'Imported Cluster',
              createdAt: DateTime(2024, 1, 1),
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            pkFixtureEntry(
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

      // The backfill + canonicalization pass rewrites legacy entry ids
      // onto the deterministic sha256 hash, so look up the repaired row by
      // the canonical id rather than the seeded legacy id.
      final canonicalId = pkFixtureCanonicalEntryId('pk-group-1', 'pk-member-a');
      final entry = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals(canonicalId))).getSingle();
      expect(entry.groupId, 'imported-group');
      expect(entry.memberId, 'member-a');
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
            pkFixtureMember(
              id: 'member-a',
              name: 'Alice',
              pluralkitUuid: 'pk-member-a',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            pkFixtureGroup(
              id: 'imported-group',
              name: 'Imported Cluster',
              createdAt: DateTime(2024, 1, 1),
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            pkFixtureEntry(
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
            pkFixtureGroup(
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
    'dismissReviewItems re-emits sync state for accumulated local edits',
    () async {
      await db
          .into(db.memberGroups)
          .insert(
            pkFixtureGroup(
              id: 'plain-group',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 1),
            ),
          );
      await db.memberGroupsDao.markGroupsSuppressedForReview(
        groupIds: const ['plain-group'],
        suspectedPkGroupUuid: 'pk-group-1',
      );

      final emittedGroupIds = <String>[];
      final service = PkGroupRepairService(
        memberGroupsDao: db.memberGroupsDao,
        aliasesDao: db.pkGroupSyncAliasesDao,
        hasRepairToken: ({String? token}) async => false,
        fetchRepairReferenceData: ({String? token}) async {
          throw StateError('unexpected fetch');
        },
        emitGroupSyncState: (groupId) async {
          emittedGroupIds.add(groupId);
        },
      );

      await service.dismissReviewItems(['plain-group']);

      expect(emittedGroupIds, ['plain-group']);
    },
  );

  test(
    'kept-local review item is not re-flagged by later repair runs',
    () async {
      await db
          .into(db.members)
          .insert(
            pkFixtureMember(
              id: 'member-a',
              name: 'Alice',
              pluralkitUuid: 'pk-member-a',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            pkFixtureGroup(
              id: 'plain-group',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 1),
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            pkFixtureEntry(
              id: 'plain-entry',
              groupId: 'plain-group',
              memberId: 'member-a',
              pkMemberUuid: 'pk-member-a',
            ),
          );

      final service = PkGroupRepairService(
        memberGroupsDao: db.memberGroupsDao,
        aliasesDao: db.pkGroupSyncAliasesDao,
        hasRepairToken: ({String? token}) async => true,
        fetchRepairReferenceData: ({String? token}) async {
          return const PkRepairReferenceData(
            system: PKSystem(id: 'system-1', name: 'Test'),
            members: [PKMember(id: 'm1', uuid: 'pk-member-a', name: 'Alice')],
            groups: [
              PKGroup(
                id: 'g1',
                uuid: 'pk-group-1',
                name: 'Cluster',
                memberIds: ['pk-member-a'],
              ),
            ],
          );
        },
      );

      final firstReport = await service.run(token: 'provided-token');
      expect(firstReport.ambiguousGroupsSuppressed, 1);
      expect(await service.getPendingReviewCount(), 1);

      await service.keepReviewItemsLocalOnly(['plain-group']);
      var group = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('plain-group'))).getSingle();
      expect(group.syncSuppressed, isTrue);
      expect(group.suspectedPkGroupUuid, null);
      expect(await service.getPendingReviewCount(), 0);

      final secondReport = await service.run(token: 'provided-token');
      expect(secondReport.ambiguousGroupsSuppressed, 0);
      expect(secondReport.pendingReviewCount, 0);
      expect(await service.getPendingReviewCount(), 0);

      group = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('plain-group'))).getSingle();
      expect(group.syncSuppressed, isTrue);
      expect(group.suspectedPkGroupUuid, null);
    },
  );

  test(
    'mid-review suppressed group with a pending UUID is not re-evaluated',
    () async {
      await db
          .into(db.members)
          .insert(
            pkFixtureMember(
              id: 'member-a',
              name: 'Alice',
              pluralkitUuid: 'pk-member-a',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            pkFixtureGroup(
              id: 'plain-group',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 1),
              syncSuppressed: true,
              suspectedPkGroupUuid: 'pk-group-1',
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            pkFixtureEntry(
              id: 'plain-entry',
              groupId: 'plain-group',
              memberId: 'member-a',
              pkMemberUuid: 'pk-member-a',
            ),
          );

      final service = PkGroupRepairService(
        memberGroupsDao: db.memberGroupsDao,
        aliasesDao: db.pkGroupSyncAliasesDao,
        hasRepairToken: ({String? token}) async => true,
        fetchRepairReferenceData: ({String? token}) async {
          return const PkRepairReferenceData(
            system: PKSystem(id: 'system-1', name: 'Test'),
            members: [PKMember(id: 'm1', uuid: 'pk-member-a', name: 'Alice')],
            groups: [
              PKGroup(
                id: 'g1',
                uuid: 'pk-group-1',
                name: 'Cluster',
                memberIds: ['pk-member-a'],
              ),
            ],
          );
        },
      );

      final report = await service.run(token: 'provided-token');
      // The group already carries suspectedPkGroupUuid + syncSuppressed.
      // The simplified skip check should leave it alone on re-run.
      expect(report.ambiguousGroupsSuppressed, 0);
      expect(report.pendingReviewCount, 1);

      final group = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('plain-group'))).getSingle();
      expect(group.syncSuppressed, isTrue);
      expect(group.suspectedPkGroupUuid, 'pk-group-1');
    },
  );

  test(
    'merge review item into canonical rehomes rows into the PK-backed winner',
    () async {
      await db
          .into(db.members)
          .insert(
            pkFixtureMember(
              id: 'member-a',
              name: 'Alice',
              pluralkitUuid: 'pk-member-a',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            pkFixtureGroup(
              id: 'canonical',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 1),
              pluralkitUuid: 'pk-group-1',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            pkFixtureGroup(
              id: 'review',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 2),
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            pkFixtureGroup(
              id: 'child',
              name: 'Child',
              createdAt: DateTime(2024, 1, 3),
              parentGroupId: 'review',
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            pkFixtureEntry(id: 'review-entry', groupId: 'review', memberId: 'member-a'),
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

      final movedEntry =
          await (db.select(db.memberGroupEntries)..where(
                (t) =>
                    t.id.equals(pkFixtureCanonicalEntryId('pk-group-1', 'pk-member-a')),
              ))
              .getSingle();
      expect(movedEntry.groupId, 'canonical');
      expect(movedEntry.pkGroupUuid, 'pk-group-1');
      expect(movedEntry.pkMemberUuid, 'pk-member-a');
      expect(
        await (db.select(
          db.memberGroupEntries,
        )..where((t) => t.id.equals('review-entry'))).getSingleOrNull(),
        null,
      );

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
            pkFixtureGroup(
              id: 'linked-group',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 1),
              pluralkitUuid: 'pk-group-1',
            ),
          );
      await db
          .into(db.members)
          .insert(
            pkFixtureMember(
              id: 'linked-member',
              name: 'Alice',
              pluralkitUuid: 'pk-member-1',
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            pkFixtureEntry(
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
            pkFixtureMember(
              id: 'member-a',
              name: 'Alice',
              pluralkitUuid: 'pk-member-a',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            pkFixtureGroup(
              id: 'winner',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 1),
              pluralkitUuid: 'pk-group-1',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            pkFixtureGroup(
              id: 'loser',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 2),
              pluralkitUuid: 'pk-group-1',
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            pkFixtureGroup(
              id: 'child',
              name: 'Child',
              createdAt: DateTime(2024, 1, 3),
              parentGroupId: 'loser',
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            pkFixtureEntry(
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

  test(
    'repair canonicalizes legacy PK entry ids and revives canonical tombstones',
    () async {
      const pkGroupUuid = 'pk-group-1';
      const pkMemberUuid = 'pk-member-a';
      final canonicalEntryId = pkFixtureCanonicalEntryId(pkGroupUuid, pkMemberUuid);

      await db
          .into(db.members)
          .insert(
            pkFixtureMember(id: 'member-a', name: 'Alice', pluralkitUuid: pkMemberUuid),
          );
      await db
          .into(db.memberGroups)
          .insert(
            pkFixtureGroup(
              id: 'group-a',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 1),
              pluralkitUuid: pkGroupUuid,
            ),
          );

      // Legacy-id active row for the logical PK edge.
      await db
          .into(db.memberGroupEntries)
          .insert(
            pkFixtureEntry(
              id: 'random-legacy',
              groupId: 'group-a',
              memberId: 'member-a',
              pkGroupUuid: pkGroupUuid,
              pkMemberUuid: pkMemberUuid,
            ),
          );
      // Canonical-id tombstone for the same logical edge.
      await db
          .into(db.memberGroupEntries)
          .insert(
            pkFixtureEntry(
              id: canonicalEntryId,
              groupId: 'group-a',
              memberId: 'member-a',
              pkGroupUuid: pkGroupUuid,
              pkMemberUuid: pkMemberUuid,
              isDeleted: true,
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

      final report = await service.run(allowStoredToken: false);

      expect(report.canonicalizedEntryIds, 0);
      expect(report.revivedTombstonesDuringCanonicalization, 1);
      expect(report.legacyEntriesSoftDeletedDuringCanonicalization, 1);

      // Canonical row is now active.
      final canonicalRow = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals(canonicalEntryId))).getSingle();
      expect(canonicalRow.isDeleted, isFalse);
      expect(canonicalRow.groupId, 'group-a');
      expect(canonicalRow.memberId, 'member-a');

      // Legacy row is soft-deleted.
      final legacyRow = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals('random-legacy'))).getSingle();
      expect(legacyRow.isDeleted, isTrue);

      // Exactly one active row for the logical edge.
      final activeForEdge =
          await (db.select(db.memberGroupEntries)..where(
                (t) =>
                    t.groupId.equals('group-a') &
                    t.memberId.equals('member-a') &
                    t.isDeleted.equals(false),
              ))
              .get();
      expect(activeForEdge, hasLength(1));
      expect(activeForEdge.single.id, canonicalEntryId);
    },
  );

  test(
    'repair canonicalizes legacy entry ids before merging duplicate groups',
    () async {
      await db.customStatement('DROP INDEX idx_member_groups_pluralkit_uuid');

      const pkGroupUuid = 'pk-group-1';
      const pkMemberUuid = 'pk-member-a';
      final canonicalEntryId = pkFixtureCanonicalEntryId(pkGroupUuid, pkMemberUuid);

      await db
          .into(db.members)
          .insert(
            pkFixtureMember(id: 'member-a', name: 'Alice', pluralkitUuid: pkMemberUuid),
          );
      await db.into(db.members).insert(pkFixtureMember(id: 'member-b', name: 'Bob'));
      await db
          .into(db.memberGroups)
          .insert(
            pkFixtureGroup(
              id: 'winner',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 1),
              pluralkitUuid: pkGroupUuid,
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            pkFixtureGroup(
              id: 'loser',
              name: 'Cluster',
              createdAt: DateTime(2024, 1, 2),
              pluralkitUuid: pkGroupUuid,
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            pkFixtureEntry(
              id: 'legacy-loser-entry',
              groupId: 'loser',
              memberId: 'member-a',
              pkGroupUuid: pkGroupUuid,
              pkMemberUuid: pkMemberUuid,
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            pkFixtureEntry(id: 'winner-b', groupId: 'winner', memberId: 'member-b'),
          );

      final service = PkGroupRepairService(
        memberGroupsDao: db.memberGroupsDao,
        aliasesDao: db.pkGroupSyncAliasesDao,
        hasRepairToken: ({String? token}) async => false,
        fetchRepairReferenceData: ({String? token}) async {
          throw StateError('unexpected fetch');
        },
      );

      final report = await service.run(allowStoredToken: false);

      expect(report.canonicalizedEntryIds, 1);
      expect(report.duplicateSetsMerged, 1);
      expect(report.entriesRehomed, 1);

      final row = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals(canonicalEntryId))).getSingle();
      expect(row.groupId, 'winner');
      expect(row.memberId, 'member-a');
      expect(row.isDeleted, isFalse);
    },
  );
}
