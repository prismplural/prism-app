import 'package:flutter/material.dart';

/// Shared spacing, radius, motion, and glass-treatment constants.
class PrismTokens {
  PrismTokens._();

  static const double radiusSmall = 12;
  static const double radiusMedium = 16;
  static const double radiusLarge = 20;
  static const double radiusXLarge = 24;
  static const double radiusPill = 30;
  static const double radiusNav = 32;

  static const double dialogMaxWidth = 400;

  static const double desktopBreakpoint = 768;
  static const double desktopBreakpointOff = 720; // hysteresis

  static const double topBarHeight = 66;
  static const double topBarActionSize = 44;
  static const double pageHorizontalPadding = 16;
  static const double sectionSpacing = 24;
  static const double sectionSpacingCompact = 12;

  static const double hairlineBorderWidth = 0.5;
  static const double glassBlurSoft = 10;
  static const double glassBlurMedium = 14;
  static const double glassBlurStrong = 20;

  // Tinted (faux) glass tokens
  static const double tintedFillAlphaLight = 0.75;
  static const double tintedFillAlphaDark = 0.10;
  static const double tintedBorderAlphaLight = 0.10;
  static const double tintedBorderAlphaDark = 0.12;
  static const double tintedHighlightAlpha = 0.06;
  static const double tintedShadowBlur = 8.0;
  static const double tintedShadowAlphaLight = 0.06;
  static const double tintedShadowAlphaDark = 0.25;
  static const double tintedNoiseOpacityLight = 0.03;
  static const double tintedNoiseOpacityDark = 0.06;

  static const EdgeInsets pagePadding = EdgeInsets.symmetric(
    horizontal: pageHorizontalPadding,
  );
  static const EdgeInsets sectionPadding = EdgeInsets.fromLTRB(
    pageHorizontalPadding,
    sectionSpacing,
    pageHorizontalPadding,
    sectionSpacingCompact,
  );
  static const EdgeInsets topBarPadding = EdgeInsets.symmetric(horizontal: 12);
}
