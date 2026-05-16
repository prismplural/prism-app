import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';

class PrismShimmerBar extends StatefulWidget {
  const PrismShimmerBar({super.key});

  @override
  State<PrismShimmerBar> createState() => _PrismShimmerBarState();
}

class _PrismShimmerBarState extends State<PrismShimmerBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    if (disableAnimations) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final colors = _ShimmerBarColors.from(Theme.of(context).colorScheme);

    return ClipRRect(
      borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(6)),
      child: disableAnimations
          ? _buildStatic(colors)
          : AnimatedBuilder(
              animation: _controller,
              builder: (context, _) =>
                  _buildAnimated(_controller.value, colors),
            ),
    );
  }

  Widget _buildStatic(_ShimmerBarColors colors) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 12.0),
      height: 12.0,
      decoration: BoxDecoration(
        color: colors.staticFill,
        borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(6)),
      ),
    );
  }

  Widget _buildAnimated(double t, _ShimmerBarColors colors) {
    final beginX = -2.0 + 4.0 * t;
    final endX = -1.0 + 4.0 * t;

    return Container(
      constraints: const BoxConstraints(maxHeight: 12.0),
      height: 12.0,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PrismShapes.of(context).radius(6)),
        color: colors.track,
        gradient: LinearGradient(
          begin: Alignment(beginX, 0),
          end: Alignment(endX, 0),
          colors: [
            colors.sweep.withValues(alpha: 0),
            colors.sweep,
            colors.sweep.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}

class _ShimmerBarColors {
  const _ShimmerBarColors({
    required this.track,
    required this.sweep,
    required this.staticFill,
  });

  final Color track;
  final Color sweep;
  final Color staticFill;

  factory _ShimmerBarColors.from(ColorScheme colorScheme) {
    final isDark = colorScheme.brightness == Brightness.dark;

    return _ShimmerBarColors(
      track: colorScheme.onSurface.withValues(alpha: isDark ? 0.14 : 0.10),
      sweep: colorScheme.primary.withValues(alpha: isDark ? 0.70 : 0.60),
      staticFill: colorScheme.primary.withValues(alpha: isDark ? 0.34 : 0.28),
    );
  }
}
