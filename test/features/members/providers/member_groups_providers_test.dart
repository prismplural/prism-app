import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/group_sort_mode.dart';
import 'package:prism_plurality/domain/models/group_sort_state.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

MemberGroup _group({
  required String id,
  String? parentGroupId,
  DateTime? createdAt,
}) => MemberGroup(
  id: id,
  name: id,
  createdAt: createdAt ?? DateTime(2024, 1, 1),
  parentGroupId: parentGroupId,
);

Member _member({
  required String id,
  bool isActive = true,
  int displayOrder = 0,
}) => Member(
  id: id,
  name: id,
  createdAt: DateTime(2024, 1, 1),
  isActive: isActive,
  displayOrder: displayOrder,
);

MemberGroupEntry _entry({required String groupId, required String memberId}) =>
    MemberGroupEntry(
      id: '$groupId:$memberId',
      groupId: groupId,
      memberId: memberId,
    );

ProviderContainer makeContainer({
  List<MemberGroup> groups = const [],
  List<MemberGroupEntry> entries = const [],
  List<Member> members = const [],
  MembersGroupedDefaultState groupedDefaultState =
      MembersGroupedDefaultState.open,
}) => ProviderContainer(
  overrides: [
    allGroupsProvider.overrideWithValue(AsyncValue.data(groups)),
    allGroupEntriesProvider.overrideWithValue(AsyncValue.data(entries)),
    allMembersProvider.overrideWithValue(AsyncValue.data(members)),
    allMemberListProvider.overrideWithValue(AsyncValue.data(members)),
    membersByIdsListProvider.overrideWith((ref, idsKey) {
      final ids = idsKey.isEmpty ? const <String>{} : idsKey.split(',').toSet();
      return Stream.value({
        for (final member in members)
          if (ids.contains(member.id)) member.id: member,
      });
    }),
    activeMemberListProvider.overrideWithValue(
      AsyncValue.data(members.where((member) => member.isActive).toList()),
    ),
    membersGroupedDefaultStateProvider.overrideWithValue(groupedDefaultState),
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

    test(
      'single root group with one member produces header then member row',
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
      },
    );

    test('group member rows follow member displayOrder, not entry order', () {
      final c = makeContainer(
        groups: [_group(id: 'root')],
        entries: [
          _entry(groupId: 'root', memberId: 'charlie'),
          _entry(groupId: 'root', memberId: 'alex'),
          _entry(groupId: 'root', memberId: 'bea'),
        ],
        members: [
          _member(id: 'charlie', displayOrder: 2),
          _member(id: 'alex', displayOrder: 0),
          _member(id: 'bea', displayOrder: 1),
        ],
      );
      addTearDown(c.dispose);

      final memberIds = c
          .read(groupedMemberListProvider)
          .whereType<MemberRowItem>()
          .map((item) => item.member.id);
      expect(memberIds, ['alex', 'bea', 'charlie']);
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
        members: [
          _member(id: 'm-root'),
          _member(id: 'm-child'),
        ],
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
        groups: [
          _group(id: 'root'),
          _group(id: 'child', parentGroupId: 'root'),
        ],
      );
      addTearDown(c.dispose);

      final list = c.read(groupedMemberListProvider);
      expect((list[0] as GroupSectionItem).depth, 0);
      expect((list[1] as GroupSectionItem).depth, 1);
    });

    test('collapsing root hides child header and all member rows', () {
      final c = makeContainer(
        groups: [
          _group(id: 'root'),
          _group(id: 'child', parentGroupId: 'root'),
        ],
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

    test('closed default starts every group collapsed', () {
      final c = makeContainer(
        groupedDefaultState: MembersGroupedDefaultState.closed,
        groups: [
          _group(id: 'root'),
          _group(id: 'child', parentGroupId: 'root'),
        ],
        entries: [_entry(groupId: 'child', memberId: 'm1')],
        members: [_member(id: 'm1')],
      );
      addTearDown(c.dispose);

      final list = c.read(groupedMemberListProvider);
      expect(list, hasLength(1));
      expect((list.single as GroupSectionItem).group.id, 'root');
      expect((list.single as GroupSectionItem).isCollapsed, isTrue);

      c.read(collapsedGroupsProvider.notifier).expandAll();
      final expanded = c.read(groupedMemberListProvider);
      expect(expanded.whereType<GroupSectionItem>(), hasLength(2));
      expect(expanded.whereType<MemberRowItem>(), hasLength(1));
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
        members: [
          _member(id: 'm-a'),
          _member(id: 'm-b'),
        ],
      );
      addTearDown(c.dispose);

      c.read(collapsedGroupsProvider.notifier).toggle('child-a');

      final list = c.read(groupedMemberListProvider);
      final groupIds = list.whereType<GroupSectionItem>().map(
        (e) => e.group.id,
      );
      final memberIds = list.whereType<MemberRowItem>().map((e) => e.member.id);
      // child-b section and its member still visible
      expect(groupIds, containsAll(['root', 'child-a', 'child-b']));
      expect(memberIds, contains('m-b'));
      expect(memberIds, isNot(contains('m-a')));
    });

    test(
      'collapsing the LAST child does not hide the parent\'s direct members',
      () {
        // Reproduces the bug where collapsing the last child subgroup hid
        // ancestor groups' direct members because the depth-reset only fired on
        // a subsequent GroupSectionItem.
        //
        //   root  ──── m-root          (parent's direct members emitted last)
        //    ├── child-a
        //    └── child-b ── m-child-b  (LAST child)
        //
        // Collapsing child-b should leave m-root and child-a visible.
        final c = makeContainer(
          groups: [
            _group(id: 'root'),
            _group(id: 'child-a', parentGroupId: 'root'),
            _group(id: 'child-b', parentGroupId: 'root'),
          ],
          entries: [
            _entry(groupId: 'root', memberId: 'm-root'),
            _entry(groupId: 'child-b', memberId: 'm-child-b'),
          ],
          members: [
            _member(id: 'm-root'),
            _member(id: 'm-child-b'),
          ],
        );
        addTearDown(c.dispose);

        c.read(collapsedGroupsProvider.notifier).toggle('child-b');

        final list = c.read(groupedMemberListProvider);
        final memberIds = list.whereType<MemberRowItem>().map(
          (e) => e.member.id,
        );
        // child-b is collapsed: its own member hidden, but root's direct member
        // (emitted after child-b's subtree in DFS) must still appear.
        expect(memberIds, contains('m-root'));
        expect(memberIds, isNot(contains('m-child-b')));
      },
    );

    test(
      'collapsing the LAST grandchild does not hide ancestor members two levels up',
      () {
        // User-reported scenario:
        //   group-b
        //    ├── subgroup-a
        //    │    └── subsubgroup-a (LAST child of subgroup-a)
        //    └── subgroup-b
        //         ├── subsubgroup-b
        //         └── subsubgroup-c (LAST child of subgroup-b, LAST overall)
        //
        // Collapsing subsubgroup-c must leave subgroup-b's and group-b's
        // direct members visible.
        final c = makeContainer(
          groups: [
            _group(id: 'group-b'),
            _group(id: 'subgroup-a', parentGroupId: 'group-b'),
            _group(id: 'subsubgroup-a', parentGroupId: 'subgroup-a'),
            _group(id: 'subgroup-b', parentGroupId: 'group-b'),
            _group(id: 'subsubgroup-b', parentGroupId: 'subgroup-b'),
            _group(id: 'subsubgroup-c', parentGroupId: 'subgroup-b'),
          ],
          entries: [
            _entry(groupId: 'group-b', memberId: 'm-gb'),
            _entry(groupId: 'subgroup-a', memberId: 'm-sga'),
            _entry(groupId: 'subgroup-b', memberId: 'm-sgb'),
            _entry(groupId: 'subsubgroup-c', memberId: 'm-ssc'),
          ],
          members: [
            _member(id: 'm-gb'),
            _member(id: 'm-sga'),
            _member(id: 'm-sgb'),
            _member(id: 'm-ssc'),
          ],
        );
        addTearDown(c.dispose);

        c.read(collapsedGroupsProvider.notifier).toggle('subsubgroup-c');

        final list = c.read(groupedMemberListProvider);
        final memberIds = list.whereType<MemberRowItem>().map(
          (e) => e.member.id,
        );
        expect(memberIds, contains('m-gb'));
        expect(memberIds, contains('m-sgb'));
        expect(memberIds, contains('m-sga'));
        expect(memberIds, isNot(contains('m-ssc')));
      },
    );

    test(
      'collapsing mid-level group hides its sub-group header and members',
      () {
        // 3-level: root → mid → leaf (with a member in leaf)
        final c = makeContainer(
          groups: [
            _group(id: 'root'),
            _group(id: 'mid', parentGroupId: 'root'),
            _group(id: 'leaf', parentGroupId: 'mid'),
          ],
          entries: [_entry(groupId: 'leaf', memberId: 'm-leaf')],
          members: [_member(id: 'm-leaf')],
        );
        addTearDown(c.dispose);

        c.read(collapsedGroupsProvider.notifier).toggle('mid');

        final list = c.read(groupedMemberListProvider);
        final groupIds = list.whereType<GroupSectionItem>().map(
          (e) => e.group.id,
        );
        final memberIds = list.whereType<MemberRowItem>().map(
          (e) => e.member.id,
        );
        // root and mid headers remain; leaf header and its member row hidden
        expect(groupIds, containsAll(['root', 'mid']));
        expect(groupIds, isNot(contains('leaf')));
        expect(memberIds, isNot(contains('m-leaf')));
      },
    );

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
        groups: [
          _group(id: 'root'),
          _group(id: 'child', parentGroupId: 'root'),
        ],
        entries: [
          _entry(groupId: 'root', memberId: 'm-root'),
          _entry(groupId: 'child', memberId: 'm-child'),
        ],
        members: [
          _member(id: 'm-root'),
          _member(id: 'm-child'),
        ],
      );
      addTearDown(c.dispose);

      final counts = c.read(groupMemberCountsProvider);
      expect(counts['root'], 2);
      expect(counts['child'], 1);
    });

    test(
      'member in multiple groups is counted once per group it belongs to',
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
      },
    );

    test('empty groups have count 0', () {
      final c = makeContainer(groups: [_group(id: 'empty')]);
      addTearDown(c.dispose);

      expect(c.read(groupMemberCountsProvider)['empty'], 0);
    });

    test('inactive members are excluded while hidden', () {
      final c = makeContainer(
        groups: [
          _group(id: 'root'),
          _group(id: 'child', parentGroupId: 'root'),
        ],
        entries: [
          _entry(groupId: 'root', memberId: 'active'),
          _entry(groupId: 'child', memberId: 'inactive'),
        ],
        members: [
          _member(id: 'active'),
          _member(id: 'inactive', isActive: false),
        ],
      );
      addTearDown(c.dispose);

      final counts = c.read(groupMemberCountsProvider);
      expect(counts['root'], 1);
      expect(counts['child'], 0);
    });

    test('inactive members are included when show inactive is enabled', () {
      final c = makeContainer(
        groups: [
          _group(id: 'root'),
          _group(id: 'child', parentGroupId: 'root'),
        ],
        entries: [
          _entry(groupId: 'root', memberId: 'active'),
          _entry(groupId: 'child', memberId: 'inactive'),
        ],
        members: [
          _member(id: 'active'),
          _member(id: 'inactive', isActive: false),
        ],
      );
      addTearDown(c.dispose);

      c.read(showInactiveMembersProvider.notifier).set(true);

      final counts = c.read(groupMemberCountsProvider);
      expect(counts['root'], 2);
      expect(counts['child'], 1);
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
        members: [
          _member(id: 'm-root'),
          _member(id: 'm-child'),
        ],
      );
      addTearDown(c.dispose);

      expect(c.read(transitiveGroupMemberIdsProvider('root')), {
        'm-root',
        'm-child',
      });
    });

    test('empty group returns empty set', () {
      final c = makeContainer(groups: [_group(id: 'empty')]);
      addTearDown(c.dispose);

      expect(c.read(transitiveGroupMemberIdsProvider('empty')), isEmpty);
    });

    test('3-level hierarchy: root includes grandchild members', () {
      final c = makeContainer(
        groups: [
          _group(id: 'root'),
          _group(id: 'child', parentGroupId: 'root'),
          _group(id: 'grandchild', parentGroupId: 'child'),
        ],
        entries: [
          _entry(groupId: 'root', memberId: 'm-root'),
          _entry(groupId: 'child', memberId: 'm-child'),
          _entry(groupId: 'grandchild', memberId: 'm-grandchild'),
        ],
        members: [
          _member(id: 'm-root'),
          _member(id: 'm-child'),
          _member(id: 'm-grandchild'),
        ],
      );
      addTearDown(c.dispose);

      expect(c.read(transitiveGroupMemberIdsProvider('root')), {
        'm-root',
        'm-child',
        'm-grandchild',
      });
      expect(c.read(transitiveGroupMemberIdsProvider('child')), {
        'm-child',
        'm-grandchild',
      });
      expect(c.read(transitiveGroupMemberIdsProvider('grandchild')), {
        'm-grandchild',
      });
    });
  });

  // ── sortedGroupMembersProvider ─────────────────────────────────────────────

  group('sortedGroupMembersProvider', () {
    MemberGroup groupWith({required String id, GroupSortState? sortState}) =>
        MemberGroup(
          id: id,
          name: id,
          createdAt: DateTime.utc(2024, 1, 1),
          sortState: sortState ?? GroupSortState.manualEmpty,
        );

    Member memberWith({
      required String id,
      String? name,
      bool isActive = true,
      DateTime? createdAt,
    }) => Member(
      id: id,
      name: name ?? id,
      createdAt: createdAt ?? DateTime.utc(2024, 1, 1),
      isActive: isActive,
    );

    MemberGroupEntry entryWith({
      required String id,
      required String groupId,
      required String memberId,
    }) => MemberGroupEntry(id: id, groupId: groupId, memberId: memberId);

    ProviderContainer container({
      required MemberGroup group,
      required List<MemberGroupEntry> entries,
      required List<Member> members,
      bool showInactive = false,
    }) {
      final c = ProviderContainer(
        overrides: [
          groupByIdProvider(
            group.id,
          ).overrideWith((ref) => Stream<MemberGroup?>.value(group)),
          groupEntriesProvider(group.id).overrideWith(
            (ref) => Stream<List<MemberGroupEntry>>.value(entries),
          ),
          allMembersProvider.overrideWith(
            (ref) => Stream<List<Member>>.value(members),
          ),
          allMemberListProvider.overrideWith(
            (ref) => Stream<List<Member>>.value(members),
          ),
          membersByIdsListProvider.overrideWith((ref, idsKey) {
            final ids = idsKey.isEmpty
                ? const <String>{}
                : idsKey.split(',').toSet();
            return Stream.value({
              for (final member in members)
                if (ids.contains(member.id)) member.id: member,
            });
          }),
        ],
      );
      if (showInactive) {
        c.read(showInactiveMembersProvider.notifier).set(true);
      }
      addTearDown(c.dispose);
      return c;
    }

    // Pump pending stream subscriptions to deliver their first value before
    // we read sortedGroupMembersProvider. StreamProviders start in
    // AsyncLoading until the underlying stream emits, and `Stream.value(x)`
    // emits on the next microtask. The .future getter waits for the first
    // value, so awaiting all three lifts the container into the data state.
    Future<void> pumpStreams(ProviderContainer c, String groupId) async {
      // Keep listeners alive so autoDispose families don't tear down between
      // the .future awaits and the .read of sortedGroupMembersProvider.
      final subs = [
        c.listen(groupByIdProvider(groupId), (_, _) {}),
        c.listen(groupEntriesProvider(groupId), (_, _) {}),
      ];
      addTearDown(() {
        for (final s in subs) {
          s.close();
        }
      });
      await c.read(groupByIdProvider(groupId).future);
      final entries = await c.read(groupEntriesProvider(groupId).future);
      final membersKey = memberIdsKey(entries.map((entry) => entry.memberId));
      final memberSub = c.listen(
        membersByIdsListProvider(membersKey),
        (_, _) {},
      );
      addTearDown(memberSub.close);
      await c.read(membersByIdsListProvider(membersKey).future);
    }

    test(
      'async provider stays loading while member batch hydration is pending',
      () async {
        final group = groupWith(id: 'g');
        final entries = [entryWith(id: 'e1', groupId: 'g', memberId: 'm1')];
        final memberBatchController =
            StreamController<Map<String, Member>>.broadcast();
        final c = ProviderContainer(
          overrides: [
            groupByIdProvider(
              group.id,
            ).overrideWith((ref) => Stream<MemberGroup?>.value(group)),
            groupEntriesProvider(group.id).overrideWith(
              (ref) => Stream<List<MemberGroupEntry>>.value(entries),
            ),
            membersByIdsListProvider.overrideWith(
              (ref, idsKey) => memberBatchController.stream,
            ),
          ],
        );
        addTearDown(() async {
          c.dispose();
          await memberBatchController.close();
        });
        final sub = c.listen(
          sortedGroupMembersAsyncProvider(group.id),
          (_, _) {},
        );
        addTearDown(sub.close);

        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        final loading = c.read(sortedGroupMembersAsyncProvider(group.id));
        expect(loading.isLoading, isTrue);
        expect(c.read(sortedGroupMembersProvider(group.id)), isEmpty);

        memberBatchController.add({'m1': memberWith(id: 'm1')});
        await Future<void>.delayed(Duration.zero);

        final hydrated = c.read(sortedGroupMembersAsyncProvider(group.id));
        expect(hydrated.hasValue, isTrue);
        expect(hydrated.requireValue.single.$2.id, 'm1');
      },
    );

    test(
      'async provider resolves empty groups without member hydration',
      () async {
        final group = groupWith(id: 'g');
        var memberBatchWatched = false;
        final memberBatchController =
            StreamController<Map<String, Member>>.broadcast();
        final c = ProviderContainer(
          overrides: [
            groupByIdProvider(
              group.id,
            ).overrideWith((ref) => Stream<MemberGroup?>.value(group)),
            groupEntriesProvider(group.id).overrideWith(
              (ref) => Stream<List<MemberGroupEntry>>.value(const []),
            ),
            membersByIdsListProvider.overrideWith((ref, idsKey) {
              memberBatchWatched = true;
              return memberBatchController.stream;
            }),
          ],
        );
        addTearDown(() async {
          c.dispose();
          await memberBatchController.close();
        });
        final sub = c.listen(
          sortedGroupMembersAsyncProvider(group.id),
          (_, _) {},
        );
        addTearDown(sub.close);

        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        final result = c.read(sortedGroupMembersAsyncProvider(group.id));
        expect(result.hasValue, isTrue);
        expect(result.requireValue, isEmpty);
        expect(memberBatchWatched, isFalse);
      },
    );

    test(
      'each of the 4 sort modes produces the expected order on a clean 3-member group',
      () async {
        final m1 = memberWith(
          id: 'm1',
          name: 'Charlie',
          createdAt: DateTime.utc(2024, 3, 1),
        );
        final m2 = memberWith(
          id: 'm2',
          name: 'Alex',
          createdAt: DateTime.utc(2024, 1, 1),
        );
        final m3 = memberWith(
          id: 'm3',
          name: 'Bea',
          createdAt: DateTime.utc(2024, 2, 1),
        );
        final entries = [
          entryWith(id: 'e1', groupId: 'g', memberId: 'm1'),
          entryWith(id: 'e2', groupId: 'g', memberId: 'm2'),
          entryWith(id: 'e3', groupId: 'g', memberId: 'm3'),
        ];

        // manual: order follows manualOrder = e2, e3, e1
        final cManual = container(
          group: groupWith(
            id: 'g',
            sortState: const GroupSortState(
              mode: GroupSortMode.manual,
              manualOrder: ['e2', 'e3', 'e1'],
            ),
          ),
          entries: entries,
          members: [m1, m2, m3],
        );
        await pumpStreams(cManual, 'g');
        expect(
          cManual.read(sortedGroupMembersProvider('g')).map((p) => p.$1.id),
          ['e2', 'e3', 'e1'],
        );

        // nameAsc: Alex, Bea, Charlie
        final cAsc = container(
          group: groupWith(
            id: 'g',
            sortState: GroupSortState.locked(GroupSortMode.nameAsc),
          ),
          entries: entries,
          members: [m1, m2, m3],
        );
        await pumpStreams(cAsc, 'g');
        expect(
          cAsc.read(sortedGroupMembersProvider('g')).map((p) => p.$2.name),
          ['Alex', 'Bea', 'Charlie'],
        );

        // nameDesc: Charlie, Bea, Alex
        final cDesc = container(
          group: groupWith(
            id: 'g',
            sortState: GroupSortState.locked(GroupSortMode.nameDesc),
          ),
          entries: entries,
          members: [m1, m2, m3],
        );
        await pumpStreams(cDesc, 'g');
        expect(
          cDesc.read(sortedGroupMembersProvider('g')).map((p) => p.$2.name),
          ['Charlie', 'Bea', 'Alex'],
        );

        // recentDesc: m1 (Mar) → m3 (Feb) → m2 (Jan)
        final cRecent = container(
          group: groupWith(
            id: 'g',
            sortState: GroupSortState.locked(GroupSortMode.recentDesc),
          ),
          entries: entries,
          members: [m1, m2, m3],
        );
        await pumpStreams(cRecent, 'g');
        expect(
          cRecent.read(sortedGroupMembersProvider('g')).map((p) => p.$2.id),
          ['m1', 'm3', 'm2'],
        );
      },
    );

    test('showInactive=false filters inactive in every mode', () async {
      final mActive = memberWith(id: 'a', name: 'Alex');
      final mInactive = memberWith(id: 'b', name: 'Bea', isActive: false);
      final entries = [
        entryWith(id: 'ea', groupId: 'g', memberId: 'a'),
        entryWith(id: 'eb', groupId: 'g', memberId: 'b'),
      ];

      for (final mode in GroupSortMode.values) {
        final state = mode == GroupSortMode.manual
            ? const GroupSortState(
                mode: GroupSortMode.manual,
                manualOrder: ['ea', 'eb'],
              )
            : GroupSortState.locked(mode);
        final c = container(
          group: groupWith(id: 'g', sortState: state),
          entries: entries,
          members: [mActive, mInactive],
        );
        await pumpStreams(c, 'g');
        final ids = c.read(sortedGroupMembersProvider('g')).map((p) => p.$2.id);
        expect(ids, ['a'], reason: 'mode $mode must filter inactive');
      }
    });

    test('unknown member id in an entry is dropped, no crash', () async {
      final m1 = memberWith(id: 'm1');
      // e2 references missing member id 'ghost' — should be dropped.
      final c = container(
        group: groupWith(
          id: 'g',
          sortState: const GroupSortState(
            mode: GroupSortMode.manual,
            manualOrder: ['e1', 'e2'],
          ),
        ),
        entries: [
          entryWith(id: 'e1', groupId: 'g', memberId: 'm1'),
          entryWith(id: 'e2', groupId: 'g', memberId: 'ghost'),
        ],
        members: [m1],
      );
      await pumpStreams(c, 'g');
      final ids = c
          .read(sortedGroupMembersProvider('g'))
          .map((p) => p.$1.id)
          .toList();
      expect(ids, ['e1']);
    });

    test(
      'manual mode: entry id NOT in manualOrder appends at end by id ascending',
      () async {
        // manualOrder lists only e2. e1 and e3 are live but unindexed —
        // appended at end, sorted by entry id ascending. (Invariant §1.)
        final members = [
          memberWith(id: 'm1'),
          memberWith(id: 'm2'),
          memberWith(id: 'm3'),
        ];
        final c = container(
          group: groupWith(
            id: 'g',
            sortState: const GroupSortState(
              mode: GroupSortMode.manual,
              manualOrder: ['e2'],
            ),
          ),
          entries: [
            entryWith(id: 'e3', groupId: 'g', memberId: 'm3'),
            entryWith(id: 'e2', groupId: 'g', memberId: 'm2'),
            entryWith(id: 'e1', groupId: 'g', memberId: 'm1'),
          ],
          members: members,
        );
        await pumpStreams(c, 'g');
        expect(c.read(sortedGroupMembersProvider('g')).map((p) => p.$1.id), [
          'e2',
          'e1',
          'e3',
        ]);
      },
    );

    test(
      'manual mode: id in manualOrder with no live entry is filtered (invariant §2)',
      () async {
        final c = container(
          group: groupWith(
            id: 'g',
            sortState: const GroupSortState(
              mode: GroupSortMode.manual,
              manualOrder: ['e1', 'ghost', 'e2'],
            ),
          ),
          entries: [
            entryWith(id: 'e1', groupId: 'g', memberId: 'm1'),
            entryWith(id: 'e2', groupId: 'g', memberId: 'm2'),
          ],
          members: [
            memberWith(id: 'm1'),
            memberWith(id: 'm2'),
          ],
        );
        await pumpStreams(c, 'g');
        expect(c.read(sortedGroupMembersProvider('g')).map((p) => p.$1.id), [
          'e1',
          'e2',
        ]);
      },
    );

    test(
      'manual mode: duplicate id in manualOrder — second occurrence ignored (invariant §3)',
      () async {
        // First occurrence of e1 wins its position; second occurrence is a
        // no-op in the position map. e2 follows at its own position.
        final c = container(
          group: groupWith(
            id: 'g',
            sortState: const GroupSortState(
              mode: GroupSortMode.manual,
              manualOrder: ['e1', 'e2', 'e1'],
            ),
          ),
          entries: [
            entryWith(id: 'e1', groupId: 'g', memberId: 'm1'),
            entryWith(id: 'e2', groupId: 'g', memberId: 'm2'),
          ],
          members: [
            memberWith(id: 'm1'),
            memberWith(id: 'm2'),
          ],
        );
        await pumpStreams(c, 'g');
        expect(c.read(sortedGroupMembersProvider('g')).map((p) => p.$1.id), [
          'e1',
          'e2',
        ]);
      },
    );

    test(
      'nameAsc with duplicate names: deterministic by id ascending',
      () async {
        final c = container(
          group: groupWith(
            id: 'g',
            sortState: GroupSortState.locked(GroupSortMode.nameAsc),
          ),
          entries: [
            entryWith(id: 'eA', groupId: 'g', memberId: 'b-alex'),
            entryWith(id: 'eB', groupId: 'g', memberId: 'a-alex'),
          ],
          members: [
            memberWith(id: 'b-alex', name: 'Alex'),
            memberWith(id: 'a-alex', name: 'Alex'),
          ],
        );
        await pumpStreams(c, 'g');
        expect(c.read(sortedGroupMembersProvider('g')).map((p) => p.$2.id), [
          'a-alex',
          'b-alex',
        ]);
      },
    );

    test(
      'corrupt sortState surfaces as manualEmpty at the model layer; list orders by entry id ascending, no crash',
      () async {
        // Provider receives the domain model directly. The mapper's
        // fallback for a corrupt column produces GroupSortState.manualEmpty,
        // so we construct that runtime state here. Behavior: manual mode +
        // empty manualOrder → all entries land in the "unindexed" bucket,
        // sorted by entry id ascending.
        final c = container(
          group: groupWith(id: 'g', sortState: GroupSortState.manualEmpty),
          entries: [
            entryWith(id: 'e3', groupId: 'g', memberId: 'm3'),
            entryWith(id: 'e1', groupId: 'g', memberId: 'm1'),
            entryWith(id: 'e2', groupId: 'g', memberId: 'm2'),
          ],
          members: [
            memberWith(id: 'm1'),
            memberWith(id: 'm2'),
            memberWith(id: 'm3'),
          ],
        );
        await pumpStreams(c, 'g');
        expect(c.read(sortedGroupMembersProvider('g')).map((p) => p.$1.id), [
          'e1',
          'e2',
          'e3',
        ]);
      },
    );

    test(
      'large-group algorithmic correctness: 1000 entries in manual mode returned in manualOrder positions',
      () async {
        // Deterministic ids zero-padded so sort and equality checks line up.
        String pad(int i) => i.toString().padLeft(4, '0');
        final entries = [
          for (var i = 0; i < 1000; i++)
            entryWith(id: 'e${pad(i)}', groupId: 'g', memberId: 'm${pad(i)}'),
        ];
        final members = [
          for (var i = 0; i < 1000; i++) memberWith(id: 'm${pad(i)}'),
        ];
        // Reverse order for manualOrder so we exercise a non-identity
        // permutation, not just "the input is already sorted."
        final manualOrder = [for (var i = 999; i >= 0; i--) 'e${pad(i)}'];

        final c = container(
          group: groupWith(
            id: 'g',
            sortState: GroupSortState(
              mode: GroupSortMode.manual,
              manualOrder: manualOrder,
            ),
          ),
          entries: entries,
          members: members,
        );
        await pumpStreams(c, 'g');

        final result = c.read(sortedGroupMembersProvider('g'));
        // Assert via Set equality on length and id-set membership; the
        // ordered list must match manualOrder exactly. (No wall-clock checks.)
        expect(result, hasLength(1000));
        final resultIds = result.map((p) => p.$1.id).toList();
        expect(resultIds.toSet(), entries.map((e) => e.id).toSet());
        expect(resultIds, manualOrder);
      },
    );

    test(
      'manualOrder longer than live entries: only live entries returned in their manualOrder positions',
      () async {
        // manualOrder has 10 ids but only 3 live entries. The 3 live entries
        // should be returned in their manualOrder positions among themselves.
        final c = container(
          group: groupWith(
            id: 'g',
            sortState: const GroupSortState(
              mode: GroupSortMode.manual,
              manualOrder: [
                'g0',
                'g1',
                'eC',
                'g3',
                'g4',
                'eA',
                'g6',
                'g7',
                'eB',
                'g9',
              ],
            ),
          ),
          entries: [
            entryWith(id: 'eA', groupId: 'g', memberId: 'mA'),
            entryWith(id: 'eB', groupId: 'g', memberId: 'mB'),
            entryWith(id: 'eC', groupId: 'g', memberId: 'mC'),
          ],
          members: [
            memberWith(id: 'mA'),
            memberWith(id: 'mB'),
            memberWith(id: 'mC'),
          ],
        );
        await pumpStreams(c, 'g');
        expect(
          c.read(sortedGroupMembersProvider('g')).map((p) => p.$1.id),
          // manualOrder positions: eC=2, eA=5, eB=8 → eC, eA, eB
          ['eC', 'eA', 'eB'],
        );
      },
    );
  });
}
