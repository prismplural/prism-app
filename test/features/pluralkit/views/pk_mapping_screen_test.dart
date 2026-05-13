import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_mapping_controller.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_mapping_applier.dart';
import 'package:prism_plurality/features/pluralkit/views/pk_mapping_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/member_search_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_select.dart';

// ---------------------------------------------------------------------------
// Fake controller that lets tests stage state directly and intercept apply().
// ---------------------------------------------------------------------------

class _FakePkMappingController extends PkMappingController {
  _FakePkMappingController(this._initial, {this.appliedResults});

  final PkMappingState _initial;

  /// If provided, apply() will set these as lastResults instead of running
  /// the real pipeline.
  final List<PkApplyResult>? appliedResults;

  int applyCallCount = 0;
  int retryCallCount = 0;
  int dismissCallCount = 0;

  final List<_PkDecisionCall> pkDecisionCalls = [];
  final List<_LocalDecisionCall> localDecisionCalls = [];

  @override
  Future<PkMappingState> build() async => _initial;

  /// Captures the localized status strings passed by the screen. Tests can
  /// assert the screen wired them through correctly.
  String? lastImportingHistoryStatus;
  String? lastPushingHistoryStatus;

  @override
  Future<PkMappingApplyOutcome?> apply({
    String? importingHistoryStatus,
    String? pushingHistoryStatus,
    String? offlineErrorMessage,
  }) async {
    applyCallCount++;
    lastImportingHistoryStatus = importingHistoryStatus;
    lastPushingHistoryStatus = pushingHistoryStatus;
    final current = state.value;
    if (current == null) return null;
    final results = appliedResults ?? const [];
    state = AsyncData(
      current.copyWith(
        isApplying: false,
        applyProgress: 1.0,
        lastResults: results,
      ),
    );
    // Mirror the real controller: return Failed if any result failed,
    // otherwise Applied.
    final hasFailed = results.any((r) => r.outcome == PkApplyOutcome.failed);
    if (hasFailed) {
      return PkMappingApplyOutcomeFailed(
        results.where((r) => r.outcome == PkApplyOutcome.failed).toList(),
      );
    }
    return const PkMappingApplyOutcomeApplied();
  }

  @override
  void retry() {
    retryCallCount++;
    // Don't call invalidateSelf — we want to observe the call, not reload.
  }

  @override
  void dismiss() {
    dismissCallCount++;
  }

  @override
  void setPkDecision(String pkUuid, PkMappingDecision decision) {
    pkDecisionCalls.add(_PkDecisionCall(pkUuid, decision));
    super.setPkDecision(pkUuid, decision);
  }

  @override
  void setLocalDecision(String localId, PkMappingDecision decision) {
    localDecisionCalls.add(_LocalDecisionCall(localId, decision));
    super.setLocalDecision(localId, decision);
  }
}

class _PkDecisionCall {
  _PkDecisionCall(this.pkUuid, this.decision);
  final String pkUuid;
  final PkMappingDecision decision;
}

class _LocalDecisionCall {
  _LocalDecisionCall(this.localId, this.decision);
  final String localId;
  final PkMappingDecision decision;
}

/// Fake controller that always emits AsyncError from build().
class _ErroringPkMappingController extends PkMappingController {
  int retryCallCount = 0;

  @override
  Future<PkMappingState> build() async {
    throw StateError('boom');
  }

  @override
  void retry() {
    retryCallCount++;
  }
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

domain.Member _local(String id, String name, {String? pkUuid}) => domain.Member(
  id: id,
  name: name,
  createdAt: DateTime(2026),
  pluralkitUuid: pkUuid,
);

PKMember _pk(String uuid, String name, {String? id}) =>
    PKMember(id: id ?? uuid.substring(0, 5), uuid: uuid, name: name);

Widget _wrap(PkMappingController controller) {
  return ProviderScope(
    overrides: [pkMappingControllerProvider.overrideWith(() => controller)],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: [Locale('en')],
      home: PkMappingScreen(),
    ),
  );
}

List<PrismSelect<String>> _selectsFor(WidgetTester tester) {
  return tester
      .widgetList<PrismSelect<String>>(find.byType(PrismSelect<String>))
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PkMappingScreen — dropdown filtering', () {
    testWidgets(
      'a local already linked by one PK row is disabled in other PK rows',
      (tester) async {
        final pkAlice = _pk('pk-alice', 'Alice');
        final pkBob = _pk('pk-bob', 'Bob');
        final locals = [_local('l1', 'Alice'), _local('l2', 'Bob')];

        // Alice is linked to l1. Bob is set to import. The Bob row should
        // still list l1 as an option, but disabled (consumed by pk-alice).
        final state = PkMappingState(
          pkMembers: [pkAlice, pkBob],
          localMembers: locals,
          decisionsByPkUuid: {
            pkAlice.uuid: PkLinkDecision(
              localMemberId: 'l1',
              pkMember: pkAlice,
            ),
            pkBob.uuid: PkImportDecision(pkMember: pkBob),
          },
        );

        final controller = _FakePkMappingController(state);
        await tester.pumpWidget(_wrap(controller));
        await tester.pumpAndSettle();

        // Two PK rows → two PK-row selects. Bob is not linked so also lands
        // in the "local members to push" pool (a third select). We just need
        // to find Bob's PK-row select (which has Import/Skip items AND l1).
        final selects = _selectsFor(tester);
        expect(selects.length, greaterThanOrEqualTo(2));

        // Bob's PK-row select: value is the import sentinel and its items
        // list contains l1 (possibly disabled).
        final bobSelect = selects.firstWhere(
          (s) =>
              s.value == kPkRowImportSentinel &&
              s.items.any((i) => i.value == 'l1'),
        );
        final bobL1Item = bobSelect.items.firstWhere((i) => i.value == 'l1');
        expect(
          bobL1Item.enabled,
          isFalse,
          reason:
              'Local l1 is already consumed by the Alice link — must be '
              'disabled in Bob\'s dropdown',
        );

        // Alice's select, by contrast, SHOULD have l1 enabled (she owns it).
        final aliceSelect = selects.firstWhere((s) => s.value == 'l1');
        final aliceL1Item = aliceSelect.items.firstWhere(
          (i) => i.value == 'l1',
        );
        expect(aliceL1Item.enabled, isTrue);
      },
    );

    testWidgets(
      'link search opens searchable member sheet and applies selected local',
      (tester) async {
        final pkDana = _pk('pk-dana', 'Dana');
        final locals = [
          _local('l1', 'Alice'),
          _local('l2', 'Bob'),
          _local('l3', 'Dana Prime'),
        ];

        final state = PkMappingState(
          pkMembers: [pkDana],
          localMembers: locals,
          decisionsByPkUuid: {pkDana.uuid: PkImportDecision(pkMember: pkDana)},
          decisionsByLocalId: const {
            'l1': PkPushNewDecision(localMemberId: 'l1'),
            'l2': PkPushNewDecision(localMemberId: 'l2'),
            'l3': PkPushNewDecision(localMemberId: 'l3'),
          },
        );

        final controller = _FakePkMappingController(state);
        await tester.pumpWidget(_wrap(controller));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('pkMappingLinkSearch-pk-dana')),
        );
        await tester.pumpAndSettle();

        expect(find.byType(MemberSearchSheet), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'prime');
        await tester.pumpAndSettle();

        final searchSheet = find.byType(MemberSearchSheet);
        final danaPrimeResult = find.descendant(
          of: searchSheet,
          matching: find.text('Dana Prime'),
        );
        expect(danaPrimeResult, findsOneWidget);
        expect(
          find.descendant(of: searchSheet, matching: find.text('Alice')),
          findsNothing,
        );

        await tester.tap(danaPrimeResult);
        await tester.pumpAndSettle();

        expect(controller.pkDecisionCalls, hasLength(1));
        final call = controller.pkDecisionCalls.single;
        expect(call.pkUuid, pkDana.uuid);
        expect(call.decision, isA<PkLinkDecision>());
        expect((call.decision as PkLinkDecision).localMemberId, 'l3');
      },
    );

    testWidgets(
      'locals already linked via pluralkitUuid never appear as options at all',
      (tester) async {
        // l1 is already linked (pluralkitUuid set); l2 is unlinked.
        final pkDana = _pk('pk-dana', 'Dana');
        final locals = [
          _local('l1', 'Alice', pkUuid: 'pk-alice'),
          _local('l2', 'Bob'),
        ];

        final state = PkMappingState(
          pkMembers: [pkDana],
          localMembers: locals,
          decisionsByPkUuid: {pkDana.uuid: PkImportDecision(pkMember: pkDana)},
          decisionsByLocalId: {
            'l2': const PkPushNewDecision(localMemberId: 'l2'),
          },
        );

        final controller = _FakePkMappingController(state);
        await tester.pumpWidget(_wrap(controller));
        await tester.pumpAndSettle();

        // The Dana row's select should offer l2 but NOT l1 — l1 is filtered
        // by the screen (where m.pluralkitUuid == null).
        final selects = _selectsFor(tester);
        final pkSelect = selects.first;
        final values = pkSelect.items.map((i) => i.value).toList();
        expect(values, contains('l2'));
        expect(
          values,
          isNot(contains('l1')),
          reason: 'Already-linked locals must not appear as link targets',
        );
      },
    );
  });

  group('PkMappingScreen — apply results', () {
    testWidgets('per-item errors are surfaced in the results summary', (
      tester,
    ) async {
      final pkAlice = _pk('pk-alice', 'Alice');
      final pkBob = _pk('pk-bob', 'Bob');
      final locals = [_local('l1', 'Alice'), _local('l2', 'Bob')];

      final state = PkMappingState(
        pkMembers: [pkAlice, pkBob],
        localMembers: locals,
        decisionsByPkUuid: {
          pkAlice.uuid: PkLinkDecision(localMemberId: 'l1', pkMember: pkAlice),
          pkBob.uuid: PkImportDecision(pkMember: pkBob),
        },
      );

      final failingResults = <PkApplyResult>[
        PkApplyResult(
          decision: PkLinkDecision(localMemberId: 'l1', pkMember: pkAlice),
          outcome: PkApplyOutcome.applied,
        ),
        PkApplyResult(
          decision: PkImportDecision(pkMember: pkBob),
          outcome: PkApplyOutcome.failed,
          error: 'boom: network unreachable',
        ),
      ];

      final controller = _FakePkMappingController(
        state,
        appliedResults: failingResults,
      );
      await tester.pumpWidget(_wrap(controller));
      await tester.pumpAndSettle();

      final applyFinder = find.text('Apply');
      await tester.ensureVisible(applyFinder);
      await tester.tap(applyFinder);
      await tester.pumpAndSettle();

      // Summary line includes counts.
      expect(find.textContaining('1 linked'), findsOneWidget);
      expect(find.textContaining('1 failed'), findsOneWidget);

      // Error bullet from the failing decision.
      expect(
        find.textContaining('boom: network unreachable'),
        findsOneWidget,
        reason: 'Per-item error message must appear in the failures list',
      );
      // Errors header visible.
      expect(find.text('Errors'), findsOneWidget);
    });

    // NOTE: idempotency-on-retry is tested at the applier level in
    // `pk_mapping_applier_test.dart` ("retry: failed → successful on second
    // run"). A widget-level test against a fake controller would be
    // tautological, so it's intentionally omitted here.
  });

  group('PkMappingScreen — local row state transitions', () {
    testWidgets(
      'switching a Push row to Skip calls setLocalDecision with a PkSkipDecision',
      (tester) async {
        final local = _local('l1', 'Alice');
        final state = PkMappingState(
          pkMembers: const [],
          localMembers: [local],
          decisionsByLocalId: {
            'l1': const PkPushNewDecision(localMemberId: 'l1'),
          },
        );

        final controller = _FakePkMappingController(state);
        await tester.pumpWidget(_wrap(controller));
        await tester.pumpAndSettle();

        // Find the local-row select (value 'push').
        final selects = _selectsFor(tester);
        final localSelect = selects.firstWhere((s) => s.value == 'push');

        // Invoke onChanged directly — the real dropdown UI uses a menu route
        // that's awkward to drive in a widget test, but the select's public
        // onChanged callback is what the menu ultimately calls.
        localSelect.onChanged('skip');
        await tester.pumpAndSettle();

        expect(controller.localDecisionCalls, hasLength(1));
        final call = controller.localDecisionCalls.single;
        expect(call.localId, 'l1');
        expect(call.decision, isA<PkSkipDecision>());
        expect((call.decision as PkSkipDecision).localMemberId, 'l1');
      },
    );
  });

  group('PkMappingScreen — build error retry', () {
    testWidgets('tapping Retry in the error view invokes controller.retry()', (
      tester,
    ) async {
      final controller = _ErroringPkMappingController();
      await tester.pumpWidget(_wrap(controller));
      await tester.pumpAndSettle();

      // Error view should be visible with a Retry button.
      expect(
        find.textContaining('Failed to load PluralKit members'),
        findsOneWidget,
      );

      final retryFinder = find.text('Retry');
      expect(retryFinder, findsOneWidget);
      await tester.tap(retryFinder);
      await tester.pumpAndSettle();

      expect(
        controller.retryCallCount,
        greaterThanOrEqualTo(1),
        reason: 'Retry tap must invoke controller.retry()',
      );
    });
  });

  // -- Post-apply status ------------------------------------------------------

  group('PkMappingScreen — post-apply status', () {
    testWidgets('phase=importingSwitches renders statusText above the button '
        'while keeping the Apply label', (tester) async {
      final pkAlice = _pk('pk-alice', 'Alice');
      final locals = [_local('l1', 'Alice')];

      final state = PkMappingState(
        pkMembers: [pkAlice],
        localMembers: locals,
        decisionsByPkUuid: {
          pkAlice.uuid: PkLinkDecision(localMemberId: 'l1', pkMember: pkAlice),
        },
        isApplying: true,
        applyProgress: 0.42,
        phase: PkMappingPhase.importingSwitches,
        statusText: 'Importing switch history…',
      );

      final controller = _FakePkMappingController(state);
      await tester.pumpWidget(_wrap(controller));
      // pumpAndSettle would loop forever — LinearProgressIndicator
      // animates continuously while isApplying=true. One pump is enough
      // to lay out the tree.
      await tester.pump();

      // Status text is rendered above the button.
      expect(find.text('Importing switch history…'), findsOneWidget);

      // The Apply button widget retains its 'Apply' label property even
      // while loading (PrismButton swaps the rendered Text for a spinner
      // but the label property is unchanged). Phase info lives in the
      // status text widget above, never on the button.
      final applyButton = tester.widget<PrismButton>(
        find.byWidgetPredicate((w) => w is PrismButton && w.label == 'Apply'),
      );
      expect(applyButton.label, 'Apply');
    });

    testWidgets(
      'phase=pushingSwitches also renders statusText with stable button label',
      (tester) async {
        final pkAlice = _pk('pk-alice', 'Alice');
        final locals = [_local('l1', 'Alice')];

        final state = PkMappingState(
          pkMembers: [pkAlice],
          localMembers: locals,
          decisionsByPkUuid: {
            pkAlice.uuid: PkLinkDecision(
              localMemberId: 'l1',
              pkMember: pkAlice,
            ),
          },
          isApplying: true,
          applyProgress: 0.0,
          phase: PkMappingPhase.pushingSwitches,
          statusText: 'Pushing switch updates to PluralKit…',
        );

        final controller = _FakePkMappingController(state);
        await tester.pumpWidget(_wrap(controller));
        await tester.pump();

        expect(
          find.text('Pushing switch updates to PluralKit…'),
          findsOneWidget,
        );
        final applyButton = tester.widget<PrismButton>(
          find.byWidgetPredicate((w) => w is PrismButton && w.label == 'Apply'),
        );
        expect(applyButton.label, 'Apply');
      },
    );

    testWidgets(
      'no statusText is rendered when not applying, even with a phase set',
      (tester) async {
        final pkAlice = _pk('pk-alice', 'Alice');
        final locals = [_local('l1', 'Alice')];

        // Pre-apply: phase defaults to applyingDecisions, statusText is null.
        final state = PkMappingState(
          pkMembers: [pkAlice],
          localMembers: locals,
          decisionsByPkUuid: {
            pkAlice.uuid: PkLinkDecision(
              localMemberId: 'l1',
              pkMember: pkAlice,
            ),
          },
        );

        final controller = _FakePkMappingController(state);
        await tester.pumpWidget(_wrap(controller));
        await tester.pumpAndSettle();

        // Neither status string should be visible while idle.
        expect(find.text('Importing switch history…'), findsNothing);
        expect(find.text('Pushing switch updates to PluralKit…'), findsNothing);
        // The Apply button is enabled (not loading) when not applying.
        expect(find.text('Apply'), findsOneWidget);
      },
    );

    testWidgets('Apply button stays disabled across all three phases', (
      tester,
    ) async {
      final pkAlice = _pk('pk-alice', 'Alice');
      final locals = [_local('l1', 'Alice')];

      Future<PrismButton> pumpAndGetApplyButton(
        PkMappingPhase phase, {
        String? statusText,
      }) async {
        final state = PkMappingState(
          pkMembers: [pkAlice],
          localMembers: locals,
          decisionsByPkUuid: {
            pkAlice.uuid: PkLinkDecision(
              localMemberId: 'l1',
              pkMember: pkAlice,
            ),
          },
          isApplying: true,
          applyProgress: 0.0,
          phase: phase,
          statusText: statusText,
        );
        final controller = _FakePkMappingController(state);
        await tester.pumpWidget(_wrap(controller));
        // pumpAndSettle hangs on the spinning LinearProgressIndicator.
        await tester.pump();

        // PrismButton swaps its label for a PrismSpinner when isLoading, so
        // find.text('Apply') is empty during apply. Match by the label
        // property on the PrismButton widget itself instead.
        return tester.widget<PrismButton>(
          find.byWidgetPredicate((w) => w is PrismButton && w.label == 'Apply'),
        );
      }

      // Phase 1 — applyingDecisions: no statusText set yet, but button is
      // disabled because isApplying = true.
      final applyButton1 = await pumpAndGetApplyButton(
        PkMappingPhase.applyingDecisions,
      );
      expect(applyButton1.enabled, isFalse);
      expect(applyButton1.isLoading, isTrue);

      // Phase 2 — importingSwitches: button still disabled, statusText shown.
      final applyButton2 = await pumpAndGetApplyButton(
        PkMappingPhase.importingSwitches,
        statusText: 'Importing switch history…',
      );
      expect(applyButton2.enabled, isFalse);
      expect(applyButton2.isLoading, isTrue);

      // Phase 3 — pushingSwitches: same invariant.
      final applyButton3 = await pumpAndGetApplyButton(
        PkMappingPhase.pushingSwitches,
        statusText: 'Pushing switch updates to PluralKit…',
      );
      expect(applyButton3.enabled, isFalse);
      expect(applyButton3.isLoading, isTrue);
    });

    testWidgets(
      'tapping Apply forwards the localized phase strings to the controller',
      (tester) async {
        final pkAlice = _pk('pk-alice', 'Alice');
        final locals = [_local('l1', 'Alice')];

        final state = PkMappingState(
          pkMembers: [pkAlice],
          localMembers: locals,
          decisionsByPkUuid: {
            pkAlice.uuid: PkLinkDecision(
              localMemberId: 'l1',
              pkMember: pkAlice,
            ),
          },
        );

        final controller = _FakePkMappingController(state);
        await tester.pumpWidget(_wrap(controller));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();

        // The screen reads the strings from AppLocalizations and forwards them
        // via the named params. Verify the controller saw the expected values.
        expect(controller.applyCallCount, 1);
        expect(
          controller.lastImportingHistoryStatus,
          'Importing switch history…',
        );
        expect(
          controller.lastPushingHistoryStatus,
          'Pushing switch updates to PluralKit…',
        );
      },
    );
  });

  group('PkMappingScreen — large text scale layout', () {
    // Regression: at Dynamic Type "Larger Accessibility" sizes the row used to
    // lay out as [Expanded(name) | SizedBox(180, select) | search]. The fixed
    // 180px select crushed the Expanded name column on a phone-width screen,
    // wrapping the scaled-up name one character per line. The row should now
    // stack vertically (name on top, controls below) once text scale crosses
    // ~1.3x.

    Future<void> setLargeText(WidgetTester tester) async {
      // Tall viewport so the lazy ListView builds every section even at
      // 2.5x text scale (where each row takes a lot of vertical space).
      tester.view.physicalSize = const Size(390 * 2, 4000 * 2);
      tester.view.devicePixelRatio = 2.0;
      tester.platformDispatcher.textScaleFactorTestValue = 2.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
    }

    testWidgets(
      'PK row stacks the select below the name at large text scale',
      (tester) async {
        await setLargeText(tester);

        final pkAlice = _pk('pk-alice', 'Alice');
        final locals = [_local('l1', 'Alice')];
        final state = PkMappingState(
          pkMembers: [pkAlice],
          localMembers: locals,
          decisionsByPkUuid: {
            pkAlice.uuid: PkImportDecision(pkMember: pkAlice),
          },
        );

        final controller = _FakePkMappingController(state);
        await tester.pumpWidget(_wrap(controller));
        await tester.pumpAndSettle();

        // Find the PK member name Text and the select inside its row.
        // At large scale the select must sit BELOW the name (top of select
        // >= bottom of name), proving the row didn't squeeze the name.
        final nameFinder = find.text('Alice').first;
        final selectFinder = find.byType(PrismSelect<String>).first;

        final nameRect = tester.getRect(nameFinder);
        final selectRect = tester.getRect(selectFinder);

        expect(
          selectRect.top,
          greaterThanOrEqualTo(nameRect.bottom),
          reason:
              'At large text scale the select must stack below the name, '
              'not sit beside an Expanded column that gets crushed to one '
              'character wide.',
        );
      },
    );

    testWidgets(
      'local row stacks the select below the name at large text scale',
      (tester) async {
        await setLargeText(tester);

        final local = _local('l1', 'Alice');
        final state = PkMappingState(
          pkMembers: const [],
          localMembers: [local],
          decisionsByLocalId: {
            'l1': const PkPushNewDecision(localMemberId: 'l1'),
          },
        );

        final controller = _FakePkMappingController(state);
        await tester.pumpWidget(_wrap(controller));
        await tester.pumpAndSettle();

        final nameFinder = find.text('Alice').first;
        final selectFinder = find.byType(PrismSelect<String>).first;

        final nameRect = tester.getRect(nameFinder);
        final selectRect = tester.getRect(selectFinder);

        expect(
          selectRect.top,
          greaterThanOrEqualTo(nameRect.bottom),
          reason:
              'Local-member row must stack vertically at large text scale.',
        );
      },
    );

    testWidgets(
      'PK row stays side-by-side at default text scale',
      (tester) async {
        // No textScaleFactor override → default 1.0.
        tester.view.physicalSize = const Size(390 * 2, 844 * 2);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final pkAlice = _pk('pk-alice', 'Alice');
        final state = PkMappingState(
          pkMembers: [pkAlice],
          localMembers: [_local('l1', 'Bob')],
          decisionsByPkUuid: {
            pkAlice.uuid: PkImportDecision(pkMember: pkAlice),
          },
        );

        final controller = _FakePkMappingController(state);
        await tester.pumpWidget(_wrap(controller));
        await tester.pumpAndSettle();

        // At normal scale the select must sit to the RIGHT of the name —
        // i.e. its left edge is greater than the name's right edge.
        final nameFinder = find.text('Alice').first;
        final selectFinder = find.byType(PrismSelect<String>).first;

        final nameRect = tester.getRect(nameFinder);
        final selectRect = tester.getRect(selectFinder);

        expect(
          selectRect.left,
          greaterThan(nameRect.right),
          reason:
              'At default text scale the layout must remain side-by-side, '
              'preserving the original compact design.',
        );
      },
    );
  });
}
