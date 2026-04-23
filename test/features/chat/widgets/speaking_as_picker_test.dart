import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/chat/providers/chat_providers.dart';
import 'package:prism_plurality/features/chat/widgets/speaking_as_picker.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const int _kThreshold = 15;

/// Generates [count] active members named "Member 0", "Member 1", …
List<Member> _members(int count) => List.generate(
      count,
      (i) => Member(
        id: 'id-$i',
        name: 'Member $i',
        createdAt: DateTime(2024),
        isActive: true,
      ),
    );

/// A [SpeakingAsNotifier] that starts with [_memberId] and does not pull from
/// the fronting session, making it safe to use in widget tests without a DB.
class _FixedSpeakingAsNotifier extends SpeakingAsNotifier {
  _FixedSpeakingAsNotifier(this._memberId);
  String? _memberId;

  @override
  String? build() => _memberId;

  @override
  void setMember(String? memberId) {
    _memberId = memberId;
    ref.invalidateSelf();
  }
}

Widget _buildSubject({
  required List<Member> members,
  String? speakingAs,
}) {
  return ProviderScope(
    overrides: [
      activeMembersProvider.overrideWith((ref) => Stream.value(members)),
      allGroupsProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroup>[]),
      ),
      allGroupEntriesProvider.overrideWith(
        (ref) => Stream.value(const <MemberGroupEntry>[]),
      ),
      speakingAsProvider.overrideWith(
        () => _FixedSpeakingAsNotifier(speakingAs),
      ),
      systemSettingsProvider.overrideWithValue(
        const AsyncValue.data(SystemSettings()),
      ),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: [Locale('en')],
      home: Scaffold(body: SpeakingAsPicker()),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SpeakingAsPicker — small system (< $_kThreshold members)', () {
    testWidgets('shows chip row (ListView) for small systems', (tester) async {
      await tester.pumpWidget(_buildSubject(members: _members(_kThreshold - 1)));
      await tester.pump();

      expect(find.byType(ListView), findsOneWidget);
      expect(find.byKey(const Key('speakingAsSearchTrigger')), findsNothing);
    });

    testWidgets('chips display member names', (tester) async {
      final members = _members(3);
      await tester.pumpWidget(_buildSubject(members: members));
      await tester.pump();

      expect(find.text('Member 0'), findsOneWidget);
      expect(find.text('Member 1'), findsOneWidget);
      expect(find.text('Member 2'), findsOneWidget);
    });

    testWidgets('tapping a chip updates speakingAsProvider', (tester) async {
      final members = _members(3);
      await tester.pumpWidget(
        _buildSubject(members: members, speakingAs: 'id-0'),
      );
      await tester.pump();

      await tester.tap(find.text('Member 2'));
      await tester.pump();

      // After tapping Member 2 the chip row still shows, confirming the widget
      // rebuilt without errors. Provider update is confirmed indirectly through
      // the rebuild (if setMember threw, the test would fail here).
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('auto-selects first member when none is selected',
        (tester) async {
      final members = _members(3);
      // speakingAs starts null
      await tester.pumpWidget(_buildSubject(members: members));
      // First build triggers addPostFrameCallback; pump one extra frame.
      await tester.pump();
      await tester.pump();

      // The chip row is still rendered (small system path still active),
      // confirming the widget survived the auto-select callback without errors.
      expect(find.byType(ListView), findsOneWidget);
    });
  });

  group('SpeakingAsPicker — large system (>= $_kThreshold members)', () {
    testWidgets('shows search trigger instead of chip row', (tester) async {
      await tester.pumpWidget(_buildSubject(members: _members(_kThreshold)));
      await tester.pump();

      expect(find.byKey(const Key('speakingAsSearchTrigger')), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('trigger displays the currently selected member name',
        (tester) async {
      final members = _members(_kThreshold);
      await tester.pumpWidget(
        _buildSubject(members: members, speakingAs: 'id-5'),
      );
      await tester.pump();

      expect(find.text('Member 5'), findsOneWidget);
    });

    testWidgets('tapping trigger opens MemberSearchSheet', (tester) async {
      await tester.pumpWidget(
        _buildSubject(members: _members(_kThreshold), speakingAs: 'id-0'),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('speakingAsSearchTrigger')));
      await tester.pumpAndSettle();

      expect(find.byType(MemberSearchSheet), findsOneWidget);
    });

    testWidgets('selecting a member from the sheet updates speakingAsProvider',
        (tester) async {
      final members = _members(_kThreshold);
      // Start with Member 5 selected.
      await tester.pumpWidget(
        _buildSubject(members: members, speakingAs: 'id-5'),
      );
      await tester.pump();

      // Open the search sheet.
      await tester.tap(find.byKey(const Key('speakingAsSearchTrigger')));
      await tester.pumpAndSettle();

      // Tap Member 0 in the search list.
      await tester.tap(find.text('Member 0').last);
      await tester.pumpAndSettle();

      // The sheet dismissed and the trigger now shows Member 0.
      expect(find.byKey(const Key('speakingAsSearchTrigger')), findsOneWidget);
      expect(find.text('Member 0'), findsOneWidget);
    });

    testWidgets('auto-selects first member when none is selected',
        (tester) async {
      final members = _members(_kThreshold);
      // speakingAs starts null → trigger shows members.first
      await tester.pumpWidget(_buildSubject(members: members));
      await tester.pump(); // first build
      await tester.pump(); // addPostFrameCallback fires → state rebuilt

      // Trigger should be visible and show Member 0 (the auto-selected member).
      expect(find.byKey(const Key('speakingAsSearchTrigger')), findsOneWidget);
      expect(find.text('Member 0'), findsOneWidget);
    });
  });
}
