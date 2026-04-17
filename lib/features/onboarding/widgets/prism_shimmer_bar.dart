import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';

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

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: disableAnimations
          ? _buildStatic()
          : AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => _buildAnimated(_controller.value),
            ),
    );
  }

  Widget _buildStatic() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 12.0),
      height: 12.0,
      decoration: BoxDecoration(
        color: AppColors.warmWhite.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }

  Widget _buildAnimated(double t) {
    final beginX = -2.0 + 4.0 * t;
    final endX = -1.0 + 4.0 * t;

    return Container(
      constraints: const BoxConstraints(maxHeight: 12.0),
      height: 12.0,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: AppColors.warmWhite.withValues(alpha: 0.15),
        gradient: LinearGradient(
          begin: Alignment(beginX, 0),
          end: Alignment(endX, 0),
          colors: [
            AppColors.warmWhite.withValues(alpha: 0.0),
            AppColors.warmWhite.withValues(alpha: 0.65),
            AppColors.warmWhite.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}
