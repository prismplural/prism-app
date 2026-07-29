import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/onboarding/providers/sync_setup_progress_provider.dart';
import 'package:prism_plurality/features/onboarding/widgets/live_count_card.dart';
import 'package:prism_plurality/features/onboarding/widgets/phase_segments.dart';
import 'package:prism_plurality/features/onboarding/widgets/prism_shimmer_bar.dart';
import 'package:prism_plurality/features/onboarding/widgets/sync_progress_view.dart';
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

Widget _wrap(
  Widget child, {
  FakeSyncSetupProgressNotifier? notifier,
  bool disableAnimations = false,
  ThemeData? theme,
}) {
  final fakeNotifier = notifier ?? FakeSyncSetupProgressNotifier();
  final resolvedTheme =
      theme ??
      ThemeData.from(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006C60)),
      );
  return ProviderScope(
    overrides: [syncSetupProgressProvider.overrideWith(() => fakeNotifier)],
    child: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: MaterialApp(
        theme: resolvedTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          backgroundColor: resolvedTheme.colorScheme.surface,
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
  int? restoreApplied,
  int? restoreTotal,
  DateTime? phaseStartedAt,
}) {
  return SyncSetupProgressState(
    phase: phase,
    liveCounts: liveCounts,
    phaseStartedAt: phaseStartedAt ?? DateTime.now(),
    timedOut: timedOut,
    wsConnected: wsConnected,
    restoreApplied: restoreApplied,
    restoreTotal: restoreTotal,
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
        await tester.pumpWidget(
          _wrap(const SyncProgressView(), notifier: notifier),
        );

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
        expect(find.text('Downloading your data'), findsOneWidget);
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

    testWidgets('restoring with applied/total renders determinate progress', (
      tester,
    ) async {
      final notifier = FakeSyncSetupProgressNotifier();
      await tester.pumpWidget(
        _wrap(
          const SyncProgressView(),
          notifier: notifier,
          disableAnimations: true,
        ),
      );

      notifier.setStateForTest(
        _stateForPhase(
          PairingProgressPhase.restoring,
          restoreApplied: 3,
          restoreTotal: 10,
        ),
      );
      await tester.pump();

      expect(find.byType(PrismShimmerBar), findsNothing);
      final progress = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(progress.value, 0.3);
      expect(
        find.text('Unpacking headmates, messages, and notes\n3 of 10'),
        findsOneWidget,
      );
    });

    testWidgets('phase 3 (finishing) renders PrismSpinner', (tester) async {
      final notifier = FakeSyncSetupProgressNotifier();
      await tester.pumpWidget(
        _wrap(const SyncProgressView(), notifier: notifier),
      );

      notifier.setStateForTest(_stateForPhase(PairingProgressPhase.finishing));
      await tester.pump();

      expect(find.byType(PrismSpinner), findsOneWidget);
      expect(find.byType(PrismShimmerBar), findsNothing);
    });

    testWidgets(
      'LiveCountCard is wrapped in Hero with sync-progress-count-card tag',
      (tester) async {
        final notifier = FakeSyncSetupProgressNotifier();
        await tester.pumpWidget(
          _wrap(const SyncProgressView(), notifier: notifier),
        );
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
        await tester.pumpWidget(
          _wrap(const SyncProgressView(), notifier: notifier),
        );

        notifier.setStateForTest(
          _stateForPhase(PairingProgressPhase.downloading, wsConnected: false),
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
        await tester.pumpWidget(
          _wrap(const SyncProgressView(), notifier: notifier),
        );

        notifier.setStateForTest(
          _stateForPhase(PairingProgressPhase.finishing, timedOut: true),
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
        await tester.pumpWidget(
          _wrap(const SyncProgressView(), notifier: notifier),
        );

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
        expect(
          find.text('Unpacking headmates, messages, and notes'),
          findsNothing,
        );
      },
    );

    testWidgets('30s in-phase shows reassurance; transition clears it', (
      tester,
    ) async {
      final notifier = FakeSyncSetupProgressNotifier();
      await tester.pumpWidget(
        _wrap(const SyncProgressView(), notifier: notifier),
      );

      // Set phase started 31 seconds ago — should show reassurance.
      notifier.setStateForTest(
        _stateForPhase(
          PairingProgressPhase.downloading,
          phaseStartedAt: DateTime.now().subtract(const Duration(seconds: 31)),
        ),
      );
      await tester.pump();

      expect(
        find.text(
          'Still going — larger restores can take a minute on slow networks.',
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
          'Still going — larger restores can take a minute on slow networks.',
        ),
        findsNothing,
      );
    });

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

        expect(find.byType(PrismShimmerBar), findsOneWidget);
        expect(find.byType(SyncProgressView), findsOneWidget);
      },
    );

    testWidgets('phase title has liveRegion semantics', (tester) async {
      final notifier = FakeSyncSetupProgressNotifier();
      await tester.pumpWidget(
        _wrap(const SyncProgressView(), notifier: notifier),
      );

      notifier.setStateForTest(_stateForPhase(PairingProgressPhase.connecting));
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
      await tester.pumpWidget(
        _wrap(const SyncProgressView(), notifier: notifier),
      );

      notifier.setStateForTest(_stateForPhase(PairingProgressPhase.restoring));
      await tester.pump();

      final segments = tester.widget<PhaseSegments>(find.byType(PhaseSegments));
      expect(
        segments.currentIndex,
        equals(PairingProgressPhase.restoring.index),
      );
      expect(segments.totalPhases, equals(4));
    });

    testWidgets(
      'uses light theme colors for spinner, text, and phase segments',
      (tester) async {
        final notifier = FakeSyncSetupProgressNotifier();
        const seed = Color(0xFF006C60);
        final colorScheme = ColorScheme.fromSeed(seedColor: seed);
        final theme = ThemeData.from(colorScheme: colorScheme);
        await tester.pumpWidget(
          _wrap(
            const SyncProgressView(),
            notifier: notifier,
            theme: theme,
            disableAnimations: true,
          ),
        );

        notifier.setStateForTest(
          _stateForPhase(PairingProgressPhase.connecting),
        );
        await tester.pump();

        final spinner = tester.widget<PrismSpinner>(find.byType(PrismSpinner));
        expect(spinner.color, colorScheme.primary);

        final subtitle = tester.widget<Text>(
          find.text('Saying hello to your other device'),
        );
        expect(
          subtitle.style?.color,
          colorScheme.onSurface.withValues(alpha: 0.74),
        );

        final segmentDecorations = tester
            .widgetList<Container>(find.byType(Container))
            .map((container) => container.decoration)
            .whereType<BoxDecoration>()
            .where((decoration) => decoration.borderRadius != null)
            .toList();

        final activeGradient =
            segmentDecorations.first.gradient as LinearGradient;
        expect(activeGradient.colors.first, colorScheme.primary);

        final pendingDecoration = segmentDecorations.last;
        expect(
          pendingDecoration.color,
          colorScheme.onSurface.withValues(alpha: 0.14),
        );
      },
    );
  });
}
