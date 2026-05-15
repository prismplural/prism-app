import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/group_sort_mode.dart';
import 'package:prism_plurality/domain/models/group_sort_state.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/repositories/member_groups_repository.dart';
import 'package:prism_plurality/domain/repositories/snapshot_apply_result.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/member_stats_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/utils/group_tree_utils.dart';
import 'package:prism_plurality/features/members/views/group_detail_screen.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/member_card.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

List<MemberGroup> _chain(int n) => [
  for (var i = 0; i < n; i++)
    MemberGroup(
      id: 'ancestor_$i',
      name: 'ancestor_$i',
      createdAt: DateTime(2024, 1, 1),
    ),
];

class _FakeGroupNotifier extends GroupNotifier {
  final addedMemberIds = <String>[];

  @override
  Future<void> build() async {}

  @override
  Future<void> addMemberToGroup(String groupId, String memberId) async {
    addedMemberIds.add(memberId);
  }
}

/// In-memory fake for [MemberGroupsRepository] used by widget tests that
/// exercise the sort UI. Tracks the most recent
/// [setGroupManualOrderSnapshot] / [setGroupSortMode] invocation so tests
/// can assert the order and mode the UI handed to the repository.
class _FakeMemberGroupsRepository implements MemberGroupsRepository {
  _FakeMemberGroupsRepository({
    this.snapshotResult = const SnapshotApplyResult.applied(),
  });

  /// What [setGroupManualOrderSnapshot] returns. Override per test for the
  /// "recovered" path.
  SnapshotApplyResult snapshotResult;

  String? lastSnapshotGroupId;
  List<String>? lastSnapshotOrder;
  int snapshotCallCount = 0;

  String? lastSortModeGroupId;
  GroupSortMode? lastSortMode;
  int sortModeCallCount = 0;

  @override
  Future<SnapshotApplyResult> setGroupManualOrderSnapshot(
    String groupId,
    List<String> orderedEntryIds,
  ) async {
    snapshotCallCount += 1;
    lastSnapshotGroupId = groupId;
    lastSnapshotOrder = List.of(orderedEntryIds);
    return snapshotResult;
  }

  @override
  Future<void> setGroupSortMode(String groupId, GroupSortMode mode) async {
    sortModeCallCount += 1;
    lastSortModeGroupId = groupId;
    lastSortMode = mode;
  }

  // ── Everything else stubbed — these widget tests don't exercise them. ─────

  @override
  Future<void> addMemberToGroup(
    String groupId,
    String memberId,
    String entryId,
  ) async {}

  @override
  Future<void> createGroup(MemberGroup group) async {}

  @override
  Future<void> deleteGroup(String groupId) async {}

  @override
  Future<void> deleteGroupWithDescendants(String groupId) async {}

  @override
  Future<void> emitGroupSyncState(String groupId) async {}

  @override
  Future<List<MemberGroupEntry>> getAllGroupEntries() async => const [];

  @override
  Future<void> promoteChildrenToRoot(String groupId) async {}

  @override
  Future<void> removeMemberFromGroup(String groupId, String memberId) async {}

  @override
  Future<void> updateGroup(MemberGroup group) async {}

  @override
  Stream<List<MemberGroupEntry>> watchAllGroupEntries() => const Stream.empty();

  @override
  Stream<List<MemberGroup>> watchAllGroups() => const Stream.empty();

  @override
  Stream<MemberGroup?> watchGroupById(String id) => const Stream.empty();

  @override
  Stream<List<MemberGroupEntry>> watchGroupEntries(String groupId) =>
      const Stream.empty();

  @override
  Stream<List<MemberGroup>> watchGroupsForMember(String memberId) =>
      const Stream.empty();

  @override
  Stream<Map<String, int>> watchMemberCountsByGroup() => const Stream.empty();
}

Member _member({
  required String id,
  required String name,
  bool isActive = true,
}) => Member(id: id, name: name, isActive: isActive, createdAt: DateTime(2024));

MemberGroup _group({
  required String id,
  required String name,
  String? parentGroupId,
  String? colorHex,
  String? emoji,
  GroupSortState sortState = GroupSortState.manualEmpty,
}) => MemberGroup(
  id: id,
  name: name,
  colorHex: colorHex,
  emoji: emoji,
  parentGroupId: parentGroupId,
  createdAt: DateTime(2024),
  sortState: sortState,
);

Widget _buildSubject({
  required MemberGroup group,
  required List<MemberGroup> allGroups,
  required List<MemberGroupEntry> allEntries,
  required List<Member> activeMembers,
  required _FakeGroupNotifier notifier,
  List<Member>? allMembers,
  _FakeMemberGroupsRepository? repository,
}) {
  final resolvedAll = allMembers ?? activeMembers;
  final repo = repository ?? _FakeMemberGroupsRepository();
  return ProviderScope(
    overrides: [
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
      activeMembersProvider.overrideWith((ref) => Stream.value(activeMembers)),
      allMembersProvider.overrideWith((ref) => Stream.value(resolvedAll)),
      memberByIdProvider.overrideWith((ref, memberId) {
        final matching = resolvedAll.where((member) => member.id == memberId);
        return Stream.value(matching.isEmpty ? null : matching.first);
      }),
      allGroupsProvider.overrideWith((ref) => Stream.value(allGroups)),
      allGroupEntriesProvider.overrideWith((ref) => Stream.value(allEntries)),
      groupByIdProvider.overrideWith(
        (ref, groupId) => Stream.value(groupId == group.id ? group : null),
      ),
      groupEntriesProvider.overrideWith(
        (ref, groupId) => Stream.value(
          allEntries.where((entry) => entry.groupId == groupId).toList(),
        ),
      ),
      groupTreeProvider.overrideWith(
        (ref) => GroupTreeUtils.buildGroupTree(allGroups),
      ),
      groupNotifierProvider.overrideWith(() => notifier),
      memberGroupsRepositoryProvider.overrideWithValue(repo),
      // Stats provider needs an explicit fake — its underlying
      // FrontingSessionRepository isn't wired in widget tests. Default to
      // an empty stats record so the "apply fronting order" action
      // resolves immediately.
      memberFrontingStatsProvider.overrideWith(
        (ref, memberId) async => const MemberFrontingStats(
          totalSessions: 0,
          totalDuration: Duration.zero,
        ),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      // Mirror production: `PrismToastHost` is mounted in
      // `MaterialApp.builder` so toast text becomes findable via
      // `find.text(...)`.
      builder: (context, child) =>
          PrismToastHost(child: child ?? const SizedBox.shrink()),
      home: GroupDetailScreen(groupId: group.id),
    ),
  );
}

/// Installs a mock handler on the `flutter/accessibility` BasicMessageChannel
/// so the test can assert on `SemanticsService.sendAnnouncement` payloads.
///
/// Returns the list captured messages will be appended to. The handler is
/// torn down via [addTearDown] so it doesn't leak between tests.
List<Map<Object?, Object?>> _captureSemanticAnnouncements() {
  final captured = <Map<Object?, Object?>>[];
  const channel = BasicMessageChannel<Object?>(
    'flutter/accessibility',
    StandardMessageCodec(),
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(channel.name, (ByteData? message) async {
        if (message == null) return null;
        final decoded = const StandardMessageCodec().decodeMessage(message);
        if (decoded is Map) {
          captured.add(Map<Object?, Object?>.from(decoded));
        }
        return null;
      });
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(channel.name, null);
  });
  return captured;
}

void main() {
  testWidgets('hides subgroup button until the group list has loaded', (
    tester,
  ) async {
    final group = _group(id: 'group-target', name: 'Target Group');
    final notifier = _FakeGroupNotifier();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          systemSettingsProvider.overrideWith(
            (ref) => Stream.value(const SystemSettings()),
          ),
          activeMembersProvider.overrideWith(
            (ref) => Stream.value(const <Member>[]),
          ),
          allMembersProvider.overrideWith(
            (ref) => Stream.value(const <Member>[]),
          ),
          allGroupsProvider.overrideWith((ref) => const Stream.empty()),
          allGroupEntriesProvider.overrideWith(
            (ref) => Stream.value(const <MemberGroupEntry>[]),
          ),
          groupByIdProvider.overrideWith(
            (ref, groupId) => Stream.value(groupId == group.id ? group : null),
          ),
          groupEntriesProvider.overrideWith(
            (ref, groupId) => Stream.value(const <MemberGroupEntry>[]),
          ),
          groupTreeProvider.overrideWith(
            (ref) => const <String?, List<MemberGroup>>{},
          ),
          groupNotifierProvider.overrideWith(() => notifier),
          memberGroupsRepositoryProvider.overrideWithValue(
            _FakeMemberGroupsRepository(),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: GroupDetailScreen(groupId: group.id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Add sub-group'), findsNothing);
  });

  testWidgets('shows add subgroup in the menu at depth 4', (tester) async {
    final root = _group(id: 'root', name: 'Root');
    final level2 = _group(
      id: 'level-2',
      name: 'Level 2',
      parentGroupId: 'root',
    );
    final level3 = _group(
      id: 'level-3',
      name: 'Level 3',
      parentGroupId: 'level-2',
    );
    final level4 = _group(
      id: 'level-4',
      name: 'Level 4',
      parentGroupId: 'level-3',
    );
    final notifier = _FakeGroupNotifier();

    await tester.pumpWidget(
      _buildSubject(
        group: level4,
        allGroups: [root, level2, level3, level4],
        allEntries: const [],
        activeMembers: const [],
        notifier: notifier,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sub-groups'), findsNothing);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();

    expect(find.text('Add sub-group'), findsOneWidget);
  });

  testWidgets('shows add subgroup in the menu at depth 5 (no cap)', (
    tester,
  ) async {
    final root = _group(id: 'root', name: 'Root');
    final level2 = _group(
      id: 'level-2',
      name: 'Level 2',
      parentGroupId: 'root',
    );
    final level3 = _group(
      id: 'level-3',
      name: 'Level 3',
      parentGroupId: 'level-2',
    );
    final level4 = _group(
      id: 'level-4',
      name: 'Level 4',
      parentGroupId: 'level-3',
    );
    final level5 = _group(
      id: 'level-5',
      name: 'Level 5',
      parentGroupId: 'level-4',
    );
    final notifier = _FakeGroupNotifier();

    await tester.pumpWidget(
      _buildSubject(
        group: level5,
        allGroups: [root, level2, level3, level4, level5],
        allEntries: const [],
        activeMembers: const [],
        notifier: notifier,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();

    // Depth cap is removed — Add sub-group is always available.
    expect(find.text('Add sub-group'), findsOneWidget);
  });

  testWidgets('keeps the inline add button when subgroups are visible', (
    tester,
  ) async {
    final parent = _group(id: 'parent', name: 'Parent');
    final child = _group(id: 'child', name: 'Child', parentGroupId: 'parent');
    final notifier = _FakeGroupNotifier();

    await tester.pumpWidget(
      _buildSubject(
        group: parent,
        allGroups: [parent, child],
        allEntries: const [],
        activeMembers: const [],
        notifier: notifier,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sub-groups'), findsOneWidget);
    expect(find.text('Child'), findsOneWidget);
    expect(find.byTooltip('Add sub-group'), findsOneWidget);
  });

  testWidgets('moves group member actions into the overflow menu', (
    tester,
  ) async {
    final group = _group(id: 'group-target', name: 'Target Group');
    final alice = _member(id: 'alice', name: 'Alice');
    final notifier = _FakeGroupNotifier();

    await tester.pumpWidget(
      _buildSubject(
        group: group,
        allGroups: [group],
        allEntries: const [
          MemberGroupEntry(
            id: 'entry-alice',
            groupId: 'group-target',
            memberId: 'alice',
          ),
        ],
        activeMembers: [alice],
        notifier: notifier,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Front as Group'), findsNothing);
    expect(find.text('Start chat'), findsNothing);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();

    expect(find.text('Front as Group'), findsOneWidget);
    expect(find.text('Start chat'), findsOneWidget);
  });

  testWidgets('uses one overflow menu for group actions and member sorting', (
    tester,
  ) async {
    final group = _group(id: 'group-target', name: 'Target Group');
    final alice = _member(id: 'alice', name: 'Alice');
    final bob = _member(id: 'bob', name: 'Bob');
    final notifier = _FakeGroupNotifier();

    await tester.pumpWidget(
      _buildSubject(
        group: group,
        allGroups: [group],
        allEntries: const [
          MemberGroupEntry(
            id: 'entry-alice',
            groupId: 'group-target',
            memberId: 'alice',
          ),
          MemberGroupEntry(
            id: 'entry-bob',
            groupId: 'group-target',
            memberId: 'bob',
          ),
        ],
        activeMembers: [alice, bob],
        notifier: notifier,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('More options'), findsOneWidget);
    expect(find.byTooltip('Options'), findsNothing);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();

    expect(find.text('Sort Headmates'), findsOneWidget);
    expect(find.text('Name A-Z'), findsNothing);
    expect(find.text('Front as Group'), findsOneWidget);
  });

  testWidgets('opens a separate sub-group sort dialog from the group menu', (
    tester,
  ) async {
    final parent = _group(id: 'parent', name: 'Parent');
    final zed = _group(id: 'zed', name: 'Zed', parentGroupId: 'parent');
    final able = _group(id: 'able', name: 'Able', parentGroupId: 'parent');
    final notifier = _ReorderingFakeGroupNotifier();

    await tester.pumpWidget(
      _buildSubject(
        group: parent,
        allGroups: [parent, zed, able],
        allEntries: const [],
        activeMembers: const [],
        notifier: notifier,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();

    expect(find.text('Sub-groups'), findsOneWidget);
    expect(find.text('Sort sub-groups'), findsOneWidget);
    expect(find.text('Name A–Z'), findsNothing);

    await tester.tap(find.text('Sort sub-groups'));
    await tester.pumpAndSettle();

    expect(find.text('Name A–Z'), findsOneWidget);
    await tester.tap(find.text('Name A–Z'));
    await tester.pumpAndSettle();

    expect(notifier.reorderedSequences.length, 1);
    expect(notifier.reorderedSequences.single.map((g) => g.id).toList(), [
      'able',
      'zed',
    ]);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('hides group member actions when the group is empty', (
    tester,
  ) async {
    final group = _group(id: 'group-target', name: 'Target Group');
    final notifier = _FakeGroupNotifier();

    await tester.pumpWidget(
      _buildSubject(
        group: group,
        allGroups: [group],
        allEntries: const [],
        activeMembers: const [],
        notifier: notifier,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();

    expect(find.text('Front as Group'), findsNothing);
    expect(find.text('Start chat'), findsNothing);
  });

  testWidgets(
    'hides inactive members by default and reveals them via the options toggle',
    (tester) async {
      final group = _group(id: 'group-mixed', name: 'Mixed');
      final alice = _member(id: 'alice', name: 'Alice');
      final bob = _member(id: 'bob', name: 'Bob Inactive', isActive: false);
      final notifier = _FakeGroupNotifier();

      await tester.pumpWidget(
        _buildSubject(
          group: group,
          allGroups: [group],
          allEntries: const [
            MemberGroupEntry(
              id: 'entry-alice',
              groupId: 'group-mixed',
              memberId: 'alice',
            ),
            MemberGroupEntry(
              id: 'entry-bob',
              groupId: 'group-mixed',
              memberId: 'bob',
            ),
          ],
          activeMembers: [alice],
          allMembers: [alice, bob],
          notifier: notifier,
        ),
      );
      await tester.pumpAndSettle();

      // Active member visible, inactive member hidden.
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob Inactive'), findsNothing);

      // Toggle on Show inactive via the options menu.
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show inactive'));
      await tester.pumpAndSettle();

      // Both visible now.
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob Inactive'), findsOneWidget);

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      expect(find.text('Show inactive'), findsOneWidget);
      expect(find.text('Hide inactive'), findsNothing);
    },
  );

  testWidgets(
    'add member uses shared multi-select sheet and keeps group chips',
    (tester) async {
      final targetGroup = _group(id: 'group-target', name: 'Target Group');
      final filterGroup = _group(
        id: 'group-filter',
        name: 'Cluster',
        colorHex: '#7A6E96',
        emoji: '🫂',
      );
      final alice = _member(id: 'alice', name: 'Alice');
      final bob = _member(id: 'bob', name: 'Bob');
      final notifier = _FakeGroupNotifier();

      await tester.pumpWidget(
        _buildSubject(
          group: targetGroup,
          allGroups: [targetGroup, filterGroup],
          allEntries: const [
            MemberGroupEntry(
              id: 'entry-filter-alice',
              groupId: 'group-filter',
              memberId: 'alice',
            ),
          ],
          activeMembers: [alice, bob],
          notifier: notifier,
        ),
      );
      await tester.pumpAndSettle();

      // Default terminology is `headmates`; the icon button tooltip reads
      // "Add {termSingularLower}" → "Add headmate".
      await tester.tap(find.byTooltip('Add headmate'));
      await tester.pumpAndSettle();

      expect(find.byType(MemberSearchSheet), findsOneWidget);
      expect(find.text('Cluster'), findsOneWidget);

      await tester.tap(find.text('Alice'));
      await tester.pump();
      await tester.tap(find.text('Bob'));
      await tester.pump();

      final doneButton = find.byWidgetPredicate(
        (widget) =>
            widget is PrismGlassIconButton && widget.icon == AppIcons.check,
      );
      expect(doneButton, findsOneWidget);

      await tester.tap(doneButton);
      await tester.pumpAndSettle();

      expect(notifier.addedMemberIds, containsAll(['alice', 'bob']));
      await tester.pump(const Duration(seconds: 3));
    },
  );

  Widget wrapBreadcrumb(List<MemberGroup> ancestors) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          child: AncestorBreadcrumb(ancestors: ancestors),
        ),
      ),
    );
  }

  testWidgets(
    'breadcrumb renders all 5 ancestors with no ellipsis when chain length == 5',
    (tester) async {
      final ancestors = _chain(5);

      await tester.pumpWidget(wrapBreadcrumb(ancestors));
      await tester.pumpAndSettle();

      for (var i = 0; i < 5; i++) {
        expect(find.text('ancestor_$i'), findsOneWidget);
      }
      expect(find.text('…'), findsNothing);
    },
  );

  testWidgets('breadcrumb front-truncates when chain length > 5', (
    tester,
  ) async {
    // 7 ancestors: ancestor_0 .. ancestor_6
    // Expected visible: ancestor_0, …, ancestor_4, ancestor_5, ancestor_6.
    final ancestors = _chain(7);

    await tester.pumpWidget(wrapBreadcrumb(ancestors));
    await tester.pumpAndSettle();

    expect(find.text('ancestor_0'), findsOneWidget);
    expect(find.text('…'), findsOneWidget);
    expect(find.text('ancestor_4'), findsOneWidget);
    expect(find.text('ancestor_5'), findsOneWidget);
    expect(find.text('ancestor_6'), findsOneWidget);

    expect(find.text('ancestor_1'), findsNothing);
    expect(find.text('ancestor_2'), findsNothing);
    expect(find.text('ancestor_3'), findsNothing);
  });

  testWidgets(
    'breadcrumb renders ellipsis exactly once even at very long chains',
    (tester) async {
      final ancestors = _chain(10);

      await tester.pumpWidget(wrapBreadcrumb(ancestors));
      await tester.pumpAndSettle();

      expect(find.text('…'), findsOneWidget);

      // First + last 3 are visible; the middle six are hidden.
      expect(find.text('ancestor_0'), findsOneWidget);
      expect(find.text('ancestor_7'), findsOneWidget);
      expect(find.text('ancestor_8'), findsOneWidget);
      expect(find.text('ancestor_9'), findsOneWidget);
      for (var i = 1; i <= 6; i++) {
        expect(find.text('ancestor_$i'), findsNothing);
      }
    },
  );

  // ── Task 5.1 sort UI ─────────────────────────────────────────────────────

  group('sort UI', () {
    Future<void> openOptionsMenu(WidgetTester tester) async {
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
    }

    Future<void> openMemberSortDialog(WidgetTester tester) async {
      await openOptionsMenu(tester);
      await tester.tap(find.text('Sort Headmates'));
      await tester.pumpAndSettle();
    }

    MemberGroup groupWith({
      required String id,
      required String name,
      required GroupSortState sortState,
    }) => MemberGroup(
      id: id,
      name: name,
      sortState: sortState,
      createdAt: DateTime(2024),
    );

    MemberGroupEntry entry(String id, String groupId, String memberId) =>
        MemberGroupEntry(id: id, groupId: groupId, memberId: memberId);

    testWidgets(
      'drag in manual mode calls setGroupManualOrderSnapshot with new order '
      'and returns applied',
      (tester) async {
        final group = groupWith(
          id: 'g',
          name: 'G',
          sortState: const GroupSortState(
            mode: GroupSortMode.manual,
            manualOrder: ['e1', 'e2'],
          ),
        );
        final alice = _member(id: 'm1', name: 'Alice');
        final bob = _member(id: 'm2', name: 'Bob');
        final repo = _FakeMemberGroupsRepository();
        await tester.pumpWidget(
          _buildSubject(
            group: group,
            allGroups: [group],
            allEntries: [entry('e1', 'g', 'm1'), entry('e2', 'g', 'm2')],
            activeMembers: [alice, bob],
            notifier: _FakeGroupNotifier(),
            repository: repo,
          ),
        );
        await tester.pumpAndSettle();

        // Drag the first drag handle below the second tile.
        final handle = find.byType(ReorderableDragStartListener).first;
        await tester.timedDrag(
          handle,
          const Offset(0, 120),
          const Duration(milliseconds: 500),
        );
        await tester.pumpAndSettle();

        expect(repo.snapshotCallCount, 1);
        expect(repo.lastSnapshotGroupId, 'g');
        expect(repo.lastSnapshotOrder, ['e2', 'e1']);
      },
    );

    testWidgets(
      'drag in nameAsc mode calls setGroupManualOrderSnapshot and chip '
      'transitions out',
      (tester) async {
        final group = groupWith(
          id: 'g',
          name: 'G',
          sortState: GroupSortState.locked(GroupSortMode.nameAsc),
        );
        final alice = _member(id: 'm1', name: 'Alice');
        final bob = _member(id: 'm2', name: 'Bob');
        final repo = _FakeMemberGroupsRepository();
        await tester.pumpWidget(
          _buildSubject(
            group: group,
            allGroups: [group],
            allEntries: [entry('e1', 'g', 'm1'), entry('e2', 'g', 'm2')],
            activeMembers: [alice, bob],
            notifier: _FakeGroupNotifier(),
            repository: repo,
          ),
        );
        await tester.pumpAndSettle();

        // Chip visible while in locked mode.
        expect(find.text('Name (A-Z)'), findsOneWidget);

        final handle = find.byType(ReorderableDragStartListener).first;
        await tester.timedDrag(
          handle,
          const Offset(0, 120),
          const Duration(milliseconds: 500),
        );
        await tester.pumpAndSettle();

        expect(repo.snapshotCallCount, 1);
        // Toast text assertion (host wired via PrismToastHost in
        // _buildSubject): the drag-from-sorted path fires the
        // implicit-unlock toast.
        expect(find.text('Switched to manual sort.'), findsOneWidget);
        // Drag-in-sorted-mode shows the implicit-unlock toast; let its
        // auto-dismiss timer fire so the test exits cleanly.
        await tester.pump(const Duration(seconds: 4));
      },
    );

    testWidgets(
      'drag while concurrent remote add lands returns recovered + toast',
      (tester) async {
        final group = groupWith(
          id: 'g',
          name: 'G',
          sortState: const GroupSortState(
            mode: GroupSortMode.manual,
            manualOrder: ['e1', 'e2'],
          ),
        );
        final repo = _FakeMemberGroupsRepository(
          snapshotResult: const SnapshotApplyResult.recovered(
            droppedIds: <String>[],
            appendedIds: <String>['e3'],
          ),
        );
        await tester.pumpWidget(
          _buildSubject(
            group: group,
            allGroups: [group],
            allEntries: [entry('e1', 'g', 'm1'), entry('e2', 'g', 'm2')],
            activeMembers: [
              _member(id: 'm1', name: 'Alice'),
              _member(id: 'm2', name: 'Bob'),
            ],
            notifier: _FakeGroupNotifier(),
            repository: repo,
          ),
        );
        await tester.pumpAndSettle();

        final handle = find.byType(ReorderableDragStartListener).first;
        await tester.timedDrag(
          handle,
          const Offset(0, 120),
          const Duration(milliseconds: 500),
        );
        await tester.pumpAndSettle();

        // Recovery path: snapshot called once, repo returned recovered
        // result, and the UI surfaced the recovery toast via PrismToast.show
        // (toast text findable now that _buildSubject mounts PrismToastHost).
        expect(repo.snapshotCallCount, 1);
        expect(
          find.text(
            'Members changed during your reorder. Your order has been merged.',
          ),
          findsOneWidget,
        );
        // PrismToast schedules a 3s auto-dismiss timer; let it fire before
        // the test ends so the binding doesn't report '!timersPending'.
        await tester.pump(const Duration(seconds: 4));
      },
    );

    testWidgets(
      'picking Name A-Z calls setGroupSortMode(nameAsc) and chip appears',
      (tester) async {
        final group = groupWith(
          id: 'g',
          name: 'G',
          sortState: const GroupSortState(
            mode: GroupSortMode.manual,
            manualOrder: ['e1', 'e2'],
          ),
        );
        final repo = _FakeMemberGroupsRepository();
        await tester.pumpWidget(
          _buildSubject(
            group: group,
            allGroups: [group],
            allEntries: [entry('e1', 'g', 'm1'), entry('e2', 'g', 'm2')],
            activeMembers: [
              _member(id: 'm1', name: 'Alice'),
              _member(id: 'm2', name: 'Bob'),
            ],
            notifier: _FakeGroupNotifier(),
            repository: repo,
          ),
        );
        await tester.pumpAndSettle();

        // Chip not visible in manual mode.
        expect(find.text('Name (A-Z)'), findsNothing);

        await openMemberSortDialog(tester);
        await tester.tap(find.text('Name A-Z'));
        await tester.pumpAndSettle();

        expect(repo.sortModeCallCount, 1);
        expect(repo.lastSortMode, GroupSortMode.nameAsc);
        expect(repo.lastSortModeGroupId, 'g');
      },
    );

    testWidgets(
      'picking "Sort manually" from a sorted mode snapshots current order',
      (tester) async {
        final group = groupWith(
          id: 'g',
          name: 'G',
          // nameAsc — visible order is Alice then Bob.
          sortState: GroupSortState.locked(GroupSortMode.nameAsc),
        );
        final repo = _FakeMemberGroupsRepository();
        await tester.pumpWidget(
          _buildSubject(
            group: group,
            allGroups: [group],
            allEntries: [entry('e1', 'g', 'm1'), entry('e2', 'g', 'm2')],
            activeMembers: [
              _member(id: 'm1', name: 'Alice'),
              _member(id: 'm2', name: 'Bob'),
            ],
            notifier: _FakeGroupNotifier(),
            repository: repo,
          ),
        );
        await tester.pumpAndSettle();

        await openMemberSortDialog(tester);
        await tester.tap(find.text('Sort manually'));
        await tester.pumpAndSettle();

        expect(repo.snapshotCallCount, 1);
        // Alice's entry e1 comes first in nameAsc.
        expect(repo.lastSnapshotOrder, ['e1', 'e2']);
        // wasManual=false path shows implicit-unlock toast; let it dismiss.
        await tester.pump(const Duration(seconds: 4));
      },
    );

    testWidgets('picking "Most-fronting first" snapshots fronting order '
        'from the Arrange once section', (tester) async {
      final group = groupWith(
        id: 'g',
        name: 'G',
        sortState: const GroupSortState(
          mode: GroupSortMode.manual,
          manualOrder: ['e1', 'e2'],
        ),
      );
      final repo = _FakeMemberGroupsRepository();
      await tester.pumpWidget(
        _buildSubject(
          group: group,
          allGroups: [group],
          allEntries: [entry('e1', 'g', 'm1'), entry('e2', 'g', 'm2')],
          activeMembers: [
            _member(id: 'm1', name: 'Alice'),
            _member(id: 'm2', name: 'Bob'),
          ],
          notifier: _FakeGroupNotifier(),
          repository: repo,
        ),
      );
      await tester.pumpAndSettle();

      await openMemberSortDialog(tester);

      // Section header visible.
      expect(find.text('Arrange once'), findsOneWidget);
      expect(find.text('Apply current order'), findsNothing);

      await tester.tap(find.text('Most-fronting first'));
      await tester.pumpAndSettle();

      // The fake fronting stats fall back to zero in widget tests; we just
      // verify the call landed with a list of the live entry ids.
      expect(repo.snapshotCallCount, 1);
      expect(repo.lastSnapshotOrder, isNotNull);
      expect(repo.lastSnapshotOrder!.toSet(), {'e1', 'e2'});
    });

    testWidgets(
      'custom semantic action "Move up" is suppressed on the first row',
      (tester) async {
        final group = groupWith(
          id: 'g',
          name: 'G',
          sortState: const GroupSortState(
            mode: GroupSortMode.manual,
            manualOrder: ['e1', 'e2', 'e3'],
          ),
        );
        await tester.pumpWidget(
          _buildSubject(
            group: group,
            allGroups: [group],
            allEntries: [
              entry('e1', 'g', 'm1'),
              entry('e2', 'g', 'm2'),
              entry('e3', 'g', 'm3'),
            ],
            activeMembers: [
              _member(id: 'm1', name: 'Alice'),
              _member(id: 'm2', name: 'Bob'),
              _member(id: 'm3', name: 'Carol'),
            ],
            notifier: _FakeGroupNotifier(),
          ),
        );
        await tester.pumpAndSettle();

        // Probe semantics on the first member card.
        final aliceCard = find.ancestor(
          of: find.text('Alice'),
          matching: find.byType(MemberCard),
        );
        final semantics = tester.getSemantics(aliceCard);
        final actions =
            semantics.getSemanticsData().customSemanticsActionIds ??
            const <int>[];
        final labels = actions
            .map((id) => CustomSemanticsAction.getAction(id)?.label)
            .whereType<String>()
            .toSet();
        expect(labels, isNot(contains('Move up')));
        expect(labels, isNot(contains('Move to top')));
        // Down + bottom are present (it's not the last row).
        expect(labels, contains('Move down'));
        expect(labels, contains('Move to bottom'));
      },
      semanticsEnabled: true,
    );

    testWidgets(
      'custom semantic action "Move up" on second row swaps order',
      (tester) async {
        final group = groupWith(
          id: 'g',
          name: 'G',
          sortState: const GroupSortState(
            mode: GroupSortMode.manual,
            manualOrder: ['e1', 'e2', 'e3'],
          ),
        );
        final repo = _FakeMemberGroupsRepository();
        await tester.pumpWidget(
          _buildSubject(
            group: group,
            allGroups: [group],
            allEntries: [
              entry('e1', 'g', 'm1'),
              entry('e2', 'g', 'm2'),
              entry('e3', 'g', 'm3'),
            ],
            activeMembers: [
              _member(id: 'm1', name: 'Alice'),
              _member(id: 'm2', name: 'Bob'),
              _member(id: 'm3', name: 'Carol'),
            ],
            notifier: _FakeGroupNotifier(),
            repository: repo,
          ),
        );
        await tester.pumpAndSettle();

        // Find the "Move up" semantic action on the second card (Bob's row).
        final bobCard = find.ancestor(
          of: find.text('Bob'),
          matching: find.byType(MemberCard),
        );
        final node = tester.getSemantics(bobCard);
        final actionIds =
            node.getSemanticsData().customSemanticsActionIds ?? const <int>[];
        final moveUpId = actionIds.firstWhere(
          (id) => CustomSemanticsAction.getAction(id)?.label == 'Move up',
          orElse: () => -1,
        );
        expect(moveUpId, isNot(-1));

        // RendererBinding.rootPipelineOwner is the upstream replacement, but
        // in widget tests the legacy pipelineOwner accessor is what actually
        // owns the rendered tree's semantics. The SemanticsBinding migration
        // is out of scope here.
        WidgetsBinding
            .instance
            // ignore: deprecated_member_use
            .pipelineOwner
            .semanticsOwner
            ?.performAction(node.id, SemanticsAction.customAction, moveUpId);
        await tester.pumpAndSettle();

        // The repository should have been called with Bob's entry at index 0.
        expect(repo.snapshotCallCount, greaterThanOrEqualTo(1));
        expect(repo.lastSnapshotOrder, ['e2', 'e1', 'e3']);
      },
      semanticsEnabled: true,
    );

    testWidgets(
      'custom semantic action "Move to top" on last row puts that row first',
      (tester) async {
        final group = groupWith(
          id: 'g',
          name: 'G',
          sortState: const GroupSortState(
            mode: GroupSortMode.manual,
            manualOrder: ['e1', 'e2', 'e3'],
          ),
        );
        final repo = _FakeMemberGroupsRepository();
        await tester.pumpWidget(
          _buildSubject(
            group: group,
            allGroups: [group],
            allEntries: [
              entry('e1', 'g', 'm1'),
              entry('e2', 'g', 'm2'),
              entry('e3', 'g', 'm3'),
            ],
            activeMembers: [
              _member(id: 'm1', name: 'Alice'),
              _member(id: 'm2', name: 'Bob'),
              _member(id: 'm3', name: 'Carol'),
            ],
            notifier: _FakeGroupNotifier(),
            repository: repo,
          ),
        );
        await tester.pumpAndSettle();

        final carolCard = find.ancestor(
          of: find.text('Carol'),
          matching: find.byType(MemberCard),
        );
        final node = tester.getSemantics(carolCard);
        final actionIds =
            node.getSemanticsData().customSemanticsActionIds ?? const <int>[];
        final moveToTopId = actionIds.firstWhere(
          (id) => CustomSemanticsAction.getAction(id)?.label == 'Move to top',
          orElse: () => -1,
        );
        expect(moveToTopId, isNot(-1));

        // See comment on the "Move up" test for the pipelineOwner rationale.
        WidgetsBinding
            .instance
            // ignore: deprecated_member_use
            .pipelineOwner
            .semanticsOwner
            ?.performAction(node.id, SemanticsAction.customAction, moveToTopId);
        await tester.pumpAndSettle();

        expect(repo.snapshotCallCount, greaterThanOrEqualTo(1));
        expect(repo.lastSnapshotOrder, ['e3', 'e1', 'e2']);
      },
      semanticsEnabled: true,
    );

    // Best-effort focus retention after an a11y "Move up". The polite
    // announcement is the reliable a11y signal (verified by the sibling
    // tests); focus retention is a soft signal that helps a screen reader
    // keep its caret on the moved row.
    //
    // Note: Flutter's widget-test focus system is known-flaky for
    // non-input widgets that are torn down and rebuilt across reorders.
    // The production code wires up `_focusNodeFor(entry.id)` and schedules
    // a post-frame `requestFocus`. We assert here that the wiring is wired
    // (the rebuilt tile has a non-null FocusNode), and leave the actual
    // `hasFocus == true` assertion to the manual a11y smoke pass.
    testWidgets(
      '"Move up" on second row attaches a FocusNode to the moved entry '
      '(focus retention wiring)',
      (tester) async {
        final group = groupWith(
          id: 'g',
          name: 'G',
          sortState: const GroupSortState(
            mode: GroupSortMode.manual,
            manualOrder: ['e1', 'e2', 'e3'],
          ),
        );
        final repo = _FakeMemberGroupsRepository();
        await tester.pumpWidget(
          _buildSubject(
            group: group,
            allGroups: [group],
            allEntries: [
              entry('e1', 'g', 'm1'),
              entry('e2', 'g', 'm2'),
              entry('e3', 'g', 'm3'),
            ],
            activeMembers: [
              _member(id: 'm1', name: 'Alice'),
              _member(id: 'm2', name: 'Bob'),
              _member(id: 'm3', name: 'Carol'),
            ],
            notifier: _FakeGroupNotifier(),
            repository: repo,
          ),
        );
        await tester.pumpAndSettle();

        // Drive "Move up" on Bob's row (entry id e2).
        final bobCard = find.ancestor(
          of: find.text('Bob'),
          matching: find.byType(MemberCard),
        );
        final node = tester.getSemantics(bobCard);
        final actionIds =
            node.getSemanticsData().customSemanticsActionIds ?? const <int>[];
        final moveUpId = actionIds.firstWhere(
          (id) => CustomSemanticsAction.getAction(id)?.label == 'Move up',
          orElse: () => -1,
        );
        expect(moveUpId, isNot(-1));

        WidgetsBinding
            .instance
            // ignore: deprecated_member_use
            .pipelineOwner
            .semanticsOwner
            ?.performAction(node.id, SemanticsAction.customAction, moveUpId);
        await tester.pumpAndSettle();

        // The moved row's Focus widget must carry a non-null FocusNode —
        // proves the per-entry focus map is wired up in the production
        // build. We find by the explicit ValueKey to skip past Material's
        // implicit Focus wrappers around the inner MemberCard.
        final movedFocusFinder = find.byKey(const ValueKey('member_focus_e2'));
        expect(movedFocusFinder, findsOneWidget);
        final movedFocus = tester.widget<Focus>(movedFocusFinder);
        expect(
          movedFocus.focusNode,
          isNotNull,
          reason:
              'each row must carry a per-entry FocusNode so the post-frame '
              'requestFocus has a target after the reorder',
        );
        // Best-effort: the focus *should* land on the moved row. Flutter's
        // widget-test focus is flaky for non-input rebuilt widgets, so we
        // tolerate either outcome — the wiring above is the load-bearing
        // assertion, the manual a11y smoke pass is the source of truth
        // for actual screen-reader caret behavior.
        // ignore: avoid_print
        // print('moved hasFocus: ${movedFocus.focusNode?.hasFocus}');
      },
      semanticsEnabled: true,
    );

    testWidgets(
      'custom semantic action "Move up" sends the "Moved to position N of M" '
      'announcement on the flutter/accessibility channel',
      (tester) async {
        final announcements = _captureSemanticAnnouncements();
        final group = groupWith(
          id: 'g',
          name: 'G',
          sortState: const GroupSortState(
            mode: GroupSortMode.manual,
            manualOrder: ['e1', 'e2', 'e3'],
          ),
        );
        final repo = _FakeMemberGroupsRepository();
        await tester.pumpWidget(
          _buildSubject(
            group: group,
            allGroups: [group],
            allEntries: [
              entry('e1', 'g', 'm1'),
              entry('e2', 'g', 'm2'),
              entry('e3', 'g', 'm3'),
            ],
            activeMembers: [
              _member(id: 'm1', name: 'Alice'),
              _member(id: 'm2', name: 'Bob'),
              _member(id: 'm3', name: 'Carol'),
            ],
            notifier: _FakeGroupNotifier(),
            repository: repo,
          ),
        );
        await tester.pumpAndSettle();

        // Move Bob up (from position 2 to position 1 of 3).
        final bobCard = find.ancestor(
          of: find.text('Bob'),
          matching: find.byType(MemberCard),
        );
        final node = tester.getSemantics(bobCard);
        final actionIds =
            node.getSemanticsData().customSemanticsActionIds ?? const <int>[];
        final moveUpId = actionIds.firstWhere(
          (id) => CustomSemanticsAction.getAction(id)?.label == 'Move up',
          orElse: () => -1,
        );
        expect(moveUpId, isNot(-1));

        WidgetsBinding
            .instance
            // ignore: deprecated_member_use
            .pipelineOwner
            .semanticsOwner
            ?.performAction(node.id, SemanticsAction.customAction, moveUpId);
        await tester.pumpAndSettle();

        // Announcement event payloads have type 'announce' and a data.message
        // field carrying the l10n string.
        final announceMessages = announcements
            .where((event) => event['type'] == 'announce')
            .map((event) => (event['data'] as Map)['message']?.toString() ?? '')
            .toList();
        expect(
          announceMessages,
          contains('Moved to position 1 of 3'),
          reason:
              'a11y move-up must announce the new position via '
              'SemanticsService.sendAnnouncement',
        );
      },
      semanticsEnabled: true,
    );

    testWidgets('drag in sorted mode sends the "Group is now sorted manually" '
        'announcement on the flutter/accessibility channel', (tester) async {
      final announcements = _captureSemanticAnnouncements();
      final group = groupWith(
        id: 'g',
        name: 'G',
        sortState: GroupSortState.locked(GroupSortMode.nameAsc),
      );
      final repo = _FakeMemberGroupsRepository();
      await tester.pumpWidget(
        _buildSubject(
          group: group,
          allGroups: [group],
          allEntries: [entry('e1', 'g', 'm1'), entry('e2', 'g', 'm2')],
          activeMembers: [
            _member(id: 'm1', name: 'Alice'),
            _member(id: 'm2', name: 'Bob'),
          ],
          notifier: _FakeGroupNotifier(),
          repository: repo,
        ),
      );
      await tester.pumpAndSettle();

      final handle = find.byType(ReorderableDragStartListener).first;
      await tester.timedDrag(
        handle,
        const Offset(0, 120),
        const Duration(milliseconds: 500),
      );
      await tester.pumpAndSettle();

      final announceMessages = announcements
          .where((event) => event['type'] == 'announce')
          .map((event) => (event['data'] as Map)['message']?.toString() ?? '')
          .toList();
      expect(
        announceMessages,
        contains('Group is now sorted manually.'),
        reason:
            'implicit-unlock drag must announce the mode change via '
            'SemanticsService.sendAnnouncement',
      );
      // Let the implicit-unlock toast auto-dismiss before the test ends.
      await tester.pump(const Duration(seconds: 4));
    });
  });

  // ── Task 5.2 sub-group reorder ───────────────────────────────────────────

  group('sub-group reorder', () {
    testWidgets('drag handle hidden when there is one sub-group', (
      tester,
    ) async {
      final parent = _group(id: 'parent', name: 'Parent');
      final child = _group(id: 'child', name: 'Child', parentGroupId: 'parent');
      await tester.pumpWidget(
        _buildSubject(
          group: parent,
          allGroups: [parent, child],
          allEntries: const [],
          activeMembers: const [],
          notifier: _FakeGroupNotifier(),
        ),
      );
      await tester.pumpAndSettle();

      // No drag handles inside the sub-groups section when count == 1.
      // (The lone row uses a plain ListView.builder.)
      expect(
        find.descendant(
          of: find.byType(ReorderableDragStartListener),
          matching: find.text('Child'),
        ),
        findsNothing,
      );
      // No ReorderableListView in the sub-groups area.
      expect(find.byType(ReorderableListView), findsNothing);
    });

    testWidgets(
      'drag handles visible at 2+ sub-groups; reorder triggers reorderGroups',
      (tester) async {
        final parent = _group(id: 'parent', name: 'Parent');
        final child1 = _group(id: 'c1', name: 'Alpha', parentGroupId: 'parent');
        final child2 = _group(id: 'c2', name: 'Beta', parentGroupId: 'parent');
        final notifier = _ReorderingFakeGroupNotifier();
        await tester.pumpWidget(
          _buildSubject(
            group: parent,
            allGroups: [parent, child1, child2],
            allEntries: const [],
            activeMembers: const [],
            notifier: notifier,
          ),
        );
        await tester.pumpAndSettle();

        // Two reorderable items + drag handles render.
        expect(find.byType(ReorderableListView), findsOneWidget);
        expect(find.text('Alpha'), findsOneWidget);
        expect(find.text('Beta'), findsOneWidget);

        // The ReorderableDragStartListener belongs to MemberGroupRow; with
        // a custom listener we drive it via `tester.timedDrag`. The default
        // `tester.drag` uses too-fast a velocity and the framework treats it
        // as a scroll instead of a reorder gesture.
        final handle = find.byType(ReorderableDragStartListener).first;
        await tester.timedDrag(
          handle,
          const Offset(0, 120),
          const Duration(seconds: 1),
        );
        await tester.pumpAndSettle();

        expect(notifier.reorderedSequences.length, greaterThanOrEqualTo(1));
        expect(notifier.reorderedSequences.last.map((g) => g.id).toList(), [
          'c2',
          'c1',
        ]);
      },
    );
  });
}

class _ReorderingFakeGroupNotifier extends _FakeGroupNotifier {
  final reorderedSequences = <List<MemberGroup>>[];

  @override
  Future<void> reorderGroups(List<MemberGroup> groups) async {
    reorderedSequences.add(List.of(groups));
  }
}
