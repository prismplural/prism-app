// Tests for WakeUpSleepSheet's member-picker section.
//
// Covers the four required scenarios:
//   1. Top suggested members remain available as quick-tap avatars.
//   2. Tapping the "Others…" path opens the shared single-select sheet.
//   3. Selecting from the shared sheet updates the chosen member label.
//   4. Dismissing the shared sheet leaves the selection unchanged.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/sleep_providers.dart';
import 'package:prism_plurality/features/fronting/widgets/wake_up_sleep_sheet.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

Member _member(String id, String name) =>
    Member(id: id, name: name, createdAt: DateTime(2024));

FrontingSession _sleepSession() => FrontingSession(
  id: 'sleep-1',
  startTime: DateTime.now().subtract(const Duration(hours: 7)),
  sessionType: SessionType.sleep,
);

// Five members so that 4 fill the top row and 1 appears behind "Others…".
// With empty morningCounts and identical displayOrder, sorted by id ascending:
//   alice, bob, charlie, diana → top row
//   eve                        → Others
List<Member> _fiveMembers() => [
  _member('alice', 'Alice'),
  _member('bob', 'Bob'),
  _member('charlie', 'Charlie'),
  _member('diana', 'Diana'),
  _member('eve', 'Eve'),
];

Widget _buildSubject({List<Member>? members}) {
  return ProviderScope(
    overrides: [
      activeMembersProvider.overrideWith(
        (ref) => Stream.value(members ?? _fiveMembers()),
      ),
      allGroupsProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroup>[]),
      ),
      allGroupEntriesProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroupEntry>[]),
      ),
      morningFrontingCountsProvider.overrideWith((ref) => Future.value({})),
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(body: WakeUpSleepSheet(session: _sleepSession())),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('WakeUpSleepSheet – member picker', () {
    // ── 1. Top quick choices ────────────────────────────────────────────────

    group('top member quick choices', () {
      testWidgets('top 4 members are rendered as named avatar tiles', (
        tester,
      ) async {
        await tester.pumpWidget(_buildSubject());
        await tester.pumpAndSettle();

        expect(find.text('Alice'), findsOneWidget);
        expect(find.text('Bob'), findsOneWidget);
        expect(find.text('Charlie'), findsOneWidget);
        expect(find.text('Diana'), findsOneWidget);
      });

      testWidgets('5th member is not shown directly in the top row', (
        tester,
      ) async {
        await tester.pumpWidget(_buildSubject());
        await tester.pumpAndSettle();

        // Eve is behind "Others…" – she must not appear as a named tile.
        expect(find.text('Eve'), findsNothing);
      });
    });

    // ── 2. Others path opens the shared sheet ───────────────────────────────

    group('others picker opens shared sheet', () {
      testWidgets('tapping Others opens MemberSearchSheet', (tester) async {
        await tester.pumpWidget(_buildSubject());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Others...'));
        await tester.pumpAndSettle();

        expect(find.byType(MemberSearchSheet), findsOneWidget);
      });
    });

    // ── 3. Selecting from the shared sheet updates the chosen member ────────

    group('selection from shared sheet', () {
      testWidgets('selecting a member dismisses the sheet and updates label', (
        tester,
      ) async {
        await tester.pumpWidget(_buildSubject());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Others...'));
        await tester.pumpAndSettle();

        // Eve is the only member shown in the search sheet.
        await tester.tap(find.text('Eve'));
        await tester.pumpAndSettle();

        // MemberSearchSheet is dismissed.
        expect(find.byType(MemberSearchSheet), findsNothing);

        // The "Others…" button now reflects Eve's name.
        expect(find.text('Eve'), findsOneWidget);
        expect(find.text('Others...'), findsNothing);
      });
    });

    // ── 4. Dismissing leaves the selection unchanged ─────────────────────────

    group('dismissing the shared sheet', () {
      testWidgets('cancel leaves the selection unchanged', (tester) async {
        await tester.pumpWidget(_buildSubject());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Others...'));
        await tester.pumpAndSettle();

        // Close via the X button in MemberSearchSheet's top bar.
        await tester.tap(find.bySemanticsLabel('Close'));
        await tester.pumpAndSettle();

        expect(find.byType(MemberSearchSheet), findsNothing);
        // Label reverts to the default.
        expect(find.text('Others...'), findsOneWidget);
      });
    });
  });
}
