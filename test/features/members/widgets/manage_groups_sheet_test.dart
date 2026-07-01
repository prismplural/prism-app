import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/widgets/manage_groups_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

MemberGroup _group(String id, {String? parentGroupId}) => MemberGroup(
  id: id,
  name: id,
  parentGroupId: parentGroupId,
  createdAt: DateTime(2024, 1, 1),
);

MemberGroupEntry _entry(String groupId, String memberId) => MemberGroupEntry(
  id: '${groupId}_$memberId',
  groupId: groupId,
  memberId: memberId,
);

const _kMemberId = 'member-1';

Widget _harness({
  required List<MemberGroup> groups,
  required List<MemberGroupEntry> entries,
  required List<MemberGroup> memberGroups,
  double? height,
}) {
  return ProviderScope(
    overrides: [
      allGroupsProvider.overrideWith((ref) => Stream.value(groups)),
      allGroupEntriesProvider.overrideWith((ref) => Stream.value(entries)),
      memberGroupsProvider(
        _kMemberId,
      ).overrideWith((ref) => Stream.value(memberGroups)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: SizedBox(
          height: height,
          width: double.infinity,
          child: const ManageGroupsSheet(
            memberId: _kMemberId,
            memberName: 'Member 1',
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows loading indicator instead of empty list while '
      'memberGroupsProvider is still loading', (tester) async {
    final memberGroupsCompleter = Completer<List<MemberGroup>>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allGroupsProvider.overrideWith(
            (ref) => Stream.value([_group('gender'), _group('age')]),
          ),
          allGroupEntriesProvider.overrideWith(
            (ref) => Stream.value([_entry('gender', _kMemberId)]),
          ),
          memberGroupsProvider(_kMemberId).overrideWith(
            (ref) => Stream.fromFuture(memberGroupsCompleter.future),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('en')],
          home: Scaffold(
            body: SizedBox.expand(
              child: ManageGroupsSheet(
                memberId: _kMemberId,
                memberName: 'Member 1',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(PrismListRow), findsNothing);
    expect(find.byType(PrismSpinner), findsOneWidget);

    memberGroupsCompleter.complete([_group('gender')]);
    await tester.pumpAndSettle();

    expect(find.byType(PrismSpinner), findsNothing);
    expect(find.byType(PrismListRow), findsNWidgets(2));
  });

  testWidgets('small-height layout does not flex overflow', (tester) async {
    await tester.pumpWidget(
      _harness(
        groups: [_group('gender'), _group('age')],
        entries: const [],
        memberGroups: const [],
        height: 24,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Groups'), findsOneWidget);
  });

  testWidgets('list keeps the last row above bottom system navigation', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewPadding);

    final groups = [for (var i = 0; i < 24; i++) _group('group-$i')];

    await tester.pumpWidget(
      _harness(groups: groups, entries: const [], memberGroups: const []),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
    await tester.pumpAndSettle();

    final lastRow = find.byKey(const ValueKey('group-23'));
    expect(lastRow, findsOneWidget);
    expect(tester.getBottomLeft(lastRow).dy, lessThanOrEqualTo(800 - 48));
  });

  testWidgets(
    'searching a parent group reveals its whole subtree; searching a child '
    'shows only the child',
    (tester) async {
      // demographics > age, plus an unrelated root "other".
      final groups = [
        _group('demographics'),
        _group('age', parentGroupId: 'demographics'),
        _group('other'),
      ];

      await tester.pumpWidget(
        _harness(groups: groups, entries: const [], memberGroups: const []),
      );
      await tester.pumpAndSettle();

      // Scope to row labels so the search field's own text isn't matched.
      Finder rowLabel(String name) => find.descendant(
        of: find.byType(PrismListRow),
        matching: find.text(name),
      );

      // No query: all three render.
      expect(find.byType(PrismListRow), findsNWidgets(3));

      // Search the parent name — the subtree (parent + child) appears, the
      // unrelated root drops out.
      await tester.enterText(find.byType(PrismTextField), 'demographics');
      await tester.pumpAndSettle();
      expect(rowLabel('demographics'), findsOneWidget);
      expect(rowLabel('age'), findsOneWidget);
      expect(rowLabel('other'), findsNothing);

      // Search the child name — only the child shows; its non-matching parent
      // is filtered out.
      await tester.enterText(find.byType(PrismTextField), 'age');
      await tester.pumpAndSettle();
      expect(rowLabel('age'), findsOneWidget);
      expect(rowLabel('demographics'), findsNothing);
      expect(rowLabel('other'), findsNothing);
    },
  );

  testWidgets(
    'two matches in different subtrees both render flush-left (a hidden '
    'sibling subtree does not over-indent the deeper match)',
    (tester) async {
      // A > blue, and A > c > "navy blue". Searching "blue" matches "blue" and
      // "navy blue" but neither "a" nor "c". The two matches live in different
      // subtrees, so both should render at depth 0.
      final groups = [
        _group('a'),
        _group('blue', parentGroupId: 'a'),
        _group('c', parentGroupId: 'a'),
        _group('navy blue', parentGroupId: 'c'),
      ];

      await tester.pumpWidget(
        _harness(groups: groups, entries: const [], memberGroups: const []),
      );
      await tester.pumpAndSettle();

      double rowLeftPad(String name) => tester
          .widget<PrismListRow>(
            find.ancestor(
              of: find.text(name),
              matching: find.byType(PrismListRow),
            ),
          )
          .padding
          .left;

      await tester.enterText(find.byType(PrismTextField), 'blue');
      await tester.pumpAndSettle();

      // Only the two matches render, both flush-left (depth 0 → 16px).
      expect(find.byType(PrismListRow), findsNWidgets(2));
      expect(rowLeftPad('blue'), 16);
      expect(rowLeftPad('navy blue'), 16);
    },
  );
}
