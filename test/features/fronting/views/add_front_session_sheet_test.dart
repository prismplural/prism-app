import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/member_group_entry.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/views/add_front_session_sheet.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/selected_member_picker.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

Member _member({required String id, required String name}) =>
    Member(id: id, name: name, createdAt: DateTime(2024));

/// 13 members → exceeds the compact threshold (12) → compact picker + search.
List<Member> _bigMemberList() =>
    List.generate(13, (i) => _member(id: 'id$i', name: 'Member $i'));

/// Records `startFronting` calls so tests can assert on the multi-select
/// payload without hitting the real DB.
class _FakeFrontingNotifier extends FrontingNotifier {
  final List<List<String>> startFrontingCalls = [];

  @override
  Future<void> build() async {}

  @override
  Future<void> startFronting(
    List<String> memberIds, {
    FrontConfidence? confidence,
    String? notes,
    DateTime? startTime,
  }) async {
    startFrontingCalls.add(List<String>.from(memberIds));
  }
}

Widget _buildSheetTrigger({
  required List<Member> members,
  List<FrontingSession> activeSessions = const [],
  _FakeFrontingNotifier? fakeNotifier,
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
      activeSessionsProvider.overrideWith(
        (ref) => Stream.value(activeSessions),
      ),
      systemSettingsProvider.overrideWith(
        (ref) => Stream.value(const SystemSettings()),
      ),
      if (fakeNotifier != null)
        frontingNotifierProvider.overrideWith(() => fakeNotifier),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Builder(
        builder: (ctx) => Scaffold(
          body: ElevatedButton(
            onPressed: () => AddFrontSessionSheet.show(ctx),
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

/// Returns the save/confirm button on the add-front sheet (PrismGlassIconButton
/// with check icon). PrismSheetTopBar always renders a close + trailing pair,
/// so we filter by the icon, and by being inside [AddFrontSessionSheet] when
/// the search sheet (which also has a confirm-check) is open at the same time.
Finder _saveButton() => find.descendant(
  of: find.byType(AddFrontSessionSheet),
  matching: find.byWidgetPredicate(
    (w) => w is PrismGlassIconButton && w.icon == AppIcons.check,
  ),
);

/// Confirms a multi-select choice in the open [MemberSearchSheet] by tapping
/// its trailing check button. The search sheet only enables the check once at
/// least one row is selected.
Future<void> _confirmSearchSelection(WidgetTester tester) async {
  final confirm = find.descendant(
    of: find.byType(MemberSearchSheet),
    matching: find.byWidgetPredicate(
      (w) => w is PrismGlassIconButton && w.icon == AppIcons.check,
    ),
  );
  await tester.tap(confirm);
  await tester.pumpAndSettle();
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // Selected member picker (compact / large-system path)
  // ══════════════════════════════════════════════════════════════════════════

  group('selected member picker', () {
    testWidgets('start button has an accessible name', (tester) async {
      await tester.pumpWidget(_buildSheetTrigger(members: _bigMemberList()));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Start session'), findsOneWidget);
      expect(find.bySemanticsLabel('Start session'), findsOneWidget);
    });

    testWidgets(
      'large systems use the shared multi-select picker instead of raw rows',
      (tester) async {
        await tester.pumpWidget(_buildSheetTrigger(members: _bigMemberList()));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // The compact path uses [SelectedMultiMemberPicker] under a stable key
        // so other surfaces (e.g. tests, instrumentation) can find it.
        expect(find.byType(SelectedMultiMemberPicker), findsOneWidget);
        expect(
          find.byKey(const Key('addFrontSessionSelectedMemberPicker')),
          findsOneWidget,
        );
        // None of the candidate names should be eagerly rendered in the sheet
        // body — they live behind the search.
        expect(find.text('Member 12'), findsNothing);
      },
    );

    testWidgets(
      'large systems start with a Select button instead of a pre-rendered list',
      (tester) async {
        await tester.pumpWidget(_buildSheetTrigger(members: _bigMemberList()));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('selectedMemberPickerSelectButton')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'large grid mode (≤12 members) skips the selected-member picker',
      (tester) async {
        final members = List.generate(
          5,
          (i) => _member(id: 'id$i', name: 'M$i'),
        );
        await tester.pumpWidget(_buildSheetTrigger(members: members));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.byType(SelectedMultiMemberPicker), findsNothing);
      },
    );

    testWidgets('tapping Select opens MemberSearchSheet', (tester) async {
      await tester.pumpWidget(_buildSheetTrigger(members: _bigMemberList()));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('selectedMemberPickerSelectButton')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MemberSearchSheet), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Search sheet selection (compact path only)
  // ══════════════════════════════════════════════════════════════════════════

  group('search sheet selection', () {
    testWidgets(
      'confirming a selection in the search sheet enables the save button',
      (tester) async {
        final notifier = _FakeFrontingNotifier();
        await tester.pumpWidget(
          _buildSheetTrigger(members: _bigMemberList(), fakeNotifier: notifier),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // Save (check) button is disabled before any selection.
        expect(
          tester.widget<PrismGlassIconButton>(_saveButton()).onPressed,
          isNull,
          reason: 'Save button should be disabled before any selection',
        );

        // Open search, toggle a member, confirm.
        await tester.tap(
          find.byKey(const Key('selectedMemberPickerSelectButton')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Member 0'));
        await tester.pumpAndSettle();
        await _confirmSearchSelection(tester);

        // Back in the sheet — save button must now be enabled.
        expect(
          tester.widget<PrismGlassIconButton>(_saveButton()).onPressed,
          isNotNull,
          reason: 'Save button should be enabled after search selection',
        );
      },
    );

    testWidgets('all members appear in search sheet (not filtered locally)', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSheetTrigger(members: _bigMemberList()));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('selectedMemberPickerSelectButton')),
      );
      await tester.pumpAndSettle();

      // The search sheet should expose the full candidate set, including items
      // near the end of the ordered list that are not eagerly rendered.
      expect(find.text('Member 0'), findsWidgets);
      await tester.enterText(
        find.descendant(
          of: find.byType(MemberSearchSheet),
          matching: find.byType(TextField),
        ),
        '12',
      );
      await tester.pumpAndSettle();
      expect(find.text('Member 12'), findsWidgets);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Unknown selection (large grid mode)
  // ══════════════════════════════════════════════════════════════════════════

  group('Unknown selection in large grid mode', () {
    testWidgets('Unknown tile is visible in the large grid', (tester) async {
      final members = List.generate(5, (i) => _member(id: 'id$i', name: 'M$i'));
      await tester.pumpWidget(_buildSheetTrigger(members: members));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Unknown'), findsOneWidget);
    });

    testWidgets('tapping Unknown in large grid enables the save button', (
      tester,
    ) async {
      final members = List.generate(5, (i) => _member(id: 'id$i', name: 'M$i'));
      await tester.pumpWidget(_buildSheetTrigger(members: members));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Unknown'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<PrismGlassIconButton>(_saveButton()).onPressed,
        isNotNull,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Multi-select behavior (per spec §2.5)
  // ══════════════════════════════════════════════════════════════════════════

  group('multi-select large grid', () {
    testWidgets('tapping a member toggles its selection on and off', (
      tester,
    ) async {
      final members = List.generate(
        3,
        (i) => _member(id: 'id$i', name: 'M$i'),
      );
      await tester.pumpWidget(_buildSheetTrigger(members: members));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // First tap selects → save enabled.
      await tester.tap(find.text('M0'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<PrismGlassIconButton>(_saveButton()).onPressed,
        isNotNull,
        reason: 'Save should enable after selecting M0',
      );

      // Second tap on the same member deselects → save disabled again.
      await tester.tap(find.text('M0'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<PrismGlassIconButton>(_saveButton()).onPressed,
        isNull,
        reason: 'Save should disable after deselecting M0',
      );
    });

    testWidgets(
      'submitting with multiple members calls startFronting with all ids',
      (tester) async {
        final notifier = _FakeFrontingNotifier();
        final members = List.generate(
          3,
          (i) => _member(id: 'id$i', name: 'M$i'),
        );
        await tester.pumpWidget(
          _buildSheetTrigger(members: members, fakeNotifier: notifier),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // Multi-select: pick M0 and M2 (skip M1).
        await tester.tap(find.text('M0'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('M2'));
        await tester.pumpAndSettle();

        // Submit.
        await tester.tap(_saveButton());
        await tester.pumpAndSettle();

        expect(notifier.startFrontingCalls, hasLength(1));
        // Order is insertion order in the sheet's selection set, which is the
        // tap order; assert both ids are present rather than the exact order
        // (storage cannot reconstruct order across sync — see plan §2.5).
        expect(
          notifier.startFrontingCalls.single.toSet(),
          equals({'id0', 'id2'}),
        );
      },
    );

    testWidgets('selecting Unknown clears any other selections (exclusive)', (
      tester,
    ) async {
      final notifier = _FakeFrontingNotifier();
      final members = List.generate(
        3,
        (i) => _member(id: 'id$i', name: 'M$i'),
      );
      await tester.pumpWidget(
        _buildSheetTrigger(members: members, fakeNotifier: notifier),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Pick a real member first, then tap Unknown — Unknown should win.
      await tester.tap(find.text('M0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unknown'));
      await tester.pumpAndSettle();

      // Submit.  Unknown maps to startFronting([unknownSentinelMemberId]); the
      // mutation service auto-creates the sentinel member if it doesn't
      // exist (see fronting_mutation_service.dart `_ensureSentinelIfNeeded`).
      await tester.tap(_saveButton());
      await tester.pumpAndSettle();

      expect(
        notifier.startFrontingCalls,
        equals(<List<String>>[
          <String>[unknownSentinelMemberId],
        ]),
      );
    });
  });
}
