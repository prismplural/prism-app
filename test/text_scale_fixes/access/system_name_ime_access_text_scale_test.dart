// System-name step with the keyboard up: the field, its helper copy, the step
// title and the footer actions all stay reachable on a 320x568 phone at every
// text scale.
//
// With the IME up the body is whatever the keyboard leaves between the header and
// the bottom bar, which can be less than the field plus its gap and helper text.
// The name body scrolls inside that space, and when the pinned chrome would leave
// it unusably short the whole flow scrolls instead, so each piece can be reached
// in turn. Nothing is shrunk, and the field keeps its text, selection and focus
// across those layout modes.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/sync/sync_disconnect_marker.dart';
import 'package:prism_plurality/features/onboarding/providers/onboarding_providers.dart';
import 'package:prism_plurality/features/onboarding/views/onboarding_screen.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

import 'access_text_scale_harness.dart';

class _SystemNameNotifier extends OnboardingNotifier {
  @override
  OnboardingState build() =>
      const OnboardingState(currentStep: OnboardingStep.systemName);
}

/// Height the software keyboard takes on the compact phone in this scenario.
const double _keyboardInset = 280;

Future<ProviderContainer> _pumpSystemName(
  WidgetTester tester, {
  TextScaler? systemScaler,
  double appFontScale = 1.0,
  String family = 'OpenDyslexic',
}) async {
  final container = ProviderContainer(
    overrides: [
      onboardingProvider.overrideWith(_SystemNameNotifier.new),
      hasCompletedOnboardingProvider.overrideWithValue(false),
      syncDisconnectMarkerProvider.overrideWith((ref) async => null),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    accessApp(
      UncontrolledProviderScope(
        container: container,
        child: const OnboardingScreen(),
      ),
      systemScaler: systemScaler,
      appFontScale: appFontScale,
      theme: accessTheme(family: family),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

bool _clipsDescendants(RenderObject object) =>
    object is RenderAbstractViewport ||
    (object is RenderClipRect && object.clipBehavior != Clip.none) ||
    (object is RenderClipRRect && object.clipBehavior != Clip.none) ||
    (object is RenderClipPath && object.clipBehavior != Clip.none) ||
    (object is RenderPhysicalModel && object.clipBehavior != Clip.none) ||
    (object is RenderPhysicalShape && object.clipBehavior != Clip.none);

/// Global paint bounds of clipping viewports and clip renderers above [finder].
List<Rect> _ancestorViewports(WidgetTester tester, Finder finder) {
  final rects = <Rect>[];
  final seen = <RenderObject>{};
  tester.element(finder).visitAncestorElements((ancestor) {
    final renderObject = ancestor.renderObject;
    if (renderObject is RenderBox &&
        _clipsDescendants(renderObject) &&
        renderObject.attached &&
        renderObject.hasSize &&
        seen.add(renderObject)) {
      final rect = MatrixUtils.transformRect(
        renderObject.getTransformTo(null),
        renderObject.paintBounds,
      );
      if (rect.width > 0 && rect.height > 0) rects.add(rect);
    }
    return true;
  });
  return rects;
}

// Diagnostic only: selection and line boxes are layout evidence, not raster ink.
void _traceParagraph(
  WidgetTester tester,
  Finder finder,
  RenderParagraph paragraph, {
  required Rect visible,
  required String phase,
  Rect? revealed,
}) {
  final text = paragraph.text.toPlainText();
  final painter =
      TextPainter(
        text: paragraph.text,
        textAlign: paragraph.textAlign,
        textDirection: paragraph.textDirection,
        textScaler: paragraph.textScaler,
        locale: paragraph.locale,
        maxLines: paragraph.maxLines,
        ellipsis: paragraph.overflow == TextOverflow.ellipsis ? '…' : null,
        strutStyle: paragraph.strutStyle,
        textWidthBasis: paragraph.textWidthBasis,
        textHeightBehavior: paragraph.textHeightBehavior,
      )..layout(
        minWidth: paragraph.constraints.hasBoundedWidth
            ? paragraph.constraints.minWidth
            : 0,
        maxWidth:
            paragraph.softWrap || paragraph.overflow == TextOverflow.ellipsis
            ? paragraph.constraints.maxWidth
            : double.infinity,
      );
  try {
    final scrolls = <Map<String, Object?>>[];
    tester.element(finder).visitAncestorElements((element) {
      if (element is StatefulElement &&
          element.state is ScrollableState &&
          scrolls.length < 8) {
        final position = (element.state as ScrollableState).position;
        scrolls.add({
          'pixels': position.pixels,
          'minScrollExtent': position.minScrollExtent,
          'maxScrollExtent': position.maxScrollExtent,
          'viewportDimension': position.viewportDimension,
        });
      }
      return true;
    });
    debugPrint(
      'IME_METRICS ${jsonEncode({
        'phase': phase,
        'size': paragraph.size.toString(),
        'paintBounds': paragraph.paintBounds.toString(),
        'globalOrigin': paragraph.localToGlobal(Offset.zero).toString(),
        'resolvedSpan': paragraph.text.toStringDeep().substring(0, paragraph.text.toStringDeep().length > 1800 ? 1800 : paragraph.text.toStringDeep().length),
        'textHeightBehavior': paragraph.textHeightBehavior.toString(),
        'scaler': paragraph.textScaler.toString(),
        'selectionBoxes': paragraph.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: text.length)).take(24).map((box) => box.toRect().toString()).toList(),
        'lineMetrics': painter.computeLineMetrics().take(24).map((line) => {'ascent': line.ascent, 'descent': line.descent, 'unscaledAscent': line.unscaledAscent, 'height': line.height, 'width': line.width, 'left': line.left, 'baseline': line.baseline}).toList(),
        'scrollAncestors': scrolls,
        'keyboardSafeClip': visible.toString(),
        'ancestorClips': _ancestorViewports(tester, finder).take(12).map((clip) => clip.toString()).toList(),
        'revealedLastLine': revealed?.toString(),
        'inkQualification': 'unknown; layout metrics only',
      })}',
    );
  } finally {
    painter.dispose();
  }
}

/// Every line of [finder]'s paragraph can be revealed by scrolling.
///
/// A paragraph taller than the viewport can never be fully visible at once, so
/// reachability means each of its laid-out lines can be scrolled to and read: the
/// line boxes come from the render object itself (`getBoxesForSelection`), each is
/// shown with `showOnScreen`, and the revealed rect is then checked against the
/// area that is actually visible above the keyboard.
Future<void> _expectParagraphLinesReachable(
  WidgetTester tester,
  Finder finder, {
  required Rect visible,
  required String reason,
}) async {
  final paragraph = paragraphOf(tester, finder);
  final plainText = paragraph.text.toPlainText();
  expect(plainText, isNotEmpty, reason: reason);
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: plainText.length),
  );
  expect(boxes, isNotEmpty, reason: '$reason (no line boxes)');
  _traceParagraph(
    tester,
    finder,
    paragraph,
    visible: visible,
    phase: '$reason: before reveal',
  );
  // Trace the actual final-line reveal even if an earlier assertion later fails.
  // The rectangle remains paragraph-local, just like the assertion loop below.
  final lastLine = boxes.last.toRect();
  paragraph.showOnScreen(rect: lastLine);
  await tester.pump();
  _traceParagraph(
    tester,
    finder,
    paragraph,
    visible: visible,
    phase: '$reason: last-line reveal',
    revealed: lastLine.shift(paragraph.localToGlobal(Offset.zero)),
  );

  for (final box in boxes) {
    // `RenderObject.showOnScreen` takes the rect in its own coordinate space, so
    // the local line box from `getBoxesForSelection` is passed as-is; it walks up
    // and reveals the line through every scrollable ancestor.
    paragraph.showOnScreen(
      rect: Rect.fromLTRB(box.left, box.top, box.right, box.bottom),
    );
    await tester.pump();
    final originAfter = paragraph.localToGlobal(Offset.zero);
    final revealed = Rect.fromLTWH(
      originAfter.dx + box.left,
      originAfter.dy + box.top,
      box.right - box.left,
      box.bottom - box.top,
    );
    expect(
      rectInside(revealed, visible),
      isTrue,
      reason: '$reason: line at $revealed is outside $visible',
    );
    // On screen is not enough: the line must also survive every ancestor clip -
    // the header's own box and the body's viewport can slice a line that happens
    // to lie inside the screen rect.
    for (final clip in _ancestorViewports(tester, finder)) {
      expect(
        rectInside(revealed, clip),
        isTrue,
        reason:
            '$reason: line at $revealed is clipped by an ancestor viewport '
            '($clip)',
      );
    }
  }
}

void main() {
  setUpAll(loadAccessFonts);

  for (final scenario
      in <({String name, TextScaler? scaler, double app, String family})>[
        (
          name: 'default text, OpenDyslexic',
          scaler: null,
          app: 1.0,
          family: 'OpenDyslexic',
        ),
        (
          name: 'default text, Lexend',
          scaler: null,
          app: 1.0,
          family: 'Lexend',
        ),
        (
          name: 'composed 1.5x, OpenDyslexic',
          scaler: const TextScaler.linear(1.0),
          app: 1.5,
          family: 'OpenDyslexic',
        ),
        (
          name: 'composed 3.375x, OpenDyslexic',
          scaler: maxSystemScaler,
          app: maxAppFontScale,
          family: 'OpenDyslexic',
        ),
        (
          name: 'composed 3.375x, Lexend',
          scaler: maxSystemScaler,
          app: maxAppFontScale,
          family: 'Lexend',
        ),
        (
          name: 'nonlinear platform scaler',
          scaler: const NonlinearTextScaler(),
          app: 1.0,
          family: 'OpenDyslexic',
        ),
      ]) {
    testWidgets('${scenario.name} with the keyboard up on a 320x568 phone: the '
        'name field stays on screen and typing still reaches the flow', (
      tester,
    ) async {
      useWindow(tester, compactPhone, keyboardInset: _keyboardInset);
      final container = await _pumpSystemName(
        tester,
        systemScaler: scenario.scaler,
        appFontScale: scenario.app,
        family: scenario.family,
      );

      expect(
        tester.takeException(),
        isNull,
        reason:
            'The name body overflowed the space left above the keyboard. A red '
            'here at the largest sizes points at the pinned bottom bar first: at '
            '3.375x it takes ~206dp of the 288dp a 280dp keyboard leaves, which '
            'is a whole-flow constraint, not the name body (which now scrolls).',
      );

      // The field must be reachable in the area that is actually visible above
      // the keyboard, not merely laid out somewhere below it.
      final visible = Offset.zero & const Size(320, 568 - _keyboardInset);
      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      await tester.ensureVisible(field);
      await tester.pump();
      expect(
        rectInside(tester.getRect(field), visible),
        isTrue,
        reason:
            'the name field must be reachable while the IME is up (visible area '
            '$visible, field ${tester.getRect(field)}).',
      );

      // And so must the helper copy, which is the piece that used to be pushed
      // out of the body entirely.
      final helper = find.text(
        'This is how this profile will be identified in the app.',
      );
      expect(helper, findsOneWidget);
      // The helper can be taller than the body on a compact phone at max text, so
      // reachability means every one of its lines can be scrolled to and read.
      await _expectParagraphLinesReachable(
        tester,
        helper,
        visible: visible,
        reason: 'the helper copy must be readable above the keyboard',
      );

      // The footer must stay reachable as well: the whole flow scrolls when the
      // keyboard leaves too little for the pinned layout, so Continue and Back
      // are reachable by scrolling rather than pinned off-screen.
      final cta = find.text('Continue');
      expect(cta, findsOneWidget);
      await tester.ensureVisible(cta);
      await tester.pump();
      expect(
        rectInside(tester.getRect(cta), visible),
        isTrue,
        reason: 'Continue must be reachable while the IME is up',
      );

      final back = find.byIcon(AppIcons.arrowBack);
      expect(back, findsOneWidget);
      await tester.ensureVisible(back);
      await tester.pump();
      expect(
        rectInside(tester.getRect(back), visible),
        isTrue,
        reason: 'Back must be reachable while the IME is up',
      );

      // The step header is part of the flow too: it must never be collapsed to
      // nothing to make room, and it must be reachable by scrolling.
      final title = find.text('Name your profile');
      expect(title, findsOneWidget);
      expect(
        tester.getSize(title).height,
        greaterThan(0),
        reason: 'the header must keep a readable height',
      );
      // The title wraps to several lines at the largest sizes, so each line must
      // be readable rather than the whole paragraph fitting in one frame.
      await _expectParagraphLinesReachable(
        tester,
        title,
        visible: visible,
        reason: 'the step title must be readable while the IME is up',
      );

      // And the field still edits the onboarding state.
      await tester.enterText(field, 'The Wrens');
      await tester.pumpAndSettle();
      expect(container.read(onboardingProvider).systemName, 'The Wrens');
    });
  }

  testWidgets(
    'a focused input keeps its text, selection and focus across pinned, '
    'fallback and pinned again on the same screen',
    (tester) async {
      // Pinned: 1x with no keyboard.
      useWindow(tester, compactPhone);
      final container = await _pumpSystemName(tester);

      final field = find.byType(TextField);
      await tester.enterText(field, 'The Wrens');
      await tester.pumpAndSettle();
      expect(container.read(onboardingProvider).systemName, 'The Wrens');

      final controller = tester.widget<TextField>(field).controller!;
      controller.selection = const TextSelection(
        baseOffset: 4,
        extentOffset: 9,
      );
      await tester.pump();

      bool fieldHasFocus() => tester
          .widget<EditableText>(find.byType(EditableText))
          .focusNode
          .hasFocus;

      expect(fieldHasFocus(), isTrue, reason: 'the field starts focused');

      // Fallback: same screen, max text and the keyboard up. The layout mode
      // changes, the element tree must not.
      tester.view.viewInsets = const FakeViewPadding(bottom: _keyboardInset);
      await tester.pumpWidget(
        accessApp(
          UncontrolledProviderScope(
            container: container,
            child: const OnboardingScreen(),
          ),
          systemScaler: maxSystemScaler,
          appFontScale: maxAppFontScale,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        controller.text,
        'The Wrens',
        reason: 'the input keeps its text across the fallback',
      );
      expect(
        controller.selection,
        const TextSelection(baseOffset: 4, extentOffset: 9),
      );
      expect(
        fieldHasFocus(),
        isTrue,
        reason:
            'the focused input keeps focus when the footer starts scrolling',
      );

      await tester.ensureVisible(field);
      await tester.pump();
      expect(
        rectInside(
          tester.getRect(field),
          Offset.zero & const Size(320, 568 - _keyboardInset),
        ),
        isTrue,
      );

      // Back to pinned: 1x, keyboard gone.
      tester.view.resetViewInsets();
      await tester.pumpWidget(
        accessApp(
          UncontrolledProviderScope(
            container: container,
            child: const OnboardingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(controller.text, 'The Wrens');
      expect(
        controller.selection,
        const TextSelection(baseOffset: 4, extentOffset: 9),
      );
      expect(fieldHasFocus(), isTrue);
      expect(container.read(onboardingProvider).systemName, 'The Wrens');
    },
  );
}
