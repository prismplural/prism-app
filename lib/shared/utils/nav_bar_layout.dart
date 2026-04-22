import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Hard ceiling for persisted primary tabs. Rendering may choose a smaller
/// visible count on constrained devices.
const int kMaxPrimaryNavTabs = 5;

/// Minimum labeled destinations we allow in the collapsed bar before relying
/// on the More menu. This is intentionally below platform "ideal" guidance so
/// extreme accessibility sizes can still preserve readable labels without
/// wrapping or clipping.
const int kMinAdaptivePrimaryNavTabs = 2;

/// When the More trigger is visible, prefer the native-feeling 4+More shape
/// and only drop lower if labeled tabs still do not fit.
const int kPreferredPrimaryTabsWithOverflow = 4;

/// Expanded overflow menu uses up to 5 columns and can fall back to 2 when
/// larger text or localized labels need more width to preserve one-line labels.
/// The fit-check in [_maxFittingOverflowColumns] steps down from the cap until
/// labels fit, so this is purely an upper bound — scaled text and long labels
/// still collapse to fewer columns as needed.
const int kMinAdaptiveOverflowColumns = 2;
const int kMaxAdaptiveOverflowColumns = 5;

/// Shared visual metrics for both the real nav bar and the settings preview.
const double kNavBarLabelFontSize = 12.0;
const double kNavBarItemIconSize = 23.0;
const double kNavBarItemIconHeight = 32.0;
const double kNavBarItemWidth = 40.0;
const double kNavBarSelectedItemPillWidth = 56.0;
const double kNavBarMoreTriggerIconSize = 22.0;

const double _kSimpleBarHorizontalPadding = 24.0;
const double _kOverflowBarHorizontalPadding = 16.0;
const double _kMoreTriggerWidth = 44.0;

/// Safety margin around a measured label so the slot does not sit exactly on
/// the text bounds when scaled text or font substitutions are active.
const double _kLabelWidthSafetyPadding = 8.0;

/// Keep slot width above the icon cluster's resting width even for short
/// labels.
const double _kMinimumCollapsedItemWidth = 44.0;

TextStyle navBarLabelTextStyle(
  BuildContext context, {
  required bool isSelected,
  Color? color,
}) {
  final base =
      Theme.of(context).textTheme.labelSmall ??
      Theme.of(context).textTheme.bodySmall ??
      const TextStyle();
  return base.copyWith(
    fontSize: kNavBarLabelFontSize,
    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
    color: color,
    letterSpacing: 0,
  );
}

typedef SplitNavLayout<T> = ({List<T> primary, List<T> overflow});

class NavBarLayoutSpec {
  const NavBarLayoutSpec({
    required this.collapsedPrimaryCount,
    required this.usesOverflowMenu,
    required this.overflowColumns,
    required this.overflowRows,
  });

  final int collapsedPrimaryCount;
  final bool usesOverflowMenu;
  final int overflowColumns;
  final int overflowRows;
}

NavBarLayoutSpec computeNavBarLayoutSpec({
  required double barWidth,
  required List<String> primaryLabels,
  required List<String> overflowLabels,
  required TextStyle labelStyle,
  required TextScaler textScaler,
  required TextDirection textDirection,
}) {
  final clampedPrimaryCount = math.min(
    primaryLabels.length,
    kMaxPrimaryNavTabs,
  );
  final currentPrimaryLabels = primaryLabels.take(clampedPrimaryCount).toList();
  final currentOverflowLabels = List<String>.from(overflowLabels);

  if (currentPrimaryLabels.isEmpty) {
    return const NavBarLayoutSpec(
      collapsedPrimaryCount: 0,
      usesOverflowMenu: false,
      overflowColumns: 0,
      overflowRows: 0,
    );
  }

  final simpleFitCount = _maxFittingTabs(
    barWidth: barWidth,
    labels: currentPrimaryLabels,
    labelStyle: labelStyle,
    textScaler: textScaler,
    textDirection: textDirection,
    reserveMoreTrigger: false,
    maxCount: currentPrimaryLabels.length,
  );

  final needsOverflowMenu =
      currentOverflowLabels.isNotEmpty ||
      simpleFitCount < currentPrimaryLabels.length;

  if (!needsOverflowMenu) {
    return NavBarLayoutSpec(
      collapsedPrimaryCount: currentPrimaryLabels.length,
      usesOverflowMenu: false,
      overflowColumns: 0,
      overflowRows: 0,
    );
  }

  final preferredPrimaryCount = math.min(
    currentPrimaryLabels.length,
    kPreferredPrimaryTabsWithOverflow,
  );

  final collapsedPrimaryCount = _maxFittingTabs(
    barWidth: barWidth,
    labels: currentPrimaryLabels,
    labelStyle: labelStyle,
    textScaler: textScaler,
    textDirection: textDirection,
    reserveMoreTrigger: true,
    maxCount: preferredPrimaryCount,
  );

  final visualOverflowLabels = [
    ...currentPrimaryLabels.skip(collapsedPrimaryCount),
    ...currentOverflowLabels,
  ];

  final overflowColumns = visualOverflowLabels.isEmpty
      ? 0
      : _maxFittingOverflowColumns(
          barWidth: barWidth,
          labels: visualOverflowLabels,
          labelStyle: labelStyle,
          textScaler: textScaler,
          textDirection: textDirection,
        );

  final overflowRows = overflowColumns == 0
      ? 0
      : (visualOverflowLabels.length / overflowColumns).ceil();

  return NavBarLayoutSpec(
    collapsedPrimaryCount: collapsedPrimaryCount,
    usesOverflowMenu: true,
    overflowColumns: overflowColumns,
    overflowRows: overflowRows,
  );
}

/// Arranges overflow tabs into visual rows with the partial (shorter) row on
/// top and full rows below, so the bottom row sits flush against the primary
/// row. Partial rows keep `null` placeholders so renderers can center the real
/// items against the full row geometry below.
///
/// Example: 5 tabs in 4 columns → `[[null, A, null, null], [B, C, D, E]]`.
List<List<T?>> arrangeOverflowRows<T>(List<T> tabs, int columns) {
  if (tabs.isEmpty || columns <= 0) return const [];
  // Single row: return as-is, no centering needed (no row below to align to).
  if (tabs.length <= columns) return [List<T?>.from(tabs)];
  final remainder = tabs.length % columns;
  final rows = <List<T?>>[];
  var start = 0;
  if (remainder != 0) {
    final leading = (columns - remainder) ~/ 2;
    final trailing = columns - remainder - leading;
    rows.add([
      ...List<T?>.filled(leading, null),
      ...tabs.take(remainder),
      ...List<T?>.filled(trailing, null),
    ]);
    start = remainder;
  }
  for (var i = start; i < tabs.length; i += columns) {
    rows.add(tabs.sublist(i, i + columns));
  }
  return rows;
}

SplitNavLayout<T> splitNavBarTabsForLayout<T>({
  required List<T> primary,
  required List<T> overflow,
  required NavBarLayoutSpec spec,
}) {
  final visiblePrimaryCount = spec.collapsedPrimaryCount < 0
      ? 0
      : math.min(spec.collapsedPrimaryCount, primary.length);
  return (
    primary: primary.take(visiblePrimaryCount).toList(),
    overflow: [...primary.skip(visiblePrimaryCount), ...overflow],
  );
}

int _maxFittingTabs({
  required double barWidth,
  required List<String> labels,
  required TextStyle labelStyle,
  required TextScaler textScaler,
  required TextDirection textDirection,
  required bool reserveMoreTrigger,
  required int maxCount,
}) {
  final upperBound = math.min(labels.length, maxCount);
  if (upperBound <= 0) return 0;

  for (var count = upperBound; count >= kMinAdaptivePrimaryNavTabs; count--) {
    if (_tabsFit(
      barWidth: barWidth,
      labels: labels.take(count).toList(),
      labelStyle: labelStyle,
      textScaler: textScaler,
      textDirection: textDirection,
      reserveMoreTrigger: reserveMoreTrigger,
    )) {
      return count;
    }
  }

  return math.min(upperBound, kMinAdaptivePrimaryNavTabs);
}

int _maxFittingOverflowColumns({
  required double barWidth,
  required List<String> labels,
  required TextStyle labelStyle,
  required TextScaler textScaler,
  required TextDirection textDirection,
}) {
  final upperBound = math.min(labels.length, kMaxAdaptiveOverflowColumns);

  for (var count = upperBound; count >= kMinAdaptiveOverflowColumns; count--) {
    if (_tabsFit(
      barWidth: barWidth,
      labels: labels,
      labelStyle: labelStyle,
      textScaler: textScaler,
      textDirection: textDirection,
      reserveMoreTrigger: false,
      explicitCount: count,
    )) {
      return count;
    }
  }

  return math.min(upperBound, kMinAdaptiveOverflowColumns);
}

bool _tabsFit({
  required double barWidth,
  required List<String> labels,
  required TextStyle labelStyle,
  required TextScaler textScaler,
  required TextDirection textDirection,
  required bool reserveMoreTrigger,
  int? explicitCount,
}) {
  if (labels.isEmpty) return true;

  final slotCount = explicitCount ?? labels.length;
  final availableWidth =
      barWidth -
      (reserveMoreTrigger
          ? _kOverflowBarHorizontalPadding
          : _kSimpleBarHorizontalPadding) -
      (reserveMoreTrigger ? _kMoreTriggerWidth : 0);
  final slotWidth = availableWidth / slotCount;

  for (final label in labels) {
    final requiredWidth = math.max(
      _kMinimumCollapsedItemWidth,
      _measureLabelWidth(
            label,
            style: labelStyle,
            textScaler: textScaler,
            textDirection: textDirection,
          ) +
          _kLabelWidthSafetyPadding,
    );
    if (requiredWidth > slotWidth) {
      return false;
    }
  }

  return true;
}

double _measureLabelWidth(
  String text, {
  required TextStyle style,
  required TextScaler textScaler,
  required TextDirection textDirection,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: textDirection,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();
  return painter.width;
}
