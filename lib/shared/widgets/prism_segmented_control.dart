import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/theme/prism_tokens.dart';

/// A segment within a [PrismSegmentedControl].
class PrismSegment<T> {
  const PrismSegment({required this.value, required this.label});

  final T value;
  final String label;
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

class _PrismSegmentedControlState<T>
    extends State<PrismSegmentedControl<T>>
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
        : AppColors.warmBlack.withValues(alpha: trackFillAlpha * 0.15);
    final trackBorderAlpha = isDark
        ? PrismTokens.tintedBorderAlphaDark
        : PrismTokens.tintedBorderAlphaLight;
    final trackBorderColor = isDark
        ? AppColors.warmWhite.withValues(alpha: trackBorderAlpha)
        : AppColors.warmBlack.withValues(alpha: trackBorderAlpha);

    // --- Pill (selected indicator) colors ---
    final pillFillAlpha = isDark
        ? PrismTokens.tintedFillAlphaDark + 0.15 + (isAccessible ? 0.15 : 0.0)
        : PrismTokens.tintedFillAlphaLight + (isAccessible ? 0.15 : 0.0);
    final pillColor = isDark
        ? AppColors.warmWhite.withValues(alpha: pillFillAlpha)
        : AppColors.warmWhite.withValues(alpha: pillFillAlpha);
    final pillBorderColor = isDark
        ? AppColors.warmWhite.withValues(alpha: trackBorderAlpha + 0.05)
        : AppColors.warmBlack.withValues(alpha: trackBorderAlpha + 0.05);

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
            PrismShapes.of(context).radius(8),
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
                            PrismShapes.of(context).radius(6),
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
                            selected: widget.segments[i].value == widget.selected,
                            button: true,
                            child: Center(
                              child: Text(
                                widget.segments[i].label,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: widget.segments[i].value == widget.selected
                                      ? theme.colorScheme.onSurface
                                      : theme.colorScheme.onSurfaceVariant,
                                  fontWeight:
                                      widget.segments[i].value == widget.selected
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
