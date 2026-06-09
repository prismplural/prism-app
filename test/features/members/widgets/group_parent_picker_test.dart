import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/widgets/group_parent_picker.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

MemberGroup _group({required String id, String? parentGroupId}) => MemberGroup(
  id: id,
  name: id,
  createdAt: DateTime(2024, 1, 1),
  parentGroupId: parentGroupId,
);

Widget _buildPicker(
  List<MemberGroup> groups, {
  String? excludeGroupId,
  String? currentParentId,
}) {
  return ProviderScope(
    overrides: [allGroupsProvider.overrideWithValue(AsyncValue.data(groups))],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: GroupParentPicker(
            excludeGroupId: excludeGroupId,
            currentParentId: currentParentId,
            onSelected: (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'all non-self, non-descendant tiles are enabled regardless of depth',
    (tester) async {
      // Build a depth-7 chain: g0 -> g1 -> g2 -> g3 -> g4 -> g5 -> g6
      final groups = <MemberGroup>[];
      String? parent;
      for (var i = 0; i < 7; i++) {
        groups.add(_group(id: 'g$i', parentGroupId: parent));
        parent = 'g$i';
      }

      await tester.pumpWidget(_buildPicker(groups));
      await tester.pumpAndSettle();

      // No tile should have opacity 0.4 (the old disabled-tile path).
      final opacityWidgets = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .where((o) => o.opacity == 0.4)
          .toList();
      expect(opacityWidgets, isEmpty);

      // No tile should show the old "Can't nest deeper" subtitle.
      expect(find.textContaining("Can't nest deeper"), findsNothing);

      // Every group should be tappable (enabled).
      for (var i = 0; i < 7; i++) {
        final row = find.ancestor(
          of: find.text('g$i'),
          matching: find.byType(PrismListRow),
        );
        expect(tester.widget<PrismListRow>(row).enabled, isTrue);
      }
    },
  );

  testWidgets('excludes only the group itself and its descendants', (
    tester,
  ) async {
    final root = _group(id: 'root');
    final moving = _group(id: 'moving', parentGroupId: 'root');
    final movingChild = _group(id: 'moving-child', parentGroupId: 'moving');
    final sibling = _group(id: 'sibling', parentGroupId: 'root');

    await tester.pumpWidget(
      _buildPicker([
        root,
        moving,
        movingChild,
        sibling,
      ], excludeGroupId: 'moving'),
    );
    await tester.pumpAndSettle();

    // 'moving' and 'moving-child' should not appear (excluded).
    expect(find.text('moving'), findsNothing);
    expect(find.text('moving-child'), findsNothing);

    // 'root' and 'sibling' should appear and be enabled.
    for (final name in ['root', 'sibling']) {
      final row = find.ancestor(
        of: find.text(name),
        matching: find.byType(PrismListRow),
      );
      expect(row, findsOneWidget);
      expect(tester.widget<PrismListRow>(row).enabled, isTrue);
    }
  });

  testWidgets(
    'search keeps parent-picker cycle filtering for excluded descendants',
    (tester) async {
      final root = _group(id: 'root');
      final moving = _group(id: 'moving', parentGroupId: 'root');
      final movingChild = _group(id: 'moving-child', parentGroupId: 'moving');
      final sibling = _group(id: 'sibling', parentGroupId: 'root');

      await tester.pumpWidget(
        _buildPicker([
          root,
          moving,
          movingChild,
          sibling,
        ], excludeGroupId: 'moving'),
      );
      await tester.pumpAndSettle();

      Finder rowLabel(String name) => find.descendant(
        of: find.byType(PrismListRow),
        matching: find.text(name),
      );

      await tester.enterText(find.byType(PrismTextField), 'moving');
      await tester.pumpAndSettle();

      expect(rowLabel('moving'), findsNothing);
      expect(rowLabel('moving-child'), findsNothing);
      expect(find.text('No groups found'), findsOneWidget);

      await tester.enterText(find.byType(PrismTextField), 'root');
      await tester.pumpAndSettle();

      expect(rowLabel('root'), findsOneWidget);
      expect(rowLabel('sibling'), findsOneWidget);
      expect(rowLabel('moving'), findsNothing);
      expect(rowLabel('moving-child'), findsNothing);
    },
  );

  testWidgets('group rows expose hierarchy and selected semantics', (
    tester,
  ) async {
    final root = _group(id: 'root');
    final child = _group(id: 'child', parentGroupId: 'root');
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _buildPicker([root, child], currentParentId: 'child'),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('root, top level group'), findsOneWidget);
    expect(
      find.bySemanticsLabel('child, nested group, selected'),
      findsOneWidget,
    );

    semantics.dispose();
  });

  testWidgets('all groups in a formerly-blocked deep tree are now enabled', (
    tester,
  ) async {
    // The old code blocked groups at depth 4 (would push a child to depth 6).
    // With the depth gate removed, every group should be enabled.
    final root = _group(id: 'root');
    final level2 = _group(id: 'level-2', parentGroupId: 'root');
    final level3 = _group(id: 'level-3', parentGroupId: 'level-2');
    final level4 = _group(id: 'level-4', parentGroupId: 'level-3');
    final level5 = _group(id: 'level-5', parentGroupId: 'level-4');

    await tester.pumpWidget(
      _buildPicker([root, level2, level3, level4, level5]),
    );
    await tester.pumpAndSettle();

    for (final name in ['root', 'level-2', 'level-3', 'level-4', 'level-5']) {
      final row = find.ancestor(
        of: find.text(name),
        matching: find.byType(PrismListRow),
      );
      expect(
        tester.widget<PrismListRow>(row).enabled,
        isTrue,
        reason: '$name should be enabled with no depth limit',
      );
    }

    // Old depth-limit subtitle must not appear.
    expect(find.textContaining("Can't nest deeper"), findsNothing);
  });
}
