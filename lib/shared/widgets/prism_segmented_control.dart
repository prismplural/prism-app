import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';

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

/// A custom segmented control with a sliding frosted glass indicator.
///
/// Replaces [SegmentedButton] with Prism's warm, glassy design language.
/// All segments are single-select.
class PrismSegmentedControl<T> extends StatefulWidget {
  const PrismSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<PrismSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  State<PrismSegmentedControl<T>> createState() =>
      _PrismSegmentedControlState<T>();
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
    final isDark = theme.brightness == Brightness.dark;
    final isAccessible = MediaQuery.of(context).highContrast;
    final segmentCount = widget.segments.length;

    // --- Track colors ---
    final trackFillAlpha = isDark
        ? PrismTokens.tintedFillAlphaDark + (isAccessible ? 0.15 : 0.0)
        : PrismTokens.tintedFillAlphaLight + (isAccessible ? 0.15 : 0.0);
    final trackColor = isDark
        ? AppColors.warmWhite.withValues(alpha: trackFillAlpha * 0.5)
        : AppColors.parchmentStrong.withValues(
            alpha: isAccessible ? 0.9 : 0.72,
          );
    final trackBorderAlpha = isDark
        ? PrismTokens.tintedBorderAlphaDark
        : PrismTokens.tintedBorderAlphaLight;
    final trackBorderColor = isDark
        ? AppColors.warmWhite.withValues(alpha: trackBorderAlpha)
        : AppColors.warmBlack.withValues(alpha: 0.12);

    // --- Pill (selected indicator) colors ---
    final pillFillAlpha = isDark
        ? PrismTokens.tintedFillAlphaDark + 0.15 + (isAccessible ? 0.15 : 0.0)
        : PrismTokens.tintedFillAlphaLight + (isAccessible ? 0.15 : 0.0);
    final pillColor = isDark
        ? AppColors.warmWhite.withValues(alpha: pillFillAlpha)
        : AppColors.warmOffWhite.withValues(alpha: 0.92);
    final pillBorderColor = isDark
        ? AppColors.warmWhite.withValues(alpha: trackBorderAlpha + 0.05)
        : AppColors.warmBlack.withValues(alpha: 0.10);

    // --- Shadow ---
    final shadowAlpha = isDark
        ? PrismTokens.tintedShadowAlphaDark * 0.5
        : PrismTokens.tintedShadowAlphaLight;

    return Semantics(
      label: context.l10n.segmentedControl,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: trackColor,
          borderRadius: BorderRadius.circular(
            PrismShapes.of(context).radius(999),
          ),
          border: Border.all(color: trackBorderColor, width: 0.5),
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
                          color: pillColor,
                          borderRadius: BorderRadius.circular(
                            PrismShapes.of(context).radius(999),
                          ),
                          border: Border.all(
                            color: pillBorderColor,
                            width: 0.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.warmBlack.withValues(
                                alpha: shadowAlpha,
                              ),
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
                            child: Center(
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
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if ((widget.segments[i].badgeCount ?? 0) >
                                      0) ...[
                                    const SizedBox(width: 6),
                                    _SegmentBadge(
                                      count: widget.segments[i].badgeCount!,
                                      semanticLabel:
                                          widget.segments[i].badgeSemanticLabel,
                                      theme: theme,
                                    ),
                                  ],
                                ],
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
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
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
        height: 18,
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
