import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/widgets/prism_scaled_height.dart';

/// Space for the configured glyph at its actual requested text size.
///
/// This is presentation-only work per visible habit build. No state is retained
/// and no completion history is scanned. Measure the same inherited style that
/// the Text uses rather than guessing from a font-size ratio.
double habitIconExtent(
  BuildContext context,
  String? icon, {
  required double fontSize,
  required double minimum,
}) {
  if (icon == null || icon.isEmpty) return minimum;
  // The glyph is a `Text` with `style: TextStyle(fontSize: ...)`, so the measurement
  // resolves the style the same way `Text` does (ambient merge plus the bold-text flag)
  // and passes the inherited locale and height behaviour, which is what keeps a
  // fallback emoji face's box from being under-measured.
  final painter = TextPainter(
    text: TextSpan(
      text: icon,
      style: prismTextStyleForMeasurement(
        context,
        TextStyle(fontSize: fontSize),
      ),
    ),
    textScaler: MediaQuery.textScalerOf(context),
    textDirection: Directionality.of(context),
    textHeightBehavior: prismTextHeightBehaviorFor(context),
    locale: Localizations.maybeLocaleOf(context),
    maxLines: 1,
  )..layout();
  try {
    return math
        .max(minimum, math.max(painter.width, painter.height) + 8)
        .ceilToDouble();
  } finally {
    painter.dispose();
  }
}
