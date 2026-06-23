import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/accent_legibility.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';

Member _member({
  required String id,
  required String name,
  String? pronouns,
  String? displayName,
}) => Member(
  id: id,
  name: name,
  pronouns: pronouns,
  displayName: displayName,
  createdAt: DateTime(2024),
);

/// Wraps [MemberSearchSheet] with the minimal l10n scaffold for widget tests.
Widget _buildSheet({
  List<Member> members = const [],
  String termPlural = 'members',
  List<MemberSearchGroup> groups = const [],
  List<MemberSearchSpecialRow> specialRows = const [],
  bool multiSelect = false,
  Set<String> initialSelected = const {},
  Set<String> fronterIds = const {},
  String? fronterSectionLabel,
  bool preferDisplayName = true,
}) {
  return ProviderScope(
    overrides: [
      memberNamePreferDisplayProvider.overrideWithValue(preferDisplayName),
    ],
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
          fronterIds: fronterIds,
          fronterSectionLabel: fronterSectionLabel,
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

void main() {
  final members = [
    _member(id: 'a', name: 'Alice', pronouns: 'she/her'),
    _member(id: 'b', name: 'Bob'),
    _member(id: 'c', name: 'Carol', pronouns: 'they/them'),
  ];
  Finder checkButton() => find.byWidgetPredicate(
    (widget) => widget is PrismGlassIconButton && widget.icon == AppIcons.check,
  );

  group('fronters on top', () {
    final roster = [
      _member(id: 'a', name: 'Alice'),
      _member(id: 'b', name: 'Bob'),
      _member(id: 'c', name: 'Carol'),
      _member(id: 'd', name: 'Dave'),
    ];

    testWidgets('floats current fronters above the rest', (tester) async {
      // Carol + Dave are fronting; they should appear above Alice + Bob even
      // though they come later in display order.
      await tester.pumpWidget(
        _buildSheet(members: roster, fronterIds: const {'c', 'd'}),
      );
      await tester.pumpAndSettle();

      final carolY = tester.getTopLeft(find.byKey(const ValueKey('c'))).dy;
      final daveY = tester.getTopLeft(find.byKey(const ValueKey('d'))).dy;
      final aliceY = tester.getTopLeft(find.byKey(const ValueKey('a'))).dy;
      final bobY = tester.getTopLeft(find.byKey(const ValueKey('b'))).dy;

      // Fronters above non-fronters.
      expect(carolY, lessThan(aliceY));
      expect(daveY, lessThan(aliceY));
      // Each group keeps display order (c before d; a before b).
      expect(carolY, lessThan(daveY));
      expect(aliceY, lessThan(bobY));
    });

    testWidgets('renders the section label when provided', (tester) async {
      await tester.pumpWidget(
        _buildSheet(
          members: roster,
          fronterIds: const {'c'},
          fronterSectionLabel: 'Fronting',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Fronting'), findsOneWidget);
    });

    testWidgets('no label/grouping when everyone is fronting', (tester) async {
      await tester.pumpWidget(
        _buildSheet(
          members: roster,
          fronterIds: const {'a', 'b', 'c', 'd'},
          fronterSectionLabel: 'Fronting',
        ),
      );
      await tester.pumpAndSettle();

      // Whole roster is one flat group — no boundary label.
      expect(find.text('Fronting'), findsNothing);
    });

    testWidgets('collapses to flat list while searching', (tester) async {
      await tester.pumpWidget(
        _buildSheet(
          members: roster,
          fronterIds: const {'c'},
          fronterSectionLabel: 'Fronting',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Fronting'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'a');
      await tester.pumpAndSettle();

      // Section boundary disappears mid-search.
      expect(find.text('Fronting'), findsNothing);
    });
  });

  group('default list display', () {
    testWidgets('shows all members by default', (tester) async {
      await tester.pumpWidget(_buildSheet(members: members));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Carol'), findsOneWidget);
    });

    testWidgets('does not show chip bar when no groups are provided', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSheet(members: members));
      await tester.pumpAndSettle();

      expect(find.text('All members'), findsNothing);
    });

    testWidgets(
      'shows "All members" chip selected by default when groups exist',
      (tester) async {
        await tester.pumpWidget(
          _buildSheet(
            members: members,
            groups: const [
              MemberSearchGroup(id: 'g1', name: 'Front Team', memberIds: {'a'}),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('All members'), findsOneWidget);
      },
    );

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

    testWidgets('shows distinct full name in member rows', (tester) async {
      await tester.pumpWidget(
        _buildSheet(
          preferDisplayName: false,
          members: [
            _member(
              id: 'reverie',
              name: 'Reverie',
              displayName: 'Reverie Loaf',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reverie'), findsOneWidget);
      expect(find.text('Reverie Loaf'), findsOneWidget);
    });

    testWidgets('hides full name subtitle when it only differs by case', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(
          preferDisplayName: false,
          members: [_member(id: 'alice', name: 'alice', displayName: 'Alice')],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('alice'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);
    });
  });

  group('group chip filtering', () {
    final groups = [
      const MemberSearchGroup(
        id: 'g1',
        name: 'Front Team',
        memberIds: {'a', 'b'},
        emoji: '🫂',
        colorHex: '#7A6E96',
      ),
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

    testWidgets('text search can match group names from all members', (
      tester,
    ) async {
      final groups = [
        const MemberSearchGroup(id: 'day', name: 'Day Crew', memberIds: {'a'}),
        const MemberSearchGroup(
          id: 'night',
          name: 'Night Crew',
          memberIds: {'b', 'c'},
        ),
      ];

      await tester.pumpWidget(_buildSheet(members: members, groups: groups));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'night crew');
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsNothing);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Carol'), findsOneWidget);
    });

    testWidgets('group-name search remains scoped to selected group', (
      tester,
    ) async {
      final groups = [
        const MemberSearchGroup(
          id: 'day',
          name: 'Day Crew',
          memberIds: {'a', 'b'},
        ),
        const MemberSearchGroup(
          id: 'night',
          name: 'Night Crew',
          memberIds: {'b', 'c'},
        ),
      ];

      await tester.pumpWidget(_buildSheet(members: members, groups: groups));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Day Crew'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'night crew');
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsNothing);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Carol'), findsNothing);
    });

    testWidgets('group chip shows avatar and tint color', (tester) async {
      await tester.pumpWidget(_buildSheet(members: members, groups: groups));
      await tester.pumpAndSettle();

      final chip = tester.widget<PrismChip>(
        find.widgetWithText(PrismChip, 'Front Team'),
      );
      expect(chip.avatar, isNotNull);
      expect(chip.tintColor, isNotNull);
    });

    testWidgets('group chip icon avatar keeps contrast with pastel colors', (
      tester,
    ) async {
      const pastelGroups = [
        MemberSearchGroup(
          id: 'g1',
          name: 'Pastel Team',
          memberIds: {'a'},
          colorHex: '#B9F7FF',
        ),
      ];

      await tester.pumpWidget(
        _buildSheet(members: members, groups: pastelGroups),
      );
      await tester.pumpAndSettle();

      final avatarDecoration = find
          .ancestor(
            of: find.byIcon(AppIcons.group),
            matching: find.byType(Container),
          )
          .evaluate()
          .map((element) => element.widget)
          .whereType<Container>()
          .map((container) => container.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((decoration) => decoration.shape == BoxShape.circle);
      final icon = tester.widget<Icon>(find.byIcon(AppIcons.group));

      expect(
        contrastRatio(icon.color!, avatarDecoration.color!),
        greaterThanOrEqualTo(prismMinimumTextContrast - 0.01),
      );
    });
  });

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

    testWidgets('modal presentation uses Prism full-screen top bar', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSingleShowWidget(members: members));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(PrismSheetTopBar), findsOneWidget);
    });

    testWidgets('cleared result from caller-provided clear row', (
      tester,
    ) async {
      MemberSearchSingleResult? result;

      await tester.pumpWidget(
        _buildSingleShowWidget(
          members: members,
          specialRows: [
            const MemberSearchSpecialRow(
              rowKey: 'clear',
              title: 'None',
              result: MemberSearchResultCleared(),
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
            const MemberSearchSpecialRow(
              rowKey: 'unknown',
              title: 'Unknown',
              result: MemberSearchResultUnknown(),
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

      // Confirm with the top-bar check button.
      await tester.tap(checkButton());
      await tester.pumpAndSettle();

      expect(result, containsAll(['a', 'c']));
      expect(result!.length, 2);
    });

    testWidgets('title shows live selected count and check state', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSheet(members: members, multiSelect: true));
      await tester.pumpAndSettle();

      expect(find.text('0 selected'), findsOneWidget);
      expect(
        tester.widget<PrismGlassIconButton>(checkButton()).onPressed,
        isNull,
      );

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(
        tester.widget<PrismGlassIconButton>(checkButton()).onPressed,
        isNotNull,
      );

      await tester.tap(find.text('Bob'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
    });
  });

  group('accessibility', () {
    testWidgets('search field is not focused on open', (tester) async {
      await tester.pumpWidget(_buildSheet(members: members));
      await tester.pumpAndSettle();

      final editableText = tester.widget<EditableText>(
        find.byType(EditableText),
      );
      expect(editableText.focusNode.hasFocus, isFalse);
    });

    testWidgets('"All members" chip exposes selected semantics', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSheet(
          members: members,
          groups: const [
            MemberSearchGroup(id: 'g1', name: 'Front Team', memberIds: {'a'}),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(find.text('All members'));
      expect(semantics.flagsCollection.isSelected, ui.Tristate.isTrue);
    });

    testWidgets('multi-select confirm button has an accessible name', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSheet(members: members, multiSelect: true));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Confirm selected members'), findsOneWidget);
      expect(find.bySemanticsLabel('Confirm selected members'), findsOneWidget);
    });

    testWidgets('unselected group chip does not expose selected semantics', (
      tester,
    ) async {
      final groups = [
        const MemberSearchGroup(id: 'g1', name: 'Front Team', memberIds: {'a'}),
      ];
      await tester.pumpWidget(_buildSheet(members: members, groups: groups));
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(find.text('Front Team'));
      expect(semantics.flagsCollection.isSelected, ui.Tristate.isFalse);
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
        expect(semantics.flagsCollection.isSelected, ui.Tristate.isTrue);
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
        expect(semantics.flagsCollection.isSelected, ui.Tristate.isFalse);
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
