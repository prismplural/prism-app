import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_scaled_height.dart';

/// Digits measured for every key so the pad uses one consistent extent.
const kPinNumpadDigits = <String>[
  '0',
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '7',
  '8',
  '9',
];

/// Breathing room kept above, below and beside a PIN key's digit so the glyph
/// never touches the key's rounded edge.
const double kPinNumpadKeyVerticalPadding = 8.0;
const double kPinNumpadKeyHorizontalPadding = 8.0;

Size _digitSize(
  BuildContext context,
  TextStyle style,
  String digit, {
  double? maxWidth,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: digit,
      style: prismTextStyleForMeasurement(context, style),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
    textHeightBehavior: prismTextHeightBehaviorFor(context),
    maxLines: 1,
  )..layout(maxWidth: maxWidth ?? double.infinity);
  final size = Size(painter.width, painter.height);
  painter.dispose();
  return size;
}

/// Height of one line of [style] at the ambient text scale, for the tallest digit.
double pinNumpadDigitLineHeight(BuildContext context, TextStyle style) {
  var height = 0.0;
  for (final digit in kPinNumpadDigits) {
    height = math.max(height, _digitSize(context, style, digit).height);
  }
  return height;
}

/// Natural (unwrapped) advance of the widest digit in [style] at the ambient
/// text scale.
double pinNumpadDigitWidth(BuildContext context, TextStyle style) {
  var width = 0.0;
  for (final digit in kPinNumpadDigits) {
    width = math.max(width, _digitSize(context, style, digit).width);
  }
  return width;
}

/// Painted size of one PIN numpad key for a caller asking for [size].
///
/// Default geometry is preserved: while every digit's line box and advance still
/// fit inside [size] the key stays square at [size] (up to ~1.8x on the 64dp
/// keys and ~2x on the 72dp ones). Past that the key grows to hold the digit at
/// the requested font size - vertically by the line box plus padding, and
/// horizontally only if a glyph ever gets wider than the caller's key, which a
/// digit does not at the bundled faces but a substituted font could. Every key in
/// a pad resolves to the same extent because the measurement covers 0-9.
({double width, double height}) pinNumpadKeyExtent(
  BuildContext context, {
  required double size,
  required TextStyle style,
}) {
  final digitHeight = pinNumpadDigitLineHeight(context, style);
  final digitWidth = pinNumpadDigitWidth(context, style);
  // TintedGlassSurface's decoration consumes one hairline on EACH edge.
  // Compare with its usable interior, not the outer key: a 71.82dp digit does
  // not fit in the 71dp interior of a 72dp glass key. The flat cell uses this
  // same conservative envelope, so all shared callers size consistently.
  const borderExtent = PrismTokens.hairlineBorderWidth * 2;
  final minimum = math.max(44.0, size);
  return (
    width: digitWidth + borderExtent <= minimum
        ? minimum
        : digitWidth + borderExtent + kPinNumpadKeyHorizontalPadding * 2,
    height: digitHeight + borderExtent <= minimum
        ? minimum
        : digitHeight + borderExtent + kPinNumpadKeyVerticalPadding,
  );
}
