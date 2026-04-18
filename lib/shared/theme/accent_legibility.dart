import 'dart:math' as math;
import 'dart:ui' show Color;

enum AccentLegibility {
  ok,
  tooDark,
  tooLight,
  tooDesaturated,
}

/// Classify whether an accent color is likely to cause legibility problems.
///
/// Prism renders the accent on both light and dark surfaces, so the color
/// needs enough luminance range and chroma to stay visible in either mode.
AccentLegibility classifyAccentLegibility(Color color) {
  final r = _srgbToLinear(color.r);
  final g = _srgbToLinear(color.g);
  final b = _srgbToLinear(color.b);
  final luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b;

  final saturation = _hslSaturation(color);

  if (saturation < 0.15) return AccentLegibility.tooDesaturated;
  if (luminance < 0.05) return AccentLegibility.tooDark;
  if (luminance > 0.85) return AccentLegibility.tooLight;
  return AccentLegibility.ok;
}

double _srgbToLinear(double c) {
  return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _hslSaturation(Color color) {
  final maxC = math.max(color.r, math.max(color.g, color.b));
  final minC = math.min(color.r, math.min(color.g, color.b));
  final l = (maxC + minC) / 2;
  if (maxC == minC) return 0;
  final d = maxC - minC;
  return l > 0.5 ? d / (2 - maxC - minC) : d / (maxC + minC);
}
