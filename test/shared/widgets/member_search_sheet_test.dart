import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

Member _member({required String id, required String name, String? pronouns}) =>
    Member(id: id, name: name, pronouns: pronouns, createdAt: DateTime(2024));

/// Wraps [MemberSearchSheet] with the minimal l10n scaffold for widget tests.
Widget _buildSheet({
  List<Member> members = const [],
  String termPlural = 'members',
  List<MemberSearchGroup> groups = const [],
  List<MemberSearchSpecialRow> specialRows = const [],
  bool multiSelect = false,
  Set<String> initialSelected = const {},
}) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: MemberSearchSheet(
          members: members,
          termPlural: termPlural,
          groups: groups,
          specialRows: specialRows,
          multiSelect: multiSelect,
          initialSelected: initialSelected,
        ),
      ),
    ),
  );
}

/// Opens [MemberSearchSheet.showSingle] from a button and returns a ref to the
/// future result container. Caller should pump the Open button tap after this.
Widget _buildSingleShowWidget({
  required List<Member> members,
  List<MemberSearchGroup> groups = const [],
  List<MemberSearchSpecialRow> specialRows = const [],
  void Function(MemberSearchSingleResult)? onResult,
}) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              final result = await MemberSearchSheet.showSingle(
                ctx,
                members: members,
                termPlural: 'members',
                groups: groups,
                specialRows: specialRows,
              );
              onResult?.call(result);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

Widget _buildMultiShowWidget({
  required List<Member> members,
  void Function(Set<String>?)? onResult,
}) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              final result = await MemberSearchSheet.showMulti(
                ctx,
                members: members,
                termPlural: 'members',
              );
              onResult?.call(result);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  final members = [
    _member(id: 'a', name: 'Alice', pronouns: 'she/her'),
    _member(id: 'b', name: 'Bob'),
    _member(id: 'c', name: 'Carol', pronouns: 'they/them'),
  ];

  // ══════════════════════════════════════════════════════════════════════════
  // Default list display
  // ══════════════════════════════════════════════════════════════════════════

  group('default list display', () {
    testWidgets('shows all members by default', (tester) async {
      await tester.pumpWidget(_buildSheet(members: members));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Carol'), findsOneWidget);
    });

    testWidgets('shows "All members" chip selected by default', (tester) async {
      await tester.pumpWidget(_buildSheet(members: members));
      await tester.pumpAndSettle();

      expect(find.text('All members'), findsOneWidget);
    });

    testWidgets('preserves incoming member order when query is empty', (
      tester,
    ) async {
      final orderedMembers = [
        _member(id: 'c', name: 'Carol'),
        _member(id: 'a', name: 'Alice'),
        _member(id: 'b', name: 'Bob'),
      ];

      await tester.pumpWidget(_buildSheet(members: orderedMembers));
      await tester.pumpAndSettle();

      final carolY = tester.getTopLeft(find.byKey(const ValueKey('c'))).dy;
      final aliceY = tester.getTopLeft(find.byKey(const ValueKey('a'))).dy;
      final bobY = tester.getTopLeft(find.byKey(const ValueKey('b'))).dy;

      expect(carolY, lessThan(aliceY));
      expect(aliceY, lessThan(bobY));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Group chip filtering
  // ══════════════════════════════════════════════════════════════════════════

  group('group chip filtering', () {
    final groups = [
      MemberSearchGroup(id: 'g1', name: 'Front Team', memberIds: {'a', 'b'}),
    ];

    testWidgets('group chip narrows visible members', (tester) async {
      await tester.pumpWidget(_buildSheet(members: members, groups: groups));
      await tester.pumpAndSettle();

      // Tap the group chip
      await tester.tap(find.text('Front Team'));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      // Carol is not in the group
      expect(find.text('Carol'), findsNothing);
    });

    testWidgets('text search filters within selected group', (tester) async {
      await tester.pumpWidget(_buildSheet(members: members, groups: groups));
      await tester.pumpAndSettle();

      // Select the group
      await tester.tap(find.text('Front Team'));
      await tester.pumpAndSettle();

      // Type in the search field
      await tester.enterText(find.byType(TextField), 'ali');
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      // Bob is in the group but doesn't match "ali"
      expect(find.text('Bob'), findsNothing);
      // Carol is not in the group at all
      expect(find.text('Carol'), findsNothing);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Single-select result contract
  // ══════════════════════════════════════════════════════════════════════════

  group('single-select result contract', () {
    testWidgets('selected(memberId) result when member is tapped', (
      tester,
    ) async {
      MemberSearchSingleResult? result;

      await tester.pumpWidget(
        _buildSingleShowWidget(members: members, onResult: (r) => result = r),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      expect(result, isA<MemberSearchResultSelected>());
      expect((result! as MemberSearchResultSelected).memberId, 'a');
    });

    testWidgets('dismissed result when sheet is closed via X button', (
      tester,
    ) async {
      MemberSearchSingleResult? result;

      await tester.pumpWidget(
        _buildSingleShowWidget(members: members, onResult: (r) => result = r),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap the close (X) icon button
      await tester.tap(find.byIcon(AppIcons.close));
      await tester.pumpAndSettle();

      expect(result, isA<MemberSearchResultDismissed>());
    });

    testWidgets('cleared result from caller-provided clear row', (
      tester,
    ) async {
      MemberSearchSingleResult? result;

      await tester.pumpWidget(
        _buildSingleShowWidget(
          members: members,
          specialRows: [
            MemberSearchSpecialRow(
              rowKey: 'clear',
              title: 'None',
              result: const MemberSearchResultCleared(),
            ),
          ],
          onResult: (r) => result = r,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();

      expect(result, isA<MemberSearchResultCleared>());
    });

    testWidgets('unknown result from caller-provided unknown row', (
      tester,
    ) async {
      MemberSearchSingleResult? result;

      await tester.pumpWidget(
        _buildSingleShowWidget(
          members: members,
          specialRows: [
            MemberSearchSpecialRow(
              rowKey: 'unknown',
              title: 'Unknown',
              result: const MemberSearchResultUnknown(),
            ),
          ],
          onResult: (r) => result = r,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Unknown'));
      await tester.pumpAndSettle();

      expect(result, isA<MemberSearchResultUnknown>());
    });

    testWidgets('returns immediately on member tap (single-select)', (
      tester,
    ) async {
      MemberSearchSingleResult? result;

      await tester.pumpWidget(
        _buildSingleShowWidget(members: members, onResult: (r) => result = r),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bob'));
      await tester.pumpAndSettle();

      // Sheet should have closed and result populated
      expect(result, isA<MemberSearchResultSelected>());
      expect((result! as MemberSearchResultSelected).memberId, 'b');
      // Sheet content should no longer be visible
      expect(find.text('Bob'), findsNothing);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Multi-select
  // ══════════════════════════════════════════════════════════════════════════

  group('multi-select', () {
    testWidgets('dismiss returns null', (tester) async {
      bool resultCalled = false;
      Set<String>? result = {'sentinel'};

      await tester.pumpWidget(
        _buildMultiShowWidget(
          members: members,
          onResult: (r) {
            resultCalled = true;
            result = r;
          },
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap the close button
      await tester.tap(find.byIcon(AppIcons.close));
      await tester.pumpAndSettle();

      expect(resultCalled, isTrue);
      expect(result, isNull);
    });

    testWidgets('confirm returns set of selected IDs', (tester) async {
      Set<String>? result;

      await tester.pumpWidget(
        _buildMultiShowWidget(members: members, onResult: (r) => result = r),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Select Alice and Carol
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Carol'));
      await tester.pumpAndSettle();

      // Confirm — the button label is "Done · 2"
      await tester.tap(find.textContaining('Done'));
      await tester.pumpAndSettle();

      expect(result, containsAll(['a', 'c']));
      expect(result!.length, 2);
    });

    testWidgets('Done button shows live count', (tester) async {
      await tester.pumpWidget(_buildSheet(members: members, multiSelect: true));
      await tester.pumpAndSettle();

      // Initially 0 selected
      expect(find.text('Done · 0'), findsOneWidget);

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      expect(find.text('Done · 1'), findsOneWidget);

      await tester.tap(find.text('Bob'));
      await tester.pumpAndSettle();
      expect(find.text('Done · 2'), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Accessibility
  // ══════════════════════════════════════════════════════════════════════════

  group('accessibility', () {
    testWidgets('search field is focused on open', (tester) async {
      await tester.pumpWidget(_buildSheet(members: members));
      await tester.pumpAndSettle();

      // autofocus: true causes the search field to receive primary focus.
      // Verify that the focus manager has a primary focused node after settle.
      final focused = tester.binding.focusManager.primaryFocus;
      expect(focused, isNotNull);
    });

    testWidgets('"All members" chip exposes selected semantics', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSheet(members: members));
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(find.text('All members'));
      expect(semantics.hasFlag(SemanticsFlag.isSelected), isTrue);
    });

    testWidgets('unselected group chip does not expose selected semantics', (
      tester,
    ) async {
      final groups = [
        MemberSearchGroup(id: 'g1', name: 'Front Team', memberIds: {'a'}),
      ];
      await tester.pumpWidget(_buildSheet(members: members, groups: groups));
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(find.text('Front Team'));
      expect(semantics.hasFlag(SemanticsFlag.isSelected), isFalse);
    });

    testWidgets(
      'selected member row exposes selected semantics in multi-select',
      (tester) async {
        await tester.pumpWidget(
          _buildSheet(members: members, multiSelect: true),
        );
        await tester.pumpAndSettle();

        // Select Alice
        await tester.tap(find.text('Alice'));
        await tester.pumpAndSettle();

        final semantics = tester.getSemantics(find.text('Alice'));
        expect(semantics.hasFlag(SemanticsFlag.isSelected), isTrue);
      },
    );

    testWidgets(
      'unselected member row has isSelected = false in multi-select',
      (tester) async {
        await tester.pumpWidget(
          _buildSheet(members: members, multiSelect: true),
        );
        await tester.pumpAndSettle();

        final semantics = tester.getSemantics(find.text('Bob'));
        expect(semantics.hasFlag(SemanticsFlag.isSelected), isFalse);
      },
    );

    testWidgets('empty-state icon is excluded from semantics', (tester) async {
      await tester.pumpWidget(
        _buildSheet(
          // No members — empty state shows
          members: [],
        ),
      );
      await tester.pumpAndSettle();

      // The decorative icon inside EmptyState is wrapped with ExcludeSemantics.
      expect(
        find.descendant(
          of: find.byType(EmptyState),
          matching: find.byType(ExcludeSemantics),
        ),
        findsAtLeastNWidgets(1),
      );
    });
  });
}
