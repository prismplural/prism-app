// Sync pairing progress: every part of the progress surface stays reachable on a
// real 320x568 phone, at default text, at the composed maximum and under a
// nonlinear platform scaler.
//
// Source proof of the original defect: `SyncProgressView` returned
// `Padding(24) > Center > Column(min, stretch)` with phases, a 48dp spinner,
// title, subtitle, the live count card and reassurance copy. Nothing there
// scrolls, and `PairingStep.connecting` renders it directly (no cancel, no
// scroll ancestor), so at 3.375x the column reported 196dp of bottom overflow
// and the counting card plus the reassurance copy were painted below the bottom
// edge with no way to reach them. The view now scrolls inside a centring
// constraint, so it looks identical when it fits and everything stays reachable
// when it does not.
//
// Bounded pumps only: the spinner animates by design and the view rebuilds on a
// one-second timer, so `pumpAndSettle` would never return here.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/onboarding/providers/sync_setup_progress_provider.dart';
import 'package:prism_plurality/features/onboarding/widgets/live_count_card.dart';
import 'package:prism_plurality/features/onboarding/widgets/phase_segments.dart';
import 'package:prism_plurality/features/onboarding/widgets/sync_progress_view.dart';

import 'access_text_scale_harness.dart';

/// Pins the progress state so the view renders a known phase without a pairing
/// attempt: no network, no phase churn.
class _FixedProgressNotifier extends SyncSetupProgressNotifier {
  _FixedProgressNotifier(this._state);

  final SyncSetupProgressState _state;

  @override
  SyncSetupProgressState build() => _state;
}

SyncSetupProgressState _restoringState({required bool reassurance}) {
  return SyncSetupProgressState(
    phase: PairingProgressPhase.restoring,
    liveCounts: const {
      'members': 12,
      'chat_messages': 1400,
      'front_sessions': 320,
    },
    phaseStartedAt: DateTime.now().subtract(
      reassurance ? const Duration(seconds: 45) : const Duration(seconds: 1),
    ),
    timedOut: false,
    wsConnected: true,
    restoreApplied: 3,
    restoreTotal: 8,
  );
}

Future<void> _pumpProgress(
  WidgetTester tester, {
  TextScaler? systemScaler,
  double appFontScale = 1.0,
  bool reassurance = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        syncSetupProgressProvider.overrideWith(
          () =>
              _FixedProgressNotifier(_restoringState(reassurance: reassurance)),
        ),
      ],
      child: accessApp(
        const Scaffold(body: SyncProgressView()),
        systemScaler: systemScaler,
        appFontScale: appFontScale,
      ),
    ),
  );
  // Bounded frames: the progress indicator and the one-second rebuild timer
  // never settle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Brings [finder] into view and asserts it is inside the 320x568 viewport.
Future<void> _expectReachable(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  final rect = tester.getRect(finder);
  expect(
    rectInside(rect, Offset.zero & compactPhone),
    isTrue,
    reason: '$finder must be reachable on a compact phone, but it is at $rect',
  );
}

void main() {
  setUpAll(loadAccessFonts);

  testWidgets('default text on a 320x568 phone: the progress surface fits and '
      'nothing scrolls', (tester) async {
    useWindow(tester, compactPhone);
    await _pumpProgress(tester);

    expect(tester.takeException(), isNull);

    for (final finder in [
      find.byType(PhaseSegments),
      find.text('Restoring your data'),
      find.byType(LiveCountCard),
    ]) {
      expect(finder, findsOneWidget);
      await _expectReachable(tester, finder);
    }

    final scrollable = find.descendant(
      of: find.byType(SyncProgressView),
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsOneWidget);
    expect(
      tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
      lessThanOrEqualTo(0.5),
      reason:
          'at default text the view keeps its centred, non-scrolling layout',
    );
  });

  for (final scenario in <({String name, TextScaler? scaler, double app})>[
    (name: 'composed 1.5x', scaler: const TextScaler.linear(1.0), app: 1.5),
    (name: 'composed 3.375x', scaler: maxSystemScaler, app: maxAppFontScale),
    (
      name: 'nonlinear platform scaler',
      scaler: const NonlinearTextScaler(),
      app: 1.0,
    ),
  ]) {
    testWidgets('${scenario.name}: the whole progress surface stays reachable '
        'instead of overflowing the bottom edge', (tester) async {
      useWindow(tester, compactPhone);
      await _pumpProgress(
        tester,
        systemScaler: scenario.scaler,
        appFontScale: scenario.app,
      );

      expect(
        tester.takeException(),
        isNull,
        reason:
            'the progress column must fit or scroll: on a 320x568 phone at this '
            'text size every piece stays reachable.',
      );

      // The phase strip, the progress indicator, the title, the live counts and
      // the reassurance copy are all reachable.
      final scrollable = find.descendant(
        of: find.byType(SyncProgressView),
        matching: find.byType(Scrollable),
      );
      expect(scrollable, findsOneWidget);
      expect(
        tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
        greaterThan(0),
        reason: 'the column is taller than the viewport at this text size',
      );

      for (final finder in [
        find.byType(PhaseSegments),
        find.text('Restoring your data'),
        find.text(
          'Still going — larger restores can take a minute on slow networks.',
        ),
      ]) {
        expect(finder, findsOneWidget, reason: scenario.name);
        await _expectReachable(tester, finder);
      }

      // The count card is taller than a 568dp phone at these sizes, so
      // reachability means each of its pieces can be scrolled to - its first and
      // last rows here - not that the whole card fits at once.
      final cardTexts = find.descendant(
        of: find.byType(LiveCountCard),
        matching: find.byType(Text),
      );
      expect(cardTexts, findsWidgets, reason: scenario.name);
      await _expectReachable(tester, cardTexts.first);
      await _expectReachable(tester, cardTexts.last);

      expect(tester.takeException(), isNull);
    });
  }
}
