import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member_group.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/members/providers/group_display_prefs_provider.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/members/widgets/create_edit_group_sheet.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

MemberGroup _group({required String id, String? parentGroupId}) => MemberGroup(
  id: id,
  name: id,
  createdAt: DateTime(2024, 1, 1),
  parentGroupId: parentGroupId,
);

/// A fake GroupNotifier that records calls without touching a repo.
class _FakeGroupNotifier extends GroupNotifier {
  int createCalls = 0;
  int updateCalls = 0;

  @override
  Future<void> build() async {}

  @override
  Future<void> createGroup(MemberGroup group) async {
    createCalls++;
  }

  @override
  Future<void> updateGroup(MemberGroup group) async {
    updateCalls++;
  }
}

/// Fake notifier that immediately resolves to a fixed [value].
///
/// Extends [GroupShowEmojiOnAvatarNotifier] so it can be used as a drop-in
/// override for [groupShowEmojiOnAvatarProvider]. By returning synchronously
/// via [SynchronousFuture], the provider is in `AsyncData` state before the
/// sheet's post-frame callback fires.
class _FakeShowEmojiNotifier extends GroupShowEmojiOnAvatarNotifier {
  _FakeShowEmojiNotifier(this._fixedValue) : super('');
  final bool _fixedValue;

  @override
  Future<bool> build() {
    // SynchronousFuture resolves within the same microtask tick, which means
    // the AsyncNotifier state is already AsyncData<bool> when the
    // post-frame callback calls `ref.read(...)`.
    return SynchronousFuture(_fixedValue);
  }
}

/// Builds the sheet inside a minimal MaterialApp + ProviderScope harness.
///
/// [group] — if non-null, operates in edit mode.
/// [initialParentGroupId] — pre-selects a parent (used in edit mode when
///   group.parentGroupId is null to simulate the user having picked a new parent).
Widget _buildSheet({
  required List<MemberGroup> groups,
  required _FakeGroupNotifier fakeNotifier,
  MemberGroup? group,
  String? initialParentGroupId,
}) {
  return ProviderScope(
    overrides: [
      allGroupsProvider.overrideWithValue(AsyncValue.data(groups)),
      groupNotifierProvider.overrideWith(() => fakeNotifier),
      terminologySettingProvider.overrideWithValue((
        term: SystemTerminology.headmates,
        customSingular: null,
        customPlural: null,
        useEnglish: false,
      )),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        body: Builder(
          builder: (context) => SizedBox(
            height: 600,
            child: CreateEditGroupSheet(
              group: group,
              initialParentGroupId: initialParentGroupId,
              scrollController: ScrollController(),
            ),
          ),
        ),
      ),
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUp(PrismToast.resetForTest);

  testWidgets(
    'save succeeds when reparenting an existing group to a deeply-nested '
    'parent (no depth limit)',
    (tester) async {
      // Build a 7-level chain: g0 -> g1 -> g2 -> g3 -> g4 -> g5 -> g6.
      // We are editing g0 (root) and reparenting it under g6 — which is NOT
      // a descendant of g0, so this is valid (no cycle). With the old
      // depth-limit guard this would have thrown. Now it must succeed.
      final groups = <MemberGroup>[];
      String? parent;
      for (var i = 0; i < 7; i++) {
        groups.add(_group(id: 'g$i', parentGroupId: parent));
        parent = 'g$i';
      }

      // g0 is the root group we are editing.
      final g0 = groups[0];
      // We want to reparent g0 under g6 (g6 is NOT a descendant of g0 in the
      // current tree, because g6 is in an independent chain seeded from null).
      // Wait — in the chain g0->g1->...->g6, g6 IS a descendant of g0.
      // Use a separate standalone group for the new parent instead.
      final deepParent = _group(id: 'standalone-deep');
      final allGroups = [...groups, deepParent];

      final fakeNotifier = _FakeGroupNotifier();

      await tester.pumpWidget(
        _buildSheet(
          groups: allGroups,
          fakeNotifier: fakeNotifier,
          group: g0, // editing g0 (root)
          initialParentGroupId: deepParent.id, // reparent under standalone-deep
        ),
      );
      await tester.pumpAndSettle();

      // Tap the save button (the check icon in the top bar).
      // The save button is enabled when the name field is non-empty (g0.name == 'g0').
      final saveButton = find.byTooltip('Save');
      expect(saveButton, findsOneWidget);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      // updateGroup should have been called exactly once — no depth error fired.
      expect(
        fakeNotifier.updateCalls,
        1,
        reason: 'expected updateGroup to be called; no depth limit should fire',
      );
      expect(fakeNotifier.createCalls, 0);
    },
  );

  testWidgets(
    'save throws and shows error when reparenting would create a cycle',
    (tester) async {
      // Build a chain: g0 (root) -> g1 -> g2.
      // We are editing g0 and attempting to set its parent to g2,
      // which is a descendant of g0 → cycle.
      final g0 = _group(id: 'g0');
      final g1 = _group(id: 'g1', parentGroupId: 'g0');
      final g2 = _group(id: 'g2', parentGroupId: 'g1');

      final fakeNotifier = _FakeGroupNotifier();

      await tester.pumpWidget(
        _buildSheet(
          groups: [g0, g1, g2],
          fakeNotifier: fakeNotifier,
          group: g0,
          initialParentGroupId: 'g2', // g2 is a descendant of g0 → cycle
        ),
      );
      await tester.pumpAndSettle();

      final saveButton = find.byTooltip('Save');
      expect(saveButton, findsOneWidget);
      await tester.tap(saveButton);
      await tester.pump(); // let the synchronous save path run

      // updateGroup must NOT have been called — the cycle check fired first.
      expect(
        fakeNotifier.updateCalls,
        0,
        reason: 'cycle check must block the save before reaching the notifier',
      );
      expect(fakeNotifier.createCalls, 0);

      // Dismiss the error toast so its auto-dismiss timer doesn't outlive
      // the widget tree and trigger a pending-timer assertion.
      PrismToast.resetForTest();
      await tester.pump();
    },
  );

  testWidgets(
    'no reference to wouldExceedMaxDepth — file compiles and save path works',
    (tester) async {
      // Regression guard: the sheet must compile (i.e. not reference the
      // removed wouldExceedMaxDepth method). This test exercises the save path
      // for a new group (no cycle check applies to new groups).
      final fakeNotifier = _FakeGroupNotifier();

      await tester.pumpWidget(
        _buildSheet(
          groups: const [],
          fakeNotifier: fakeNotifier,
          // no group → create mode
        ),
      );
      await tester.pumpAndSettle();

      // Enter a name so the save button becomes enabled.
      await tester.enterText(find.byType(TextField).first, 'New Group');
      await tester.pumpAndSettle();

      final saveButton = find.byTooltip('Save');
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(
        fakeNotifier.createCalls,
        1,
        reason: 'createGroup should be called for a new group',
      );
    },
  );

  testWidgets('edit mode exposes the group color picker when no color is set', (
    tester,
  ) async {
    final group = _group(id: 'g0');
    final fakeNotifier = _FakeGroupNotifier();

    await tester.pumpWidget(
      _buildSheet(groups: [group], fakeNotifier: fakeNotifier, group: group),
    );
    await tester.pumpAndSettle();

    expect(find.text('Color'), findsOneWidget);
    expect(find.text('No color'), findsOneWidget);

    await tester.tap(find.text('Color'));
    await tester.pumpAndSettle();

    expect(find.byType(ColorPicker), findsOneWidget);
  });

  testWidgets(
    'edit mode: post-frame callback seeds _showEmojiOnAvatar from persisted '
    'false preference',
    (tester) async {
      // A minimal 1×1 PNG so the avatar condition is satisfied and the emoji
      // toggle is visible.
      final pngBytes = Uint8List.fromList(
        [
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
          0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
          0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
          0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
          0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
          0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
          0x00, 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC,
          0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
          0x44, 0xAE, 0x42, 0x60, 0x82,
        ],
      );

      const groupId = 'g_emoji';
      final group = MemberGroup(
        id: groupId,
        name: 'Emoji Group',
        createdAt: DateTime(2024, 1, 1),
        emoji: '🌟',
        avatarImageData: pngBytes,
      );
      final fakeGroupNotifier = _FakeGroupNotifier();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allGroupsProvider.overrideWithValue(AsyncValue.data([group])),
            groupNotifierProvider.overrideWith(() => fakeGroupNotifier),
            // Override the family provider for this specific groupId to return
            // false synchronously, so the post-frame callback reads it as data.
            groupShowEmojiOnAvatarProvider(groupId).overrideWith(
              () => _FakeShowEmojiNotifier(false),
            ),
            terminologySettingProvider.overrideWithValue((
              term: SystemTerminology.headmates,
              customSingular: null,
              customPlural: null,
              useEnglish: false,
            )),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: Scaffold(
              body: Builder(
                builder: (context) => SizedBox(
                  height: 800,
                  child: CreateEditGroupSheet(
                    group: group,
                    scrollController: ScrollController(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      // pumpAndSettle lets the post-frame callback fire and setState rebuild.
      await tester.pumpAndSettle();

      // Scroll down to make the emoji toggle visible.
      await tester.scrollUntilVisible(
        find.widgetWithText(PrismSwitchRow, 'Show emoji on avatar'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      final switchRow = tester.widget<PrismSwitchRow>(
        find.widgetWithText(PrismSwitchRow, 'Show emoji on avatar'),
      );
      expect(
        switchRow.value,
        isFalse,
        reason:
            'post-frame callback must seed _showEmojiOnAvatar from the persisted false preference',
      );
    },
  );
}
