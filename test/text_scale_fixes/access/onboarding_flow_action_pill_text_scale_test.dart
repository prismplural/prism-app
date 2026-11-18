// Onboarding action pills inside their real flows.
//
// `sync_device_step.dart` and `import_data_step.dart` wrap PrismButton in
// `SizedBox(height: 52)`. PrismButton is 12dp of padding plus up to a two-line
// 15pt label, so a tight 52dp box clips the label from ~1.5x on. These cases
// drive the real step widgets - not a copy of the wrapper - and assert the
// label is laid out at the size the user asked for and stays inside its pill,
// plus the flow's own busy / disabled / back behaviour at the same text size.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/sync/sync_disconnect_marker.dart';
import 'package:prism_plurality/features/onboarding/providers/device_pairing_provider.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/onboarding/views/onboarding_screen.dart';
import 'package:prism_plurality/features/onboarding/widgets/import_data_step.dart';
import 'package:prism_plurality/features/onboarding/widgets/phase_segments.dart';
import 'package:prism_plurality/features/onboarding/widgets/sync_device_step.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

import 'access_text_scale_harness.dart';

// ---------------------------------------------------------------------------
// Harness: onboarding on the import step
// ---------------------------------------------------------------------------

class _ImportStepNotifier extends OnboardingNotifier {
  int nextCalls = 0;

  @override
  OnboardingState build() =>
      const OnboardingState(currentStep: OnboardingStep.importData);

  /// Runs the real forward action and records that it happened, so a case can
  /// assert the flow actually advanced rather than a counter that could fire
  /// without the step moving.
  @override
  void next() {
    nextCalls += 1;
    super.next();
  }
}

class _ImportHarness {
  _ImportHarness() {
    container = ProviderContainer(
      overrides: [
        onboardingProvider.overrideWith(_ImportStepNotifier.new),
        hasCompletedOnboardingProvider.overrideWithValue(false),
        syncDisconnectMarkerProvider.overrideWith((ref) async => null),
      ],
    );
  }

  late final ProviderContainer container;

  OnboardingState get state => container.read(onboardingProvider);

  _ImportStepNotifier get notifier =>
      container.read(onboardingProvider.notifier) as _ImportStepNotifier;

  Future<void> pump(
    WidgetTester tester, {
    TextScaler? systemScaler,
    double appFontScale = 1.0,
  }) async {
    await tester.pumpWidget(
      accessApp(
        UncontrolledProviderScope(
          container: container,
          child: const OnboardingScreen(),
        ),
        systemScaler: systemScaler,
        appFontScale: appFontScale,
      ),
    );
    await tester.pumpAndSettle();
  }

  void dispose() => container.dispose();
}

// ---------------------------------------------------------------------------
// Harness: the sync-device step on its own
// ---------------------------------------------------------------------------

/// Pins the pairing step so the join prompt (or the connecting view) renders
/// without any network attempt.
class _FixedPairingNotifier extends DevicePairingNotifier {
  _FixedPairingNotifier(this._state);

  final PairingState _state;

  @override
  PairingState build() => _state;
}

/// The real initial join prompt with its real action, but no network: the
/// rendezvous request is recorded instead of being sent.
class _RecordingPairingNotifier extends DevicePairingNotifier {
  int requests = 0;

  @override
  PairingState build() => const PairingState(step: PairingStep.enterUrl);

  @override
  Future<void> generateRequest({
    String? relayUrl,
    String? registrationToken,
  }) async {
    requests += 1;
  }
}

Widget _syncStepHost({
  PairingState? pairing,
  bool recordingPairing = false,
  VoidCallback? onBack,
  TextScaler? systemScaler,
  double appFontScale = 1.0,
}) {
  final pinned = pairing;
  return ProviderScope(
    overrides: [
      if (pinned != null)
        devicePairingProvider.overrideWith(() => _FixedPairingNotifier(pinned)),
      if (recordingPairing)
        devicePairingProvider.overrideWith(_RecordingPairingNotifier.new),
    ],
    child: accessApp(
      Scaffold(
        body: SafeArea(
          child: SyncDeviceStep(onBack: onBack ?? () {}, onComplete: () {}),
        ),
      ),
      systemScaler: systemScaler,
      appFontScale: appFontScale,
    ),
  );
}

/// Scroll the import step's own body until [finder] is visible, then tap it.
///
/// At large text the flow's cards and action button start below the fold, and a
/// lazy list only builds what is in view, so a plain find/tap can resolve to
/// nothing; `scrollUntilVisible` walks the body until the target exists.
Future<void> _scrollAndTap(WidgetTester tester, Finder finder) async {
  final bodyScrollable = find
      .descendant(
        of: find.byType(ImportDataStep),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(finder, 120, scrollable: bodyScrollable);
  await tester.pumpAndSettle();
  final trace = <String>[_importHitTrace(tester, finder, 'after body reveal')];
  // A nested body can expose the label to its own viewport while the flow's
  // pinned footer still covers it. Reveal through every real ancestor; never
  // tap the footer or call the intended callback directly to bypass this case.
  for (final alignment in [0.5, 0.0, 1.0]) {
    if (finder.hitTestable().evaluate().isNotEmpty) break;
    await Scrollable.ensureVisible(
      tester.element(finder),
      alignment: alignment,
    );
    await tester.pumpAndSettle();
    trace.add(_importHitTrace(tester, finder, 'alignment $alignment'));
  }
  expect(
    finder.hitTestable(),
    findsOneWidget,
    reason:
        'The intended import control must receive its own tap. '
        'Bounded nested-scroll trace:\n${trace.join('\n')}',
  );
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String _importHitTrace(WidgetTester tester, Finder finder, String stage) {
  final target = tester.renderObject<RenderBox>(finder);
  final center = target.localToGlobal(target.size.center(Offset.zero));
  final media = MediaQuery.of(tester.element(finder));
  final clipsAndOffsets = <String>[];
  final seen = <RenderObject>{};
  tester.element(finder).visitAncestorElements((ancestor) {
    if (ancestor is StatefulElement && ancestor.state is ScrollableState) {
      final position = (ancestor.state as ScrollableState).position;
      clipsAndOffsets.add(
        'scroll ${position.axisDirection}: '
        '${position.pixels} in '
        '[${position.minScrollExtent}, ${position.maxScrollExtent}]',
      );
    }
    final render = ancestor.renderObject;
    if (render is RenderBox &&
        render.attached &&
        render.hasSize &&
        seen.add(render) &&
        (render is RenderAbstractViewport ||
            (render is RenderClipRect && render.clipBehavior != Clip.none) ||
            (render is RenderClipRRect && render.clipBehavior != Clip.none))) {
      clipsAndOffsets.add(
        'clip ${render.runtimeType}: '
        '${MatrixUtils.transformRect(render.getTransformTo(null), render.paintBounds)}',
      );
    }
    return true;
  });
  final message =
      '$stage: $finder rect=${tester.getRect(finder)} '
      'center=$center screen=${media.size} insets=${media.viewInsets} '
      'padding=${media.padding} viewPadding=${media.viewPadding}; '
      '${clipsAndOffsets.join('; ')}; '
      'hit=${tester.hitTestOnBinding(center)}';
  debugPrint(message);
  return message;
}

// ---------------------------------------------------------------------------
// Assertions
// ---------------------------------------------------------------------------

/// The pill's label is at its requested size and inside the pill surface.
///
/// Measured from the paragraph actually on screen - its resolved span, scaler,
/// width, line cap and text-height behaviour - so the expected height belongs to
/// the font the user is reading rather than to a style rebuilt in the test.
void _expectPillLabelFits(WidgetTester tester, String label) {
  final text = find.text(label);
  expect(text, findsOneWidget, reason: '"$label" must be on screen');
  final pill = find
      .ancestor(of: text, matching: find.byType(PrismButton))
      .first;
  final pillRect = tester.getRect(pill);
  final paragraph = paragraphOf(tester, text);
  final labelRect = paragraph.localToGlobal(Offset.zero) & paragraph.size;

  expect(
    rectInside(labelRect, pillRect),
    isTrue,
    reason:
        '"$label" ($labelRect) must sit inside its pill ($pillRect); the pill is a '
        'minimum height, so it grows with the label instead of clipping it.',
  );

  final needed = paragraphHeight(paragraph);
  final natural = paragraphMaxIntrinsicHeight(paragraph);
  final lines = paragraphLineCount(paragraph);
  expect(
    paragraph.size.height + 0.5,
    greaterThanOrEqualTo(needed),
    reason:
        '"$label" needs ${needed.toStringAsFixed(1)}dp for its $lines natural '
        'line(s) but is laid out at '
        '${paragraph.size.height.toStringAsFixed(1)}dp',
  );
  expect(
    paragraph.size.height,
    lessThanOrEqualTo(natural + 0.5),
    reason: '"$label" is laid out no taller than its own span needs',
  );
}

void main() {
  setUpAll(loadAccessFonts);

  // -------------------------------------------------------------------------
  // sync_device_step: the "Request to Join" pill
  // -------------------------------------------------------------------------
  testWidgets('sync step at default text: the join pill keeps its 52dp height '
      'and its label, and Back still leaves the step', (tester) async {
    useWindow(tester, compactPhone);
    var backs = 0;
    await tester.pumpWidget(_syncStepHost(onBack: () => backs += 1));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Request to Join'), findsOneWidget);
    expect(
      tester.getSize(find.byType(PrismButton).first).height,
      closeTo(52, 0.5),
    );
    _expectPillLabelFits(tester, 'Request to Join');

    // The step's own Back control is on screen and leaves the step.
    final back = find.text('Back');
    expect(back, findsOneWidget);
    expect(tester.getRect(back).top, greaterThanOrEqualTo(0));
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(backs, 1);
  });

  // The real initial join prompt, at large text, with its real action. The
  // request itself is stubbed (recorded, never sent) so the case proves the
  // wiring without a network attempt.
  for (final scenario in <({String name, TextScaler? scaler, double app})>[
    (name: 'composed 1.5x', scaler: const TextScaler.linear(1.0), app: 1.5),
    (name: 'composed 3.375x', scaler: maxSystemScaler, app: maxAppFontScale),
  ]) {
    testWidgets(
      '${scenario.name} on a compact phone: the real join prompt keeps its '
      'controls on screen and its Request to Join action still fires',
      (tester) async {
        useWindow(tester, compactPhone);
        await tester.pumpWidget(
          _syncStepHost(
            recordingPairing: true,
            systemScaler: scenario.scaler,
            appFontScale: scenario.app,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason:
              'the self-hosted toggle label must wrap inside its row rather than '
              'overflowing to the right.',
        );

        final viewport = Offset.zero & compactPhone;

        // The self-hosted toggle: its label wraps at the requested size and the
        // whole control stays inside the viewport.
        final toggle = find.text('Self-hosted relay?');
        expect(toggle, findsOneWidget);
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        final toggleParagraph = paragraphOf(tester, toggle);
        expect(
          toggleParagraph.size.height + 0.5,
          greaterThanOrEqualTo(paragraphHeight(toggleParagraph)),
          reason: 'the toggle label is laid out at its own wrapped height',
        );
        expect(rectInside(tester.getRect(toggle), viewport), isTrue);

        // Back is on screen, and the only action is reachable and acts.
        expect(find.text('Back'), findsOneWidget);
        final action = find.text('Request to Join');
        expect(action, findsOneWidget);
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        _expectPillLabelFits(tester, 'Request to Join');
        expect(rectInside(tester.getRect(action), viewport), isTrue);

        final notifier =
            ProviderScope.containerOf(
                  tester.element(find.byType(SyncDeviceStep)),
                ).read(devicePairingProvider.notifier)
                as _RecordingPairingNotifier;
        expect(notifier.requests, 0);

        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(
          notifier.requests,
          1,
          reason: 'the join action must still request a rendezvous',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  // The error view is the flow's other real action surface (a scroll view with
  // the same `_ActionButton` wrapper); kept as an independent case.
  for (final scenario in <({String name, TextScaler? scaler, double app})>[
    (name: 'composed 1.5x', scaler: const TextScaler.linear(1.0), app: 1.5),
    (name: 'composed 3.375x', scaler: maxSystemScaler, app: maxAppFontScale),
  ]) {
    testWidgets(
      '${scenario.name} on a compact phone: the pairing error view is '
      'scrollable, and its Try Again pill grows with its label instead of '
      'clipping it',
      (tester) async {
        useWindow(tester, compactPhone);
        await tester.pumpWidget(
          _syncStepHost(
            pairing: const PairingState(
              step: PairingStep.error,
              errorMessage: 'Could not reach the other device.',
            ),
            systemScaler: scenario.scaler,
            appFontScale: scenario.app,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason:
              'the error view scrolls, so it must not overflow at '
              '${scenario.name}',
        );

        final pill = find.text('Try Again');
        expect(pill, findsOneWidget);
        await tester.ensureVisible(pill);
        await tester.pumpAndSettle();
        _expectPillLabelFits(tester, 'Try Again');

        final pillRect = tester.getRect(
          find.ancestor(of: pill, matching: find.byType(PrismButton)).first,
        );
        expect(pillRect.right, lessThanOrEqualTo(compactPhone.width + 0.5));
        expect(pillRect.bottom, lessThanOrEqualTo(compactPhone.height + 0.5));
      },
    );
  }

  testWidgets(
    'sync step while a pairing attempt runs: the progress surface is on screen '
    'and reachable, and no action is offered while it runs',
    (tester) async {
      useWindow(tester, compactPhone);
      await tester.pumpWidget(
        _syncStepHost(
          pairing: const PairingState(step: PairingStep.connecting),
          systemScaler: maxSystemScaler,
          appFontScale: maxAppFontScale,
        ),
      );
      // Bounded frames only: the spinner animates by design and the progress
      // view rebuilds on a one-second timer, so pumpAndSettle would never stop.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);

      final title = find.text('Connecting…');
      expect(title, findsOneWidget);
      await tester.ensureVisible(title);
      await tester.pump();

      final viewport = Offset.zero & compactPhone;
      expect(
        rectInside(tester.getRect(title), viewport),
        isTrue,
        reason:
            'the phase title must be reachable on a compact phone at max '
            'text',
      );

      final segments = find.byType(PhaseSegments);
      expect(segments, findsOneWidget);
      await tester.ensureVisible(segments);
      await tester.pump();
      expect(rectInside(tester.getRect(segments), viewport), isTrue);

      expect(
        find.text('Request to Join'),
        findsNothing,
        reason: 'no action is offered while the pairing attempt runs',
      );
    },
  );

  // -------------------------------------------------------------------------
  // import_data_step inside the real screen: PK token flow + busy/Back
  // -------------------------------------------------------------------------
  testWidgets(
    'import step at default text: the PluralKit import pill keeps its '
    '52dp height inside the real flow',
    (tester) async {
      useWindow(tester, compactPhone);
      final harness = _ImportHarness();
      addTearDown(harness.dispose);
      await harness.pump(tester);

      expect(tester.takeException(), isNull);
      await _scrollAndTap(tester, find.text('PluralKit'));
      await _scrollAndTap(tester, find.text('Import with a token'));

      final bodyScrollable = find
          .descendant(
            of: find.byType(ImportDataStep),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Import PluralKit Data'),
        120,
        scrollable: bodyScrollable,
      );
      await tester.pumpAndSettle();
      _expectPillLabelFits(tester, 'Import PluralKit Data');
    },
  );

  for (final scenario in <({String name, TextScaler? scaler, double app})>[
    (name: 'composed 1.5x', scaler: const TextScaler.linear(1.0), app: 1.5),
    (name: 'composed 3.375x', scaler: maxSystemScaler, app: maxAppFontScale),
  ]) {
    testWidgets('${scenario.name} on a compact phone: the PluralKit import pill '
        'in the real flow is laid out at full size, on screen, and a busy import '
        'hides footer Back and disables Continue', (tester) async {
      useWindow(tester, compactPhone);
      final harness = _ImportHarness();
      addTearDown(harness.dispose);
      await harness.pump(
        tester,
        systemScaler: scenario.scaler,
        appFontScale: scenario.app,
      );

      expect(tester.takeException(), isNull);

      // Picker -> PluralKit -> token path. Every step is the real flow widget,
      // and at this size each target starts below the fold, so it is scrolled to.
      await _scrollAndTap(tester, find.text('PluralKit'));
      await _scrollAndTap(tester, find.text('Import with a token'));

      final pill = find.text('Import PluralKit Data');
      final bodyScrollable = find
          .descendant(
            of: find.byType(ImportDataStep),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(pill, 120, scrollable: bodyScrollable);
      await tester.pumpAndSettle();
      _expectPillLabelFits(tester, 'Import PluralKit Data');

      final pillRect = tester.getRect(
        find.ancestor(of: pill, matching: find.byType(PrismButton)).first,
      );
      expect(pillRect.right, lessThanOrEqualTo(compactPhone.width + 0.5));
      expect(pillRect.bottom, lessThanOrEqualTo(compactPhone.height + 0.5));

      // During a running operation, visible Back is hidden and Continue is inert.
      // System/hardware Back policy is outside these UI-scale cases.
      harness.container.read(onboardingImportBusyProvider.notifier).set(true);
      await tester.pumpAndSettle();

      expect(
        find.byIcon(AppIcons.arrowBack),
        findsNothing,
        reason: 'the footer back control is removed while an import runs',
      );

      await tester.ensureVisible(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(
        harness.notifier.nextCalls,
        0,
        reason: 'a busy import step cannot be left by Continue',
      );

      // Idle again: the footer restores. While a sub-flow is open the footer's
      // Continue runs that flow's pending action, so the step is left first and
      // the real advance is asserted on the picker, where nothing shadows it.
      harness.container.read(onboardingImportBusyProvider.notifier).set(false);
      await tester.pumpAndSettle();
      expect(find.byIcon(AppIcons.arrowBack), findsOneWidget);

      await _scrollAndTap(tester, find.text('Other import options'));
      expect(
        find.text('Import with a token'),
        findsOneWidget,
        reason: 'the first Back returns from token entry to the method picker',
      );
      expect(find.text('Import from pk;export file'), findsOneWidget);
      expect(find.text('Import PluralKit Data'), findsNothing);
      expect(
        find.text('PluralKit'),
        findsNothing,
        reason: 'the method picker is still inside the PluralKit source',
      );

      await _scrollAndTap(tester, find.text('Other import options'));
      expect(find.text('Import with a token'), findsNothing);
      expect(
        find.text('PluralKit'),
        findsOneWidget,
        reason: 'the flow returns to the source picker',
      );

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(
        harness.notifier.nextCalls,
        1,
        reason: 'an idle import step still advances',
      );
      expect(
        harness.state.currentStep,
        isNot(OnboardingStep.importData),
        reason: 'the real forward action moves the flow on',
      );
    });
  }
}
