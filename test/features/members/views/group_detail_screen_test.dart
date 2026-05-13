import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/utils/group_tree_utils.dart';
import 'package:prism_plurality/features/members/views/group_detail_screen.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';

class _FakeGroupNotifier extends GroupNotifier {
  final addedMemberIds = <String>[];

  @override
  Future<void> build() async {}

  @override
  Future<void> addMemberToGroup(String groupId, String memberId) async {
    addedMemberIds.add(memberId);
  }
}

Member _member({required String id, required String name}) =>
    Member(id: id, name: name, createdAt: DateTime(2024));

MemberGroup _group({
  required String id,
  required String name,
  String? parentGroupId,
  String? colorHex,
  String? emoji,
}) => MemberGroup(
  id: id,
  name: name,
  colorHex: colorHex,
  emoji: emoji,
  parentGroupId: parentGroupId,
  createdAt: DateTime(2024),
);

Widget _buildSubject({
  required MemberGroup group,
  required List<MemberGroup> allGroups,
  required List<MemberGroupEntry> allEntries,
  required List<Member> activeMembers,
  required _FakeGroupNotifier notifier,
}) {
  return ProviderScope(
    overrides: [
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
      activeMembersProvider.overrideWith((ref) => Stream.value(activeMembers)),
      allMembersProvider.overrideWith((ref) => Stream.value(activeMembers)),
      memberByIdProvider.overrideWith((ref, memberId) {
        final matching = activeMembers.where((member) => member.id == memberId);
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
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: GroupDetailScreen(groupId: group.id),
    ),
  );
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
}
