import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';

class PhaseSegments extends StatefulWidget {
  final int currentIndex;
  final int totalPhases;

  const PhaseSegments({
    required this.currentIndex,
    required this.totalPhases,
    super.key,
  });

  @override
  State<PhaseSegments> createState() => _PhaseSegmentsState();
}

class _PhaseSegmentsState extends State<PhaseSegments>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  static const _filledGradient = LinearGradient(
    colors: [AppColors.prismPurple, AppColors.warmWhite],
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _opacity = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateAnimation();
  }

  @override
  void didUpdateWidget(PhaseSegments oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateAnimation();
  }

  void _updateAnimation() {
    final disable = MediaQuery.of(context).disableAnimations;
    if (disable) {
      _controller.stop();
    } else {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
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

    return Semantics(
      label: 'Step ${widget.currentIndex + 1} of ${widget.totalPhases}',
      container: true,
      child: AnimatedBuilder(
        animation: _opacity,
        builder: (context, _) {
          return Row(
            children: List.generate(widget.totalPhases * 2 - 1, (i) {
              // Even indices are segments, odd indices are gaps.
              if (i.isOdd) {
                return const SizedBox(width: 4);
              }

              final segmentIndex = i ~/ 2;
              return Expanded(child: _buildSegment(segmentIndex, disableAnimations));
            }),
          );
        },
      ),
    );
  }

  Widget _buildSegment(int index, bool disableAnimations) {
    const radius = BorderRadius.all(Radius.circular(2));

    if (index < widget.currentIndex) {
      return Container(
        height: 4,
        decoration: const BoxDecoration(
          gradient: _filledGradient,
          borderRadius: radius,
        ),
      );
    }

    if (index == widget.currentIndex) {
      final effectiveOpacity = disableAnimations ? 1.0 : _opacity.value;
      return Opacity(
        opacity: effectiveOpacity,
        child: Container(
          height: 4,
          decoration: const BoxDecoration(
            gradient: _filledGradient,
            borderRadius: radius,
          ),
        ),
      );
    }

    // Pending
    return Container(
      height: 4,
      decoration: BoxDecoration(
        color: AppColors.warmWhite.withValues(alpha: 0.2),
        borderRadius: radius,
      ),
    );
  }
}
