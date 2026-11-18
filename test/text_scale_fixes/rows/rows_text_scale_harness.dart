// Shared harness for the list-row text-scale regressions: label/value rows (member
// stats, statistics overview, database diagnostics, the crypto engine state), the
// ranking chart's slot bounds, navigation-editor rows, the sleep warning chip, the
// conversation tile, the post header, the board section header and the reminder
// composer's label/control rows.
//
// Text size is composed exactly like `lib/app.dart`: the user's system
// accessibility scaler, then Prism's own font-size preference, delegated per
// font size through [PrismTextScaler]. Nothing is clamped. The real bundled
// faces are loaded so measurements come from the glyphs the app paints.
//
// Every assertion is about painted geometry: a paragraph's own laid-out width
// is compared with the text it would need, and its rect is compared with the
// row/card/window it has to stay inside. An ancestor such as `FittedBox` or a
// squeezed `Row` can leave a paragraph's width intact while painting it
// outside, so both are checked.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/l10n/app_localizations.dart';
import 'package:prism_plurality/shared/theme/prism_text_scaler.dart';

import '../../helpers/prism_golden.dart' show loadPrismGoldenFonts;

/// Narrow phone: the narrowest width these rows have to survive.
const Size compactPhone = Size(320, 568);

/// Ordinary phone width.
const Size phoneWindow = Size(390, 780);

/// Compact phone width with a tall viewport, for screens whose body is a lazy
/// `ListView`: the horizontal geometry under test is the compact 320dp width,
/// while the height only makes sure every section is actually built.
const Size tallCompactPage = Size(320, 4000);

/// Wide window (tablet/desktop) used to prove the fix does not depend on a
/// narrow viewport.
const Size wideWindow = Size(1024, 900);

/// (system accessibility scaler, Prism font-size preference, label).
const List<(double, double, String)> rowsScales = [
  (1.0, 0.5, 'system 100% x Prism 50% = 0.5x'),
  (1.0, 1.0, 'default text'),
  (1.5, 1.0, 'large text'),
  (2.25, 1.5, 'system 225% x Prism 150% = 3.375x'),
];

/// The two bundled faces the app ships for body text.
const List<String> rowsFontFamilies = ['Lexend', 'OpenDyslexic'];

Future<void> loadRowsFonts() => loadPrismGoldenFonts();

/// Deterministic window size for one test.
void useWindow(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

ThemeData rowsTheme(String fontFamily) => ThemeData(
  fontFamily: fontFamily,
  fontFamilyFallback: const ['NotoColorEmoji'],
);

/// MaterialApp that composes the system scaler with Prism's preference exactly
/// like `app.dart`.
Widget rowsApp(
  Widget home, {
  required double system,
  required double app,
  String fontFamily = 'Lexend',
  TextScaler? scalerOverride,
  Locale locale = const Locale('en'),
  RouterConfig<Object>? routerConfig,
  TextDirection? textDirection,
}) {
  final scaler =
      scalerOverride ?? PrismTextScaler(TextScaler.linear(system), app);
  Widget builder(BuildContext context, Widget? child) {
    final content = MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: scaler),
      child: child ?? const SizedBox.shrink(),
    );
    if (textDirection == null) return content;
    return Directionality(textDirection: textDirection, child: content);
  }

  if (routerConfig != null) {
    return MaterialApp.router(
      theme: rowsTheme(fontFamily),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('en'), Locale('es')],
      locale: locale,
      routerConfig: routerConfig,
      builder: builder,
    );
  }

  return MaterialApp(
    theme: rowsTheme(fontFamily),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: const [Locale('en'), Locale('es')],
    locale: locale,
    builder: builder,
    home: home,
  );
}

/// A deliberately nonlinear scaler: no row may assume that one length follows
/// from multiplying another by a single ratio.
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
  int get hashCode => 0x726f7773; // 'rows'
}

/// The paragraph that paints [finder]; exactly one must match.
RenderParagraph paragraphOf(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  return tester.renderObject<RenderParagraph>(finder);
}

/// Height [paragraph] needs at the width it was actually given.
///
/// Measured through the render object's own intrinsics: `RenderParagraph` keeps a
/// **separate** cached painter for this (`_textIntrinsics`) and re-copies the real
/// one into it on every access - same `InlineSpan` tree, same `maxLines`, same
/// `ellipsis`, locale, strut style and height behaviour - so the measurement can
/// neither disagree with what the paragraph paints nor disturb its layout. In
/// particular an intentionally ellipsised one-line string measures as one line and
/// is not mistaken for vertically clipped text.
double neededHeightAt(RenderParagraph paragraph) =>
    paragraph.getMaxIntrinsicHeight(paragraph.size.width);

/// Width [paragraph] needs if none of its text may wrap (the "one line" width).
///
/// Same intrinsic path as [neededHeightAt], so a mixed `InlineSpan` tree keeps its
/// per-span styles; nothing is flattened to a single `TextStyle`.
double neededSingleLineWidth(RenderParagraph paragraph) =>
    paragraph.getMaxIntrinsicWidth(double.infinity);

/// A painter that mirrors [paragraph] exactly, for measurements the render object
/// does not expose (line count).
///
/// Every property that changes shaping is copied from the paragraph itself, and
/// the text is the paragraph's own `InlineSpan`, so mixed span styles survive.
TextPainter clonedParagraphPainter(RenderParagraph paragraph) {
  return TextPainter(
    text: paragraph.text,
    textAlign: paragraph.textAlign,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    locale: paragraph.locale,
    strutStyle: paragraph.strutStyle,
    textWidthBasis: paragraph.textWidthBasis,
    textHeightBehavior: paragraph.textHeightBehavior,
    maxLines: paragraph.maxLines,
    ellipsis: paragraph.overflow == TextOverflow.ellipsis ? '\u2026' : null,
  );
}

/// Number of lines [paragraph] is actually laid out in.
///
/// Counted from the layout's own line metrics, using a painter that mirrors the
/// paragraph (see [clonedParagraphPainter]); a one-line ellipsised string counts as
/// one line.
int lineCountOf(RenderParagraph paragraph) {
  final painter = clonedParagraphPainter(paragraph)
    ..layout(maxWidth: paragraph.size.width);
  final lines = painter.computeLineMetrics().length;
  painter.dispose();
  return lines;
}

/// Opt-in switch for the cause filters below, read from the environment at compile
/// time.
///
/// It exists so a single widget's layout defect can be measured while a *different*
/// surface on the same screen (a fixed-height top bar, a segmented control) is still
/// being fixed. It is unset by default, and when it is unset the filters are `null` and
/// no layout error is ever ignored - a passing run cannot hide a real overflow.
const bool kLayoutBaseline = bool.fromEnvironment('PRISM_LAYOUT_BASELINE');

/// Layout errors caused by a fixed-height top or sheet bar (`prism_top_bar.dart`,
/// `prism_sheet.dart`), i.e. a title/subtitle that outgrows a constant bar height. Only
/// ever non-`null` when [kLayoutBaseline] asks for it.
final RegExp? fixedHeightBarLayoutErrors = kLayoutBaseline
    ? RegExp(r'prism_(top_bar|sheet)\.dart')
    : null;

/// Layout errors caused by the segmented control (`prism_segmented_control.dart`), i.e.
/// a fixed-height track whose labels outgrow it. Only ever non-`null` when
/// [kLayoutBaseline] asks for it.
final RegExp? segmentedControlLayoutErrors = kLayoutBaseline
    ? RegExp(r'prism_segmented_control\.dart')
    : null;

/// Pumps in small steps until [finder] matches, then stops.
///
/// `pumpAndSettle` cannot be used on a screen that shows a [PrismSpinner]: its
/// `AnimationController.repeat()` never settles, so `pumpAndSettle` reports a
/// timeout even though the widget under test rendered. This waits for the real
/// condition instead (the expected content) and fails with a readable message if
/// it never arrives, which distinguishes "the fixture never produced data" from a
/// geometry failure.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  String label = 'content',
  Duration timeout = const Duration(seconds: 10),
}) async {
  final steps = (timeout.inMilliseconds / 20).ceil();
  for (var i = 0; i < steps; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 20));
  }
  // One last frame so the failure message shows the tree that actually built.
  await tester.pump();
  expect(
    finder,
    findsWidgets,
    reason:
        '$label did not appear within ${timeout.inSeconds}s of pumped frames - '
        'the fixture, not the layout, is the likely cause',
  );
}

/// Pumps in small steps until [finder] matches nothing.
///
/// The readiness signal for screens whose data arrives asynchronously and whose
/// loading state is animated: a repeating spinner never lets `pumpAndSettle` finish,
/// and "the widget exists" can be true on the very first frame, before the futures
/// resolve. Asserting that the loading indicator is *gone* is both bounded and
/// meaningful.
Future<void> pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  String label = 'loading indicator',
  Duration timeout = const Duration(seconds: 10),
}) async {
  final steps = (timeout.inMilliseconds / 20).ceil();
  for (var i = 0; i < steps; i++) {
    if (finder.evaluate().isEmpty) return;
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(
    finder,
    findsNothing,
    reason: '$label was still on screen after ${timeout.inSeconds}s of pumping',
  );
}

/// Fails when layout reported a `RenderFlex overflowed` (or any other) error.
///
/// Drains every pending exception, not just the first: several rows can overflow
/// in one frame, and a leftover would otherwise fail the test at teardown with no
/// useful message.
///
/// [ignoreCauseMatching] drops errors whose text names a surface owned by another
/// surface. Use it only with a specific file reference (for example a fixed-height
/// top bar), and say so in the test comment: this test
/// then proves nothing about that surface.
void expectNoLayoutError(
  WidgetTester tester, {
  required String label,
  RegExp? ignoreCauseMatching,
  RegExp? ignoreAlso,
}) {
  bool isIgnored(String text) =>
      (ignoreCauseMatching?.hasMatch(text) ?? false) ||
      (ignoreAlso?.hasMatch(text) ?? false);
  final patterns = [ignoreCauseMatching, ignoreAlso].nonNulls.toList();
  final errors = <String>[];
  final ignored = <String>[];
  for (
    Object? error = tester.takeException();
    error != null;
    error = tester.takeException()
  ) {
    final text = error.toString();
    if (isIgnored(text)) {
      ignored.add(text.split('\n').first);
      continue;
    }
    errors.add(text.split('\n').first);
  }
  expect(
    errors,
    isEmpty,
    reason:
        '$label: layout reported ${errors.length} error(s): '
        '${errors.join(' | ')}'
        '${ignored.isEmpty ? '' : ' (ignored ${ignored.length} from '
                  '${patterns.map((p) => p.pattern).join(', ')})'}',
  );
}

/// Asserts [finder] paints inside [bounds] (defaults to the window).
void expectPaintedInside(
  WidgetTester tester,
  Finder finder, {
  required String label,
  Rect? bounds,
}) {
  final window =
      bounds ??
      Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
  final rect = tester.getRect(finder);
  expect(
    rect.left,
    greaterThanOrEqualTo(window.left - 0.5),
    reason: '$label: left edge ${rect.left} is outside ${window.left}',
  );
  expect(
    rect.right,
    lessThanOrEqualTo(window.right + 0.5),
    reason: '$label: right edge ${rect.right} is outside ${window.right}',
  );
  expect(
    rect.top,
    greaterThanOrEqualTo(window.top - 0.5),
    reason: '$label: top edge ${rect.top} is outside ${window.top}',
  );
  expect(
    rect.bottom,
    lessThanOrEqualTo(window.bottom + 0.5),
    reason: '$label: bottom edge ${rect.bottom} is outside ${window.bottom}',
  );
}

/// Asserts every paragraph inside [container] paints inside its rect.
///
/// A `Row` that overflows still reports its own constrained size, so the
/// overflow shows up in its children instead: a non-flex child keeps its
/// intrinsic width and its rect leaves the container. This walks the painted
/// paragraphs rather than trusting the row's own box.
void expectDescendantTextInside(
  WidgetTester tester,
  Finder container, {
  required String label,
}) {
  final containerRect = tester.getRect(container);
  final paragraphs = find.descendant(
    of: container,
    matching: find.byType(RichText),
  );
  for (final element in paragraphs.evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final rect = paragraph.localToGlobal(Offset.zero) & paragraph.size;
    final text = paragraph.text.toPlainText();
    expect(
      rect.left,
      greaterThanOrEqualTo(containerRect.left - 0.5),
      reason:
          '$label: "$text" starts outside its container '
          '(${rect.left} < ${containerRect.left})',
    );
    expect(
      rect.right,
      lessThanOrEqualTo(containerRect.right + 0.5),
      reason:
          '$label: "$text" paints past its container '
          '(${rect.right} > ${containerRect.right})',
    );
  }
}

/// Asserts [finder]'s paragraph is laid out in at most [maxLines] lines.
///
/// Rule, deliberately narrow: **finite, static label text that the app authors** -
/// a navigation destination name ("Chat", "Settings") - must stay readable as a
/// label instead of being shattered into one or two characters per line behind a
/// row of 44dp controls.
///
/// It is **not** a general policy. Unbounded user content (conversation titles,
/// member names, note titles) is out of scope: it may ellipsise or wrap freely, and
/// that trade-off is accepted - do not assert against it with this helper.
void expectAtMostLines(
  WidgetTester tester,
  Finder finder, {
  required int maxLines,
  required String label,
}) {
  final paragraph = paragraphOf(tester, finder);
  final lines = lineCountOf(paragraph);
  expect(
    lines,
    lessThanOrEqualTo(maxLines),
    reason:
        '$label: "${paragraph.text.toPlainText()}" is laid out in $lines line(s); '
        'at most $maxLines expected for finite label text',
  );
}

/// Asserts a **static, app-authored label** is painted in full at the requested
/// size: no ellipsis and no vertical clamp.
///
/// Use this only for text the app itself writes and the user cannot make longer -
/// section labels, row labels, hints, counts, formatted timestamps. For unbounded
/// user content use [expectNotVerticallyClipped] instead.
void expectStaticLabelFullyPainted(
  WidgetTester tester,
  Finder finder, {
  required String label,
}) {
  final paragraph = paragraphOf(tester, finder);
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: '$label: "${paragraph.text.toPlainText()}" was ellipsised',
  );
  final needed = neededHeightAt(paragraph);
  expect(
    paragraph.size.height,
    greaterThanOrEqualTo(needed - 0.5),
    reason:
        '$label: "${paragraph.text.toPlainText()}" needs '
        '${needed.toStringAsFixed(1)}px but is laid out at '
        '${paragraph.size.height.toStringAsFixed(1)}px',
  );
}

/// Asserts a paragraph is not chopped vertically.
///
/// This is the right check for **user content that is allowed to truncate
/// horizontally** (conversation titles, member names): a single-line ellipsis is
/// accepted, being clipped by a shorter box is not. The comparison uses the
/// paragraph's own `maxLines`/`ellipsis`, so an ellipsised one-liner measures as one
/// line.
void expectNotVerticallyClipped(
  WidgetTester tester,
  Finder finder, {
  required String label,
}) {
  final paragraph = paragraphOf(tester, finder);
  final needed = neededHeightAt(paragraph);
  expect(
    paragraph.size.height,
    greaterThanOrEqualTo(needed - 0.5),
    reason:
        '$label: "${paragraph.text.toPlainText()}" needs '
        '${needed.toStringAsFixed(1)}px at this width but is laid out at '
        '${paragraph.size.height.toStringAsFixed(1)}px',
  );
}

/// Asserts a single-line paragraph is given at least the width its text needs at
/// the requested size, i.e. its own measured width was honoured.
///
/// Used for the ranking chart, whose contract is that the slot is sized from the
/// measured name ("labels never wrap or clip"). It says nothing about how the width
/// is won, and it does not treat a name as required to be ellipsis-free elsewhere.
void expectHonoursSingleLineWidth(
  WidgetTester tester,
  Finder finder, {
  required String label,
}) {
  final paragraph = paragraphOf(tester, finder);
  final needed = neededSingleLineWidth(paragraph);
  expect(
    paragraph.size.width,
    greaterThanOrEqualTo(needed - 0.5),
    reason:
        '$label: "${paragraph.text.toPlainText()}" is given '
        '${paragraph.size.width.toStringAsFixed(1)}px but needs '
        '${needed.toStringAsFixed(1)}px on one line',
  );
}

/// Asserts two widgets are laid out beside each other (their rects overlap
/// vertically). Content that fits must not be pushed onto separate lines.
void expectOnTheSameLine(
  WidgetTester tester,
  Finder a,
  Finder b, {
  required String label,
}) {
  final rectA = tester.getRect(a);
  final rectB = tester.getRect(b);
  expect(
    rectA.top,
    lessThan(rectB.bottom),
    reason:
        '$label: not on the same line - A is ${rectA.top}..${rectA.bottom}, '
        'B is ${rectB.top}..${rectB.bottom}',
  );
  expect(
    rectB.top,
    lessThan(rectA.bottom),
    reason:
        '$label: not on the same line - B is ${rectB.top}..${rectB.bottom}, '
        'A is ${rectA.top}..${rectA.bottom}',
  );
}
