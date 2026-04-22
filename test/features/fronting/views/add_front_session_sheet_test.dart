import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/fronting_session.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/views/add_front_session_sheet.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/inline_expandable_member_picker.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_glass_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

Member _member({required String id, required String name}) =>
    Member(id: id, name: name, createdAt: DateTime(2024));

/// 13 members → exceeds the compact threshold (12) → compact list + search icon.
List<Member> _bigMemberList() =>
    List.generate(13, (i) => _member(id: 'id$i', name: 'Member $i'));

/// Fake notifier: prevents real DB calls during widget tests.
class _FakeFrontingNotifier extends FrontingNotifier {
  @override
  Future<void> build() async {}

  @override
  Future<void> startFrontingWithDetails({
    required String? memberId,
    List<String> coFronterIds = const [],
    FrontConfidence? confidence,
    String? notes,
    DateTime? startTime,
  }) async {}
}

Widget _buildSheetTrigger({
  required List<Member> members,
  List<FrontingSession> activeSessions = const [],
  _FakeFrontingNotifier? fakeNotifier,
}) {
  return ProviderScope(
    overrides: [
      activeMembersProvider.overrideWith((ref) => Stream.value(members)),
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

/// Returns the save/confirm button (PrismGlassIconButton with check icon).
///
/// PrismSheetTopBar always renders two PrismGlassIconButton widgets (close +
/// trailing). Selecting by icon avoids "too many elements" errors.
Finder _saveButton() => find.byWidgetPredicate(
  (w) => w is PrismGlassIconButton && w.icon == AppIcons.check,
);

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // Compact list search icon
  // ══════════════════════════════════════════════════════════════════════════

  group('compact list search icon', () {
    testWidgets(
      'large systems use the shared inline picker instead of raw rows',
      (tester) async {
        await tester.pumpWidget(_buildSheetTrigger(members: _bigMemberList()));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.byType(InlineExpandableMemberPicker), findsOneWidget);
        expect(
          find.byKey(const Key('addFrontSessionInlineMemberPicker')),
          findsOneWidget,
        );
        expect(find.text('Member 12'), findsNothing);
      },
    );

    testWidgets(
      'search icon appears when member count exceeds compact threshold',
      (tester) async {
        await tester.pumpWidget(_buildSheetTrigger(members: _bigMemberList()));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.byIcon(AppIcons.search), findsOneWidget);
      },
    );

    testWidgets('expanded inline picker uses capped internal scroller', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSheetTrigger(members: _bigMemberList()));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(InlineExpandableMemberPicker));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('inlineExpandablePickerList')),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(find.byKey(const Key('inlineExpandablePickerList')))
            .height,
        lessThanOrEqualTo(320),
      );
    });

    testWidgets('no search icon in large grid mode (≤12 members)', (
      tester,
    ) async {
      final members = List.generate(5, (i) => _member(id: 'id$i', name: 'M$i'));
      await tester.pumpWidget(_buildSheetTrigger(members: members));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byIcon(AppIcons.search), findsNothing);
    });

    testWidgets(
      'search icon is a standalone IconButton, not inside a PrismTextField',
      (tester) async {
        // Guard: the old inline search embedded AppIcons.search inside PrismTextField.
        // After the refactor, the icon lives in an IconButton.
        await tester.pumpWidget(_buildSheetTrigger(members: _bigMemberList()));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        final searchIconParentIsTextField = find.ancestor(
          of: find.byIcon(AppIcons.search),
          matching: find.byType(PrismTextField),
        );
        expect(
          searchIconParentIsTextField,
          findsNothing,
          reason:
              'Search icon must be a standalone IconButton, '
              'not embedded inside a PrismTextField (old inline search)',
        );
      },
    );

    testWidgets('tapping search icon opens MemberSearchSheet', (tester) async {
      await tester.pumpWidget(_buildSheetTrigger(members: _bigMemberList()));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(AppIcons.search));
      await tester.pumpAndSettle();

      expect(find.byType(MemberSearchSheet), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Search sheet selection
  // ══════════════════════════════════════════════════════════════════════════

  group('search sheet selection', () {
    testWidgets(
      'selecting a member via the search sheet enables the save button',
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

        // Open search, pick a member.
        await tester.tap(find.byIcon(AppIcons.search));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Member 0').last);
        await tester.pumpAndSettle();

        // Back in the sheet — save button must now be enabled.
        expect(
          tester.widget<PrismGlassIconButton>(_saveButton()).onPressed,
          isNotNull,
          reason: 'Save button should be enabled after search selection',
        );
      },
    );

    testWidgets('selecting Unknown via search sheet enables the save button', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSheetTrigger(members: _bigMemberList()));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(AppIcons.search));
      await tester.pumpAndSettle();

      // Tap the "Unknown" special row in the search sheet (use .last because
      // the compact list below the sheet also has an "Unknown" row).
      await tester.tap(find.text('Unknown').last);
      await tester.pumpAndSettle();

      expect(
        tester.widget<PrismGlassIconButton>(_saveButton()).onPressed,
        isNotNull,
        reason: 'Save button should be enabled after selecting Unknown',
      );
    });

    testWidgets('all members appear in search sheet (not filtered locally)', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSheetTrigger(members: _bigMemberList()));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(AppIcons.search));
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
  // Fronting state in search sheet
  // ══════════════════════════════════════════════════════════════════════════

  group('fronting state in search sheet', () {
    testWidgets(
      'fronting member is excluded from search sheet in co-front mode',
      (tester) async {
        // Session with id0 fronting → triggers co-front toggle in the UI.
        final session = FrontingSession(
          id: 's1',
          startTime: DateTime(2024),
          memberId: 'id0',
        );
        final members = _bigMemberList();

        await tester.pumpWidget(
          _buildSheetTrigger(members: members, activeSessions: [session]),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // Switch to co-front mode.
        await tester.tap(find.text('Co-front'));
        await tester.pumpAndSettle();

        // Open search sheet.
        await tester.tap(find.byIcon(AppIcons.search));
        await tester.pumpAndSettle();

        // Member 0 is fronting → must not appear *inside* the search sheet.
        // (The underlying compact list still shows all members; we only check
        // what the search sheet offers as candidates.)
        expect(
          find.descendant(
            of: find.byType(MemberSearchSheet),
            matching: find.text('Member 0'),
          ),
          findsNothing,
        );
        // Other members are still available in the search sheet.
        expect(
          find.descendant(
            of: find.byType(MemberSearchSheet),
            matching: find.text('Member 1'),
          ),
          findsWidgets,
        );
      },
    );

    testWidgets('Unknown row is absent from search sheet in co-front mode', (
      tester,
    ) async {
      final session = FrontingSession(
        id: 's1',
        startTime: DateTime(2024),
        memberId: 'id0',
      );
      await tester.pumpWidget(
        _buildSheetTrigger(
          members: _bigMemberList(),
          activeSessions: [session],
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Co-front'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(AppIcons.search));
      await tester.pumpAndSettle();

      expect(find.text('Unknown'), findsNothing);
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
  // Unknown selection in compact mode
  // ══════════════════════════════════════════════════════════════════════════

  group('Unknown selection in compact list mode', () {
    testWidgets('Unknown row is present in the expanded inline picker', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSheetTrigger(members: _bigMemberList()));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(InlineExpandableMemberPicker));
      await tester.pumpAndSettle();

      expect(find.text('Unknown'), findsOneWidget);
    });

    testWidgets(
      'tapping Unknown in the inline picker enables the save button',
      (tester) async {
        await tester.pumpWidget(_buildSheetTrigger(members: _bigMemberList()));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(InlineExpandableMemberPicker));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Unknown'));
        await tester.pumpAndSettle();

        expect(
          tester.widget<PrismGlassIconButton>(_saveButton()).onPressed,
          isNotNull,
        );
      },
    );
  });

  group('co-fronter picker', () {
    testWidgets('selected fronter uses inline multi picker for co-fronters', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSheetTrigger(members: _bigMemberList()));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(AppIcons.search));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Member 0').last);
      await tester.pumpAndSettle();

      expect(find.byType(InlineExpandableMultiMemberPicker), findsOneWidget);
      expect(
        find.byKey(const Key('addFrontSessionCoFrontersInlinePicker')),
        findsOneWidget,
      );
    });
  });
}
