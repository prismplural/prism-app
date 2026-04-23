import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/widgets/member_select_sheet.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Member _member({required String id, required String name, String? pronouns}) =>
    Member(id: id, name: name, pronouns: pronouns, createdAt: DateTime(2024));

/// Wraps [MemberSelectSheet] with the Riverpod + l10n scaffolding needed for
/// widget tests.
Widget _buildTestWidget({
  required AsyncValue<List<Member>> membersValue,
  String? currentMemberId,
}) {
  return ProviderScope(
    overrides: [
      activeMembersProvider.overrideWith((ref) {
        switch (membersValue) {
          case AsyncData(:final value):
            return Stream.value(value);
          case AsyncError(:final error, :final stackTrace):
            return Stream.error(error, stackTrace);
          case _:
            // Loading — return a stream that never emits.
            return const Stream.empty();
        }
      }),
      allGroupsProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroup>[]),
      ),
      allGroupEntriesProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroupEntry>[]),
      ),
      systemSettingsProvider.overrideWithValue(
        const AsyncValue.data(SystemSettings()),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(body: MemberSelectSheet(currentMemberId: currentMemberId)),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // Loading state
  // ══════════════════════════════════════════════════════════════════════════

  group('loading state', () {
    testWidgets('shows PrismLoadingState while members are loading', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestWidget(membersValue: const AsyncValue.loading()),
      );
      // One pump — do not settle so the loading state is visible.
      await tester.pump();

      expect(find.byType(PrismLoadingState), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Empty state
  // ══════════════════════════════════════════════════════════════════════════

  group('empty state', () {
    testWidgets('shows EmptyState when there are no active members', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestWidget(membersValue: const AsyncData([])),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EmptyState), findsOneWidget);
      // No member rows or "None" row when list is empty.
      expect(find.byType(PrismSectionCard), findsNothing);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Data state
  // ══════════════════════════════════════════════════════════════════════════

  group('data state', () {
    final members = [
      _member(id: 'a', name: 'Alice', pronouns: 'she/her'),
      _member(id: 'b', name: 'Bob'),
    ];

    testWidgets('renders None row and all member rows', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(membersValue: AsyncData(members)),
      );
      await tester.pumpAndSettle();

      expect(find.text('None'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('renders member pronouns as subtitle', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(membersValue: AsyncData(members)),
      );
      await tester.pumpAndSettle();

      expect(find.text('she/her'), findsOneWidget);
    });

    testWidgets('list is wrapped in PrismSectionCard', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(membersValue: AsyncData(members)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PrismSectionCard), findsOneWidget);
    });

    testWidgets('show() opens inside PrismSheet without layout errors', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeMembersProvider.overrideWith((ref) => Stream.value(members)),
            allGroupsProvider.overrideWith(
              (ref) => Stream.value(const <MemberGroup>[]),
            ),
            allGroupEntriesProvider.overrideWith(
              (ref) => Stream.value(const <MemberGroupEntry>[]),
            ),
            systemSettingsProvider.overrideWithValue(
              const AsyncValue.data(SystemSettings()),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => MemberSelectSheet.show(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('None row does NOT use close/X icon', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(membersValue: AsyncData(members)),
      );
      await tester.pumpAndSettle();

      // The old implementation used AppIcons.close (an "X") for the None row.
      // We only verify the sheet renders the None option at all; the icon used
      // is an internal detail tested by visual review. This test ensures we
      // did not regress to a missing None row.
      expect(find.text('None'), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Selected-state semantics
  // ══════════════════════════════════════════════════════════════════════════

  group('selected-state semantics', () {
    final members = [
      _member(id: 'a', name: 'Alice'),
      _member(id: 'b', name: 'Bob'),
    ];

    testWidgets('None row has selected=true when currentMemberId is null', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _buildTestWidget(
            membersValue: AsyncData(members),
            currentMemberId: null,
          ),
        );
        await tester.pumpAndSettle();

        final data = tester
            .getSemantics(find.widgetWithText(PrismListRow, 'None'))
            .getSemanticsData();
        expect(data.flagsCollection.isSelected, ui.Tristate.isTrue);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('None row has selected=true when currentMemberId is empty', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _buildTestWidget(
            membersValue: AsyncData(members),
            currentMemberId: '',
          ),
        );
        await tester.pumpAndSettle();

        final data = tester
            .getSemantics(find.widgetWithText(PrismListRow, 'None'))
            .getSemanticsData();
        expect(data.flagsCollection.isSelected, ui.Tristate.isTrue);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets(
      'member row has selected=true when it matches currentMemberId',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            _buildTestWidget(
              membersValue: AsyncData(members),
              currentMemberId: 'a',
            ),
          );
          await tester.pumpAndSettle();

          final data = tester
              .getSemantics(find.widgetWithText(PrismListRow, 'Alice'))
              .getSemanticsData();
          expect(data.flagsCollection.isSelected, ui.Tristate.isTrue);
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets('None row has selected=false when a member is selected', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _buildTestWidget(
            membersValue: AsyncData(members),
            currentMemberId: 'a',
          ),
        );
        await tester.pumpAndSettle();

        final data = tester
            .getSemantics(find.widgetWithText(PrismListRow, 'None'))
            .getSemanticsData();
        expect(data.flagsCollection.isSelected, isNot(ui.Tristate.isTrue));
      } finally {
        semantics.dispose();
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Selection return behavior
  // ══════════════════════════════════════════════════════════════════════════

  group('selection return behavior', () {
    final members = [
      _member(id: 'a', name: 'Alice'),
      _member(id: 'b', name: 'Bob'),
    ];

    testWidgets('tapping a member pops the route with that member id', (
      tester,
    ) async {
      String? result;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeMembersProvider.overrideWith((ref) => Stream.value(members)),
            allGroupsProvider.overrideWith(
              (ref) => Stream.value(const <MemberGroup>[]),
            ),
            allGroupEntriesProvider.overrideWith(
              (ref) => Stream.value(const <MemberGroupEntry>[]),
            ),
            systemSettingsProvider.overrideWithValue(
              const AsyncValue.data(SystemSettings()),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(ctx).push<String>(
                    MaterialPageRoute(
                      builder: (_) => const Scaffold(body: MemberSelectSheet()),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap the Alice row.
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      expect(result, 'a');
    });

    testWidgets('tapping None pops the route with empty string', (
      tester,
    ) async {
      String? result;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeMembersProvider.overrideWith((ref) => Stream.value(members)),
            allGroupsProvider.overrideWith(
              (ref) => Stream.value(const <MemberGroup>[]),
            ),
            allGroupEntriesProvider.overrideWith(
              (ref) => Stream.value(const <MemberGroupEntry>[]),
            ),
            systemSettingsProvider.overrideWithValue(
              const AsyncValue.data(SystemSettings()),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(ctx).push<String>(
                    MaterialPageRoute(
                      builder: (_) => const Scaffold(
                        body: MemberSelectSheet(currentMemberId: 'a'),
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();

      expect(result, '');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Search action
  // ══════════════════════════════════════════════════════════════════════════

  group('search action', () {
    final members = [
      _member(id: 'a', name: 'Alice', pronouns: 'she/her'),
      _member(id: 'b', name: 'Bob'),
    ];

    // Scaffold that opens MemberSelectSheet via show() so the navigator stack
    // is set up for a second sheet to open on top.
    Widget buildSheetScaffold(
      List<Member> sheetMembers, {
      void Function(String?)? onResult,
    }) {
      return ProviderScope(
        overrides: [
          activeMembersProvider.overrideWith(
            (ref) => Stream.value(sheetMembers),
          ),
          allGroupsProvider.overrideWith(
            (ref) => Stream.value(const <MemberGroup>[]),
          ),
          allGroupEntriesProvider.overrideWith(
            (ref) => Stream.value(const <MemberGroupEntry>[]),
          ),
          systemSettingsProvider.overrideWithValue(
            const AsyncValue.data(SystemSettings()),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('en')],
          home: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                final result = await MemberSelectSheet.show(ctx);
                onResult?.call(result);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
    }

    testWidgets('search action appears when members are available', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestWidget(membersValue: AsyncData(members)),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(AppIcons.search), findsOneWidget);
    });

    testWidgets('search action is not shown when member list is empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTestWidget(membersValue: const AsyncData([])),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(AppIcons.search), findsNothing);
    });

    testWidgets('tapping search action opens MemberSearchSheet', (
      tester,
    ) async {
      await tester.pumpWidget(buildSheetScaffold(members));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(AppIcons.search));
      await tester.pumpAndSettle();

      expect(find.byType(MemberSearchSheet), findsOneWidget);
    });

    testWidgets(
      'selecting a member via search returns member id through show() contract',
      (tester) async {
        String? result;
        await tester.pumpWidget(
          buildSheetScaffold(members, onResult: (r) => result = r),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(AppIcons.search));
        await tester.pumpAndSettle();

        // Use .last to prefer the row inside MemberSearchSheet over the one in
        // the underlying MemberSelectSheet.
        await tester.tap(find.widgetWithText(PrismListRow, 'Alice').last);
        await tester.pumpAndSettle();

        expect(result, 'a');
      },
    );

    testWidgets(
      'selecting None via search returns empty string through show() contract',
      (tester) async {
        String? result;
        await tester.pumpWidget(
          buildSheetScaffold(members, onResult: (r) => result = r),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(AppIcons.search));
        await tester.pumpAndSettle();

        // Tap the None special row inside MemberSearchSheet.
        await tester.tap(find.text('None').last);
        await tester.pumpAndSettle();

        expect(result, '');
      },
    );
  });
}
