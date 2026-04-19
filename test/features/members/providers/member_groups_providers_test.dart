import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

MemberGroup _group({
  required String id,
  String? parentGroupId,
  DateTime? createdAt,
}) =>
    MemberGroup(
      id: id,
      name: id,
      createdAt: createdAt ?? DateTime(2024, 1, 1),
      parentGroupId: parentGroupId,
    );

Member _member({required String id, bool isActive = true}) => Member(
      id: id,
      name: id,
      createdAt: DateTime(2024, 1, 1),
      isActive: isActive,
    );

MemberGroupEntry _entry({required String groupId, required String memberId}) =>
    MemberGroupEntry(id: '$groupId:$memberId', groupId: groupId, memberId: memberId);

ProviderContainer makeContainer({
  List<MemberGroup> groups = const [],
  List<MemberGroupEntry> entries = const [],
  List<Member> members = const [],
}) =>
    ProviderContainer(
      overrides: [
        allGroupsProvider.overrideWithValue(AsyncValue.data(groups)),
        allGroupEntriesProvider.overrideWithValue(AsyncValue.data(entries)),
        allMembersProvider.overrideWithValue(AsyncValue.data(members)),
      ],
    );

// ── groupedMemberListProvider ─────────────────────────────────────────────────

void main() {
  group('groupedMemberListProvider', () {
    test('empty state produces empty list', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      expect(c.read(groupedMemberListProvider), isEmpty);
    });

    test('single root group with one member produces header then member row',
        () {
      final c = makeContainer(
        groups: [_group(id: 'root')],
        entries: [_entry(groupId: 'root', memberId: 'm1')],
        members: [_member(id: 'm1')],
      );
      addTearDown(c.dispose);

      final list = c.read(groupedMemberListProvider);
      expect(list, hasLength(2));
      expect(list[0], isA<GroupSectionItem>());
      expect((list[0] as GroupSectionItem).group.id, 'root');
      expect(list[1], isA<MemberRowItem>());
      expect((list[1] as MemberRowItem).member.id, 'm1');
    });

    test('two-level tree: child header appears before root members', () {
      final root = _group(id: 'root');
      final child = _group(id: 'child', parentGroupId: 'root');
      final c = makeContainer(
        groups: [root, child],
        entries: [
          _entry(groupId: 'root', memberId: 'm-root'),
          _entry(groupId: 'child', memberId: 'm-child'),
        ],
        members: [_member(id: 'm-root'), _member(id: 'm-child')],
      );
      addTearDown(c.dispose);

      final list = c.read(groupedMemberListProvider);
      // root header → child header → child member → root member
      expect(list[0], isA<GroupSectionItem>());
      expect((list[0] as GroupSectionItem).group.id, 'root');
      expect(list[1], isA<GroupSectionItem>());
      expect((list[1] as GroupSectionItem).group.id, 'child');
      expect(list[2], isA<MemberRowItem>());
      expect((list[2] as MemberRowItem).member.id, 'm-child');
      expect(list[3], isA<MemberRowItem>());
      expect((list[3] as MemberRowItem).member.id, 'm-root');
    });

    test('depth is 0 for root, 1 for child', () {
      final c = makeContainer(
        groups: [_group(id: 'root'), _group(id: 'child', parentGroupId: 'root')],
      );
      addTearDown(c.dispose);

      final list = c.read(groupedMemberListProvider);
      expect((list[0] as GroupSectionItem).depth, 0);
      expect((list[1] as GroupSectionItem).depth, 1);
    });

    test('collapsing root hides child header and all member rows', () {
      final c = makeContainer(
        groups: [_group(id: 'root'), _group(id: 'child', parentGroupId: 'root')],
        entries: [_entry(groupId: 'child', memberId: 'm1')],
        members: [_member(id: 'm1')],
      );
      addTearDown(c.dispose);

      c.read(collapsedGroupsProvider.notifier).toggle('root');

      final list = c.read(groupedMemberListProvider);
      // Only the root header should remain; child header and member row hidden.
      expect(list, hasLength(1));
      expect(list[0], isA<GroupSectionItem>());
      expect((list[0] as GroupSectionItem).isCollapsed, isTrue);
    });

    test('collapsing child hides only child members, not sibling groups', () {
      final c = makeContainer(
        groups: [
          _group(id: 'root'),
          _group(id: 'child-a', parentGroupId: 'root'),
          _group(id: 'child-b', parentGroupId: 'root'),
        ],
        entries: [
          _entry(groupId: 'child-a', memberId: 'm-a'),
          _entry(groupId: 'child-b', memberId: 'm-b'),
        ],
        members: [_member(id: 'm-a'), _member(id: 'm-b')],
      );
      addTearDown(c.dispose);

      c.read(collapsedGroupsProvider.notifier).toggle('child-a');

      final list = c.read(groupedMemberListProvider);
      final groupIds = list.whereType<GroupSectionItem>().map((e) => e.group.id);
      final memberIds = list.whereType<MemberRowItem>().map((e) => e.member.id);
      // child-b section and its member still visible
      expect(groupIds, containsAll(['root', 'child-a', 'child-b']));
      expect(memberIds, contains('m-b'));
      expect(memberIds, isNot(contains('m-a')));
    });

    test('ungrouped section appears for active members with no entry', () {
      final c = makeContainer(
        groups: [_group(id: 'root')],
        members: [_member(id: 'orphan')],
      );
      addTearDown(c.dispose);

      final list = c.read(groupedMemberListProvider);
      expect(list.any((e) => e is UngroupedSectionItem), isTrue);
      expect(
        list.whereType<MemberRowItem>().map((e) => e.member.id),
        contains('orphan'),
      );
    });

    test('ungrouped section absent when all active members are grouped', () {
      final c = makeContainer(
        groups: [_group(id: 'root')],
        entries: [_entry(groupId: 'root', memberId: 'm1')],
        members: [_member(id: 'm1')],
      );
      addTearDown(c.dispose);

      final list = c.read(groupedMemberListProvider);
      expect(list.any((e) => e is UngroupedSectionItem), isFalse);
    });

    test('inactive members are excluded from all sections', () {
      final c = makeContainer(
        groups: [_group(id: 'root')],
        entries: [_entry(groupId: 'root', memberId: 'inactive')],
        members: [_member(id: 'inactive', isActive: false)],
      );
      addTearDown(c.dispose);

      final list = c.read(groupedMemberListProvider);
      expect(list.whereType<MemberRowItem>(), isEmpty);
      expect(list.whereType<UngroupedSectionItem>(), isEmpty);
    });
  });

  // ── CollapsedGroupsNotifier ─────────────────────────────────────────────────

  group('CollapsedGroupsNotifier', () {
    test('starts empty', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      expect(c.read(collapsedGroupsProvider), isEmpty);
    });

    test('toggle adds group ID', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      c.read(collapsedGroupsProvider.notifier).toggle('a');
      expect(c.read(collapsedGroupsProvider), {'a'});
    });

    test('toggle twice removes group ID', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      c.read(collapsedGroupsProvider.notifier).toggle('a');
      c.read(collapsedGroupsProvider.notifier).toggle('a');
      expect(c.read(collapsedGroupsProvider), isEmpty);
    });

    test('expandAll clears all collapsed groups', () {
      final c = makeContainer();
      addTearDown(c.dispose);
      c.read(collapsedGroupsProvider.notifier).toggle('a');
      c.read(collapsedGroupsProvider.notifier).toggle('b');
      c.read(collapsedGroupsProvider.notifier).expandAll();
      expect(c.read(collapsedGroupsProvider), isEmpty);
    });
  });

  // ── groupMemberCountsProvider ─────────────────────────────────────────────

  group('groupMemberCountsProvider', () {
    test('root count includes direct and descendant members', () {
      final c = makeContainer(
        groups: [_group(id: 'root'), _group(id: 'child', parentGroupId: 'root')],
        entries: [
          _entry(groupId: 'root', memberId: 'm-root'),
          _entry(groupId: 'child', memberId: 'm-child'),
        ],
        members: [_member(id: 'm-root'), _member(id: 'm-child')],
      );
      addTearDown(c.dispose);

      final counts = c.read(groupMemberCountsProvider);
      expect(counts['root'], 2);
      expect(counts['child'], 1);
    });

    test('member in multiple groups is counted once per group it belongs to',
        () {
      final c = makeContainer(
        groups: [
          _group(id: 'root'),
          _group(id: 'child-a', parentGroupId: 'root'),
          _group(id: 'child-b', parentGroupId: 'root'),
        ],
        entries: [
          _entry(groupId: 'child-a', memberId: 'shared'),
          _entry(groupId: 'child-b', memberId: 'shared'),
        ],
        members: [_member(id: 'shared')],
      );
      addTearDown(c.dispose);

      final counts = c.read(groupMemberCountsProvider);
      // Root sees 'shared' from both children but deduplicates to 1.
      expect(counts['root'], 1);
    });

    test('empty groups have count 0', () {
      final c = makeContainer(
        groups: [_group(id: 'empty')],
      );
      addTearDown(c.dispose);

      expect(c.read(groupMemberCountsProvider)['empty'], 0);
    });
  });

  // ── transitiveGroupMemberIdsProvider ─────────────────────────────────────

  group('transitiveGroupMemberIdsProvider', () {
    test('leaf group returns only its direct members', () {
      final c = makeContainer(
        groups: [_group(id: 'leaf')],
        entries: [_entry(groupId: 'leaf', memberId: 'm1')],
        members: [_member(id: 'm1')],
      );
      addTearDown(c.dispose);

      expect(c.read(transitiveGroupMemberIdsProvider('leaf')), {'m1'});
    });

    test('root group includes members from all descendant groups', () {
      final c = makeContainer(
        groups: [
          _group(id: 'root'),
          _group(id: 'child', parentGroupId: 'root'),
        ],
        entries: [
          _entry(groupId: 'root', memberId: 'm-root'),
          _entry(groupId: 'child', memberId: 'm-child'),
        ],
        members: [_member(id: 'm-root'), _member(id: 'm-child')],
      );
      addTearDown(c.dispose);

      expect(c.read(transitiveGroupMemberIdsProvider('root')),
          {'m-root', 'm-child'});
    });

    test('empty group returns empty set', () {
      final c = makeContainer(
        groups: [_group(id: 'empty')],
      );
      addTearDown(c.dispose);

      expect(c.read(transitiveGroupMemberIdsProvider('empty')), isEmpty);
    });
  });
}
