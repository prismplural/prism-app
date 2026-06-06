import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/database_encryption.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/models/member.dart' as domain;
import 'package:prism_plurality/features/pluralkit/models/pk_models.dart';
import 'package:prism_plurality/features/pluralkit/models/pk_sync_config.dart';
import 'package:prism_plurality/features/pluralkit/providers/pk_mapping_controller.dart';
import 'package:prism_plurality/features/pluralkit/providers/pluralkit_providers.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_mapping_applier.dart';
import 'package:prism_plurality/features/pluralkit/services/pluralkit_sync_service.dart';
import 'package:prism_plurality/features/pluralkit/views/pk_mapping_screen.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_fronter_choice_card.dart';
import 'package:prism_plurality/features/pluralkit/widgets/pk_who_is_fronting_sheet.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

import '../../../helpers/fake_repositories.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

PKSwitch _emptySwitch() =>
    PKSwitch(id: 'sw-test', timestamp: DateTime(2026), members: const []);

domain.Member _localMember(String id, String name) =>
    domain.Member(id: id, name: name, createdAt: DateTime(2026));

// ---------------------------------------------------------------------------
// Fake PluralKitSyncNotifier: returns disconnected state so profile disclosure
// guard short-circuits (syncState.isConnected == false).
// ---------------------------------------------------------------------------

class _FakeSyncNotifier extends PluralKitSyncNotifier {
  @override
  PluralKitSyncState build() => const PluralKitSyncState(isConnected: false);

  @override
  Future<PKSystem?> fetchSystemProfile() async => null;
}

// ---------------------------------------------------------------------------
// Fake controllers
// ---------------------------------------------------------------------------

/// A fake [PkMappingController] that lets tests stage the outcome returned by [apply].
class _OutcomeFakePkMappingController extends PkMappingController {
  _OutcomeFakePkMappingController({
    required PkMappingState initialState,
    required this.applyOutcome,
    this.resolutionOutcome = const PkMappingApplyOutcomeApplied(),
  }) : _initialState = initialState;

  final PkMappingState _initialState;
  final PkMappingApplyOutcome? applyOutcome;
  final PkMappingApplyOutcome? resolutionOutcome;

  // Spy counters.
  int applyCallCount = 0;
  int applyFronterResolutionCallCount = 0;
  int deferBootstrapCallCount = 0;
  Set<String>? lastChosenLocalMemberIds;
  String? lastResolvingFrontersStatus;

  @override
  Future<PkMappingState> build() async => _initialState;

  @override
  Future<PkMappingApplyOutcome?> apply({
    String? importingHistoryStatus,
    String? pushingHistoryStatus,
    String? offlineErrorMessage,
  }) async {
    applyCallCount++;
    return applyOutcome;
  }

  @override
  Future<PkMappingApplyOutcome?> applyFronterResolution({
    required Set<String> chosenLocalMemberIds,
    required PkSyncDirection direction,
    required PkSyncMode mode,
    required PKSwitch pkCurrentSwitch,
    String? resolvingFrontersStatus,
    String? importingHistoryStatus,
    String? pushingHistoryStatus,
  }) async {
    applyFronterResolutionCallCount++;
    lastChosenLocalMemberIds = chosenLocalMemberIds;
    lastResolvingFrontersStatus = resolvingFrontersStatus;
    return resolutionOutcome;
  }

  @override
  Future<void> deferBootstrap() async {
    deferBootstrapCallCount++;
  }

  @override
  void dismiss() {}

  @override
  void retry() {}
}

// ---------------------------------------------------------------------------
// State + repo factories
// ---------------------------------------------------------------------------

PKMember _pkAlice() =>
    const PKMember(id: 'alice', uuid: 'pk-alice-uuid', name: 'Alice');

PkMappingState _minimalState() {
  final pkAlice = _pkAlice();
  return PkMappingState(
    pkMembers: [pkAlice],
    localMembers: [_localMember('l1', 'Alice Local')],
    decisionsByPkUuid: {'pk-alice-uuid': PkImportDecision(pkMember: pkAlice)},
  );
}

FakeMemberRepository _seededMemberRepo() {
  final repo = FakeMemberRepository();
  repo.seed([
    _localMember('l1', 'Alice Local'),
    _localMember('l2', 'Bob Local'),
  ]);
  return repo;
}

// ---------------------------------------------------------------------------
// Wrapper that nests the mapping screen inside a pushable route so we can
// observe Navigator.pop() calls.
// ---------------------------------------------------------------------------

Widget _wrapWithRoute(
  _OutcomeFakePkMappingController controller, {
  void Function()? onPopped,
  FakeMemberRepository? memberRepo,
}) {
  final repo = memberRepo ?? _seededMemberRepo();
  return ProviderScope(
    overrides: [
      // §4 verifiedStartupKeyProvider throws by default; widget tests don't
      // run the boot probe.
      verifiedStartupKeyProvider.overrideWithValue('aa' * 32),
      pkMappingControllerProvider.overrideWith(() => controller),
      memberRepositoryProvider.overrideWithValue(repo),
      pluralKitSyncProvider.overrideWith(_FakeSyncNotifier.new),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Builder(
        builder: (ctx) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              await Navigator.of(ctx).push<void>(
                MaterialPageRoute(builder: (_) => const PkMappingScreen()),
              );
              onPopped?.call();
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // -------------------------------------------------------------------------
  // (a) Applied → screen pops; sheet NOT pushed
  // -------------------------------------------------------------------------
  group('outcome: Applied', () {
    testWidgets('pops back after Applied outcome; no sheet shown', (
      tester,
    ) async {
      final controller = _OutcomeFakePkMappingController(
        initialState: _minimalState(),
        applyOutcome: const PkMappingApplyOutcomeApplied(),
      );

      var popped = false;
      await tester.pumpWidget(
        _wrapWithRoute(controller, onPopped: () => popped = true),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(PrismButton, 'Apply'));
      await tester.pumpAndSettle();

      expect(popped, isTrue, reason: 'Applied outcome should pop the screen');
      expect(
        find.byType(PkWhoIsFrontingSheet),
        findsNothing,
        reason: 'No resolution sheet should appear for Applied outcome',
      );
      expect(controller.applyCallCount, 1);
      expect(controller.applyFronterResolutionCallCount, 0);
    });
  });

  // -------------------------------------------------------------------------
  // (b) NeedsFronterResolution → sheet shown; pick a set → applyFronterResolution
  // -------------------------------------------------------------------------
  group('outcome: NeedsFronterResolution — pick a set', () {
    testWidgets(
      'pushes PkWhoIsFrontingSheet; picking a card calls applyFronterResolution and pops',
      (tester) async {
        final pkSwitch = _emptySwitch();
        final controller = _OutcomeFakePkMappingController(
          initialState: _minimalState(),
          applyOutcome: PkMappingApplyOutcomeNeedsFronterResolution(
            localFronterMemberIds: {'l1'},
            pkFronterMemberIds: {'l2'},
            direction: PkSyncDirection.bidirectional,
            mode: PkSyncMode.fullSync,
            pkCurrentSwitch: pkSwitch,
          ),
        );

        var popped = false;
        await tester.pumpWidget(
          _wrapWithRoute(controller, onPopped: () => popped = true),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(PrismButton, 'Apply'));
        await tester.pumpAndSettle();

        expect(
          find.byType(PkWhoIsFrontingSheet),
          findsOneWidget,
          reason: 'Resolution sheet should appear for NeedsFronterResolution',
        );

        final choiceCards = find.byType(PkFronterChoiceCard);
        expect(
          choiceCards,
          findsWidgets,
          reason: 'At least one fronter choice card should be shown',
        );

        await tester.tap(choiceCards.first);
        await tester.pumpAndSettle();

        expect(
          controller.applyFronterResolutionCallCount,
          1,
          reason:
              'applyFronterResolution should be called once after the user picks',
        );
        expect(
          controller.lastResolvingFrontersStatus,
          'Resolving fronter choice…',
        );
        expect(controller.deferBootstrapCallCount, 0);
        expect(
          popped,
          isTrue,
          reason: 'Screen should pop after fronter resolution',
        );
      },
    );

    testWidgets(
      'keeps the mapping screen open when fronter resolution returns null',
      (tester) async {
        final pkSwitch = _emptySwitch();
        final controller = _OutcomeFakePkMappingController(
          initialState: _minimalState().copyWith(error: 'Resolution failed'),
          applyOutcome: PkMappingApplyOutcomeNeedsFronterResolution(
            localFronterMemberIds: {'l1'},
            pkFronterMemberIds: {'l2'},
            direction: PkSyncDirection.bidirectional,
            mode: PkSyncMode.fullSync,
            pkCurrentSwitch: pkSwitch,
          ),
          resolutionOutcome: null,
        );

        var popped = false;
        await tester.pumpWidget(
          _wrapWithRoute(controller, onPopped: () => popped = true),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(PrismButton, 'Apply'));
        await tester.pumpAndSettle();

        final choiceCards = find.byType(PkFronterChoiceCard);
        expect(choiceCards, findsWidgets);

        await tester.tap(choiceCards.first);
        await tester.pumpAndSettle();

        expect(controller.applyFronterResolutionCallCount, 1);
        expect(popped, isFalse);
        expect(find.byType(PkMappingScreen), findsOneWidget);
      },
    );
  });

  // -------------------------------------------------------------------------
  // (c) NeedsFronterResolution → "Decide later" → deferBootstrap, pop
  // -------------------------------------------------------------------------
  group('outcome: NeedsFronterResolution — Decide later', () {
    testWidgets(
      '"Decide later" calls deferBootstrap and pops; applyFronterResolution NOT called',
      (tester) async {
        final pkSwitch = _emptySwitch();
        final controller = _OutcomeFakePkMappingController(
          initialState: _minimalState(),
          applyOutcome: PkMappingApplyOutcomeNeedsFronterResolution(
            localFronterMemberIds: {'l1'},
            pkFronterMemberIds: {'l2'},
            direction: PkSyncDirection.bidirectional,
            mode: PkSyncMode.fullSync,
            pkCurrentSwitch: pkSwitch,
          ),
        );

        var popped = false;
        await tester.pumpWidget(
          _wrapWithRoute(controller, onPopped: () => popped = true),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(PrismButton, 'Apply'));
        await tester.pumpAndSettle();

        expect(
          find.byType(PkWhoIsFrontingSheet),
          findsOneWidget,
          reason: 'Sheet should be shown',
        );

        // Tap "Decide later".
        await tester.tap(find.widgetWithText(PrismButton, 'Decide later'));
        await tester.pumpAndSettle();

        expect(
          controller.deferBootstrapCallCount,
          1,
          reason: '"Decide later" should call deferBootstrap',
        );
        expect(
          controller.applyFronterResolutionCallCount,
          0,
          reason: 'applyFronterResolution must NOT be called on "Decide later"',
        );
        expect(
          popped,
          isTrue,
          reason: 'Screen should pop after "Decide later"',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // (d) Failed → failure UI shown; screen does NOT pop
  // -------------------------------------------------------------------------
  group('outcome: Failed', () {
    testWidgets('Failed outcome keeps the screen open', (tester) async {
      final pkAlice = _pkAlice();
      final failedResult = PkApplyResult(
        decision: PkImportDecision(pkMember: pkAlice),
        outcome: PkApplyOutcome.failed,
        error: 'Network timeout',
      );

      final controller = _OutcomeFakePkMappingController(
        initialState: _minimalState().copyWith(lastResults: [failedResult]),
        applyOutcome: PkMappingApplyOutcomeFailed([failedResult]),
      );

      var popped = false;
      await tester.pumpWidget(
        _wrapWithRoute(controller, onPopped: () => popped = true),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(PrismButton, 'Apply'));
      await tester.pumpAndSettle();

      expect(find.byType(PkMappingScreen), findsOneWidget);
      expect(popped, isFalse, reason: 'Failed outcome must NOT pop the screen');
      expect(find.byType(PkWhoIsFrontingSheet), findsNothing);
      expect(controller.applyCallCount, 1);
    });
  });

  // -------------------------------------------------------------------------
  // (e) Null outcome → screen stays, no crash
  // -------------------------------------------------------------------------
  group('outcome: null', () {
    testWidgets('null outcome keeps the screen open without throwing', (
      tester,
    ) async {
      final controller = _OutcomeFakePkMappingController(
        initialState: _minimalState().copyWith(error: 'Something went wrong'),
        applyOutcome: null,
      );

      var popped = false;
      await tester.pumpWidget(
        _wrapWithRoute(controller, onPopped: () => popped = true),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(PrismButton, 'Apply'));
      await tester.pumpAndSettle();

      expect(find.byType(PkMappingScreen), findsOneWidget);
      expect(popped, isFalse, reason: 'Null outcome must NOT pop the screen');
      expect(find.byType(PkWhoIsFrontingSheet), findsNothing);
      expect(controller.applyCallCount, 1);
    });
  });
}
