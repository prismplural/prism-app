import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
import 'package:prism_plurality/features/members/widgets/member_group_row.dart';
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
  Stream<List<MemberGroup>>? groupsStream,
}) {
  return ProviderScope(
    overrides: [
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
      allGroupsProvider.overrideWith(
        (ref) => groupsStream ?? Stream.value(groups),
      ),
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

/// Phone-sized view (390x844 logical, 3x) with notch and home-indicator
/// safe-area insets.
void _usePhoneView(WidgetTester tester) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.padding = const FakeViewPadding(top: 141, bottom: 102);
  tester.view.viewPadding = const FakeViewPadding(top: 141, bottom: 102);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });
}

/// The reorder handle inside the group row showing [name]. Matches any
/// [ReorderableDragStartListener] subtype.
Finder _groupHandle(String name) => find.descendant(
  of: find.widgetWithText(MemberGroupRow, name),
  matching: find.byWidgetPredicate((w) => w is ReorderableDragStartListener),
);

ScrollableState _rootScrollable(WidgetTester tester) =>
    tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(ReorderableListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );

/// A drag distance that moves a row exactly one slot down: past the next
/// row's midpoint but not past its end.
Offset _oneSlotDown(WidgetTester tester, String name) => Offset(
  0,
  tester.getSize(find.widgetWithText(MemberGroupRow, name)).height * 0.75,
);

/// Drives a pointer like a real device: one move event per frame with
/// increasing timestamps, pumping a frame between events.
Future<void> _framedSwipe(
  WidgetTester tester,
  Offset start,
  Offset total, {
  int frames = 12,
  Duration frameInterval = const Duration(milliseconds: 16),
  Duration holdBeforeMove = Duration.zero,
  PointerDeviceKind kind = PointerDeviceKind.touch,
  bool cancelInsteadOfUp = false,
  Future<void> Function()? midway,
}) async {
  final gesture = await tester.startGesture(start, kind: kind);
  var elapsed = Duration.zero;
  if (holdBeforeMove > Duration.zero) {
    await tester.pump(holdBeforeMove);
    elapsed += holdBeforeMove;
  }
  final step = total / frames.toDouble();
  for (var frame = 1; frame <= frames; frame++) {
    elapsed += frameInterval;
    await gesture.moveBy(step, timeStamp: elapsed);
    await tester.pump(frameInterval);
    if (frame == frames ~/ 2 && midway != null) await midway();
  }
  if (cancelInsteadOfUp) {
    await gesture.cancel();
  } else {
    await gesture.up(timeStamp: elapsed);
  }
  await tester.pumpAndSettle();
}

List<MemberGroup> _manyRootGroups() => [
  for (var index = 0; index < 40; index++)
    _group(id: 'group-$index', name: 'Group $index', displayOrder: index),
];

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

  group('reorder handle gestures on a phone', () {
    for (final frameMs in [8, 16, 100]) {
      testWidgets(
        'touch scroll that starts on a reorder handle scrolls and never '
        'writes ($frameMs ms frames)',
        (tester) async {
          _usePhoneView(tester);
          final notifier = _RecordingGroupNotifier();
          await tester.pumpWidget(
            _buildSubject(groups: _manyRootGroups(), notifier: notifier),
          );
          await tester.pumpAndSettle();
          final initialOffset = _rootScrollable(tester).position.pixels;

          await _framedSwipe(
            tester,
            tester.getCenter(_groupHandle('Group 3')),
            const Offset(0, -180),
            frameInterval: Duration(milliseconds: frameMs),
          );

          expect(notifier.reorderedSequences, isEmpty);
          expect(
            _rootScrollable(tester).position.pixels,
            greaterThan(initialOffset),
          );
        },
      );
    }

    testWidgets('touch fling that starts on a reorder handle never writes', (
      tester,
    ) async {
      _usePhoneView(tester);
      final notifier = _RecordingGroupNotifier();
      await tester.pumpWidget(
        _buildSubject(groups: _manyRootGroups(), notifier: notifier),
      );
      await tester.pumpAndSettle();
      final initialOffset = _rootScrollable(tester).position.pixels;

      await tester.flingFrom(
        tester.getCenter(_groupHandle('Group 4')),
        const Offset(0, -260),
        2000,
      );
      await tester.pumpAndSettle();

      expect(notifier.reorderedSequences, isEmpty);
      expect(
        _rootScrollable(tester).position.pixels,
        greaterThan(initialOffset),
      );
    });

    testWidgets(
      'second flick that lands on a handle during inertia never writes',
      (tester) async {
        _usePhoneView(tester);
        final notifier = _RecordingGroupNotifier();
        await tester.pumpWidget(
          _buildSubject(groups: _manyRootGroups(), notifier: notifier),
        );
        await tester.pumpAndSettle();

        // First flick from a row body starts a ballistic scroll.
        await tester.flingFrom(
          tester.getCenter(find.text('Group 6')),
          const Offset(0, -200),
          1500,
        );
        await tester.pump(const Duration(milliseconds: 60));
        final flingingOffset = _rootScrollable(tester).position.pixels;

        // The next flick lands wherever a handle now is.
        // Taken from layout, not hit-testing: while the list is still
        // flinging, Scrollable ignores pointers on its content.
        final visibleHandle = find
            .byWidgetPredicate((w) => w is ReorderableDragStartListener)
            .at(3);
        await _framedSwipe(
          tester,
          tester.getCenter(visibleHandle),
          const Offset(0, -160),
          frames: 8,
        );

        expect(notifier.reorderedSequences, isEmpty);
        expect(
          _rootScrollable(tester).position.pixels,
          greaterThan(flingingOffset),
        );
      },
    );

    testWidgets('holding a handle with touch, then dragging, reorders', (
      tester,
    ) async {
      _usePhoneView(tester);
      final alpha = _group(id: 'alpha', name: 'Alpha', displayOrder: 0);
      final beta = _group(id: 'beta', name: 'Beta', displayOrder: 1);
      final gamma = _group(id: 'gamma', name: 'Gamma', displayOrder: 2);
      final notifier = _RecordingGroupNotifier();
      await tester.pumpWidget(
        _buildSubject(groups: [alpha, beta, gamma], notifier: notifier),
      );
      await tester.pumpAndSettle();

      await _framedSwipe(
        tester,
        tester.getCenter(_groupHandle('Alpha')),
        _oneSlotDown(tester, 'Alpha'),
        frames: 20,
        holdBeforeMove: kLongPressTimeout + const Duration(milliseconds: 100),
      );

      expect(notifier.reorderedSequences, hasLength(1));
      expect(notifier.reorderedSequences.single.map((g) => g.id), [
        'beta',
        'alpha',
        'gamma',
      ]);
    });

    testWidgets(
      'screen reader "Move up" on a root group writes one reorder',
      (tester) async {
        final alpha = _group(id: 'alpha', name: 'Alpha', displayOrder: 0);
        final beta = _group(id: 'beta', name: 'Beta', displayOrder: 1);
        final gamma = _group(id: 'gamma', name: 'Gamma', displayOrder: 2);
        final notifier = _RecordingGroupNotifier();
        await tester.pumpWidget(
          _buildSubject(groups: [alpha, beta, gamma], notifier: notifier),
        );
        await tester.pumpAndSettle();

        final node = tester.getSemantics(
          find.widgetWithText(MemberGroupRow, 'Beta'),
        );
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

        expect(notifier.reorderedSequences, hasLength(1));
        expect(notifier.reorderedSequences.single.map((g) => g.id), [
          'beta',
          'alpha',
          'gamma',
        ]);
      },
      semanticsEnabled: true,
    );

    testWidgets('mouse drag on a handle reorders without a hold', (
      tester,
    ) async {
      final alpha = _group(id: 'alpha', name: 'Alpha', displayOrder: 0);
      final beta = _group(id: 'beta', name: 'Beta', displayOrder: 1);
      final gamma = _group(id: 'gamma', name: 'Gamma', displayOrder: 2);
      final notifier = _RecordingGroupNotifier();
      await tester.pumpWidget(
        _buildSubject(groups: [alpha, beta, gamma], notifier: notifier),
      );
      await tester.pumpAndSettle();

      await _framedSwipe(
        tester,
        tester.getCenter(_groupHandle('Alpha')),
        _oneSlotDown(tester, 'Alpha'),
        frames: 20,
        kind: PointerDeviceKind.mouse,
      );

      expect(notifier.reorderedSequences, hasLength(1));
      expect(notifier.reorderedSequences.single.map((g) => g.id), [
        'beta',
        'alpha',
        'gamma',
      ]);
    });

    for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
      testWidgets('handle drag cancelled mid-flight never writes ($kind)', (
        tester,
      ) async {
        _usePhoneView(tester);
        final notifier = _RecordingGroupNotifier();
        await tester.pumpWidget(
          _buildSubject(groups: _manyRootGroups(), notifier: notifier),
        );
        await tester.pumpAndSettle();
        final group0Top = tester.getTopLeft(find.text('Group 0')).dy;

        await _framedSwipe(
          tester,
          tester.getCenter(_groupHandle('Group 0')),
          const Offset(0, 200),
          frames: 20,
          kind: kind,
          holdBeforeMove: kind == PointerDeviceKind.touch
              ? kLongPressTimeout + const Duration(milliseconds: 100)
              : Duration.zero,
          cancelInsteadOfUp: true,
        );

        expect(notifier.reorderedSequences, isEmpty);
        expect(tester.getTopLeft(find.text('Group 0')).dy, group0Top);
      });
    }

    testWidgets(
      'a synced group list change during a drag never moves another group',
      (tester) async {
        final initial = [
          for (var index = 0; index < 6; index++)
            _group(
              id: 'group-$index',
              name: 'Group $index',
              displayOrder: index,
            ),
        ];
        final inserted = _group(
          id: 'inserted',
          name: 'Inserted',
          displayOrder: -1,
        );
        final controller = StreamController<List<MemberGroup>>();
        addTearDown(controller.close);
        controller.add(initial);
        final notifier = _RecordingGroupNotifier();
        await tester.pumpWidget(
          _buildSubject(
            groups: initial,
            notifier: notifier,
            groupsStream: controller.stream,
          ),
        );
        await tester.pumpAndSettle();

        // Mouse-drag Group 2 toward the top; mid-drag another device's
        // insert arrives and shifts every index by one.
        await _framedSwipe(
          tester,
          tester.getCenter(_groupHandle('Group 2')),
          const Offset(0, -150),
          frames: 20,
          kind: PointerDeviceKind.mouse,
          midway: () async {
            controller.add([inserted, ...initial]);
            await tester.pump();
            await tester.pump();
          },
        );

        for (final written in notifier.reorderedSequences) {
          final othersWritten = [
            for (final g in written)
              if (g.id != 'group-2') g.id,
          ];
          final othersBefore = [
            for (final g in [inserted, ...initial])
              if (g.id != 'group-2' &&
                  written.any((candidate) => candidate.id == g.id))
                g.id,
          ];
          expect(
            othersWritten,
            othersBefore,
            reason: 'only the dragged group may change position',
          );
        }
        // The drop is still written, it keeps the synced group, and the
        // dragged group moved up past Group 1.
        expect(notifier.reorderedSequences, hasLength(1));
        final written = [
          for (final g in notifier.reorderedSequences.single) g.id,
        ];
        expect(
          written.toSet(),
          {'inserted', for (final g in initial) g.id},
          reason: 'a group synced during the drag must not be dropped',
        );
        expect(
          written.indexOf('group-2'),
          lessThan(written.indexOf('group-1')),
        );
        expect(find.text('Inserted'), findsOneWidget);
      },
    );

    testWidgets(
      'rows stay put during a drag and synced changes appear after the drop',
      (tester) async {
        final initial = [
          for (var index = 0; index < 6; index++)
            _group(
              id: 'group-$index',
              name: 'Group $index',
              displayOrder: index,
            ),
        ];
        final inserted = _group(
          id: 'inserted',
          name: 'Inserted',
          displayOrder: -1,
        );
        final controller = StreamController<List<MemberGroup>>();
        addTearDown(controller.close);
        controller.add(initial);
        final notifier = _RecordingGroupNotifier();
        await tester.pumpWidget(
          _buildSubject(
            groups: initial,
            notifier: notifier,
            groupsStream: controller.stream,
          ),
        );
        await tester.pumpAndSettle();

        var shownDuringDrag = true;
        await _framedSwipe(
          tester,
          tester.getCenter(_groupHandle('Group 2')),
          const Offset(0, -150),
          frames: 20,
          kind: PointerDeviceKind.mouse,
          midway: () async {
            controller.add([inserted, ...initial]);
            await tester.pump();
            await tester.pump();
            shownDuringDrag = find.text('Inserted').evaluate().isNotEmpty;
          },
        );

        expect(shownDuringDrag, isFalse);
        expect(find.text('Inserted'), findsOneWidget);
      },
    );

    testWidgets(
      'a group synced during the touch hold does not change which group lifts',
      (tester) async {
        _usePhoneView(tester);
        final initial = [
          for (var index = 0; index < 6; index++)
            _group(
              id: 'group-$index',
              name: 'Group $index',
              displayOrder: index,
            ),
        ];
        final inserted = _group(
          id: 'inserted',
          name: 'Inserted',
          displayOrder: -1,
        );
        final controller = StreamController<List<MemberGroup>>();
        addTearDown(controller.close);
        controller.add(initial);
        final notifier = _RecordingGroupNotifier();
        await tester.pumpWidget(
          _buildSubject(
            groups: initial,
            notifier: notifier,
            groupsStream: controller.stream,
          ),
        );
        await tester.pumpAndSettle();

        // Press Group 2's handle; another device's insert arrives before the
        // hold completes and would shift every row down by one.
        final gesture = await tester.startGesture(
          tester.getCenter(_groupHandle('Group 2')),
        );
        await tester.pump(const Duration(milliseconds: 200));
        controller.add([inserted, ...initial]);
        await tester.pump();
        await tester.pump(kLongPressTimeout);
        var elapsed = kLongPressTimeout + const Duration(milliseconds: 200);
        for (var frame = 0; frame < 20; frame++) {
          elapsed += const Duration(milliseconds: 16);
          await gesture.moveBy(const Offset(0, -150 / 20), timeStamp: elapsed);
          await tester.pump(const Duration(milliseconds: 16));
        }
        await gesture.up(timeStamp: elapsed);
        await tester.pumpAndSettle();

        expect(notifier.reorderedSequences, hasLength(1));
        final written = [
          for (final g in notifier.reorderedSequences.single) g.id,
        ];
        final live = ['inserted', for (final g in initial) g.id];
        expect(written.toSet(), live.toSet());
        expect(
          [
            for (final id in written)
              if (id != 'group-2') id,
          ],
          [
            for (final id in live)
              if (id != 'group-2') id,
          ],
          reason: 'only the pressed group (Group 2) may move',
        );
        expect(
          written.indexOf('group-2'),
          lessThan(written.indexOf('group-1')),
        );
        expect(find.text('Inserted'), findsOneWidget);
      },
    );

    testWidgets('a synced reorder during a drag never moves the wrong group', (
      tester,
    ) async {
      final initial = [
        for (var index = 0; index < 6; index++)
          _group(id: 'group-$index', name: 'Group $index', displayOrder: index),
      ];
      // Same group count: another device moves Group 0 to the end.
      final resorted = [
        for (final g in initial)
          g.id == 'group-0' ? g.copyWith(displayOrder: 10) : g,
      ];
      final controller = StreamController<List<MemberGroup>>();
      addTearDown(controller.close);
      controller.add(initial);
      final notifier = _RecordingGroupNotifier();
      await tester.pumpWidget(
        _buildSubject(
          groups: initial,
          notifier: notifier,
          groupsStream: controller.stream,
        ),
      );
      await tester.pumpAndSettle();

      await _framedSwipe(
        tester,
        tester.getCenter(_groupHandle('Group 2')),
        const Offset(0, -150),
        frames: 20,
        kind: PointerDeviceKind.mouse,
        midway: () async {
          controller.add(resorted);
          await tester.pump();
          await tester.pump();
        },
      );

      const live = [
        'group-1',
        'group-2',
        'group-3',
        'group-4',
        'group-5',
        'group-0',
      ];
      expect(notifier.reorderedSequences, hasLength(1));
      final written = [
        for (final g in notifier.reorderedSequences.single) g.id,
      ];
      expect(written.toSet(), live.toSet());
      expect(
        [
          for (final id in written)
            if (id != 'group-2') id,
        ],
        [
          for (final id in live)
            if (id != 'group-2') id,
        ],
        reason: 'only the dragged group may move; the synced order is kept',
      );
      expect(written, isNot(live));
    });

    testWidgets(
      'a dragged group deleted by sync during the drag is never written',
      (tester) async {
        final initial = [
          for (var index = 0; index < 6; index++)
            _group(
              id: 'group-$index',
              name: 'Group $index',
              displayOrder: index,
            ),
        ];
        final controller = StreamController<List<MemberGroup>>();
        addTearDown(controller.close);
        controller.add(initial);
        final notifier = _RecordingGroupNotifier();
        await tester.pumpWidget(
          _buildSubject(
            groups: initial,
            notifier: notifier,
            groupsStream: controller.stream,
          ),
        );
        await tester.pumpAndSettle();

        await _framedSwipe(
          tester,
          tester.getCenter(_groupHandle('Group 2')),
          const Offset(0, -150),
          frames: 20,
          kind: PointerDeviceKind.mouse,
          midway: () async {
            controller.add([
              for (final g in initial)
                if (g.id != 'group-2') g,
            ]);
            await tester.pump();
            await tester.pump();
          },
        );

        expect(notifier.reorderedSequences, isEmpty);
        expect(find.text('Group 2'), findsNothing);
        expect(find.text('Group 1'), findsOneWidget);
      },
    );

    testWidgets(
      'a cancelled drag with a synced insert writes nothing and shows it',
      (tester) async {
        final initial = [
          for (var index = 0; index < 6; index++)
            _group(
              id: 'group-$index',
              name: 'Group $index',
              displayOrder: index,
            ),
        ];
        final inserted = _group(
          id: 'inserted',
          name: 'Inserted',
          displayOrder: -1,
        );
        final controller = StreamController<List<MemberGroup>>();
        addTearDown(controller.close);
        controller.add(initial);
        final notifier = _RecordingGroupNotifier();
        await tester.pumpWidget(
          _buildSubject(
            groups: initial,
            notifier: notifier,
            groupsStream: controller.stream,
          ),
        );
        await tester.pumpAndSettle();

        await _framedSwipe(
          tester,
          tester.getCenter(_groupHandle('Group 2')),
          const Offset(0, -150),
          frames: 20,
          kind: PointerDeviceKind.mouse,
          cancelInsteadOfUp: true,
          midway: () async {
            controller.add([inserted, ...initial]);
            await tester.pump();
            await tester.pump();
          },
        );

        expect(notifier.reorderedSequences, isEmpty);
        expect(find.text('Inserted'), findsOneWidget);
      },
    );

    testWidgets(
      'a drag dropped where it started writes nothing and shows later syncs',
      (tester) async {
        final initial = [
          for (var index = 0; index < 6; index++)
            _group(
              id: 'group-$index',
              name: 'Group $index',
              displayOrder: index,
            ),
        ];
        final inserted = _group(
          id: 'inserted',
          name: 'Inserted',
          displayOrder: -1,
        );
        final controller = StreamController<List<MemberGroup>>();
        addTearDown(controller.close);
        controller.add(initial);
        final notifier = _RecordingGroupNotifier();
        await tester.pumpWidget(
          _buildSubject(
            groups: initial,
            notifier: notifier,
            groupsStream: controller.stream,
          ),
        );
        await tester.pumpAndSettle();

        // Mouse drag down a little and back to where it started.
        final gesture = await tester.startGesture(
          tester.getCenter(_groupHandle('Group 2')),
          kind: PointerDeviceKind.mouse,
        );
        for (final dy in [8.0, 8.0, 8.0, -8.0, -8.0, -8.0]) {
          await gesture.moveBy(Offset(0, dy));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await gesture.up();
        await tester.pumpAndSettle();
        expect(notifier.reorderedSequences, isEmpty);

        controller.add([inserted, ...initial]);
        await tester.pumpAndSettle();
        expect(find.text('Inserted'), findsOneWidget);
      },
    );

    testWidgets(
      'a scroll that starts on a handle shows a group synced during it',
      (tester) async {
        _usePhoneView(tester);
        final initial = _manyRootGroups();
        final inserted = _group(
          id: 'inserted',
          name: 'Inserted',
          displayOrder: 100,
        );
        final controller = StreamController<List<MemberGroup>>();
        addTearDown(controller.close);
        controller.add(initial);
        final notifier = _RecordingGroupNotifier();
        await tester.pumpWidget(
          _buildSubject(
            groups: initial,
            notifier: notifier,
            groupsStream: controller.stream,
          ),
        );
        await tester.pumpAndSettle();

        await _framedSwipe(
          tester,
          tester.getCenter(_groupHandle('Group 3')),
          const Offset(0, -180),
          midway: () async {
            controller.add([...initial, inserted]);
            await tester.pump();
          },
        );

        expect(notifier.reorderedSequences, isEmpty);
        await tester.scrollUntilVisible(
          find.text('Inserted'),
          300,
          scrollable: find
              .descendant(
                of: find.byType(ReorderableListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text('Inserted'), findsOneWidget);
      },
    );

    testWidgets(
      'a root drag with expanded children writes root siblings only when a '
      'child is synced during it',
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
        final betaChildNew = _group(
          id: 'beta-child-new',
          name: 'Beta child new',
          displayOrder: 2,
          parentGroupId: 'beta',
        );
        final initial = [alpha, beta, betaChildOne, betaChildTwo, gamma];
        final controller = StreamController<List<MemberGroup>>();
        addTearDown(controller.close);
        controller.add(initial);
        final notifier = _RecordingGroupNotifier();
        await tester.pumpWidget(
          _buildSubject(
            groups: initial,
            notifier: notifier,
            groupsStream: controller.stream,
          ),
        );
        await tester.pumpAndSettle();

        // Drag Gamma to the top; a new Beta child syncs in meanwhile.
        await _framedSwipe(
          tester,
          tester.getCenter(_groupHandle('Gamma')),
          Offset(
            0,
            tester.getTopLeft(find.text('Alpha')).dy -
                tester.getTopLeft(find.text('Gamma')).dy -
                40,
          ),
          frames: 30,
          kind: PointerDeviceKind.mouse,
          midway: () async {
            controller.add([...initial, betaChildNew]);
            await tester.pump();
            await tester.pump();
          },
        );

        expect(notifier.reorderedSequences, hasLength(1));
        expect(notifier.reorderedSequences.single.map((g) => g.id), [
          'gamma',
          'alpha',
          'beta',
        ]);
        expect(find.text('Beta child new'), findsOneWidget);
      },
    );

    testWidgets(
      'a dragged root group moved under another group by sync is never '
      'written',
      (tester) async {
        final initial = [
          for (var index = 0; index < 6; index++)
            _group(
              id: 'group-$index',
              name: 'Group $index',
              displayOrder: index,
            ),
        ];
        final controller = StreamController<List<MemberGroup>>();
        addTearDown(controller.close);
        controller.add(initial);
        final notifier = _RecordingGroupNotifier();
        await tester.pumpWidget(
          _buildSubject(
            groups: initial,
            notifier: notifier,
            groupsStream: controller.stream,
          ),
        );
        await tester.pumpAndSettle();

        await _framedSwipe(
          tester,
          tester.getCenter(_groupHandle('Group 2')),
          const Offset(0, -150),
          frames: 20,
          kind: PointerDeviceKind.mouse,
          midway: () async {
            controller.add([
              for (final g in initial)
                g.id == 'group-2'
                    ? g.copyWith(parentGroupId: 'group-5', displayOrder: 0)
                    : g,
            ]);
            await tester.pump();
            await tester.pump();
          },
        );

        expect(notifier.reorderedSequences, isEmpty);
      },
    );

    testWidgets(
      'a second drag while the first write is pending uses current groups',
      (tester) async {
        final initial = [
          for (var index = 0; index < 6; index++)
            _group(
              id: 'group-$index',
              name: 'Group $index',
              displayOrder: index,
            ),
        ];
        final controller = StreamController<List<MemberGroup>>();
        addTearDown(controller.close);
        controller.add(initial);
        // The first write never completes, so its optimistic order stays.
        final notifier = _RecordingGroupNotifier(
          reorderCompleter: Completer<void>(),
        );
        await tester.pumpWidget(
          _buildSubject(
            groups: initial,
            notifier: notifier,
            groupsStream: controller.stream,
          ),
        );
        await tester.pumpAndSettle();

        Future<void> dragToTop(String name) => _framedSwipe(
          tester,
          tester.getCenter(_groupHandle(name)),
          Offset(
            0,
            tester.getTopLeft(find.byType(MemberGroupRow).first).dy -
                tester.getTopLeft(find.text(name)).dy -
                20,
          ),
          frames: 30,
          kind: PointerDeviceKind.mouse,
        );

        await dragToTop('Group 2');
        expect(notifier.reorderedSequences, hasLength(1));
        expect(notifier.reorderedSequences.single.map((g) => g.id), [
          'group-2',
          'group-0',
          'group-1',
          'group-3',
          'group-4',
          'group-5',
        ]);

        // Before that write lands, sync moves Group 4 under Group 5. The
        // provider still has the old display orders.
        controller.add([
          for (final g in initial)
            g.id == 'group-4'
                ? g.copyWith(parentGroupId: 'group-5', displayOrder: 0)
                : g,
        ]);
        await tester.pumpAndSettle();

        await dragToTop('Group 3');
        expect(notifier.reorderedSequences, hasLength(2));
        final second = notifier.reorderedSequences.last;
        expect(
          second.map((g) => g.id),
          ['group-3', 'group-2', 'group-0', 'group-1', 'group-5'],
          reason:
              'the pending order is kept, and Group 4 (now a sub-group) is '
              'not written as a root group',
        );
        expect(second.every((g) => g.parentGroupId == null), isTrue);
      },
    );
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

      // Touch reorders start with a hold on the handle.
      await _framedSwipe(
        tester,
        tester.getCenter(_groupHandle('Alpha')),
        const Offset(0, 220),
        frames: 30,
        holdBeforeMove: kLongPressTimeout + const Duration(milliseconds: 100),
      );

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
