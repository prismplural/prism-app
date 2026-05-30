import 'dart:math' as math;

import 'package:flutter/material.dart';

enum AccentLegibility { ok, tooDark, tooLight, tooDesaturated }

const double prismMinimumAccentContrast = 3.0;
const double prismMinimumTextContrast = 4.5;

const Color prismLightAccentBackground = Color(0xFFF1E7D6);
const Color prismDarkAccentBackground = Color(0xFF33302B);

/// Classify whether an accent color is likely to cause legibility problems.
///
/// Prism renders the accent on both light and dark surfaces, so the color
/// needs enough luminance range and chroma to stay visible in either mode.
AccentLegibility classifyAccentLegibility(Color color) {
  final lightContrast = contrastRatio(color, prismLightAccentBackground);
  final darkContrast = contrastRatio(color, prismDarkAccentBackground);
  if (lightContrast < prismMinimumAccentContrast) {
    return AccentLegibility.tooLight;
  }
  if (darkContrast < prismMinimumAccentContrast) {
    return AccentLegibility.tooDark;
  }

  final saturation = _hslSaturation(color);
  if (saturation < 0.15) return AccentLegibility.tooDesaturated;

  return AccentLegibility.ok;
}

/// WCAG relative luminance for an opaque sRGB color.
double relativeLuminance(Color color) {
  final opaque = color.withValues(alpha: 1);
  final r = _srgbToLinear(opaque.r);
  final g = _srgbToLinear(opaque.g);
  final b = _srgbToLinear(opaque.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// WCAG contrast ratio between two opaque colors.
double contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = relativeLuminance(foreground);
  final backgroundLuminance = relativeLuminance(background);
  final lighter = math.max(foregroundLuminance, backgroundLuminance);
  final darker = math.min(foregroundLuminance, backgroundLuminance);
  return (lighter + 0.05) / (darker + 0.05);
}

/// Shift an accent's HSL lightness until it meets [minRatio] on [background].
///
/// The stored accent color remains unchanged; this returns a rendered color for
/// a specific theme brightness so a single saved accent can work in both modes.
Color contrastAdjustedAccent(
  Color color,
  Color background, {
  double minRatio = prismMinimumTextContrast,
}) {
  final opaqueColor = color.withValues(alpha: 1);
  final opaqueBackground = background.withValues(alpha: 1);

  if (contrastRatio(opaqueColor, opaqueBackground) >= minRatio) {
    return opaqueColor;
  }

  final hsl = HSLColor.fromColor(opaqueColor);
  final darken = relativeLuminance(opaqueBackground) > 0.5;

  var low = 0.0;
  var high = 1.0;
  var best = opaqueColor;

  for (var i = 0; i < 24; i++) {
    final amount = (low + high) / 2;
    final lightness = darken
        ? hsl.lightness * (1 - amount)
        : hsl.lightness + (1 - hsl.lightness) * amount;
    final candidate = hsl.withLightness(lightness).toColor();

    if (contrastRatio(candidate, opaqueBackground) >= minRatio) {
      best = candidate;
      high = amount;
    } else {
      low = amount;
    }
  }

  return best;
}

/// Shift an accent until [foreground] remains legible after alpha compositing.
///
/// This is useful for filled controls that intentionally keep a translucent
/// accent fill but still need the same foreground treatment as opaque accent
/// controls.
Color contrastAdjustedTranslucentAccent(
  Color color,
  Color background, {
  required Color foreground,
  required double alpha,
  double minRatio = prismMinimumTextContrast,
}) {
  final opaqueColor = color.withValues(alpha: 1);
  final opaqueBackground = background.withValues(alpha: 1);
  final opaqueForeground = foreground.withValues(alpha: 1);

  bool passes(Color candidate) {
    final rendered = Color.alphaBlend(
      candidate.withValues(alpha: alpha),
      opaqueBackground,
    );
    return contrastRatio(opaqueForeground, rendered) >= minRatio;
  }

  if (passes(opaqueColor)) return opaqueColor;

  final hsl = HSLColor.fromColor(opaqueColor);
  final foregroundIsLight = relativeLuminance(opaqueForeground) > 0.5;

  var low = 0.0;
  var high = 1.0;
  var best = opaqueColor;

  for (var i = 0; i < 24; i++) {
    final amount = (low + high) / 2;
    final lightness = foregroundIsLight
        ? hsl.lightness * (1 - amount)
        : hsl.lightness + (1 - hsl.lightness) * amount;
    final candidate = hsl.withLightness(lightness).toColor();

    if (passes(candidate)) {
      best = candidate;
      high = amount;
    } else {
      low = amount;
    }
  }

  return best;
}

@immutable
class PrismTintedControlColors {
  const PrismTintedControlColors({
    required this.fill,
    required this.foreground,
    required this.border,
    required this.accent,
  });

  final Color fill;
  final Color foreground;
  final Color border;
  final Color accent;
}

/// Contrast-safe colors for compact tinted controls.
PrismTintedControlColors resolveTintedControlColors(
  ThemeData theme, {
  required Color accent,
  Color? fillBase,
  Color? foregroundBase,
  double fillAlpha = 0.15,
  double foregroundAccentWeight = 0.32,
  double borderAlpha = 0.72,
  double borderMinRatio = prismMinimumAccentContrast,
  double foregroundMinRatio = prismMinimumTextContrast,
}) {
  final base = (fillBase ?? theme.colorScheme.surfaceContainerHighest)
      .withValues(alpha: 1);
  final fill = Color.alphaBlend(accent.withValues(alpha: fillAlpha), base);
  final visibleAccent = _contrastAdjustedColorOn(
    accent,
    fill,
    minRatio: borderMinRatio,
  );
  final baseText = (foregroundBase ?? theme.colorScheme.onSurface).withValues(
    alpha: 1,
  );
  final tintedForeground = Color.lerp(
    baseText,
    visibleAccent,
    foregroundAccentWeight,
  )!.withValues(alpha: 1);
  final foreground = contrastRatio(tintedForeground, fill) >= foregroundMinRatio
      ? tintedForeground
      : _contrastAdjustedColorOn(
          tintedForeground,
          fill,
          minRatio: foregroundMinRatio,
        );

  return PrismTintedControlColors(
    fill: fill,
    foreground: foreground,
    border: visibleAccent.withValues(alpha: borderAlpha),
    accent: visibleAccent,
  );
}

/// Pick black or white foreground text for the highest contrast on [background].
Color highContrastForeground(Color background) {
  final opaqueBackground = background.withValues(alpha: 1);
  final whiteContrast = contrastRatio(Colors.white, opaqueBackground);
  final blackContrast = contrastRatio(Colors.black, opaqueBackground);
  return whiteContrast >= blackContrast ? Colors.white : Colors.black;
}

Color _contrastAdjustedColorOn(
  Color color,
  Color background, {
  required double minRatio,
}) {
  final adjusted = contrastAdjustedAccent(
    color,
    background,
    minRatio: minRatio,
  );
  if (contrastRatio(adjusted, background) >= minRatio) return adjusted;
  return highContrastForeground(background);
}

double _srgbToLinear(double c) {
  return c <= 0.04045
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _hslSaturation(Color color) {
  final maxC = math.max(color.r, math.max(color.g, color.b));
  final minC = math.min(color.r, math.min(color.g, color.b));
  final l = (maxC + minC) / 2;
  if (maxC == minC) return 0;
  final d = maxC - minC;
  return l > 0.5 ? d / (2 - maxC - minC) : d / (maxC + minC);
}
