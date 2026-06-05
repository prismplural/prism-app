import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/members/navigation/member_navigation_branch.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/views/group_detail_screen.dart';
import 'package:prism_plurality/features/members/views/groups_screen.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

class _RecordingGroupNotifier extends GroupNotifier {
  _RecordingGroupNotifier({this.reorderCompleter});

  final Completer<void>? reorderCompleter;
  final reorderedSequences = <List<MemberGroup>>[];
  final deletedIds = <String>[];

  @override
  Future<void> build() async {}

  @override
  Future<void> reorderGroups(List<MemberGroup> groups) async {
    reorderedSequences.add(List.of(groups));
    await (reorderCompleter?.future ?? Future<void>.value());
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    deletedIds.add(groupId);
  }
}

MemberGroup _group({
  required String id,
  required String name,
  int displayOrder = 0,
  String? parentGroupId,
  DateTime? createdAt,
}) => MemberGroup(
  id: id,
  name: name,
  displayOrder: displayOrder,
  parentGroupId: parentGroupId,
  createdAt: createdAt ?? DateTime(2024),
);

Widget _buildSubject({
  required List<MemberGroup> groups,
  required _RecordingGroupNotifier notifier,
}) {
  return ProviderScope(
    overrides: [
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
      allGroupsProvider.overrideWith((ref) => Stream.value(groups)),
      allGroupEntriesProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroupEntry>[]),
      ),
      groupByIdProvider.overrideWith((ref, groupId) {
        final matching = groups.where((group) => group.id == groupId);
        return Stream.value(matching.isEmpty ? null : matching.first);
      }),
      groupEntriesProvider.overrideWith(
        (ref, groupId) => Stream.value(const <MemberGroupEntry>[]),
      ),
      activeMembersProvider.overrideWith(
        (ref) => Stream.value(const <Member>[]),
      ),
      allMembersProvider.overrideWith((ref) => Stream.value(const <Member>[])),
      groupNotifierProvider.overrideWith(() => notifier),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      builder: (context, child) =>
          PrismToastHost(child: child ?? const SizedBox.shrink()),
      home: const GroupsScreen(showBackButton: false),
    ),
  );
}

void main() {
  test('member navigation branch maps group routes explicitly', () {
    expect(
      MemberNavigationBranch.settings.groupPath('crew'),
      AppRoutePaths.settingsGroup('crew'),
    );
    expect(
      MemberNavigationBranch.members.groupPath('crew'),
      AppRoutePaths.memberGroup('crew'),
    );
    expect(
      MemberNavigationBranch.groups.groupPath('crew'),
      AppRoutePaths.group('crew'),
    );
  });

  testWidgets('wide layouts drill into groups in the centered primary view', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final group = _group(id: 'crew', name: 'Crew');
    final notifier = _RecordingGroupNotifier();

    await tester.pumpWidget(_buildSubject(groups: [group], notifier: notifier));
    await tester.pumpAndSettle();

    expect(find.byType(GroupDetailScreen), findsNothing);
    expect(find.byTooltip('Back'), findsNothing);

    await tester.tap(find.text('Crew'));
    await tester.pumpAndSettle();

    expect(find.byType(GroupDetailScreen), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.byType(GroupDetailScreen), findsNothing);
    expect(find.text('Crew'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
  });

  testWidgets('wide layouts handle system back from group detail', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final group = _group(id: 'crew', name: 'Crew');
    final notifier = _RecordingGroupNotifier();

    await tester.pumpWidget(_buildSubject(groups: [group], notifier: notifier));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Crew'));
    await tester.pumpAndSettle();

    expect(find.byType(GroupDetailScreen), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);

    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(handled, isTrue);
    expect(find.byType(GroupDetailScreen), findsNothing);
    expect(find.text('Crew'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
  });

  testWidgets('wide layouts delete group without popping app route', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final group = _group(id: 'crew', name: 'Crew');
    final notifier = _RecordingGroupNotifier();

    await tester.pumpWidget(_buildSubject(groups: [group], notifier: notifier));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Crew'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(notifier.deletedIds, ['crew']);
    expect(find.byType(GroupsScreen), findsOneWidget);
    expect(find.byType(GroupDetailScreen), findsNothing);
    expect(find.text('Crew'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('wide layouts reset when the groups tab is selected', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final group = _group(id: 'crew', name: 'Crew');
    final notifier = _RecordingGroupNotifier();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          systemSettingsProvider.overrideWith(
            (ref) => Stream.value(const SystemSettings()),
          ),
          allGroupsProvider.overrideWith((ref) => Stream.value([group])),
          allGroupEntriesProvider.overrideWith(
            (ref) => Stream.value(const <MemberGroupEntry>[]),
          ),
          groupByIdProvider.overrideWith(
            (ref, groupId) => Stream.value(groupId == group.id ? group : null),
          ),
          groupEntriesProvider.overrideWith(
            (ref, groupId) => Stream.value(const <MemberGroupEntry>[]),
          ),
          activeMembersProvider.overrideWith(
            (ref) => Stream.value(const <Member>[]),
          ),
          allMembersProvider.overrideWith(
            (ref) => Stream.value(const <Member>[]),
          ),
          groupNotifierProvider.overrideWith(() => notifier),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('en')],
          home: GroupsScreen(
            showBackButton: false,
            branch: MemberNavigationBranch.groups,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Crew'));
    await tester.pumpAndSettle();

    expect(find.byType(GroupDetailScreen), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(GroupsScreen)),
    );
    container
        .read(tabSelectionProvider.notifier)
        .fire(
          branchIndex: appShellBranchIndex(AppShellTabId.groups),
          isRetap: true,
        );
    await tester.pumpAndSettle();

    expect(find.byType(GroupDetailScreen), findsNothing);
    expect(find.text('Crew'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
  });

  testWidgets('offers one-shot sorting for root groups and sub-groups', (
    tester,
  ) async {
    final rootBeta = _group(id: 'root-beta', name: 'Beta', displayOrder: 0);
    final childZed = _group(
      id: 'child-zed',
      name: 'Zed',
      displayOrder: 0,
      parentGroupId: 'root-beta',
    );
    final childAble = _group(
      id: 'child-able',
      name: 'Able',
      displayOrder: 1,
      parentGroupId: 'root-beta',
    );
    final rootAlpha = _group(id: 'root-alpha', name: 'Alpha', displayOrder: 1);
    final notifier = _RecordingGroupNotifier();

    await tester.pumpWidget(
      _buildSubject(
        groups: [rootBeta, childZed, childAble, rootAlpha],
        notifier: notifier,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('More options'), findsOneWidget);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Name A'));
    await tester.pumpAndSettle();

    expect(find.text('Sort groups'), findsOneWidget);
    await tester.tap(find.text('Groups and sub-groups'));
    await tester.pumpAndSettle();

    expect(notifier.reorderedSequences.length, 2);
    expect(notifier.reorderedSequences[0].map((group) => group.id).toList(), [
      'root-alpha',
      'root-beta',
    ]);
    expect(notifier.reorderedSequences[1].map((group) => group.id).toList(), [
      'child-able',
      'child-zed',
    ]);
    expect(find.text('Order updated'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('can sort only top-level groups when sub-groups exist', (
    tester,
  ) async {
    final rootBeta = _group(id: 'root-beta', name: 'Beta', displayOrder: 0);
    final childZed = _group(
      id: 'child-zed',
      name: 'Zed',
      displayOrder: 0,
      parentGroupId: 'root-beta',
    );
    final childAble = _group(
      id: 'child-able',
      name: 'Able',
      displayOrder: 1,
      parentGroupId: 'root-beta',
    );
    final rootAlpha = _group(id: 'root-alpha', name: 'Alpha', displayOrder: 1);
    final notifier = _RecordingGroupNotifier();

    await tester.pumpWidget(
      _buildSubject(
        groups: [rootBeta, childZed, childAble, rootAlpha],
        notifier: notifier,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Name A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Top-level groups only'));
    await tester.pumpAndSettle();

    expect(notifier.reorderedSequences.length, 1);
    expect(
      notifier.reorderedSequences.single.map((group) => group.id).toList(),
      ['root-alpha', 'root-beta'],
    );
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('keeps overflow visible for a single group', (tester) async {
    final group = _group(id: 'solo', name: 'Solo');
    final notifier = _RecordingGroupNotifier();

    await tester.pumpWidget(_buildSubject(groups: [group], notifier: notifier));
    await tester.pumpAndSettle();

    expect(find.byTooltip('More options'), findsOneWidget);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Name A'));
    await tester.pumpAndSettle();

    expect(notifier.reorderedSequences, isEmpty);
  });

  testWidgets(
    'dragging a root group below an expanded root reorders root siblings '
    'optimistically',
    (tester) async {
      final alpha = _group(id: 'alpha', name: 'Alpha', displayOrder: 0);
      final beta = _group(id: 'beta', name: 'Beta', displayOrder: 1);
      final betaChildOne = _group(
        id: 'beta-child-one',
        name: 'Beta child one',
        displayOrder: 0,
        parentGroupId: 'beta',
      );
      final betaChildTwo = _group(
        id: 'beta-child-two',
        name: 'Beta child two',
        displayOrder: 1,
        parentGroupId: 'beta',
      );
      final gamma = _group(id: 'gamma', name: 'Gamma', displayOrder: 2);
      final persistence = Completer<void>();
      final notifier = _RecordingGroupNotifier(reorderCompleter: persistence);

      await tester.pumpWidget(
        _buildSubject(
          groups: [alpha, beta, betaChildOne, betaChildTwo, gamma],
          notifier: notifier,
        ),
      );
      await tester.pumpAndSettle();

      final alphaHandle = find.byType(ReorderableDragStartListener).first;
      await tester.timedDrag(
        alphaHandle,
        const Offset(0, 220),
        const Duration(milliseconds: 500),
      );
      await tester.pumpAndSettle();

      expect(notifier.reorderedSequences.length, 1);
      expect(notifier.reorderedSequences.single.map((g) => g.id), [
        'beta',
        'alpha',
        'gamma',
      ]);
      expect(
        tester.getTopLeft(find.text('Beta')).dy <
            tester.getTopLeft(find.text('Alpha')).dy,
        isTrue,
      );

      persistence.complete();
      await tester.pumpAndSettle();
    },
  );
}
