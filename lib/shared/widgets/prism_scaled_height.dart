import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:prism_plurality/shared/theme/prism_tokens.dart';

/// A chrome widget that can report the height it needs at the ambient text
/// scale — the user's system accessibility scaler composed with Prism's own
/// font-size preference (`PrismTextScaler` in `app.dart`), never clamped and
/// never rounded to a constant.
///
/// A pinned header has to know its extent before its child is laid out, so a bar
/// that can grow exposes this instead of relying on a fixed
/// [PreferredSizeWidget] size. [preferredHeightFor] returns the height at the
/// ambient text scale; the returned value excludes system padding (the safe-area
/// top), which the sliver adds once for every bar.
abstract interface class PrismScaledHeight {
  /// Height this widget needs, at the text scale in [context].
  ///
  /// [availableWidth] is the cross-axis space the widget will actually be given,
  /// when the caller knows it. Content that wraps or that sizes itself from its
  /// own width (filter rows, segmented tracks, chip strips) must measure against
  /// this width instead of guessing from the window; content that is a single
  /// ellipsised line is width-independent and may ignore it.
  double preferredHeightFor(BuildContext context, {double? availableWidth});
}

/// The effective [TextStyle] a [Text] with [style] paints in, at [context].
///
/// Mirrors `Text.build` in `flutter/lib/src/widgets/text.dart`: the ambient
/// [DefaultTextStyle] is merged **only** when [style] is null or `style.inherit`,
/// and `MediaQuery.boldText` is applied last as [FontWeight.bold] (w700). A
/// measurement that skips either step measures a different face or weight from the
/// one that is painted, which is exactly how a bar ends up a few dp short.
///
/// This is the style every measurement painter in this file starts from; callers
/// pass the style they hand to [Text] (theme style, or a caller override), not a
/// pre-merged one.
TextStyle prismTextStyleForMeasurement(BuildContext context, TextStyle? style) {
  final defaultTextStyle = DefaultTextStyle.of(context);
  TextStyle effective;
  if (style == null || style.inherit) {
    effective = defaultTextStyle.style.merge(style);
  } else {
    effective = style;
  }
  if (MediaQuery.boldTextOf(context)) {
    effective = effective.merge(const TextStyle(fontWeight: FontWeight.bold));
  }
  return effective;
}

/// [TextHeightBehavior] the painted text inherits, for measurement painters.
TextHeightBehavior? prismTextHeightBehaviorFor(BuildContext context) =>
    DefaultTextStyle.of(context).textHeightBehavior;

/// Height one line of [text] occupies at the text scale in [context], measured
/// by laying the paragraph out with the resolved style, scaler and text
/// direction.
///
/// Deliberately not `fontSize * textScaleFactor`: the composed scaler is
/// nonlinear on platforms that expose one, and a face's line box is not its em
/// square. The text itself is measured, not a representative glyph, because a
/// run resolved to a fallback face (emoji, CJK, Arabic) can report a taller line
/// box than the primary face — laying out `'M'` alone would under-measure
/// exactly those titles.
///
/// This is the paragraph's line box, i.e. the box the text paints in and the box
/// a bar can reserve. A fallback face can still draw ink a little outside its
/// own line box, which is why the bars keep breathing space above and below the
/// block when they grow (see [PrismTopBar]'s grown padding) and why the
/// regressions assert glyph-run ink boxes, not only the paragraph box (the same
/// allowance the timeline header uses).
double prismLineHeight(
  BuildContext context,
  TextStyle? style, {
  String text = 'M',
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: prismTextStyleForMeasurement(context, style),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    textHeightBehavior: prismTextHeightBehaviorFor(context),
    locale: Localizations.maybeLocaleOf(context),
    maxLines: 1,
  )..layout();
  final height = painter.height;
  painter.dispose();
  return height;
}

/// Height [bar] needs at the text scale in [context].
///
/// A [PrismScaledHeight] bar reports its own measured height; any other
/// [PreferredSizeWidget] keeps its declared `preferredSize` (so a bar that has
/// not opted in behaves exactly as before); anything else falls back to the
/// [PrismTokens.topBarHeight] minimum.
double prismScaledHeightOf(
  BuildContext context,
  Widget bar, {
  double? availableWidth,
}) {
  // A typed pattern, not an `is` promotion: [Widget] and the two interfaces are
  // unrelated types, so Dart does not promote across the test.
  if (bar case final PrismScaledHeight scaled) {
    return scaled.preferredHeightFor(context, availableWidth: availableWidth);
  }
  if (bar case final PreferredSizeWidget sized) {
    return sized.preferredSize.height;
  }
  return PrismTokens.topBarHeight;
}

/// Resolves [bar]'s height for a slot that reserves a fixed extent.
///
/// `Scaffold.appBar` is the only such slot in Prism: it caps its child at
/// `AppBar.preferredHeightFor(context, appBar.preferredSize) +
/// MediaQuery.padding.top` (`scaffold.dart`, `_ScaffoldSlot.appBar`), so a bar
/// whose [PreferredSizeWidget.preferredSize] is a constant cannot grow there —
/// `preferredSize` is a getter without a `BuildContext`.
///
/// Use this adapter where a context exists, and pass the *content* height: the
/// returned size excludes the status bar, because `Scaffold` adds
/// `MediaQuery.padding.top` to the cap itself and the bar's own `SafeArea`
/// consumes it. Adding the inset here as well would reserve a status bar of
/// empty space above the bar.
///
/// ```dart
/// final bar = PrismGlassAppBar(title: title);
/// return Scaffold(appBar: prismScaledPreferredSize(context, bar));
/// ```
///
/// Bars that do not implement [PrismScaledHeight] fall back to their declared
/// `preferredSize` (see [prismScaledHeightOf]), i.e. exactly today's behaviour.
PreferredSizeWidget prismScaledPreferredSize(
  BuildContext context,
  Widget bar, {
  double? availableWidth,
}) {
  return PreferredSize(
    preferredSize: Size.fromHeight(
      prismScaledHeightOf(context, bar, availableWidth: availableWidth),
    ),
    child: bar,
  );
}

/// How far [text]'s glyph ink escapes its own line box, vertically.
///
/// A paragraph's height is its line box; a run resolved to a fallback face can
/// still paint above the first line's top or below its bottom (emoji, CJK, and
/// faces with unusual ascenders — the same allowance the timeline header makes).
/// Returns the larger of the two escapes, so a bar that keeps this much space
/// above *and* below a block of height [prismLineHeight] contains the ink at the
/// requested text size without shrinking anything.
///
/// Measured from the same paragraph the text will paint (style, scaler and
/// direction), via the laid-out run boxes; additive helper, no existing
/// signature or behaviour is changed by it.
double prismTextInkEscape(
  BuildContext context,
  TextStyle? style, {
  required String text,
}) {
  if (text.isEmpty) return 0;
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: prismTextStyleForMeasurement(context, style),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    textHeightBehavior: prismTextHeightBehaviorFor(context),
    locale: Localizations.maybeLocaleOf(context),
    maxLines: 1,
  )..layout();
  final boxes = painter.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  final lineHeight = painter.height;
  var escape = 0.0;
  for (final box in boxes) {
    escape = math.max(escape, -box.top);
    escape = math.max(escape, box.bottom - lineHeight);
  }
  painter.dispose();
  return math.max(0.0, escape);
}
