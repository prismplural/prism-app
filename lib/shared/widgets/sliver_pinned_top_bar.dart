import 'package:flutter/material.dart';

import 'package:prism_plurality/shared/widgets/prism_scaled_height.dart';

/// A sliver that pins a [PrismTopBar] at the top of a [CustomScrollView],
/// with a subtle gradient fade below it (mirroring the bottom nav bar style).
///
/// The gradient overlaps the scrolling content rather than pushing it down,
/// creating a smooth fade from the bar into the list.
///
/// The pinned extent comes from the bar itself: a [PrismScaledHeight] child is
/// asked for its height at the ambient text scale, measured against the real
/// cross-axis width of this sliver, so a bar that grows for large text grows the
/// band it sits in. Any other [PreferredSizeWidget] keeps its declared
/// `preferredSize` (nothing changes for it).
///
/// Measurement is cached for the current inputs only — the child widget instance,
/// the cross-axis width, the text scaler, direction, locale, theme and the bold /
/// high-contrast flags — and dropped when the platform font set changes
/// (`PaintingBinding.systemFonts`). `SliverLayoutBuilder` re-runs its builder on
/// every layout (scroll offset is part of [SliverConstraints]), so without this
/// cache a bar would re-shape its text on every scroll frame.
///
/// Asset faces are registered through `FontLoader` before the first frame and the
/// app never swaps them at runtime; a font *preference* change arrives as a new
/// `ThemeData`, which is already a cache key.
///
/// [minBodyExtent] is opt-in and defaults to zero, which is exactly the previous
/// behaviour: a plain bar stays pinned. A composite header whose own content can
/// outgrow a short window (keyboard up) passes the body height it needs there;
/// when the viewport cannot give the bar that much room the header is laid out
/// unpinned, so it scrolls away instead of squeezing the body to nothing.
class SliverPinnedTopBar extends StatefulWidget {
  const SliverPinnedTopBar({
    super.key,
    required this.child,
    this.gradientHeight = 24.0,
    this.maxWidth = double.infinity,
    this.minBodyExtent = 0.0,
  });

  /// The top bar widget to pin.
  final PreferredSizeWidget child;

  /// Height of the gradient fade below the bar.
  final double gradientHeight;

  /// Max width of the bar surface, centered. Use [PrismTokens.contentMaxWidth]
  /// on content-primary screens so the bar lines up with the clamped body.
  final double maxWidth;

  /// Body height that must remain visible for this bar to stay pinned. Zero (the
  /// default) pins the bar whenever it fits at all, i.e. unchanged behaviour for
  /// ordinary bars; a composite header that grows for large text opts in.
  final double minBodyExtent;

  @override
  State<SliverPinnedTopBar> createState() => _SliverPinnedTopBarState();
}

class _SliverPinnedTopBarState extends State<SliverPinnedTopBar> {
  _BarExtentCache? _cache;

  @override
  void initState() {
    super.initState();
    // The platform's font set can change while the app runs; a measurement taken
    // with the old set is no longer trustworthy.
    PaintingBinding.instance.systemFonts.addListener(_handleSystemFontsChanged);
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(
      _handleSystemFontsChanged,
    );
    super.dispose();
  }

  void _handleSystemFontsChanged() {
    if (!mounted) return;
    setState(() => _cache = null);
  }

  /// Height the bar needs at [width], reusing the last measurement only while
  /// every input that can change it is unchanged.
  double _barHeightFor(BuildContext context, double width) {
    final child = widget.child;
    // `PrismTopBar` chooses its title size from the *window* width
    // (desktopBreakpoint), which is not the same value as this sliver's
    // cross-axis width inside a fixed-width pane. Both are keys.
    final windowWidth = MediaQuery.sizeOf(context).width;
    final scaler = MediaQuery.textScalerOf(context);
    // Measurements resolve their style through `DefaultTextStyle` (and honour its
    // height behaviour), so an inherited style change is a cache input too.
    final defaultTextStyle = DefaultTextStyle.of(context);
    final baseStyle = defaultTextStyle.style;
    final textHeightBehavior = defaultTextStyle.textHeightBehavior;
    final direction = Directionality.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final boldText = MediaQuery.boldTextOf(context);
    final highContrast = MediaQuery.highContrastOf(context);

    final cached = _cache;
    if (cached != null &&
        identical(cached.child, child) &&
        cached.width == width &&
        cached.windowWidth == windowWidth &&
        cached.scaler == scaler &&
        cached.direction == direction &&
        identical(cached.theme, theme) &&
        cached.locale == locale &&
        cached.boldText == boldText &&
        cached.highContrast == highContrast &&
        cached.baseStyle == baseStyle &&
        cached.textHeightBehavior == textHeightBehavior) {
      return cached.height;
    }

    final height = prismScaledHeightOf(context, child, availableWidth: width);
    _cache = _BarExtentCache(
      child: child,
      width: width,
      windowWidth: windowWidth,
      scaler: scaler,
      direction: direction,
      theme: theme,
      locale: locale,
      boldText: boldText,
      highContrast: highContrast,
      baseStyle: baseStyle,
      textHeightBehavior: textHeightBehavior,
      height: height,
    );
    return height;
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).viewPadding.top;

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final barHeight =
            _barHeightFor(context, constraints.crossAxisExtent) + topPadding;
        final pinned =
            barHeight + widget.minBodyExtent <=
            constraints.viewportMainAxisExtent;

        return SliverPersistentHeader(
          pinned: pinned,
          delegate: _PinnedTopBarDelegate(
            child: widget.child,
            barHeight: barHeight,
            gradientHeight: widget.gradientHeight,
            maxWidth: widget.maxWidth,
          ),
        );
      },
    );
  }
}

/// One resolved extent, valid only for the inputs recorded with it.
class _BarExtentCache {
  const _BarExtentCache({
    required this.child,
    required this.width,
    required this.windowWidth,
    required this.scaler,
    required this.direction,
    required this.theme,
    required this.locale,
    required this.boldText,
    required this.highContrast,
    required this.baseStyle,
    required this.textHeightBehavior,
    required this.height,
  });

  final Widget child;

  /// Cross-axis extent of this sliver.
  final double width;

  /// Window width, the input `PrismTopBar` uses to pick 22pt vs 18pt.
  final double windowWidth;
  final TextScaler scaler;
  final TextDirection direction;
  final ThemeData theme;
  final Locale? locale;
  final bool boldText;
  final bool highContrast;
  final TextStyle baseStyle;
  final TextHeightBehavior? textHeightBehavior;
  final double height;
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
