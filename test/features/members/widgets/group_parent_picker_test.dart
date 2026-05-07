import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/widgets/group_parent_picker.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';

MemberGroup _group({required String id, String? parentGroupId}) => MemberGroup(
  id: id,
  name: id,
  createdAt: DateTime(2024, 1, 1),
  parentGroupId: parentGroupId,
);

Widget _buildPicker(List<MemberGroup> groups, {String? excludeGroupId}) {
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
            currentParentId: null,
            onSelected: (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('blocks only parents that would exceed depth 5', (tester) async {
    final root = _group(id: 'root');
    final level2 = _group(id: 'level-2', parentGroupId: 'root');
    final level3 = _group(id: 'level-3', parentGroupId: 'level-2');
    final level4 = _group(id: 'level-4', parentGroupId: 'level-3');
    final level5 = _group(id: 'level-5', parentGroupId: 'level-4');

    await tester.pumpWidget(
      _buildPicker([root, level2, level3, level4, level5]),
    );
    await tester.pumpAndSettle();

    final level4Row = find.ancestor(
      of: find.text('level-4'),
      matching: find.byType(PrismListRow),
    );
    final level5Row = find.ancestor(
      of: find.text('level-5'),
      matching: find.byType(PrismListRow),
    );

    expect(tester.widget<PrismListRow>(level4Row).enabled, isTrue);
    expect(tester.widget<PrismListRow>(level5Row).enabled, isFalse);
    expect(find.text("Can't nest deeper"), findsOneWidget);
  });

  testWidgets('blocks reparenting a subtree past depth 5', (tester) async {
    final root = _group(id: 'root');
    final moving = _group(id: 'moving', parentGroupId: 'root');
    final movingChild = _group(id: 'moving-child', parentGroupId: 'moving');
    final allowedParent = _group(
      id: 'allowed-parent',
      parentGroupId: 'level-2',
    );
    final level2 = _group(id: 'level-2', parentGroupId: 'root');
    final blockedLevel2 = _group(id: 'blocked-level-2', parentGroupId: 'root');
    final blockedLevel3 = _group(
      id: 'blocked-level-3',
      parentGroupId: 'blocked-level-2',
    );
    final blockedParent = _group(
      id: 'blocked-parent',
      parentGroupId: 'blocked-level-3',
    );

    await tester.pumpWidget(
      _buildPicker([
        root,
        moving,
        movingChild,
        level2,
        allowedParent,
        blockedLevel2,
        blockedLevel3,
        blockedParent,
      ], excludeGroupId: 'moving'),
    );
    await tester.pumpAndSettle();

    final allowedRow = find.ancestor(
      of: find.text('allowed-parent'),
      matching: find.byType(PrismListRow),
    );
    final blockedRow = find.ancestor(
      of: find.text('blocked-parent'),
      matching: find.byType(PrismListRow),
    );

    expect(tester.widget<PrismListRow>(allowedRow).enabled, isTrue);
    expect(tester.widget<PrismListRow>(blockedRow).enabled, isFalse);
  });
}
