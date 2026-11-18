// Onboarding progress and CTA: the progress strip fits the slot it is given at
// any width, and the Continue / Get started action stays inside the viewport and
// stays tappable at every text scale.
//
// The strip is fixed geometry - fifteen capsules with the current one double
// width - so it can exceed a narrow slot; the CTA is the only forward action, so
// it must never paint past the edge. Both are measured here from the painted
// boxes, and the CTA's tap is checked against the flow it advances.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/sync/sync_disconnect_marker.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/onboarding/views/onboarding_screen.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';

import 'access_text_scale_harness.dart';

/// Seeds onboarding on the features step (its body scrolls, so a case measures
/// the shared header, the step body and the shared bottom bar) and records
/// forwards instead of moving the flow, so a tap has an observable result
/// without dragging database providers into the case.
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

  _RecordingFeaturesNotifier get notifier =>
      container.read(onboardingProvider.notifier) as _RecordingFeaturesNotifier;

  Future<void> pump(
    WidgetTester tester, {
    TextScaler? systemScaler,
    double appFontScale = 1.0,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      accessApp(
        UncontrolledProviderScope(
          container: container,
          child: const OnboardingScreen(),
        ),
        systemScaler: systemScaler,
        appFontScale: appFontScale,
        theme: theme,
      ),
    );
    await tester.pumpAndSettle();
  }

  void dispose() => container.dispose();
}

/// Every capsule in the progress strip, measured as the box it actually paints.
///
/// An `AnimatedContainer` with a margin reports the *outer* box (painted width
/// plus both margins), so the margin the widget itself carries is subtracted here
/// rather than assumed: comparing outer boxes would read 28/16 for a 24/12 strip.
List<Rect> _capsuleRects(WidgetTester tester) {
  final rects = <Rect>[];
  for (final element in find.byType(AnimatedContainer).evaluate()) {
    final widget = element.widget as AnimatedContainer;
    final box = element.renderObject! as RenderBox;
    // `margin` is an EdgeInsetsGeometry: resolve it with the direction this
    // element is actually laid out in, so `left`/`right` follow the widget's
    // directionality rather than being assumed.
    final margin = (widget.margin ?? EdgeInsets.zero).resolve(
      Directionality.of(element),
    );
    if ((box.size.height - 4).abs() > 0.01) continue; // the strip's capsules
    final painted = box.size.width - margin.horizontal;
    final topLeft = box.localToGlobal(Offset.zero);
    rects.add(
      Rect.fromLTWH(
        topLeft.dx + margin.left,
        topLeft.dy + (box.size.height - 4) / 2,
        painted,
        4,
      ),
    );
  }
  return rects;
}

/// The margin the strip's capsules carry, read from the widget itself.
double _capsuleMargin(WidgetTester tester) {
  for (final element in find.byType(AnimatedContainer).evaluate()) {
    final widget = element.widget as AnimatedContainer;
    final geometry = widget.margin;
    if (geometry == null) continue;
    final margin = geometry.resolve(Directionality.of(element));
    if (margin.vertical == 0 && margin.horizontal > 0) {
      return margin.horizontal;
    }
  }
  return 0;
}

void main() {
  setUpAll(loadAccessFonts);

  // The header reserves 20dp padding plus a 48dp action slot on each side.
  const headerPadding = 20.0;
  const actionSlot = 48.0;

  testWidgets('default text: the 15 progress capsules fit the header slot on a '
      'compact phone', (tester) async {
    useWindow(tester, compactPhone);
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(tester);

    // Fifteen capsules cannot overflow the slot they are laid out in.
    expect(tester.takeException(), isNull);

    final capsules = _capsuleRects(tester);
    expect(capsules, hasLength(15));

    const slotLeft = headerPadding + actionSlot;
    final slotRight = compactPhone.width - headerPadding - actionSlot;
    for (final rect in capsules) {
      expect(
        rect.left,
        greaterThanOrEqualTo(slotLeft - 0.5),
        reason: 'capsule at $rect starts left of the progress slot',
      );
      expect(
        rect.right,
        lessThanOrEqualTo(slotRight + 0.5),
        reason:
            'capsule at $rect paints past the progress slot on a 320dp '
            'phone; the strip must fit the width it is given',
      );
    }

    // Structure, from the render tree rather than assumed numbers: one current
    // capsule wider than the fourteen others, all of them inside the slot.
    final widths = capsules.map((r) => r.width).toList();
    final uniqueWidths = widths.toSet();
    expect(
      uniqueWidths.length,
      2,
      reason: 'exactly one capsule is the current one (widths: $uniqueWidths)',
    );
    final sorted = uniqueWidths.toList()..sort();
    expect(
      widths.where((w) => (w - sorted.last).abs() < 0.01),
      hasLength(1),
      reason: 'a single capsule carries the current-step emphasis',
    );
    expect(
      widths.where((w) => (w - sorted.first).abs() < 0.01),
      hasLength(14),
      reason: 'the other fourteen capsules share one width',
    );
  });

  testWidgets('wide layout: default capsule geometry and CTA placement are '
      'unchanged', (tester) async {
    useWindow(tester, wideDesktop);
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pump(
      tester,
      systemScaler: maxSystemScaler,
      appFontScale: maxAppFontScale,
    );

    expect(tester.takeException(), isNull);

    final capsules = _capsuleRects(tester);
    expect(capsules, hasLength(15));

    // Structure, not assumed numbers: on a wide window the strip keeps its
    // ideal geometry, so the current capsule is exactly twice a peer, the other
    // fourteen share one width, and the whole strip stays narrower than the slot
    // (which is wide here, so the cap is what holds it).
    final widths = capsules.map((r) => r.width).toList();
    final uniqueWidths = widths.toSet().toList()..sort();
    expect(uniqueWidths, hasLength(2), reason: 'widths: $uniqueWidths');
    expect(
      uniqueWidths.last,
      closeTo(uniqueWidths.first * 2, 0.01),
      reason: 'the current capsule is double width',
    );
    expect(
      widths.where((w) => (w - uniqueWidths.last).abs() < 0.01),
      hasLength(1),
    );
    expect(
      widths.where((w) => (w - uniqueWidths.first).abs() < 0.01),
      hasLength(14),
    );
    final stripWidth =
        capsules.fold<double>(0, (sum, r) => sum + r.width) +
        capsules.length * _capsuleMargin(tester);
    expect(
      stripWidth,
      lessThanOrEqualTo(252 + 0.5),
      reason: 'the strip keeps its 252dp ideal width when it has room',
    );

    // On a wide screen no label needs to wrap: the CTA keeps one line and
    // stays against the right edge of the shared 24dp padding.
    final label = find.text('Continue');
    final paragraph = paragraphOf(tester, label);
    expect(
      paragraphLineCount(paragraph),
      1,
      reason: 'the CTA label must not wrap when it has the width to fit',
    );
    expect(
      paragraph.size.height,
      lessThanOrEqualTo(paragraphHeight(paragraph) + 0.5),
    );
    final labelRect = paragraph.localToGlobal(Offset.zero) & paragraph.size;
    expect(labelRect.right, lessThanOrEqualTo(wideDesktop.width - 24 + 0.5));
    expect(labelRect.right, greaterThan(wideDesktop.width - 24 - 240));
  });

  for (final scenario
      in <({String name, Size size, TextScaler? scaler, double app})>[
        (name: 'default text', size: compactPhone, scaler: null, app: 1.0),
        (
          name: 'composed 1.5x',
          size: compactPhone,
          scaler: const TextScaler.linear(1.0),
          app: 1.5,
        ),
        (
          name: 'composed 3.375x',
          size: compactPhone,
          scaler: maxSystemScaler,
          app: maxAppFontScale,
        ),
        (
          name: 'Prism 50% small text',
          size: compactPhone,
          scaler: const TextScaler.linear(1.0),
          app: 0.5,
        ),
      ]) {
    testWidgets('${scenario.name}: the Continue CTA stays inside the viewport '
        'and still forwards the flow', (tester) async {
      useWindow(tester, scenario.size);
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.pump(
        tester,
        systemScaler: scenario.scaler,
        appFontScale: scenario.app,
      );

      expect(tester.takeException(), isNull);

      final label = find.text('Continue');
      expect(label, findsOneWidget);
      final labelRect = tester.getRect(label);
      expect(
        labelRect.left,
        greaterThanOrEqualTo(0),
        reason:
            'the CTA label must stay inside the ${320}dp viewport: it is at '
            '$labelRect',
      );
      expect(labelRect.right, lessThanOrEqualTo(scenario.size.width));

      // The label is not clipped: the paragraph that is really on screen is
      // laid out as tall as its own resolved span needs at its own width.
      final paragraph = paragraphOf(tester, label);
      final needed = paragraphHeight(paragraph);
      expect(
        paragraph.size.height + 0.5,
        greaterThanOrEqualTo(needed),
        reason:
            'the CTA label must be laid out at its full requested size '
            '(needs ${needed.toStringAsFixed(1)}dp, has '
            '${paragraph.size.height.toStringAsFixed(1)}dp)',
      );

      // The hit target itself is inside the viewport, and a tap reaches the
      // flow: this is the only forward action on the step.
      final surfaceRect = tester.getRect(
        find.ancestor(of: label, matching: find.byType(AnimatedScale)).first,
      );
      expect(surfaceRect.right, lessThanOrEqualTo(scenario.size.width + 0.5));
      expect(surfaceRect.left, greaterThanOrEqualTo(0));

      expect(harness.notifier.nextCalls, 0);
      await tester.tap(label);
      await tester.pumpAndSettle();
      expect(harness.notifier.nextCalls, 1);
    });
  }
}
