// Tests for EditFrontSessionScreen member pickers after migration to
// MemberSearchSheet.
//
// Per per-member-sessions refactor (§3): each session has exactly one
// memberId; co-fronting is emergent overlap, not a multi-select on the
// session. The co-fronter picker UI was removed, so the co-fronter-picker
// test group was deleted with it.
//
// Verified behaviour:
//   1. Fronter selection path opens the shared single-select MemberSearchSheet.
//   2. Existing fronter is shown in the picker row before the sheet opens.
//   3. Selecting a new fronter via the sheet updates the displayed fronter.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/views/edit_front_session_screen.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

Member _member({required String id, required String name}) =>
    Member(id: id, name: name, emoji: '😀', createdAt: DateTime(2024));

FrontingSession _session({
  String id = 'test-session',
  String? memberId,
}) => FrontingSession(
  id: id,
  startTime: DateTime(2024, 1, 1, 10),
  memberId: memberId,
);

/// Builds EditFrontSessionScreen with the given session and members, all
/// real-provider reads mocked out so no database is hit.
Widget _buildSubject({
  required FrontingSession session,
  required List<Member> members,
}) {
  return ProviderScope(
    overrides: [
      sessionByIdProvider(
        session.id,
      ).overrideWith((ref) => Stream.value(session)),
      activeMembersProvider.overrideWith((ref) => Stream.value(members)),
      allGroupsProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroup>[]),
      ),
      allGroupEntriesProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroupEntry>[]),
      ),
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(body: EditFrontSessionScreen(sessionId: session.id)),
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
    testWidgets('tapping the fronter search icon opens MemberSearchSheet', (
      tester,
    ) async {
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

    testWidgets('existing fronter name is shown before opening the sheet', (
      tester,
    ) async {
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
      },
    );
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
      },
    );
  });
}
