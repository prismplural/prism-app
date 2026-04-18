import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_mapping_controller.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_mapping_applier.dart';
import 'package:prism_plurality/features/pluralkit/views/pk_mapping_screen.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
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

  final List<_LocalDecisionCall> localDecisionCalls = [];

  @override
  Future<PkMappingState> build() async => _initial;

  @override
  Future<void> apply() async {
    applyCallCount++;
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(
      isApplying: false,
      applyProgress: 1.0,
      lastResults: appliedResults ?? const [],
    ));
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
  void setLocalDecision(String localId, PkMappingDecision decision) {
    localDecisionCalls.add(_LocalDecisionCall(localId, decision));
    super.setLocalDecision(localId, decision);
  }
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

domain.Member _local(
  String id,
  String name, {
  String? pkUuid,
}) =>
    domain.Member(
      id: id,
      name: name,
      createdAt: DateTime(2026),
      pluralkitUuid: pkUuid,
    );

PKMember _pk(String uuid, String name, {String? id}) => PKMember(
      id: id ?? uuid.substring(0, 5),
      uuid: uuid,
      name: name,
    );

Widget _wrap(PkMappingController controller) {
  return ProviderScope(
    overrides: [
      pkMappingControllerProvider.overrideWith(() => controller),
    ],
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
            pkAlice.uuid: PkLinkDecision(localMemberId: 'l1', pkMember: pkAlice),
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
        final bobL1Item =
            bobSelect.items.firstWhere((i) => i.value == 'l1');
        expect(bobL1Item.enabled, isFalse,
            reason:
                'Local l1 is already consumed by the Alice link — must be '
                'disabled in Bob\'s dropdown');

        // Alice's select, by contrast, SHOULD have l1 enabled (she owns it).
        final aliceSelect = selects.firstWhere((s) => s.value == 'l1');
        final aliceL1Item =
            aliceSelect.items.firstWhere((i) => i.value == 'l1');
        expect(aliceL1Item.enabled, isTrue);
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
          decisionsByPkUuid: {
            pkDana.uuid: PkImportDecision(pkMember: pkDana),
          },
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
        expect(values, isNot(contains('l1')),
            reason: 'Already-linked locals must not appear as link targets');
      },
    );
  });

  group('PkMappingScreen — apply results', () {
    testWidgets('per-item errors are surfaced in the results summary',
        (tester) async {
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
    testWidgets(
      'tapping Retry in the error view invokes controller.retry()',
      (tester) async {
        final controller = _ErroringPkMappingController();
        await tester.pumpWidget(_wrap(controller));
        await tester.pumpAndSettle();

        // Error view should be visible with a Retry button.
        expect(find.textContaining('Failed to load PluralKit members'),
            findsOneWidget);

        final retryFinder = find.text('Retry');
        expect(retryFinder, findsOneWidget);
        await tester.tap(retryFinder);
        await tester.pumpAndSettle();

        expect(controller.retryCallCount, greaterThanOrEqualTo(1),
            reason: 'Retry tap must invoke controller.retry()');
      },
    );
  });
}
