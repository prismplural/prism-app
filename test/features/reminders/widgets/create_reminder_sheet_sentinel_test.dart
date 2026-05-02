import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/reminder.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/reminders/widgets/create_reminder_sheet.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Member _member({required String id, required String name}) =>
    Member(id: id, name: name, createdAt: DateTime(2024));

/// An onFrontChange reminder so the member-target picker renders. The
/// scheduled-trigger UI hides the member section entirely; only front-change
/// reminders surface the picker we want to test.
Reminder _editingFrontChangeReminder() => Reminder(
      id: 'r1',
      name: 'Test',
      message: '',
      trigger: ReminderTrigger.onFrontChange,
      delayHours: 0,
      createdAt: DateTime(2024, 1, 1),
      modifiedAt: DateTime(2024, 1, 1),
    );

Widget _buildTestWidget(List<Member> members) {
  return ProviderScope(
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
      home: Scaffold(
        body: CreateReminderSheet(editing: _editingFrontChangeReminder()),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // The reminder sheet is a non-fronting picker (front-change reminder
  // targets); the Unknown sentinel must never appear in its candidate list.
  // We assert it's filtered out by driving the search sheet open and checking
  // the rendered candidates.
  testWidgets(
    'Unknown sentinel is filtered out of the front-change reminder picker',
    (tester) async {
      final members = [
        _member(id: 'a', name: 'Alice'),
        Member(
          id: unknownSentinelMemberId,
          name: 'Unknown',
          createdAt: DateTime(2024),
        ),
        _member(id: 'b', name: 'Bob'),
      ];

      await tester.pumpWidget(_buildTestWidget(members));
      await tester.pumpAndSettle();

      // The member target row shows on the create-reminder sheet for
      // front-change triggers; tap it to open the search sheet which
      // renders the candidate list. The placeholder copy is "Any front
      // change" until a target is set.
      final pickerRow = find.text('Any front change').last;
      expect(pickerRow, findsOneWidget);
      await tester.tap(pickerRow);
      await tester.pumpAndSettle();

      // Search sheet now open. Sentinel must not appear in the list — even
      // though it was emitted by the upstream activeMembersProvider stream.
      expect(find.byType(MemberSearchSheet), findsOneWidget);
      expect(find.text('Alice'), findsAtLeastNWidgets(1));
      expect(find.text('Bob'), findsAtLeastNWidgets(1));
      expect(find.text('Unknown'), findsNothing);
    },
  );
}
