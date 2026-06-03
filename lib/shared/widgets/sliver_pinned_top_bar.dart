import 'package:flutter/material.dart';

/// A sliver that pins a [PrismTopBar] at the top of a [CustomScrollView],
/// with a subtle gradient fade below it (mirroring the bottom nav bar style).
///
/// The gradient overlaps the scrolling content rather than pushing it down,
/// creating a smooth fade from the bar into the list.
class SliverPinnedTopBar extends StatelessWidget {
  const SliverPinnedTopBar({
    super.key,
    required this.child,
    this.gradientHeight = 24.0,
    this.maxWidth = double.infinity,
  });

  /// The top bar widget to pin.
  final PreferredSizeWidget child;

  /// Height of the gradient fade below the bar.
  final double gradientHeight;

  /// Max width of the bar surface, centered. Use [PrismTokens.contentMaxWidth]
  /// on content-primary screens so the bar lines up with the clamped body.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).viewPadding.top;
    final barHeight = child.preferredSize.height + topPadding;

    return SliverPersistentHeader(
      pinned: true,
      delegate: _PinnedTopBarDelegate(
        child: child,
        barHeight: barHeight,
        gradientHeight: gradientHeight,
        maxWidth: maxWidth,
      ),
    );
  }
}

class _PinnedTopBarDelegate extends SliverPersistentHeaderDelegate {
  const _PinnedTopBarDelegate({
    required this.child,
    required this.barHeight,
    required this.gradientHeight,
    required this.maxWidth,
  });

  final PreferredSizeWidget child;
  final double barHeight;
  final double gradientHeight;
  final double maxWidth;

  @override
  double get maxExtent => barHeight;

  @override
  double get minExtent => barHeight;

  @override
  bool shouldRebuild(covariant _PinnedTopBarDelegate oldDelegate) =>
      child != oldDelegate.child ||
      barHeight != oldDelegate.barHeight ||
      gradientHeight != oldDelegate.gradientHeight ||
      maxWidth != oldDelegate.maxWidth;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(
          height: barHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Gradient overlapping the bottom portion of the bar itself
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          scaffoldBg,
                          scaffoldBg,
                          scaffoldBg.withValues(alpha: 0),
                        ],
                        stops: const [0.0, 0.6, 1.0],
                      ),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              // Bar content
              Positioned.fill(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
