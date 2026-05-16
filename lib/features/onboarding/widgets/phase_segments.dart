import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _opacity = Tween<double>(
      begin: 0.6,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
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
      label: context.l10n.onboardingPhaseSegmentsSemantics(
        widget.currentIndex + 1,
        widget.totalPhases,
      ),
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
              return Expanded(
                child: _buildSegment(context, segmentIndex, disableAnimations),
              );
            }),
          );
        },
      ),
    );
  }

  Widget _buildSegment(
    BuildContext context,
    int index,
    bool disableAnimations,
  ) {
    final colors = _PhaseSegmentColors.from(Theme.of(context).colorScheme);
    final radius = BorderRadius.all(
      Radius.circular(PrismShapes.of(context).radius(2)),
    );

    if (index < widget.currentIndex) {
      return Container(
        height: 4,
        decoration: BoxDecoration(
          gradient: colors.filledGradient,
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
          decoration: BoxDecoration(
            gradient: colors.filledGradient,
            borderRadius: radius,
          ),
        ),
      );
    }

    return Container(
      height: 4,
      decoration: BoxDecoration(color: colors.pending, borderRadius: radius),
    );
  }
}

class _PhaseSegmentColors {
  const _PhaseSegmentColors({
    required this.filledGradient,
    required this.pending,
  });

  final LinearGradient filledGradient;
  final Color pending;

  factory _PhaseSegmentColors.from(ColorScheme colorScheme) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final gradientEnd = Color.lerp(
      colorScheme.primary,
      colorScheme.onSurface,
      isDark ? 0.22 : 0.18,
    )!;

    return _PhaseSegmentColors(
      filledGradient: LinearGradient(
        colors: [colorScheme.primary, gradientEnd],
      ),
      pending: colorScheme.onSurface.withValues(alpha: isDark ? 0.18 : 0.14),
    );
  }
}
