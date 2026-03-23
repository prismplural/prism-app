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
  });

  /// The top bar widget to pin.
  final PreferredSizeWidget child;

  /// Height of the gradient fade below the bar.
  final double gradientHeight;

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
      ),
    );
  }
}

class _PinnedTopBarDelegate extends SliverPersistentHeaderDelegate {
  const _PinnedTopBarDelegate({
    required this.child,
    required this.barHeight,
    required this.gradientHeight,
  });

  final PreferredSizeWidget child;
  final double barHeight;
  final double gradientHeight;

  @override
  double get maxExtent => barHeight;

  @override
  double get minExtent => barHeight;

  @override
  bool shouldRebuild(covariant _PinnedTopBarDelegate oldDelegate) =>
      child != oldDelegate.child ||
      barHeight != oldDelegate.barHeight ||
      gradientHeight != oldDelegate.gradientHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;

    return SizedBox(
      height: barHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Gradient from top of bar through below
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: -gradientHeight,
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
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          // Bar content
          Positioned.fill(
            child: child,
          ),
        ],
      ),
    );
  }
}
