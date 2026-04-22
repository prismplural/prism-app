// Tests for EditFrontSessionScreen member pickers after migration to
// MemberSearchSheet.
//
// Verified behaviour:
//   1. Fronter selection path opens the shared single-select MemberSearchSheet.
//   2. Co-fronter selection path opens the shared multi-select MemberSearchSheet.
//   3. Existing fronter is shown in the picker row before the sheet opens.
//   4. Existing co-fronters are pre-selected (reflected in "Done · N") when
//      the multi-select sheet opens.
//   5. Selecting a new fronter via the sheet updates the displayed fronter.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/views/edit_front_session_screen.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

Member _member({required String id, required String name}) => Member(
      id: id,
      name: name,
      emoji: '😀',
      createdAt: DateTime(2024),
    );

FrontingSession _session({
  String id = 'test-session',
  String? memberId,
  List<String> coFronterIds = const [],
}) =>
    FrontingSession(
      id: id,
      startTime: DateTime(2024, 1, 1, 10),
      memberId: memberId,
      coFronterIds: coFronterIds,
    );

/// Builds EditFrontSessionScreen with the given session and members, all
/// real-provider reads mocked out so no database is hit.
Widget _buildSubject({
  required FrontingSession session,
  required List<Member> members,
}) {
  return ProviderScope(
    overrides: [
      sessionByIdProvider(session.id).overrideWith(
        (ref) => Stream.value(session),
      ),
      activeMembersProvider.overrideWith((ref) => Stream.value(members)),
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: EditFrontSessionScreen(sessionId: session.id),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // Fronter picker
  // ══════════════════════════════════════════════════════════════════════════

  group('fronter picker', () {
    testWidgets('tapping the fronter search icon opens MemberSearchSheet',
        (tester) async {
      final members = [
        _member(id: 'alice', name: 'Alice'),
        _member(id: 'bob', name: 'Bob'),
      ];
      await tester.pumpWidget(
        _buildSubject(session: _session(), members: members),
      );
      await tester.pumpAndSettle();

      // The fronter search icon is the first search icon in the widget tree.
      final icons = find.byIcon(AppIcons.search);
      expect(icons, findsWidgets);

      await tester.tap(icons.first);
      await tester.pumpAndSettle();

      expect(find.byType(MemberSearchSheet), findsOneWidget);
    });

    testWidgets('existing fronter name is shown before opening the sheet',
        (tester) async {
      final members = [
        _member(id: 'alice', name: 'Alice'),
        _member(id: 'bob', name: 'Bob'),
      ];
      await tester.pumpWidget(
        _buildSubject(
          session: _session(memberId: 'alice'),
          members: members,
        ),
      );
      await tester.pumpAndSettle();

      // Alice's name should appear in the fronter picker row before the sheet
      // is opened (confirming existing selection is preserved in the UI).
      expect(find.text('Alice'), findsWidgets);
    });

    testWidgets(
        'selecting a member via the fronter sheet updates the displayed fronter',
        (tester) async {
      final members = [
        _member(id: 'alice', name: 'Alice'),
        _member(id: 'bob', name: 'Bob'),
      ];
      // Session starts with no fronter selected.
      await tester.pumpWidget(
        _buildSubject(session: _session(), members: members),
      );
      await tester.pumpAndSettle();

      // Open the fronter search sheet.
      await tester.tap(find.byIcon(AppIcons.search).first);
      await tester.pumpAndSettle();

      expect(find.byType(MemberSearchSheet), findsOneWidget);

      // Pick Alice in the sheet.
      await tester.tap(find.text('Alice').last);
      await tester.pumpAndSettle();

      // Sheet should have closed and Alice's name appears in the picker row.
      expect(find.byType(MemberSearchSheet), findsNothing);
      expect(find.text('Alice'), findsWidgets);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Co-fronter picker
  // ══════════════════════════════════════════════════════════════════════════

  group('co-fronter picker', () {
    testWidgets('tapping the co-fronter search icon opens MemberSearchSheet',
        (tester) async {
      final members = [
        _member(id: 'alice', name: 'Alice'),
        _member(id: 'bob', name: 'Bob'),
        _member(id: 'charlie', name: 'Charlie'),
      ];
      await tester.pumpWidget(
        _buildSubject(
          session: _session(memberId: 'alice'),
          members: members,
        ),
      );
      await tester.pumpAndSettle();

      // The co-fronter search icon is the last search icon in the widget tree.
      final icons = find.byIcon(AppIcons.search);
      expect(icons, findsWidgets);

      await tester.tap(icons.last);
      await tester.pumpAndSettle();

      expect(find.byType(MemberSearchSheet), findsOneWidget);
    });

    testWidgets(
        'existing co-fronters are pre-selected when the multi-select sheet opens',
        (tester) async {
      final members = [
        _member(id: 'alice', name: 'Alice'),
        _member(id: 'bob', name: 'Bob'),
        _member(id: 'charlie', name: 'Charlie'),
      ];
      // Session has Bob as a co-fronter.
      await tester.pumpWidget(
        _buildSubject(
          session: _session(memberId: 'alice', coFronterIds: ['bob']),
          members: members,
        ),
      );
      await tester.pumpAndSettle();

      // Open the co-fronter multi-select sheet.
      await tester.tap(find.byIcon(AppIcons.search).last);
      await tester.pumpAndSettle();

      expect(find.byType(MemberSearchSheet), findsOneWidget);

      // "Done · 1" indicates Bob is pre-selected.
      expect(find.textContaining('Done · 1'), findsOneWidget);
    });

    testWidgets(
        'confirming co-fronter selection updates the displayed co-fronters',
        (tester) async {
      final members = [
        _member(id: 'alice', name: 'Alice'),
        _member(id: 'bob', name: 'Bob'),
        _member(id: 'charlie', name: 'Charlie'),
      ];
      await tester.pumpWidget(
        _buildSubject(
          session: _session(memberId: 'alice'),
          members: members,
        ),
      );
      await tester.pumpAndSettle();

      // Open the co-fronter sheet.
      await tester.tap(find.byIcon(AppIcons.search).last);
      await tester.pumpAndSettle();

      // Select Charlie.
      await tester.tap(find.text('Charlie').last);
      await tester.pump();

      // Confirm via "Done · 1".
      await tester.tap(find.textContaining('Done'));
      await tester.pumpAndSettle();

      // Charlie should now appear as a selected co-fronter chip.
      expect(find.text('Charlie'), findsWidgets);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Save behavior
  // ══════════════════════════════════════════════════════════════════════════

  group('save behavior', () {
    testWidgets(
        'after picking a new fronter via the sheet the picker row reflects the new selection',
        (tester) async {
      final members = [
        _member(id: 'alice', name: 'Alice'),
        _member(id: 'bob', name: 'Bob'),
      ];
      // Session starts with Alice as fronter.
      await tester.pumpWidget(
        _buildSubject(
          session: _session(memberId: 'alice'),
          members: members,
        ),
      );
      await tester.pumpAndSettle();

      // Open fronter picker and select Bob.
      await tester.tap(find.byIcon(AppIcons.search).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bob').last);
      await tester.pumpAndSettle();

      // Bob is now shown in the fronter picker row, meaning _memberId was
      // updated and would be sent to _save() if the user taps the save button.
      expect(find.text('Bob'), findsWidgets);
    });

    testWidgets(
        'after updating co-fronters via the sheet the new set is reflected',
        (tester) async {
      final members = [
        _member(id: 'alice', name: 'Alice'),
        _member(id: 'bob', name: 'Bob'),
        _member(id: 'charlie', name: 'Charlie'),
      ];
      // Session starts with no co-fronters.
      await tester.pumpWidget(
        _buildSubject(
          session: _session(memberId: 'alice'),
          members: members,
        ),
      );
      await tester.pumpAndSettle();

      // Open co-fronter sheet, select Bob, confirm.
      await tester.tap(find.byIcon(AppIcons.search).last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bob').last);
      await tester.pump();

      await tester.tap(find.textContaining('Done'));
      await tester.pumpAndSettle();

      // Bob's chip is now shown, meaning _coFronterIds was updated.
      expect(find.text('Bob'), findsWidgets);
    });
  });
}
