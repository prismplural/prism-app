// Onboarding header/body composition: on a 320x568 phone at the maximum
// composed text size the step body must still exist, and the step's controls
// and the only forward action must still be reachable.
//
// Source proof of the original defect (onboarding_screen.dart, pre-fix): the
// progress strip (28dp when the close action is hidden), the step header
// (8 + 56 logo + 12 + a 28pt title + 4 + a 15pt subtitle + 20) and the bottom
// bar (32 + a two-line 16pt pill) are all fixed blocks in one Column, while the
// step body is the only flexible child. At 3.375x the 28pt title alone is ~94.5px,
// so "Pick your tools" wraps to ~4 lines of ~118dp (472dp) and the subtitle to
// ~3 lines of ~64dp (192dp): the header is ~764dp, the pinned pieces are ~234dp,
// the body is laid out at 0dp and the Column overflows the 568dp viewport by
// several hundred dp. Nothing in the body can be hit-tested, so the step is
// unusable even though the CTA itself is on screen.
//
// Desired behaviour, asserted below: the body keeps a usable height, the header
// scrolls instead of eating it, the step body's own controls can be scrolled to
// and operated, and the flow still forwards.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/sync/sync_disconnect_marker.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/onboarding/views/onboarding_screen.dart';
import 'package:prism_plurality/features/onboarding/widgets/features_step.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

import 'access_text_scale_harness.dart';

class _RecordingFeaturesNotifier extends OnboardingNotifier {
  int nextCalls = 0;

  @override
  OnboardingState build() =>
      const OnboardingState(currentStep: OnboardingStep.features);

  @override
  void next() {
    nextCalls += 1;
  }
}

class _Harness {
  _Harness() {
    container = ProviderContainer(
      overrides: [
        onboardingProvider.overrideWith(_RecordingFeaturesNotifier.new),
        hasCompletedOnboardingProvider.overrideWithValue(false),
        syncDisconnectMarkerProvider.overrideWith((ref) async => null),
      ],
    );
  }

  late final ProviderContainer container;

  OnboardingState get state => container.read(onboardingProvider);

  _RecordingFeaturesNotifier get notifier =>
      container.read(onboardingProvider.notifier) as _RecordingFeaturesNotifier;

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

/// The step body's own viewport.
Rect _bodyRect(WidgetTester tester) =>
    tester.getRect(find.byType(FeaturesStep));

void main() {
  setUpAll(loadAccessFonts);

  testWidgets('composed 3.375x on a 320x568 phone: the step body keeps a usable '
      'height and its controls can be reached and operated', (tester) async {
    useWindow(tester, compactPhone);
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(
      tester,
      systemScaler: maxSystemScaler,
      appFontScale: maxAppFontScale,
    );

    expect(
      tester.takeException(),
      isNull,
      reason:
          'the onboarding column must fit its viewport: the header negotiates its '
          'height with the parent that lays it out.',
    );

    // The body is not squeezed out of existence.
    final body = _bodyRect(tester);
    expect(
      body.height,
      greaterThanOrEqualTo(96),
      reason:
          'the step body must keep a usable height on a compact phone at max '
          'text, not be squeezed out of existence.',
    );
    expect(body.top, greaterThanOrEqualTo(0));
    expect(body.bottom, lessThanOrEqualTo(compactPhone.height));

    // The body's own scrolling still works, and it has content to reach.
    final bodyScrollable = find.descendant(
      of: find.byType(FeaturesStep),
      matching: find.byType(Scrollable),
    );
    expect(bodyScrollable, findsOneWidget);
    final position = tester.state<ScrollableState>(bodyScrollable).position;
    expect(
      position.maxScrollExtent,
      greaterThan(0),
      reason: 'the step options are taller than the space they are given',
    );

    // A real control: bring the first feature switch on screen and flip it.
    final firstSwitch = find.descendant(
      of: find.byType(FeaturesStep),
      matching: find.byType(Switch),
    );
    expect(firstSwitch, findsWidgets);
    final before = harness.state.chatEnabled;

    await tester.ensureVisible(firstSwitch.first);
    await tester.pumpAndSettle();

    final switchRect = tester.getRect(firstSwitch.first);
    final visible = _bodyRect(tester);
    expect(
      switchRect.center.dy,
      inInclusiveRange(visible.top, visible.bottom),
      reason: 'the switch must be inside the body viewport before it is tapped',
    );

    await tester.tap(firstSwitch.first);
    await tester.pumpAndSettle();
    expect(
      harness.state.chatEnabled,
      isNot(before),
      reason: 'the step control must still act on the onboarding state',
    );

    // The only forward action is on screen and still forwards the flow.
    final cta = find.text('Continue');
    expect(cta, findsOneWidget);
    final ctaRect = tester.getRect(cta);
    expect(ctaRect.bottom, lessThanOrEqualTo(compactPhone.height));
    expect(ctaRect.right, lessThanOrEqualTo(compactPhone.width));

    await tester.tap(cta);
    await tester.pumpAndSettle();
    expect(harness.notifier.nextCalls, 1);
  });

  testWidgets(
    'composed 3.375x: the header text stays at the requested size and '
    'is reachable by scrolling the header, not by shrinking it',
    (tester) async {
      useWindow(tester, compactPhone);
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.pump(
        tester,
        systemScaler: maxSystemScaler,
        appFontScale: maxAppFontScale,
      );

      final title = find.text('Pick your tools');
      expect(title, findsOneWidget);

      // Full requested size: 28pt title at 3.375x.
      final scaler = effectiveScaler(tester, title);
      expect(scaler.scale(28), closeTo(94.5, 0.01));
      expect(tester.widget<Text>(title).style!.fontSize, 28);

      // Measured composition: the title really wraps at the requested size
      // instead of being compressed or ellipsised to one line, and the
      // paragraph is laid out as tall as its own span needs.
      final paragraph = paragraphOf(tester, title);
      final lines = paragraphLineCount(paragraph);
      expect(
        lines,
        greaterThan(1),
        reason:
            'a 28pt title in a 272dp line box wraps (measured $lines line(s))',
      );
      final needed = paragraphMaxIntrinsicHeight(paragraph);
      expect(
        paragraph.size.height + 0.5,
        greaterThanOrEqualTo(needed),
        reason:
            'the title must be laid out at its full wrapped height (needs '
            '${needed.toStringAsFixed(1)}dp, has '
            '${paragraph.size.height.toStringAsFixed(1)}dp)',
      );

      // The header scrolls within its budget: its viewport is smaller than its
      // content, so the title is reachable by scrolling.
      final headerScrollable = find.ancestor(
        of: title,
        matching: find.byType(SingleChildScrollView),
      );
      expect(headerScrollable, findsWidgets);
      final headerPosition = tester
          .state<ScrollableState>(
            find.descendant(
              of: headerScrollable.first,
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      expect(
        headerPosition.maxScrollExtent,
        greaterThan(0),
        reason: 'the header content is taller than the height it is given',
      );
    },
  );

  testWidgets('composed 1.5x and default text on a 320x568 phone: the header '
      'keeps its natural height and nothing clips', (tester) async {
    for (final scenario in <({String name, TextScaler? scaler, double app})>[
      (name: 'default text', scaler: null, app: 1.0),
      (name: 'composed 1.5x', scaler: const TextScaler.linear(1.0), app: 1.5),
    ]) {
      useWindow(tester, compactPhone);
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.pump(
        tester,
        systemScaler: scenario.scaler,
        appFontScale: scenario.app,
      );

      expect(tester.takeException(), isNull, reason: scenario.name);

      // Header text is fully on screen (not clipped by a header budget that
      // bites when it should not).
      for (final text in [
        'Pick your tools',
        'Turn on what you need. Change anytime.',
      ]) {
        final finder = find.text(text);
        expect(finder, findsOneWidget, reason: '${scenario.name}: $text');
        final rect = tester.getRect(finder);
        expect(
          rect.top,
          greaterThanOrEqualTo(0),
          reason: '${scenario.name}: $text',
        );
        expect(
          rect.bottom,
          lessThanOrEqualTo(compactPhone.height),
          reason: '${scenario.name}: $text must not be pushed off screen',
        );
      }

      // Nothing to scroll in the header at these sizes.
      final headerScrollable = find.ancestor(
        of: find.text('Pick your tools'),
        matching: find.byType(SingleChildScrollView),
      );
      final headerPosition = tester
          .state<ScrollableState>(
            find.descendant(
              of: headerScrollable.first,
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      expect(
        headerPosition.maxScrollExtent,
        lessThanOrEqualTo(0.5),
        reason:
            '${scenario.name}: the header keeps its natural height when it fits',
      );

      expect(
        _bodyRect(tester).height,
        greaterThan(96),
        reason: '${scenario.name}: the body keeps its share',
      );
    }
  });

  testWidgets('diagnostic: a tall narrow window shows the same header at max '
      'text without needing the header budget', (tester) async {
    useWindow(tester, narrowTallPhone);
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(
      tester,
      systemScaler: maxSystemScaler,
      appFontScale: maxAppFontScale,
    );

    expect(tester.takeException(), isNull);
    expect(
      _bodyRect(tester).height,
      greaterThan(0),
      reason: 'a tall window renders the body without needing the budget',
    );
  });
}
