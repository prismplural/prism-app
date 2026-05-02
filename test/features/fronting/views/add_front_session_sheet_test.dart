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

/// Records `startFronting` and `replaceFronting` calls so tests can assert
/// on the multi-select payload without hitting the real DB.
class _FakeFrontingNotifier extends FrontingNotifier {
  final List<List<String>> startFrontingCalls = [];
  final List<List<String>> replaceFrontingCalls = [];

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

  @override
  Future<void> replaceFronting(
    List<String> memberIds, {
    FrontConfidence? confidence,
    String? notes,
  }) async {
    replaceFrontingCalls.add(List<String>.from(memberIds));
  }
}

Widget _buildSheetTrigger({
  required List<Member> members,
  List<FrontingSession> activeSessions = const [],
  _FakeFrontingNotifier? fakeNotifier,
  FrontStartBehavior addFrontDefaultBehavior = FrontStartBehavior.additive,
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
        (ref) => Stream.value(
          SystemSettings(addFrontDefaultBehavior: addFrontDefaultBehavior),
        ),
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

    // ────────────────────────────────────────────────────────────────────────
    // Symmetric-difference contract for the compact-search confirm path.
    //
    // The compact search sheet returns a `Set<String>` representing the new
    // authoritative selection. The sheet must reconcile that set against the
    // pre-search selection by toggling exactly the members whose membership
    // actually changed — never by re-toggling already-selected members or
    // ignoring deselected ones. Pre-fix, the compact path looped over `result`
    // and called `onToggle` for every id, which inverted multi-select state
    // for large systems.
    // ────────────────────────────────────────────────────────────────────────

    /// Re-opens the search sheet from the compact picker. Once at least one
    /// member is selected, the picker swaps the empty-state "Select" button
    /// for an "Add" button (`selectedMemberPickerAddButton`); pre-selection
    /// the empty-state key (`selectedMemberPickerSelectButton`) is what's
    /// rendered. Try both, fall back to tapping the picker itself.
    Future<void> reopenSearch(WidgetTester tester) async {
      final addButton = find.byKey(const Key('selectedMemberPickerAddButton'));
      final selectButton = find.byKey(
        const Key('selectedMemberPickerSelectButton'),
      );
      if (addButton.evaluate().isNotEmpty) {
        await tester.tap(addButton);
      } else {
        await tester.tap(selectButton);
      }
      await tester.pumpAndSettle();
    }

    testWidgets(
      'confirm with {B, C} when starting from {A, B} ends at {B, C}',
      (tester) async {
        final notifier = _FakeFrontingNotifier();
        await tester.pumpWidget(
          _buildSheetTrigger(members: _bigMemberList(), fakeNotifier: notifier),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // Build initial selection {Member 0, Member 1} (= "A, B") by opening
        // the search sheet, picking both, confirming.
        await reopenSearch(tester);
        await tester.tap(find.text('Member 0'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Member 1'));
        await tester.pumpAndSettle();
        await _confirmSearchSelection(tester);

        // Re-open search and confirm {Member 1, Member 2} (= "B, C"):
        // deselect Member 0, leave Member 1 alone, add Member 2.
        // Already-selected names also render as chips in the parent picker
        // body, so scope row taps to descendants of the search sheet.
        await reopenSearch(tester);
        await tester.tap(
          find
              .descendant(
                of: find.byType(MemberSearchSheet),
                matching: find.text('Member 0'),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .descendant(
                of: find.byType(MemberSearchSheet),
                matching: find.text('Member 2'),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await _confirmSearchSelection(tester);

        // Submit and inspect the call payload.
        await tester.tap(_saveButton());
        await tester.pumpAndSettle();

        expect(notifier.startFrontingCalls, hasLength(1));
        expect(
          notifier.startFrontingCalls.single.toSet(),
          equals({'id1', 'id2'}),
          reason:
              'Member 0 should be removed, Member 2 added, '
              'Member 1 preserved',
        );
      },
    );

    testWidgets(
      'confirm with {A} when starting from {A} keeps {A} (no toggles)',
      (tester) async {
        final notifier = _FakeFrontingNotifier();
        await tester.pumpWidget(
          _buildSheetTrigger(members: _bigMemberList(), fakeNotifier: notifier),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // Build initial selection {Member 0}.
        await reopenSearch(tester);
        await tester.tap(find.text('Member 0'));
        await tester.pumpAndSettle();
        await _confirmSearchSelection(tester);

        // Re-open search and confirm without changing anything.
        await reopenSearch(tester);
        await _confirmSearchSelection(tester);

        await tester.tap(_saveButton());
        await tester.pumpAndSettle();

        expect(notifier.startFrontingCalls, hasLength(1));
        expect(
          notifier.startFrontingCalls.single.toSet(),
          equals({'id0'}),
          reason: 'Re-confirming the same set must not toggle Member 0 off',
        );
      },
    );

    testWidgets('confirm with {A, B, C} when starting from {} adds all three', (
      tester,
    ) async {
      final notifier = _FakeFrontingNotifier();
      await tester.pumpWidget(
        _buildSheetTrigger(members: _bigMemberList(), fakeNotifier: notifier),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // No prior selection — open search, pick three, confirm.
      await tester.tap(
        find.byKey(const Key('selectedMemberPickerSelectButton')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Member 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Member 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Member 2'));
      await tester.pumpAndSettle();
      await _confirmSearchSelection(tester);

      await tester.tap(_saveButton());
      await tester.pumpAndSettle();

      expect(notifier.startFrontingCalls, hasLength(1));
      expect(
        notifier.startFrontingCalls.single.toSet(),
        equals({'id0', 'id1', 'id2'}),
      );
    });

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
      final members = List.generate(3, (i) => _member(id: 'id$i', name: 'M$i'));
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
      final members = List.generate(3, (i) => _member(id: 'id$i', name: 'M$i'));
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

  // ══════════════════════════════════════════════════════════════════════════
  // Add-front mode segmented control (1B-δ)
  //
  // The segmented control at the top of the sheet defaults to the
  // `add_front_default_behavior` system setting and offers a per-action
  // override. Per spec, the user's override applies only to this submit and
  // is NEVER written back to the persisted setting.
  // ══════════════════════════════════════════════════════════════════════════

  group('add-front mode segmented control', () {
    testWidgets(
      'segmented control renders both options when settings have loaded',
      (tester) async {
        final members = List.generate(
          3,
          (i) => _member(id: 'id$i', name: 'M$i'),
        );
        await tester.pumpWidget(_buildSheetTrigger(members: members));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('addFrontModeSegmentedControl')),
          findsOneWidget,
        );
        expect(find.text('Add as co-fronter'), findsOneWidget);
        expect(find.text('Replace current'), findsOneWidget);
      },
    );

    testWidgets('submitting in additive mode (default) calls startFronting', (
      tester,
    ) async {
      final notifier = _FakeFrontingNotifier();
      final members = List.generate(3, (i) => _member(id: 'id$i', name: 'M$i'));
      await tester.pumpWidget(
        _buildSheetTrigger(members: members, fakeNotifier: notifier),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('M0'));
      await tester.pumpAndSettle();
      await tester.tap(_saveButton());
      await tester.pumpAndSettle();

      expect(notifier.startFrontingCalls, hasLength(1));
      expect(notifier.startFrontingCalls.single, equals(['id0']));
      expect(
        notifier.replaceFrontingCalls,
        isEmpty,
        reason: 'additive mode must not call replaceFronting',
      );
    });

    testWidgets('when preference is replace, submit calls replaceFronting', (
      tester,
    ) async {
      final notifier = _FakeFrontingNotifier();
      final members = List.generate(3, (i) => _member(id: 'id$i', name: 'M$i'));
      await tester.pumpWidget(
        _buildSheetTrigger(
          members: members,
          fakeNotifier: notifier,
          addFrontDefaultBehavior: FrontStartBehavior.replace,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('M0'));
      await tester.pumpAndSettle();
      await tester.tap(_saveButton());
      await tester.pumpAndSettle();

      expect(notifier.replaceFrontingCalls, hasLength(1));
      expect(notifier.replaceFrontingCalls.single, equals(['id0']));
      expect(
        notifier.startFrontingCalls,
        isEmpty,
        reason: 'replace mode must not call startFronting',
      );
    });

    testWidgets(
      'tapping the Replace segment overrides the preference for this submit',
      (tester) async {
        final notifier = _FakeFrontingNotifier();
        final members = List.generate(
          3,
          (i) => _member(id: 'id$i', name: 'M$i'),
        );
        await tester.pumpWidget(
          _buildSheetTrigger(
            members: members,
            fakeNotifier: notifier,
            addFrontDefaultBehavior: FrontStartBehavior.additive,
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Replace current'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('M0'));
        await tester.pumpAndSettle();
        await tester.tap(_saveButton());
        await tester.pumpAndSettle();

        expect(notifier.replaceFrontingCalls, hasLength(1));
        expect(notifier.startFrontingCalls, isEmpty);
      },
    );

    testWidgets(
      'tapping the Add segment overrides a replace preference for this submit',
      (tester) async {
        final notifier = _FakeFrontingNotifier();
        final members = List.generate(
          3,
          (i) => _member(id: 'id$i', name: 'M$i'),
        );
        await tester.pumpWidget(
          _buildSheetTrigger(
            members: members,
            fakeNotifier: notifier,
            addFrontDefaultBehavior: FrontStartBehavior.replace,
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Add as co-fronter'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('M0'));
        await tester.pumpAndSettle();
        await tester.tap(_saveButton());
        await tester.pumpAndSettle();

        expect(notifier.startFrontingCalls, hasLength(1));
        expect(notifier.replaceFrontingCalls, isEmpty);
      },
    );

    testWidgets(
      'changing the toggle does NOT write back to the persisted setting',
      (tester) async {
        // The sheet must NEVER write to `add_front_default_behavior`.
        // We assert the negative by observing that the override only affects
        // the in-flight submit: a second sheet open continues to default
        // from the (unchanged) preference.
        final notifier = _FakeFrontingNotifier();
        final members = List.generate(
          3,
          (i) => _member(id: 'id$i', name: 'M$i'),
        );

        // Open #1: pref=additive, override to replace, submit.
        await tester.pumpWidget(
          _buildSheetTrigger(
            members: members,
            fakeNotifier: notifier,
            addFrontDefaultBehavior: FrontStartBehavior.additive,
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Replace current'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('M0'));
        await tester.pumpAndSettle();
        await tester.tap(_saveButton());
        await tester.pumpAndSettle();

        expect(notifier.replaceFrontingCalls, hasLength(1));

        // Open #2: same preference (additive) — submit should call
        // startFronting (default), NOT replaceFronting (which would
        // indicate the override leaked back into the setting).
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('M1'));
        await tester.pumpAndSettle();
        await tester.tap(_saveButton());
        await tester.pumpAndSettle();

        expect(
          notifier.startFrontingCalls,
          hasLength(1),
          reason:
              'second open should default to additive — the user\'s '
              'first-open override of "replace" must not have persisted',
        );
        expect(notifier.replaceFrontingCalls, hasLength(1));
      },
    );
  });
}
