import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/data/repositories/drift_fronting_session_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_groups_repository.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/domain/models/member_group.dart'
    as group_domain;
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/members/providers/member_stats_providers.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/services/stress_data_generator.dart';
import 'package:prism_plurality/shared/providers/member_avatar_image_provider.dart';

const _memberUiPreset = StressPreset(
  label: 'Member UI Performance',
  members: 300,
  sessions: 8000,
  conversations: 80,
  messages: 8000,
  habits: 80,
  completions: 4000,
  notes: 300,
  polls: 80,
  groups: 120,
  customFields: 20,
  years: 3,
  estimatedSizeMb: 80,
  estimatedSeconds: 20,
  realisticProfiles: true,
  groupMembershipsPerMember: 12,
  customFieldValueCoverage: 0.85,
  imageLibraryItems: 40,
  memberAvatarEvery: 3,
  memberHeaderEvery: 7,
  groupAvatarEvery: 4,
  groupNestingDepth: 8,
  frontingDenseHistory: true,
  frontingMaxMembersPerSession: 5,
  activeFrontingMembers: 5,
);

Future<T> _expectUnder<T>(
  String label,
  FutureOr<T> Function() body, {
  required int budgetMs,
}) async {
  final sw = Stopwatch()..start();
  final result = await body();
  sw.stop();
  // Keep the measured wall-clock visible in expanded test output so local
  // benchmark runs can be compared without intentionally failing the test.
  // ignore: avoid_print
  print('$label: ${sw.elapsedMilliseconds}ms');
  expect(
    sw.elapsedMilliseconds,
    lessThan(budgetMs),
    reason: '$label should stay comfortably below ${budgetMs}ms',
  );
  return result;
}

void main() {
  late AppDatabase db;
  late DriftMemberRepository memberRepo;
  late DriftMemberGroupsRepository groupRepo;
  late DriftFrontingSessionRepository sessionRepo;
  late DriftCustomFieldsRepository customFieldsRepo;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    final generator = StressDataGenerator(db);
    await for (final _ in generator.generate(_memberUiPreset)) {}
    memberRepo = DriftMemberRepository(db.membersDao, null);
    groupRepo = DriftMemberGroupsRepository(
      db.memberGroupsDao,
      null,
      memberRepository: memberRepo,
    );
    sessionRepo = DriftFrontingSessionRepository(db.frontingSessionsDao, null);
    customFieldsRepo = DriftCustomFieldsRepository(db.customFieldsDao, null);
  });

  tearDownAll(() async {
    await db.close();
  });

  test(
    'member startup providers build nested group surfaces quickly',
    () async {
      final members = await memberRepo.getAllMembers();
      final listMembers = await memberRepo.watchAllMembersForList().first;
      final groups = await groupRepo.getAllGroups();
      final entries = await groupRepo.getAllGroupEntries();

      expect(members.length, _memberUiPreset.members);
      expect(listMembers.length, members.length);
      expect(
        listMembers.any((member) => member.avatarImageData != null),
        isFalse,
      );
      expect(
        listMembers.any((member) => member.profileHeaderImageData != null),
        isFalse,
      );
      expect(
        listMembers.any((member) => member.pkBannerImageData != null),
        isFalse,
      );
      expect(groups.length, _memberUiPreset.groups);
      expect(groups.any((group) => group.parentGroupId != null), isTrue);

      final activeListMembers = listMembers
          .where((member) => member.isActive)
          .toList();
      final container = ProviderContainer(
        overrides: [
          allMembersProvider.overrideWithValue(AsyncValue.data(members)),
          activeMembersProvider.overrideWithValue(
            AsyncValue.data(
              members.where((member) => member.isActive).toList(),
            ),
          ),
          allMemberListProvider.overrideWithValue(AsyncValue.data(listMembers)),
          activeMemberListProvider.overrideWithValue(
            AsyncValue.data(activeListMembers),
          ),
          allGroupsProvider.overrideWithValue(AsyncValue.data(groups)),
          allGroupEntriesProvider.overrideWithValue(AsyncValue.data(entries)),
          membersGroupedDefaultStateProvider.overrideWithValue(
            MembersGroupedDefaultState.open,
          ),
        ],
      );
      addTearDown(container.dispose);

      await _expectUnder('member grouped startup providers', () {
        final tree = container.read(groupTreeProvider);
        final flatGroups = container.read(flatGroupListProvider);
        final counts = container.read(groupMemberCountsProvider);
        final grouped = container.read(groupedMemberListProvider);
        final maxDepth = flatGroups.fold<int>(
          0,
          (current, item) => item.depth > current ? item.depth : current,
        );
        expect(tree, isNotEmpty);
        expect(maxDepth, _memberUiPreset.groupNestingDepth - 1);
        expect(counts.length, groups.length);
        expect(grouped.whereType<GroupSectionItem>().length, groups.length);
      }, budgetMs: 600);
    },
  );

  test('pk sync member provider keeps image blobs out of AppShell', () async {
    final fullMembers = await memberRepo.getAllMembers();
    final mediaMember = fullMembers.firstWhere(
      (member) =>
          member.avatarImageData != null &&
          member.profileHeaderImageData != null &&
          member.bio != null,
    );

    final pkSyncMembers = await memberRepo.watchAllMembersForPkSync().first;
    final pkSyncMember = pkSyncMembers.firstWhere(
      (member) => member.id == mediaMember.id,
    );

    expect(pkSyncMembers, hasLength(fullMembers.length));
    expect(pkSyncMember.bio, mediaMember.bio);
    expect(pkSyncMember.pronouns, mediaMember.pronouns);
    expect(pkSyncMember.pluralkitId, mediaMember.pluralkitId);
    expect(pkSyncMember.pluralkitDisplayName, mediaMember.pluralkitDisplayName);
    expect(
      pkSyncMembers.any((member) => member.avatarImageData != null),
      isFalse,
    );
    expect(
      pkSyncMembers.any((member) => member.profileHeaderImageData != null),
      isFalse,
    );
    expect(
      pkSyncMembers.any((member) => member.pkBannerImageData != null),
      isFalse,
    );
  });

  test('light list members still hydrate avatar bytes by id', () async {
    final fullMembers = await memberRepo.getAllMembers();
    final mediaMember = fullMembers.firstWhere(
      (member) => member.avatarImageData != null,
    );

    final listMembers = await memberRepo.watchAllMembersForList().first;
    final listMember = listMembers.firstWhere(
      (member) => member.id == mediaMember.id,
    );
    expect(listMember.avatarImageData, isNull);

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    final avatarProvider = memberAvatarImageDataProvider(mediaMember.id);
    final avatarSubscription = container.listen(
      avatarProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(avatarSubscription.close);

    final hydratedBytes = await container.read(avatarProvider.future);
    expect(hydratedBytes, isNotNull);
    expect(hydratedBytes, orderedEquals(mediaMember.avatarImageData!));

    final missingProvider = memberAvatarImageDataProvider('missing-member');
    final missingSubscription = container.listen(
      missingProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(missingSubscription.close);

    final missingBytes = await container.read(missingProvider.future);
    expect(missingBytes, isNull);
  });

  test('large member and group reorder writes stay bounded', () async {
    final members = await memberRepo.getAllMembers();
    final reversedMembers = members.reversed.toList();

    await _expectUnder(
      'member reorder',
      () => memberRepo.reorderMembers(reversedMembers),
      budgetMs: 1000,
    );
    final reorderedMembers = await memberRepo.getAllMembers();
    expect(reorderedMembers.first.id, reversedMembers.first.id);
    expect(reorderedMembers.first.displayOrder, 0);

    final groups = await groupRepo.getAllGroups();
    final siblingsByParent = <String?, List<group_domain.MemberGroup>>{};
    for (final group in groups) {
      siblingsByParent.putIfAbsent(group.parentGroupId, () => []).add(group);
    }
    final siblings = siblingsByParent.values.reduce(
      (a, b) => a.length >= b.length ? a : b,
    )..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    expect(siblings.length, greaterThan(1));

    final reversedGroups = siblings.reversed.toList();
    await _expectUnder(
      'group reorder',
      () => groupRepo.reorderGroups(reversedGroups),
      budgetMs: 1000,
    );
    final refreshedGroups = {
      for (final group in await groupRepo.getAllGroups()) group.id: group,
    };
    expect(refreshedGroups[reversedGroups.first.id]!.displayOrder, 0);
  });

  test('fronting-based member ordering aggregates stats once', () async {
    final members = await memberRepo.getAllMembers();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        frontingSessionRepositoryProvider.overrideWithValue(sessionRepo),
      ],
    );
    addTearDown(container.dispose);

    await _expectUnder('fronting stats aggregate and sort', () async {
      final statsMap = await container.read(
        allMemberFrontingStatsProvider.future,
      );
      expect(statsMap, isNotEmpty);

      final sorted = [...members]
        ..sort((a, b) {
          final aDuration = statsMap[a.id]?.totalDuration ?? Duration.zero;
          final bDuration = statsMap[b.id]?.totalDuration ?? Duration.zero;
          return bDuration.compareTo(aDuration);
        });
      expect(sorted.length, members.length);
      expect(statsMap[sorted.first.id]?.totalDuration, isNotNull);
    }, budgetMs: 1000);
  });

  test(
    'member edit, custom field edit, group membership, and session edit',
    () async {
      final members = await memberRepo.getAllMembers();
      final member = members.firstWhere((m) => m.id == 'stress-member-42');
      final mediaMember = members.firstWhere(
        (m) => m.profileHeaderImageData != null && m.bio != null,
      );
      final mediaListMember = (await memberRepo.watchAllMembersForList().first)
          .firstWhere((m) => m.id == mediaMember.id);
      expect(mediaListMember.bio, isNull);
      expect(mediaListMember.profileHeaderImageData, isNull);

      await _expectUnder(
        'member active sparse edit from list row',
        () => memberRepo.updateMemberFields(mediaListMember.id, {
          'is_active': !mediaListMember.isActive,
        }),
        budgetMs: 1000,
      );
      final mediaMemberAfter = await memberRepo.getMemberById(mediaMember.id);
      expect(mediaMemberAfter!.bio, mediaMember.bio);
      expect(
        mediaMemberAfter.profileHeaderImageData!.length,
        mediaMember.profileHeaderImageData!.length,
      );

      await _expectUnder(
        'member profile edit',
        () => memberRepo.updateMember(
          member.copyWith(
            bio: '${member.bio ?? ''}\n\nPerformance smoke profile edit.',
          ),
        ),
        budgetMs: 1000,
      );
      expect(
        (await memberRepo.getMemberById(member.id))!.bio,
        contains('Performance smoke profile edit'),
      );

      final fields = await customFieldsRepo.getAllFields();
      final field = fields.firstWhere(_isProfileValueField);
      final existingValue = await customFieldsRepo.getValueForField(
        field.id,
        member.id,
      );
      await _expectUnder(
        'custom field value edit',
        () => customFieldsRepo.upsertValue(
          CustomFieldValue(
            id:
                existingValue?.id ??
                'stress-cfv-smoke-${field.id}-${member.id}',
            customFieldId: field.id,
            memberId: member.id,
            value: 'performance smoke value',
          ),
        ),
        budgetMs: 1000,
      );
      expect(
        (await customFieldsRepo.getValueForField(field.id, member.id))!.value,
        'performance smoke value',
      );

      final groups = await groupRepo.getAllGroups();
      final entries = await groupRepo.getAllGroupEntries();
      final targetGroup = groups.first;
      final existingMemberIds = entries
          .where((entry) => entry.groupId == targetGroup.id)
          .map((entry) => entry.memberId)
          .toSet();
      final memberToAdd = members.firstWhere(
        (candidate) => !existingMemberIds.contains(candidate.id),
      );
      await _expectUnder(
        'group membership add',
        () => groupRepo.addMemberToGroup(
          targetGroup.id,
          memberToAdd.id,
          'stress-entry-smoke-${targetGroup.id}-${memberToAdd.id}',
        ),
        budgetMs: 1000,
      );
      final updatedEntries = await groupRepo.getAllGroupEntries();
      expect(
        updatedEntries.any(
          (entry) =>
              entry.groupId == targetGroup.id &&
              entry.memberId == memberToAdd.id,
        ),
        isTrue,
      );

      final session = (await sessionRepo.getAllSessions()).first;
      await _expectUnder(
        'fronting session edit',
        () => sessionRepo.updateSession(
          session.copyWith(notes: 'performance smoke session edit'),
        ),
        budgetMs: 1000,
      );
      expect(
        (await sessionRepo.getSessionById(session.id))!.notes,
        'performance smoke session edit',
      );
    },
  );
}

bool _isProfileValueField(CustomField field) {
  if (field.fieldTypeId == 'group') return false;
  return switch (field.fieldType) {
    CustomFieldType.text ||
    CustomFieldType.longText ||
    CustomFieldType.choice => true,
    CustomFieldType.color || CustomFieldType.date => false,
  };
}
