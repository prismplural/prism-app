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
  static const double buttonMaxWidth = 360;

  static const double desktopBreakpoint = 768;
  static const double desktopBreakpointOff = 720; // hysteresis

  /// Content-area width at which a list screen splits into a two-pane
  /// list-detail layout (list on the left, selected item's detail on the
  /// right). Matches Material 3's "expanded" window size class lower bound.
  /// Measured against the *available content width*, not the whole window —
  /// the desktop sidebar is already subtracted by the time a screen body
  /// measures itself with LayoutBuilder.
  static const double listDetailBreakpoint = 840;

  /// Content-area width at which the two-pane layout steps up to its
  /// "extra wide" tier, giving the list pane more room once the detail pane is
  /// comfortably wide. Tuned a little below Material 3's "large" lower bound
  /// (1200) so the wider list pane appears as soon as there's room for it.
  static const double listDetailBreakpointXWide = 1080;

  /// Width of the list pane in the "wide" tier (just past
  /// [listDetailBreakpoint]). Kept narrow so the detail pane clearly
  /// dominates rather than the two columns looking evenly split.
  static const double listPaneWidth = 360;

  /// Width of the list pane in the "extra wide" tier (past
  /// [listDetailBreakpointXWide]).
  static const double listPaneWidthXWide = 440;

  /// Max width for content-primary screens (dashboards/feeds like home, polls,
  /// boards, stats) so the body doesn't stretch edge-to-edge on wide windows.
  /// These screens clamp their content and open per-item detail in a modal
  /// side sheet rather than squishing into a permanent list pane.
  static const double contentMaxWidth = 720;

  /// Window width at or above which content-primary screens open per-item
  /// detail in a modal side sheet; below this they push a full-screen route.
  static const double detailSideSheetMinWidth = 900;

  /// Width of the modal detail side sheet on wide windows.
  static const double detailSideSheetWidth = 520;

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
  static const double tintedTintAlpha = 0.15;
  static const double tintedDefaultTintAlphaLight = 0.08;
  static const double tintedDefaultTintAlphaDark = 0.14;
  static const double avatarTintAlpha = 0.28;
  static const double avatarAccentBorderAlphaLight = 0.42;
  static const double avatarAccentBorderAlphaDark = 0.56;
  static const double tintedBorderAlphaLight = 0.10;
  static const double tintedBorderAlphaDark = 0.12;
  static const double tintedHighlightAlpha = 0.10;
  static const double tintedShadowBlur = 4.0;
  static const double tintedShadowAlphaLight = 0.03;
  static const double tintedShadowAlphaDark = 0.10;
  static const double tintedNoiseOpacityLight = 0.03;
  static const double tintedNoiseOpacityDark = 0.06;

  // Button glass tokens
  static const double buttonFilledAlphaLight = 0.80;
  static const double buttonFilledPressedAlphaLight = 0.86;
  static const double buttonFilledAlphaDark = 0.96;
  static const double buttonFilledPressedAlphaDark = 1.0;

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
