import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';
import 'package:prism_plurality/shared/widgets/prism_scaled_height.dart';

/// Minimum painted height of the track at normal text. Preserved exactly: the
/// outer box is this tall when the labels fit on one line.
const double kPrismSegmentedControlMinHeight = 44.0;

/// Hairline around the track. The border insets the labels by this much on each
/// side, so the track's painted height is its content height plus twice this.
const double _kTrackBorderWidth = 0.5;

/// Gap between a segment label and its badge.
const double _kBadgeGap = 6.0;
const double _kBadgeMinSize = 18.0;
const double _kBadgeHorizontalPadding = 6.0;

/// A segment within a [PrismSegmentedControl].
class PrismSegment<T> {
  const PrismSegment({
    required this.value,
    required this.label,
    this.badgeCount,
    this.badgeSemanticLabel,
  });

  final T value;
  final String label;

  /// Optional numeric badge count. Null or <= 0 hides the badge entirely
  /// (no gap reserved).
  final int? badgeCount;

  /// Localized semantic label for the badge — read aloud instead of the bare
  /// number so the kind of unread (e.g. "3 unread direct messages") is clear.
  final String? badgeSemanticLabel;
}

class PrismSegmentedControlColors {
  const PrismSegmentedControlColors({
    required this.trackColor,
    required this.trackBorderColor,
    required this.pillColor,
    required this.pillBorderColor,
    required this.shadowColor,
  });

  final Color trackColor;
  final Color trackBorderColor;
  final Color pillColor;
  final Color pillBorderColor;
  final Color shadowColor;

  static PrismSegmentedControlColors resolve(
    ThemeData theme, {
    required bool highContrast,
  }) {
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final trackColor = Color.alphaBlend(
      colors.onSurface.withValues(
        alpha: isDark
            ? (highContrast ? 0.12 : 0.08)
            : (highContrast ? 0.12 : 0.06),
      ),
      colors.surfaceContainerHighest,
    );
    final trackBorderColor = colors.outline.withValues(
      alpha: isDark
          ? (highContrast ? 0.78 : 0.56)
          : (highContrast ? 0.64 : 0.44),
    );
    final pillBase = isDark
        ? colors.surfaceContainerHighest
        : colors.surfaceContainerLowest;
    final pillColor = isDark
        ? Color.alphaBlend(
            colors.onSurface.withValues(alpha: highContrast ? 0.36 : 0.26),
            pillBase,
          )
        : Color.alphaBlend(
            Colors.white.withValues(alpha: highContrast ? 0.78 : 0.68),
            pillBase,
          );
    final pillBorderColor = colors.outline.withValues(
      alpha: isDark
          ? (highContrast ? 0.72 : 0.50)
          : (highContrast ? 0.52 : 0.34),
    );
    final shadowColor = colors.shadow.withValues(
      alpha: isDark
          ? PrismTokens.tintedShadowAlphaDark * 0.6
          : PrismTokens.tintedShadowAlphaLight,
    );

    return PrismSegmentedControlColors(
      trackColor: trackColor,
      trackBorderColor: trackBorderColor,
      pillColor: pillColor,
      pillBorderColor: pillBorderColor,
      shadowColor: shadowColor,
    );
  }
}

/// A custom segmented control with a sliding frosted glass indicator.
///
/// Replaces [SegmentedButton] with Prism's warm, glassy design language.
/// All segments are single-select.
class PrismSegmentedControl<T> extends StatefulWidget
    implements PrismScaledHeight {
  const PrismSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<PrismSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  /// Painted height of the track at the text scale in [context].
  ///
  /// Exactly what the widget renders: labels wrap at the width they really get
  /// (two lines are allowed, then they ellipsise), badges keep their own line
  /// box, and the track never goes below [kPrismSegmentedControlMinHeight] or
  /// below its content plus the hairline border. Pass [availableWidth] when the
  /// caller knows the cross-axis space; without it labels are measured as single
  /// lines, which is the same result only when they do not wrap.
  @override
  double preferredHeightFor(BuildContext context, {double? availableWidth}) {
    if (segments.isEmpty) return kPrismSegmentedControlMinHeight;

    final theme = Theme.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final baseStyle = theme.textTheme.labelLarge ?? const TextStyle();
    // The hairline is painted on top (foregroundDecoration), so it takes no space
    // and each segment gets exactly its share of the caller's width.
    final slotWidth = availableWidth == null
        ? double.infinity
        : math.max(0.0, availableWidth) / segments.length;

    var contentHeight = 0.0;
    for (final segment in segments) {
      final badge = _measureBadge(
        context,
        theme,
        segment,
        textScaler,
        textDirection,
        locale,
      );
      final labelMaxWidth = slotWidth.isFinite
          ? math.max(
              1.0,
              slotWidth - (badge == null ? 0.0 : badge.width + _kBadgeGap),
            )
          : double.infinity;
      final labelHeight = _measureLabelHeight(
        context,
        label: segment.label,
        style: baseStyle.copyWith(
          fontWeight: segment.value == selected
              ? FontWeight.w600
              : FontWeight.w500,
        ),
        textScaler: textScaler,
        textDirection: textDirection,
        locale: locale,
        maxWidth: labelMaxWidth,
      );
      contentHeight = math.max(
        contentHeight,
        badge == null ? labelHeight : math.max(labelHeight, badge.height),
      );
    }

    return math.max(kPrismSegmentedControlMinHeight, contentHeight);
  }

  @override
  State<PrismSegmentedControl<T>> createState() =>
      _PrismSegmentedControlState<T>();
}

Size? _measureBadge(
  BuildContext context,
  ThemeData theme,
  PrismSegment<dynamic> segment,
  TextScaler textScaler,
  TextDirection textDirection,
  Locale? locale,
) {
  final count = segment.badgeCount ?? 0;
  if (count <= 0) return null;
  final label = count <= 9 ? '$count' : '9+';
  // The badge is painted at w600 with height 1.0; the prediction has to use the
  // same style or its width - and the room it leaves the label - comes out wrong.
  // The painted badge is labelSmall at w600 with height 1.0; the prediction has to
  // start from the same style or the width it takes - and the room it leaves the
  // label - comes out wrong.
  final style = prismTextStyleForMeasurement(
    context,
    (theme.textTheme.labelSmall ?? const TextStyle()).merge(
      const TextStyle(fontWeight: FontWeight.w600, height: 1.0),
    ),
  );
  final painter = TextPainter(
    text: TextSpan(text: label, style: style),
    textDirection: textDirection,
    textScaler: textScaler,
    locale: locale,
    textHeightBehavior: prismTextHeightBehaviorFor(context),
    maxLines: 1,
  )..layout();
  final size = Size(
    painter.width + _kBadgeHorizontalPadding * 2,
    painter.height,
  );
  painter.dispose();
  return Size(
    math.max(_kBadgeMinSize, size.width),
    math.max(_kBadgeMinSize, size.height),
  );
}

double _measureLabelHeight(
  BuildContext context, {
  required String label,
  required TextStyle style,
  required TextScaler textScaler,
  required TextDirection textDirection,
  required Locale? locale,
  required double maxWidth,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: prismTextStyleForMeasurement(context, style),
    ),
    textDirection: textDirection,
    textScaler: textScaler,
    locale: locale,
    textHeightBehavior: prismTextHeightBehaviorFor(context),
    textAlign: TextAlign.center,
    maxLines: 2,
  )..layout(maxWidth: maxWidth);
  final height = painter.height;
  painter.dispose();
  return height;
}

class _PrismSegmentedControlState<T> extends State<PrismSegmentedControl<T>>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _previousIndex = 0;

  // Apple-like spring: fast start, smooth settle, subtle overshoot.
  static final _spring = SpringDescription.withDampingRatio(
    mass: 1.0,
    stiffness: 180.0,
    ratio: 0.75,
  );

  int get _selectedIndex {
    for (int i = 0; i < widget.segments.length; i++) {
      if (widget.segments[i].value == widget.selected) return i;
    }
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _previousIndex = _selectedIndex;
    _controller = AnimationController.unbounded(
      vsync: this,
      value: _previousIndex.toDouble(),
    );
  }

  @override
  void didUpdateWidget(covariant PrismSegmentedControl<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newIndex = _selectedIndex;
    if (newIndex != _previousIndex) {
      final reduceMotion = MediaQuery.of(context).disableAnimations;
      if (reduceMotion) {
        _controller.value = newIndex.toDouble();
      } else {
        _controller.animateWith(
          SpringSimulation(
            _spring,
            _controller.value,
            newIndex.toDouble(),
            0, // initial velocity
          ),
        );
      }
      _previousIndex = newIndex;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controlColors = PrismSegmentedControlColors.resolve(
      theme,
      highContrast: MediaQuery.highContrastOf(context),
    );
    final segmentCount = widget.segments.length;

    return Semantics(
      label: context.l10n.segmentedControl,
      child: Container(
        // Sizes to its labels: the border insets them, so the painted height is
        // exactly max(44, content + border) - the same value preferredHeightFor
        // reports to callers that reserve space for this track.
        decoration: BoxDecoration(
          color: controlColors.trackColor,
          borderRadius: BorderRadius.circular(
            PrismShapes.of(context).radius(999),
          ),
        ),
        // Painted on top so the hairline does not inset the segments: the track's
        // full height is tappable, and its painted height stays 44dp at normal text.
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(
            PrismShapes.of(context).radius(999),
          ),
          border: Border.all(
            color: controlColors.trackBorderColor,
            width: _kTrackBorderWidth,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final segmentWidth = constraints.maxWidth / segmentCount;

            return Stack(
              children: [
                // Sliding pill indicator
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final left = _controller.value * segmentWidth;
                    return Positioned(
                      left: left + 2,
                      top: 2,
                      bottom: 2,
                      width: segmentWidth - 4,
                      child: Container(
                        decoration: BoxDecoration(
                          color: controlColors.pillColor,
                          borderRadius: BorderRadius.circular(
                            PrismShapes.of(context).radius(999),
                          ),
                          border: Border.all(
                            color: controlColors.pillBorderColor,
                            width: 0.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: controlColors.shadowColor,
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                // Segment labels
                Row(
                  children: [
                    for (int i = 0; i < segmentCount; i++)
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (widget.segments[i].value != widget.selected) {
                              widget.onChanged(widget.segments[i].value);
                            }
                          },
                          child: Semantics(
                            selected:
                                widget.segments[i].value == widget.selected,
                            button: true,
                            // The segment itself is the tap target, so it holds
                            // the track's full minimum height while the label is
                            // short, and grows when the label does.
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                minHeight: kPrismSegmentedControlMinHeight,
                              ),
                              // heightFactor: 1 makes the segment take its own
                              // content height even when the parent hands down a
                              // finite max height (a Scaffold body, a pinned band, a
                              // sheet column). Without it the Center fills that
                              // parent and the track grows to the parent's height.
                              child: Center(
                                heightFactor: 1,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        widget.segments[i].label,
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(
                                              color:
                                                  widget.segments[i].value ==
                                                      widget.selected
                                                  ? theme.colorScheme.onSurface
                                                  : theme
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                              fontWeight:
                                                  widget.segments[i].value ==
                                                      widget.selected
                                                  ? FontWeight.w600
                                                  : FontWeight.w500,
                                            ),
                                        maxLines: 2,
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if ((widget.segments[i].badgeCount ?? 0) >
                                        0) ...[
                                      const SizedBox(width: 6),
                                      _SegmentBadge(
                                        count: widget.segments[i].badgeCount!,
                                        semanticLabel: widget
                                            .segments[i]
                                            .badgeSemanticLabel,
                                        theme: theme,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Numeric pill rendered inside a [PrismSegment] to surface unread counts.
///
/// Capped at "9+" so the segment label keeps room to breathe. Caller decides
/// whether to render at all — this widget assumes [count] > 0.
class _SegmentBadge extends StatelessWidget {
  const _SegmentBadge({
    required this.count,
    required this.semanticLabel,
    required this.theme,
  });

  final int count;
  final String? semanticLabel;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final label = count <= 9 ? '$count' : '9+';

    // Cross-fade across the number when count changes so a 2 → 3 transition
    // doesn't snap. Width still adapts via the pill's intrinsic min/padding.
    final inner = AnimatedSwitcher(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: Text(
        label,
        key: ValueKey<String>(label),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w600,
          height: 1.0,
        ),
      ),
    );

    final pill = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(999),
        ),
        child: inner,
      ),
    );

    final semantics = Semantics(
      label: semanticLabel ?? '$count',
      container: true,
      child: pill,
    );

    if (reduceMotion) return semantics;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      builder: (context, t, child) {
        final scale = 0.8 + (0.2 * t);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: semantics,
    );
  }
}
