import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/onboarding/providers/sync_setup_progress_provider.dart';
import 'package:prism_plurality/features/onboarding/widgets/live_count_card.dart';
import 'package:prism_plurality/features/onboarding/widgets/phase_segments.dart';
import 'package:prism_plurality/features/onboarding/widgets/prism_shimmer_bar.dart';
import 'package:prism_plurality/features/onboarding/widgets/sync_progress_view.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';

// ---------------------------------------------------------------------------
// Fake notifier that lets tests inject state directly.
// ---------------------------------------------------------------------------

class FakeSyncSetupProgressNotifier extends SyncSetupProgressNotifier {
  @override
  SyncSetupProgressState build() {
    return SyncSetupProgressState.initial(DateTime.now());
  }

  // ignore: use_setters_to_change_properties
  void setStateForTest(SyncSetupProgressState s) {
    state = s;
  }
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

// A stub record for terminologySettingProvider that avoids Drift.
const _stubTerminology = (
  term: SystemTerminology.headmates,
  customSingular: null as String?,
  customPlural: null as String?,
  useEnglish: false,
);

Widget _wrap(
  Widget child, {
  FakeSyncSetupProgressNotifier? notifier,
  bool disableAnimations = false,
}) {
  final fakeNotifier = notifier ?? FakeSyncSetupProgressNotifier();
  return ProviderScope(
    overrides: [
      syncSetupProgressProvider.overrideWith(() => fakeNotifier),
      // Override terminology to avoid activating the Drift-backed
      // systemSettingsProvider, which leaves pending timers in tests.
      terminologySettingProvider.overrideWithValue(_stubTerminology),
    ],
    child: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          backgroundColor: const Color(0xFF1A1612),
          body: child,
        ),
      ),
    ),
  );
}

SyncSetupProgressState _stateForPhase(
  PairingProgressPhase phase, {
  Map<String, int> liveCounts = const {},
  bool timedOut = false,
  bool wsConnected = true,
  DateTime? phaseStartedAt,
}) {
  return SyncSetupProgressState(
    phase: phase,
    liveCounts: liveCounts,
    phaseStartedAt: phaseStartedAt ?? DateTime.now(),
    timedOut: timedOut,
    wsConnected: wsConnected,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SyncProgressView', () {
    testWidgets(
      'phase 0 (connecting) renders PrismSpinner and connect title/subtitle',
      (tester) async {
        final notifier = FakeSyncSetupProgressNotifier();
        await tester.pumpWidget(_wrap(const SyncProgressView(), notifier: notifier));

        notifier.setStateForTest(
          _stateForPhase(PairingProgressPhase.connecting),
        );
        await tester.pump();

        expect(find.byType(PrismSpinner), findsOneWidget);
        expect(find.byType(PrismShimmerBar), findsNothing);
        expect(find.text('Connecting…'), findsOneWidget);
        expect(find.text('Saying hello to your other device'), findsOneWidget);
      },
    );

    testWidgets(
      'phase 1 (downloading) renders PrismShimmerBar and download title',
      (tester) async {
        final notifier = FakeSyncSetupProgressNotifier();
        // Use disableAnimations so AnimatedSwitcher transitions instantly.
        await tester.pumpWidget(
          _wrap(
            const SyncProgressView(),
            notifier: notifier,
            disableAnimations: true,
          ),
        );

        notifier.setStateForTest(
          _stateForPhase(PairingProgressPhase.downloading),
        );
        await tester.pump();

        expect(find.byType(PrismShimmerBar), findsOneWidget);
        expect(find.byType(PrismSpinner), findsNothing);
        expect(find.text('Downloading your system'), findsOneWidget);
      },
    );

    testWidgets(
      'phase 2 (restoring) renders PrismShimmerBar and restore title',
      (tester) async {
        final notifier = FakeSyncSetupProgressNotifier();
        // Use disableAnimations so AnimatedSwitcher transitions instantly.
        await tester.pumpWidget(
          _wrap(
            const SyncProgressView(),
            notifier: notifier,
            disableAnimations: true,
          ),
        );

        notifier.setStateForTest(
          _stateForPhase(PairingProgressPhase.restoring),
        );
        await tester.pump();

        expect(find.byType(PrismShimmerBar), findsOneWidget);
        expect(find.byType(PrismSpinner), findsNothing);
        expect(find.text('Restoring your data'), findsOneWidget);
      },
    );

    testWidgets('phase 3 (finishing) renders PrismSpinner', (tester) async {
      final notifier = FakeSyncSetupProgressNotifier();
      await tester.pumpWidget(_wrap(const SyncProgressView(), notifier: notifier));

      notifier.setStateForTest(
        _stateForPhase(PairingProgressPhase.finishing),
      );
      await tester.pump();

      expect(find.byType(PrismSpinner), findsOneWidget);
      expect(find.byType(PrismShimmerBar), findsNothing);
    });

    testWidgets(
      'LiveCountCard is wrapped in Hero with sync-progress-count-card tag',
      (tester) async {
        final notifier = FakeSyncSetupProgressNotifier();
        await tester.pumpWidget(_wrap(const SyncProgressView(), notifier: notifier));
        await tester.pump();

        final heroFinder = find.byWidgetPredicate(
          (widget) =>
              widget is Hero && widget.tag == 'sync-progress-count-card',
        );
        expect(heroFinder, findsOneWidget);

        // Verify LiveCountCard is a descendant of the Hero.
        final heroElement = tester.element(heroFinder);
        final countCardFinder = find.descendant(
          of: find.byElementPredicate((e) => e == heroElement),
          matching: find.byType(LiveCountCard),
        );
        expect(countCardFinder, findsOneWidget);
      },
    );

    testWidgets(
      'wsConnected=false in phase=downloading swaps subtitle to Reconnecting',
      (tester) async {
        final notifier = FakeSyncSetupProgressNotifier();
        await tester.pumpWidget(_wrap(const SyncProgressView(), notifier: notifier));

        notifier.setStateForTest(
          _stateForPhase(
            PairingProgressPhase.downloading,
            wsConnected: false,
          ),
        );
        await tester.pump();

        expect(find.text('Reconnecting to the relay…'), findsOneWidget);
        expect(find.text('Pulling the encrypted snapshot'), findsNothing);
      },
    );

    testWidgets(
      'timedOut=true in phase=finishing swaps subtitle to still-pulling copy',
      (tester) async {
        final notifier = FakeSyncSetupProgressNotifier();
        await tester.pumpWidget(_wrap(const SyncProgressView(), notifier: notifier));

        notifier.setStateForTest(
          _stateForPhase(
            PairingProgressPhase.finishing,
            timedOut: true,
          ),
        );
        await tester.pump();

        expect(
          find.text(
            'Still pulling updates in the background. You can continue.',
          ),
          findsOneWidget,
        );
        expect(find.text('Locking things in for good'), findsNothing);
      },
    );

    testWidgets(
      'all-zero liveCounts during restoring after 2s shows no-data-to-restore',
      (tester) async {
        final notifier = FakeSyncSetupProgressNotifier();
        await tester.pumpWidget(_wrap(const SyncProgressView(), notifier: notifier));

        // Pre-seed phaseStartedAt 3 seconds in the past so the 2s threshold is met.
        notifier.setStateForTest(
          _stateForPhase(
            PairingProgressPhase.restoring,
            liveCounts: {},
            phaseStartedAt: DateTime.now().subtract(const Duration(seconds: 3)),
          ),
        );
        await tester.pump();

        expect(
          find.text('No prior data to restore — starting fresh.'),
          findsOneWidget,
        );
        expect(find.text('Unpacking headmates, messages, and notes'), findsNothing);
      },
    );

    testWidgets(
      '30s in-phase shows reassurance; transition clears it',
      (tester) async {
        final notifier = FakeSyncSetupProgressNotifier();
        await tester.pumpWidget(_wrap(const SyncProgressView(), notifier: notifier));

        // Set phase started 31 seconds ago — should show reassurance.
        notifier.setStateForTest(
          _stateForPhase(
            PairingProgressPhase.downloading,
            phaseStartedAt:
                DateTime.now().subtract(const Duration(seconds: 31)),
          ),
        );
        await tester.pump();

        expect(
          find.text(
            'Still going — larger systems can take a minute on slow networks.',
          ),
          findsOneWidget,
        );

        // Transition to a new phase (phaseStartedAt = now → <30s elapsed).
        notifier.setStateForTest(
          _stateForPhase(
            PairingProgressPhase.restoring,
            phaseStartedAt: DateTime.now(),
          ),
        );
        await tester.pump();

        expect(
          find.text(
            'Still going — larger systems can take a minute on slow networks.',
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'disableAnimations=true: no running animations in the whole view',
      (tester) async {
        final notifier = FakeSyncSetupProgressNotifier();
        await tester.pumpWidget(
          _wrap(
            const SyncProgressView(),
            notifier: notifier,
            disableAnimations: true,
          ),
        );

        notifier.setStateForTest(
          _stateForPhase(PairingProgressPhase.downloading),
        );
        await tester.pump();

        // With disableAnimations, the AnimatedSwitcher uses Duration.zero and
        // PrismShimmerBar stops its controller. The frame should settle without
        // pending animations.
        await tester.pumpAndSettle();

        // No assertion on animation internals — just verify the tree renders
        // without errors and the right widgets are shown.
        expect(find.byType(PrismShimmerBar), findsOneWidget);
        expect(find.byType(SyncProgressView), findsOneWidget);
      },
    );

    testWidgets('phase title has liveRegion semantics', (tester) async {
      final notifier = FakeSyncSetupProgressNotifier();
      await tester.pumpWidget(_wrap(const SyncProgressView(), notifier: notifier));

      notifier.setStateForTest(
        _stateForPhase(PairingProgressPhase.connecting),
      );
      await tester.pump();

      // Find a Semantics node with liveRegion: true that contains the phase title.
      final semanticsFinder = find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.liveRegion == true,
      );
      expect(semanticsFinder, findsAtLeastNWidgets(1));

      // The phase title text should be a descendant of a liveRegion node.
      final titleInsideLiveRegion = find.descendant(
        of: semanticsFinder,
        matching: find.text('Connecting…'),
      );
      expect(titleInsideLiveRegion, findsOneWidget);
    });

    testWidgets('PhaseSegments renders with correct currentIndex', (
      tester,
    ) async {
      final notifier = FakeSyncSetupProgressNotifier();
      await tester.pumpWidget(_wrap(const SyncProgressView(), notifier: notifier));

      notifier.setStateForTest(
        _stateForPhase(PairingProgressPhase.restoring),
      );
      await tester.pump();

      final segments = tester.widget<PhaseSegments>(
        find.byType(PhaseSegments),
      );
      expect(segments.currentIndex, equals(PairingProgressPhase.restoring.index));
      expect(segments.totalPhases, equals(4));
    });
  });
}
