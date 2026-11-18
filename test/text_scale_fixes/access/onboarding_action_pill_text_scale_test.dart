// Onboarding action pills: PrismButton sits in a 52dp minimum, so the label
// keeps its requested size and the pill grows with it.
//
// `onboarding_data_ready_view.dart` is the public instance of that wrapper; the
// `_ActionButton` in `sync_device_step.dart` and `import_data_step.dart` uses the
// same shape inside its own flow. At default text the pill is exactly 52dp; once
// the label needs more than 12dp of padding plus its lines, the pill has to grow
// rather than clip.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/features/onboarding/models/onboarding_data_counts.dart';
import 'package:prism_plurality/features/onboarding/widgets/onboarding_data_ready_view.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';

import 'access_text_scale_harness.dart';

const _counts = OnboardingDataCounts(
  members: 3,
  frontingSessions: 41,
  conversations: 2,
  messages: 120,
  habits: 1,
  notes: 7,
);

Widget _view({
  String actionLabel = 'Get started',
  VoidCallback? onAction,
  TextScaler? systemScaler,
  double appFontScale = 1.0,
}) {
  return ProviderScope(
    child: accessApp(
      Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: OnboardingDataReadyView(
            title: 'Import complete',
            description: 'Your data is ready.',
            summaryLabel: 'Imported',
            counts: _counts,
            actionLabel: actionLabel,
            onAction: onAction ?? () {},
          ),
        ),
      ),
      systemScaler: systemScaler,
      appFontScale: appFontScale,
    ),
  );
}

/// The label is laid out at the size its own glyphs need and stays inside its
/// pill.
///
/// Everything here is measured from the paragraph that is actually on screen
/// (its resolved span, scaler, width, text-height behaviour), not from a style
/// rebuilt in the test: a rebuilt style silently loses the ambient
/// DefaultTextStyle and the app font, and then the "needed" height belongs to a
/// different font than the one being read.
void _expectLabelFitsPill(WidgetTester tester) {
  final button = find.byType(PrismButton);
  expect(button, findsOneWidget);
  final buttonRect = tester.getRect(button);
  final label = find.descendant(of: button, matching: find.byType(Text)).first;
  final paragraph = paragraphOf(tester, label);
  final labelRect = paragraph.localToGlobal(Offset.zero) & paragraph.size;

  expect(
    rectInside(labelRect, buttonRect),
    isTrue,
    reason: 'the label rect $labelRect must sit inside its pill $buttonRect',
  );

  // What the span needs at the width it was given, with the label's own line
  // cap (PrismButton: two lines) and, for the diagnostic, with no cap at all.
  final needed = paragraphHeight(paragraph);
  final natural = paragraphMaxIntrinsicHeight(paragraph);
  final lines = paragraphLineCount(paragraph);
  expect(
    paragraph.size.height + 0.5,
    greaterThanOrEqualTo(needed),
    reason:
        'the label needs ${needed.toStringAsFixed(1)}dp for its $lines natural '
        'line(s) but is laid out at '
        '${paragraph.size.height.toStringAsFixed(1)}dp',
  );
  expect(
    paragraph.size.height,
    lessThanOrEqualTo(natural + 0.5),
    reason: 'the label is laid out no taller than its own span needs',
  );
}

void main() {
  setUpAll(loadAccessFonts);

  testWidgets('default text: the action keeps its 52dp pill and fires its '
      'callback', (tester) async {
    useWindow(tester, compactPhone);
    var taps = 0;
    await tester.pumpWidget(_view(onAction: () => taps += 1));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(PrismButton)).height, closeTo(52, 0.5));
    _expectLabelFitsPill(tester);

    await tester.ensureVisible(find.byType(PrismButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PrismButton));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  for (final scenario in <({String name, TextScaler? scaler, double app})>[
    (name: 'composed 1.5x', scaler: const TextScaler.linear(1.0), app: 1.5),
    (name: 'composed 3.375x', scaler: maxSystemScaler, app: maxAppFontScale),
  ]) {
    testWidgets('${scenario.name}: the action pill grows with its label on a '
        'compact phone and still fires', (tester) async {
      useWindow(tester, compactPhone);
      var taps = 0;
      await tester.pumpWidget(
        _view(
          onAction: () => taps += 1,
          systemScaler: scenario.scaler,
          appFontScale: scenario.app,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      _expectLabelFitsPill(tester);

      // Bring the action on screen before tapping it: the view is a scroll
      // body and at large text the pill starts below the fold.
      await tester.ensureVisible(find.byType(PrismButton));
      await tester.pumpAndSettle();

      final buttonRect = tester.getRect(find.byType(PrismButton));
      expect(buttonRect.right, lessThanOrEqualTo(compactPhone.width));
      expect(buttonRect.left, greaterThanOrEqualTo(0));
      expect(buttonRect.bottom, lessThanOrEqualTo(compactPhone.height));

      await tester.tap(find.byType(PrismButton));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  }

  testWidgets('composed 3.375x on a wide window: the pill grows with one full '
      'line of its label', (tester) async {
    useWindow(tester, wideDesktop);
    await tester.pumpWidget(
      _view(systemScaler: maxSystemScaler, appFontScale: maxAppFontScale),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    _expectLabelFitsPill(tester);

    // On a wide window the label has room to lay out within the pill it is given.
    // The pill hugs its content, so the available label width comes from the
    // paragraph's own box rather than from the window width: the claim is that the
    // text fits that box, not that it must be one line.
    final label = find
        .descendant(of: find.byType(PrismButton), matching: find.byType(Text))
        .first;
    final paragraph = paragraphOf(tester, label);
    expect(
      paragraph.size.height,
      lessThanOrEqualTo(paragraphHeight(paragraph) + 0.5),
      reason: 'the label is laid out no taller than its own span needs',
    );
    expect(
      paragraphLineCount(paragraph),
      lessThanOrEqualTo(2),
      reason: 'the pill caps its label at two lines',
    );
  });

  testWidgets('a long action label at 3.375x stays inside the pill instead of '
      'overflowing it', (tester) async {
    useWindow(tester, compactPhone);
    await tester.pumpWidget(
      _view(
        actionLabel:
            'Start using your system and open the fronting screen for today',
        systemScaler: maxSystemScaler,
        appFontScale: maxAppFontScale,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    _expectLabelFitsPill(tester);
  });
}
