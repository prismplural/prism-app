import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/fronting/providers/fronting_providers.dart';
import 'package:prism_plurality/features/fronting/views/add_co_fronter_sheet.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

Member _member({required String id, required String name}) => Member(
      id: id,
      name: name,
      createdAt: DateTime(2024),
    );

// Fake notifier that records addCoFronter calls without hitting the real service.
class _FakeFrontingNotifier extends FrontingNotifier {
  final addedIds = <String>[];

  @override
  Future<void> build() async {}

  @override
  Future<void> addCoFronter(String memberId) async {
    addedIds.add(memberId);
  }
}

// Opens AddCoFronterSheet as a modal bottom sheet so Navigator.pop() works
// correctly (sheet is on top of a route, not the root route itself).
Widget _buildSheetTrigger({
  required List<Member> members,
  String? currentFronterId,
  List<String> existingCoFronterIds = const [],
  _FakeFrontingNotifier? fakeNotifier,
  void Function(bool?)? onResult,
}) {
  return ProviderScope(
    overrides: [
      activeMembersProvider.overrideWith((ref) => Stream.value(members)),
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
            onPressed: () async {
              final result = await showModalBottomSheet<bool>(
                context: ctx,
                isScrollControlled: true,
                builder: (_) => AddCoFronterSheet(
                  currentFronterId: currentFronterId,
                  existingCoFronterIds: existingCoFronterIds,
                ),
              );
              onResult?.call(result);
            },
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

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // Search icon
  // ══════════════════════════════════════════════════════════════════════════

  group('search icon', () {
    testWidgets('search icon appears in header when available members exist',
        (tester) async {
      final members = [
        _member(id: 'b', name: 'Bob'),
        _member(id: 'c', name: 'Charlie'),
      ];
      await tester.pumpWidget(
        _buildSheetTrigger(
          members: members,
          currentFronterId: 'fronter',
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byIcon(AppIcons.search), findsOneWidget);
    });

    testWidgets('tapping search icon opens MemberSearchSheet', (tester) async {
      final members = [
        _member(id: 'b', name: 'Bob'),
        _member(id: 'c', name: 'Charlie'),
      ];
      await tester.pumpWidget(
        _buildSheetTrigger(
          members: members,
          currentFronterId: 'fronter',
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(AppIcons.search));
      await tester.pumpAndSettle();

      expect(find.byType(MemberSearchSheet), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Excluded IDs
  // ══════════════════════════════════════════════════════════════════════════

  group('excluded IDs', () {
    testWidgets(
        'current fronter and existing co-fronters are not shown in search sheet',
        (tester) async {
      final members = [
        _member(id: 'alice', name: 'Alice'),    // current fronter → excluded
        _member(id: 'bob', name: 'Bob'),        // existing co-fronter → excluded
        _member(id: 'charlie', name: 'Charlie'), // available
      ];
      await tester.pumpWidget(
        _buildSheetTrigger(
          members: members,
          currentFronterId: 'alice',
          existingCoFronterIds: const ['bob'],
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(AppIcons.search));
      await tester.pumpAndSettle();

      // Only Charlie should be available in the search sheet.
      // Alice and Bob are excluded from the search sheet; Charlie appears in
      // both the underlying sheet and the search sheet, so use findsWidgets.
      expect(find.text('Charlie'), findsWidgets);
      expect(find.text('Alice'), findsNothing);
      expect(find.text('Bob'), findsNothing);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Selection via search
  // ══════════════════════════════════════════════════════════════════════════

  group('selection via search', () {
    testWidgets('confirming from search sheet enables the Add button',
        (tester) async {
      final members = [
        _member(id: 'b', name: 'Bob'),
        _member(id: 'c', name: 'Charlie'),
      ];
      await tester.pumpWidget(
        _buildSheetTrigger(
          members: members,
          currentFronterId: 'fronter',
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Add button starts disabled (no selection yet).
      final addButtonFinder = find.widgetWithText(PrismButton, 'Add');
      expect(
        tester.widget<PrismButton>(addButtonFinder).enabled,
        isFalse,
        reason: 'Add button should be disabled before any selection',
      );

      // Open search, select Bob, confirm.
      await tester.tap(find.byIcon(AppIcons.search));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bob').last);
      await tester.pump();

      // Tap "Done · 1" button to confirm.
      final doneFinder = find.textContaining('Done');
      expect(doneFinder, findsOneWidget);
      await tester.tap(doneFinder);
      await tester.pumpAndSettle();

      // Back in AddCoFronterSheet — Add button should now be enabled.
      expect(
        tester.widget<PrismButton>(addButtonFinder).enabled,
        isTrue,
        reason: 'Add button should be enabled after confirming search selection',
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Save behavior after search
  // ══════════════════════════════════════════════════════════════════════════

  group('save behavior after search', () {
    testWidgets('tapping Add after search selection calls addCoFronter',
        (tester) async {
      final notifier = _FakeFrontingNotifier();
      final members = [
        _member(id: 'bob', name: 'Bob'),
      ];
      bool? sheetResult;

      await tester.pumpWidget(
        _buildSheetTrigger(
          members: members,
          currentFronterId: 'alice',
          fakeNotifier: notifier,
          onResult: (r) => sheetResult = r,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Select Bob via the search sheet.
      await tester.tap(find.byIcon(AppIcons.search));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bob').last);
      await tester.pump();

      await tester.tap(find.textContaining('Done'));
      await tester.pumpAndSettle();

      // Tap Add.
      await tester.tap(find.widgetWithText(PrismButton, 'Add'));
      await tester.pumpAndSettle();

      expect(notifier.addedIds, contains('bob'));
      expect(sheetResult, isTrue);
    });
  });
}
