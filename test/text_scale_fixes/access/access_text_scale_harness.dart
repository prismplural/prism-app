// Shared harness for the onboarding, recovery-word and invite text-scale
// regressions.
//
// Mirrors how `lib/app.dart` composes text size: the user's system
// accessibility scaler, then Prism's own font-size preference, delegated per
// font size through [PrismTextScaler] (no global clamp anywhere). Real bundled
// faces (Lexend/OpenDyslexic + the emoji fallback) are loaded so measurements
// come from the glyphs the app actually paints, not the square test font.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/prism_text_scaler.dart';

import '../../helpers/prism_golden.dart' show loadPrismGoldenFonts;

/// Compact phone the scenario is measured on.
const Size compactPhone = Size(320, 568);

/// Desktop/tablet width used for the "wide" controls.
const Size wideDesktop = Size(1440, 900);

/// Platform accessibility ceiling used by the stress scenarios (225%).
const TextScaler maxSystemScaler = TextScaler.linear(2.25);

/// Prism's own font-size ceiling (150%).
const double maxAppFontScale = 1.5;

/// A long, narrow window: same 320dp width as the compact phone but enough
/// height for the shared onboarding header. Used only where a case measures a
/// horizontal defect and must not also exercise the separate header/body
/// vertical squeeze on short windows.
const Size narrowTallPhone = Size(320, 1800);

Future<void> loadAccessFonts() => loadPrismGoldenFonts();

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

/// Theme with the bundled faces the app ships; [family] selects which one.
ThemeData accessTheme({String family = 'OpenDyslexic'}) =>
    ThemeData(fontFamily: family, fontFamilyFallback: const ['NotoColorEmoji']);

/// MaterialApp that composes the system scaler with Prism's preference exactly
/// like `app.dart`, so measurements see the same text size the user chose.
Widget accessApp(
  Widget home, {
  TextScaler? systemScaler,
  double appFontScale = 1.0,
  ThemeData? theme,
}) {
  return MaterialApp(
    theme: theme ?? accessTheme(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en')],
    builder: (context, child) {
      final content = child ?? const SizedBox.shrink();
      if (systemScaler == null) return content;
      return MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: PrismTextScaler(systemScaler, appFontScale)),
        child: content,
      );
    },
    home: home,
  );
}

/// A deliberately nonlinear scaler: no case may assume a single scale ratio or
/// derive one length from another by multiplication.
class NonlinearTextScaler extends TextScaler {
  const NonlinearTextScaler();

  @override
  double scale(double fontSize) =>
      fontSize < 20 ? fontSize * 3.0 : fontSize * 1.6;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => 1.0;

  @override
  bool operator ==(Object other) => other is NonlinearTextScaler;

  @override
  int get hashCode => 0x4e0a;
}

/// The scaler in effect inside the widget under test.
TextScaler effectiveScaler(WidgetTester tester, Finder finder) =>
    MediaQuery.textScalerOf(tester.element(finder));

/// The paragraph a [Text] really rendered: its resolved span (family, height,
/// leading included), scaler, direction, locale and the width it was given.
///
/// Measuring from this - never from `Text.style` - is what makes a height
/// assertion describe the glyphs on screen. `Text.style` carries only the
/// explicit part of the style, so a painter built from it silently drops the
/// ambient DefaultTextStyle and the app's font family.
RenderParagraph paragraphOf(WidgetTester tester, Finder textFinder) {
  return tester.renderObject<RenderParagraph>(
    find.descendant(of: textFinder, matching: find.byType(RichText)).first,
  );
}

double _layoutWidth(RenderParagraph paragraph) {
  final width = paragraph.constraints.hasBoundedWidth
      ? paragraph.constraints.maxWidth
      : paragraph.size.width;
  // RenderParagraph widens the layout to infinity when the text neither wraps
  // nor ellipsises (`softWrap || overflow == ellipsis ? maxWidth : infinity`).
  // TextPainter has no softWrap/overflow parameters, so mirror that decision
  // here instead of inventing constructor fields.
  return paragraph.softWrap || paragraph.overflow == TextOverflow.ellipsis
      ? width
      : double.infinity;
}

double _layoutMinWidth(RenderParagraph paragraph) =>
    paragraph.constraints.hasBoundedWidth ? paragraph.constraints.minWidth : 0;

/// A painter configured exactly like the paragraph's own, so heights and line
/// counts describe the same glyphs.
TextPainter _mirrorPainter(
  RenderParagraph paragraph, {
  bool unboundedLines = false,
}) {
  return TextPainter(
    text: paragraph.text,
    textAlign: paragraph.textAlign,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    maxLines: unboundedLines ? null : paragraph.maxLines,
    ellipsis: paragraph.overflow == TextOverflow.ellipsis ? '\u2026' : null,
    locale: paragraph.locale,
    textWidthBasis: paragraph.textWidthBasis,
    textHeightBehavior: paragraph.textHeightBehavior,
  );
}

/// Height [paragraph]'s own span needs at the width it was given.
///
/// [unboundedLines] drops the widget's own line cap so a case can ask for the
/// full natural height; the default keeps the cap the widget renders with,
/// which is what "not squeezed" means.
double paragraphHeight(
  RenderParagraph paragraph, {
  bool unboundedLines = false,
  double? atWidth,
}) {
  final painter = _mirrorPainter(paragraph, unboundedLines: unboundedLines)
    ..layout(
      minWidth: atWidth == null ? _layoutMinWidth(paragraph) : 0,
      maxWidth: atWidth ?? _layoutWidth(paragraph),
    );
  return painter.height;
}

/// Number of lines [paragraph]'s span needs at the width it was given.
int paragraphLineCount(RenderParagraph paragraph) {
  final painter = _mirrorPainter(paragraph)
    ..layout(
      minWidth: _layoutMinWidth(paragraph),
      maxWidth: _layoutWidth(paragraph),
    );
  return painter.computeLineMetrics().length;
}

/// Upper bound: the tallest [paragraph]'s own span can be at the width it was
/// given, computed by the paragraph itself.
///
/// `getMaxIntrinsicHeight` is the SDK's own answer for "how tall would this
/// paragraph be at this width with the line cap lifted", so the bound cannot
/// disagree with the text on screen. Rebuilding a painter at an unbounded one-line
/// width was wrong: at large text it reported a single line (32dp) for a label
/// that legitimately wraps to two (64dp) and turned a correct layout into a
/// failure.
double paragraphMaxIntrinsicHeight(RenderParagraph paragraph) =>
    paragraph.getMaxIntrinsicHeight(_layoutWidth(paragraph));

/// Width [paragraph]'s span needs on one line at its own size.
double paragraphIntrinsicWidth(RenderParagraph paragraph) {
  final painter = _mirrorPainter(paragraph)..layout();
  return painter.width;
}

/// The editable text render object inside a text field.
RenderEditable editableOf(WidgetTester tester, Finder fieldFinder) {
  final fieldRect = tester.getRect(fieldFinder);
  for (final candidate in tester.allRenderObjects.whereType<RenderEditable>()) {
    if (!candidate.attached || !candidate.hasSize) continue;
    final rect = candidate.localToGlobal(Offset.zero) & candidate.size;
    if (fieldRect.contains(rect.center)) return candidate;
  }
  throw StateError('no RenderEditable inside $fieldFinder');
}

/// Height one line of [editable]'s own span needs.
///
/// `RenderEditable.preferredLineHeight` is the SDK's own measurement of a
/// typical line in that editable's style, scaler and locale, so it needs no
/// re-created painter and cannot disagree with the glyphs on screen.
double editableLineHeight(RenderEditable editable) =>
    editable.preferredLineHeight;

/// True when [inner] sits inside [outer] (with a half-pixel of slack): the
/// no-shrink check - a laid-out box that paints outside its container has been
/// clipped or displaced.
bool rectInside(Rect inner, Rect outer, {double slack = 0.5}) =>
    inner.top >= outer.top - slack &&
    inner.bottom <= outer.bottom + slack &&
    inner.left >= outer.left - slack &&
    inner.right <= outer.right + slack;
