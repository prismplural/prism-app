// Shared harness for the chrome (top bar / sheet bar / pinned header)
// text-scale regressions.
//
// Mirrors how `lib/app.dart` composes text size: the user's system
// accessibility scaler, then Prism's own font-size preference, delegated per
// font size through [PrismTextScaler]. Nothing is clamped anywhere. The real
// bundled faces are loaded so measurements come from the glyphs the app paints.
//
// Every assertion here is global painted geometry: the paragraph's laid-out
// height is compared with the rect it is actually painted into, because a
// `FittedBox(scaleDown)` ancestor leaves the laid-out height intact and only
// shrinks the painted rect.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/prism_text_scaler.dart';
import 'package:prism_plurality/shared/widgets/sliver_pinned_top_bar.dart';

import '../../helpers/prism_golden.dart' show loadPrismGoldenFonts;

/// Compact phone used for the narrow cases.
const Size compactPhone = Size(320, 568);

/// Wide window: above PrismTokens.desktopBreakpoint, so the desktop title size
/// (18pt) is in play.
const Size wideWindow = Size(1440, 900);

/// (system accessibility scaler, Prism font-size preference, label).
const List<(double, double, String)> chromeScales = [
  (1.0, 0.5, 'system 100% x Prism 50% = 0.5x'),
  (1.0, 1.0, 'default text'),
  (1.5, 1.0, 'large text'),
  (2.25, 1.5, 'system 225% x Prism 150% = 3.375x'),
];

/// The two bundled faces the app ships for body text.
const List<String> chromeFontFamilies = ['Lexend', 'OpenDyslexic'];

Future<void> loadChromeFonts() => loadPrismGoldenFonts();

/// Deterministic window size, with an optional software-keyboard inset.
void useWindow(WidgetTester tester, Size size, {double keyboardInset = 0}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  if (keyboardInset > 0) {
    tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);
  }
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewInsets();
  });
}

ThemeData chromeTheme(String fontFamily) => ThemeData(
  fontFamily: fontFamily,
  fontFamilyFallback: const ['NotoColorEmoji'],
);

/// MaterialApp that composes the system scaler with Prism's preference exactly
/// like `app.dart`.
Widget chromeApp(
  Widget home, {
  required double system,
  required double app,
  String fontFamily = 'Lexend',
  TextScaler? scalerOverride,
  TextDirection? textDirection,
  bool boldText = false,
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    theme: chromeTheme(fontFamily),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en'), Locale('es')],
    locale: locale,
    builder: (context, child) {
      final content = child ?? const SizedBox.shrink();
      final scaler =
          scalerOverride ?? PrismTextScaler(TextScaler.linear(system), app);
      return MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: scaler, boldText: boldText),
        child: textDirection == null
            ? content
            : Directionality(textDirection: textDirection, child: content),
      );
    },
    home: home,
  );
}

/// A deliberately nonlinear scaler: no chrome case may assume that one length
/// follows from multiplying another by a single ratio.
class NonlinearTextScaler extends TextScaler {
  const NonlinearTextScaler();

  @override
  double scale(double fontSize) =>
      fontSize <= 14 ? fontSize * 3.0 : fontSize * 1.6;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => 1.0;

  @override
  bool operator ==(Object other) => other is NonlinearTextScaler;

  @override
  int get hashCode => 0x6368726f; // 'chro'
}

/// Height one line of [text] needs under [scaler], measured from real glyphs.
double lineHeightFor(
  String text,
  TextStyle style,
  TextScaler scaler, {
  double maxWidth = double.infinity,
  int maxLines = 1,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: maxLines,
  )..layout(maxWidth: maxWidth);
  final height = painter.height;
  painter.dispose();
  return height;
}

/// The paragraph that paints [text]; exactly one must exist.
RenderParagraph paragraphOf(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(finder, findsOneWidget, reason: 'exactly one "$text" paragraph');
  return tester.renderObject<RenderParagraph>(finder);
}

/// Height the paragraph would occupy if nothing constrained it: same text,
/// same style, same inherited scaler, no vertical clamp.
double neededHeight(RenderParagraph paragraph) {
  final painter = TextPainter(
    text: TextSpan(
      text: paragraph.text.toPlainText(),
      style: paragraph.text.style,
    ),
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    textAlign: paragraph.textAlign,
    maxLines: 1,
  )..layout();
  final height = painter.height;
  painter.dispose();
  return height;
}

/// Asserts [text] is painted at the size the user asked for, inside [container]
/// and inside the window, without a shrink or a clamp. Returns the painted rect.
Rect expectFullSizeText(
  WidgetTester tester,
  String text, {
  required String label,
  Rect? container,
  Finder? finder,
}) {
  final target = finder ?? find.text(text);
  expect(target, findsOneWidget, reason: 'exactly one paragraph for "$text"');
  final paragraph = tester.renderObject<RenderParagraph>(target);
  final needed = neededHeight(paragraph);
  final laidOut = paragraph.size.height;
  final painted = tester.getRect(target);

  expect(
    laidOut,
    greaterThanOrEqualTo(needed - 0.5),
    reason:
        '$label: CLIPPED - "$text" needs ${needed.toStringAsFixed(1)}px but its '
        'paragraph is laid out at ${laidOut.toStringAsFixed(1)}px',
  );
  expect(
    painted.height,
    greaterThanOrEqualTo(laidOut * 0.98),
    reason:
        '$label: SHRUNK - "$text" is painted at ${painted.height.toStringAsFixed(1)}px '
        'for a ${laidOut.toStringAsFixed(1)}px layout '
        '(x${(painted.height / (laidOut == 0 ? 1 : laidOut)).toStringAsFixed(3)})',
  );
  if (container != null) {
    expect(
      painted.top,
      greaterThanOrEqualTo(container.top - 0.5),
      reason: '$label: "$text" is cut off at the top of its container',
    );
    expect(
      painted.bottom,
      lessThanOrEqualTo(container.bottom + 0.5),
      reason: '$label: "$text" is cut off at the bottom of its container',
    );
  }
  final windowSize = Size(
    tester.view.physicalSize.width / tester.view.devicePixelRatio,
    tester.view.physicalSize.height / tester.view.devicePixelRatio,
  );
  final window = Offset.zero & windowSize;
  expect(
    painted.left,
    greaterThanOrEqualTo(window.left - 0.5),
    reason: '$label: "$text" starts outside the window',
  );
  expect(
    painted.right,
    lessThanOrEqualTo(window.right + 0.5),
    reason: '$label: "$text" runs past the right edge of the window',
  );
  return painted;
}

/// No layout exception was reported by any ancestor this frame.
void expectNoLayoutException(WidgetTester tester, String label) {
  final exception = tester.takeException();
  expect(exception, isNull, reason: '$label: layout exception: $exception');
}

/// Height the pinned header currently occupies, read from its own sliver
/// geometry instead of from whatever content happens to sit below it (a list's
/// first tile can be preceded by banners, padding or section headers).
double pinnedBandHeight(WidgetTester tester, {Finder? finder}) {
  final target = finder ?? find.byType(SliverPinnedTopBar);
  expect(target, findsOneWidget, reason: 'exactly one pinned header sliver');
  final sliver = tester.renderObject<RenderSliver>(target);
  final geometry = sliver.geometry;
  expect(geometry, isNotNull, reason: 'the pinned header has been laid out');
  return geometry!.scrollExtent;
}

/// Laid-out glyph-run boxes for [text]: the ink extents the paragraph will paint,
/// including runs resolved to a fallback face (emoji, CJK, Arabic).
///
/// A paragraph's line box does not prove a fallback face's ink stays inside it, so
/// the chrome regressions check these boxes against the bar's rect — the same
/// allowance the timeline header tests use.
List<ui.TextBox> glyphBoxes(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(finder, findsOneWidget, reason: 'exactly one "$text" paragraph');
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  return boxes;
}

/// Asserts the painted glyph runs of [text] (not just the paragraph box) stay
/// inside [container].
void expectInkInside(
  WidgetTester tester,
  String text, {
  required Rect container,
  required String label,
}) {
  final rect = tester.getRect(find.text(text));
  final boxes = glyphBoxes(tester, text);
  expect(
    boxes,
    isNotEmpty,
    reason: '$label: "$text" rendered no glyph runs, including fallback ink',
  );
  for (final box in boxes) {
    expect(
      rect.top + box.top,
      greaterThanOrEqualTo(container.top - 0.5),
      reason: '$label: "$text" ink is clipped at the top of its container',
    );
    expect(
      rect.top + box.bottom,
      lessThanOrEqualTo(container.bottom + 0.5),
      reason: '$label: "$text" ink is clipped at the bottom of its container',
    );
  }
}

/// Height the bars' own rule needs for this text, computed from what is painted:
/// the laid-out line box of each paragraph plus breathing that covers the measured
/// ink escape (`max(12, 2 * escape + 2)`), with the 3dp title/subtitle gap.
///
/// This is the *actual fit* criterion for "does it still fit 66dp" - a scale
/// threshold is not, because a face whose ink escapes its line box needs more room
/// even below 1.5x, and a face that fits needs none.
double naturalBarBlockHeight(
  WidgetTester tester, {
  required String title,
  String? subtitle,
}) {
  double escape(String text) {
    final boxes = glyphBoxes(tester, text);
    final lineHeight = paragraphOf(tester, text).size.height;
    var value = 0.0;
    for (final box in boxes) {
      value = math.max(value, -box.top);
      value = math.max(value, box.bottom - lineHeight);
    }
    return math.max(0.0, value);
  }

  final titleLine = paragraphOf(tester, title).size.height;
  final block = subtitle == null
      ? titleLine
      : titleLine + 3 + paragraphOf(tester, subtitle).size.height;
  final maxEscape = subtitle == null
      ? escape(title)
      : math.max(escape(title), escape(subtitle));
  return block + math.max(12.0, maxEscape * 2 + 2);
}
