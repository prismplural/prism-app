import 'dart:math';

import 'package:flutter/material.dart';

/// A ring of dots that pulse in sequence — used as the inline loading
/// indicator for buttons (small) and as the page-level loader (large).
///
/// The sequential cosine pulse creates a sense of orbital motion without
/// actual rotation. Scale [size] and [dotCount] up for page-level contexts;
/// tune [duration] to slow the cycle for calmer waiting states.
class PrismSpinner extends StatefulWidget {
  const PrismSpinner({
    super.key,
    required this.color,
    this.size = 20,
    this.dotCount = 6,
    this.duration = const Duration(milliseconds: 1800),
  });

  final Color color;
  final double size;
  final int dotCount;

  /// Full cycle duration. Default 1800ms suits button contexts; use longer
  /// values (e.g. 3000ms) for page-level loaders where calm matters more.
  final Duration duration;

  @override
  State<PrismSpinner> createState() => _PrismSpinnerState();
}

class _PrismSpinnerState extends State<PrismSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return _buildStatic();
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => _buildAnimated(_controller.value),
    );
  }

  Widget _buildStatic() {
    return CustomPaint(
      size: Size.square(widget.size),
      painter: _SpinnerPainter(
        color: widget.color,
        dotCount: widget.dotCount,
        t: 0,
        animate: false,
      ),
    );
  }

  Widget _buildAnimated(double t) {
    return CustomPaint(
      size: Size.square(widget.size),
      painter: _SpinnerPainter(
        color: widget.color,
        dotCount: widget.dotCount,
        t: t,
        animate: true,
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter({
    required this.color,
    required this.dotCount,
    required this.t,
    required this.animate,
  });

  final Color color;
  final int dotCount;
  final double t;
  final bool animate;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Dots sit on a ring inset from the edges.
    final ringRadius = size.width * 0.38;
    final dotRadius = size.width * 0.065;

    for (int i = 0; i < dotCount; i++) {
      final angle = (i / dotCount) * 2 * pi - pi / 2; // start at top
      final dx = center.dx + ringRadius * cos(angle);
      final dy = center.dy + ringRadius * sin(angle);

      double opacity;
      if (animate) {
        // Each dot's "highlight" phase is staggered around the ring.
        // A soft cosine window creates a smooth pulse that travels
        // around the circle.
        final phase = (t - i / dotCount) % 1.0;
        // Cosine window: peak at phase=0, trough at phase=0.5
        final pulse = (cos(phase * 2 * pi) + 1) / 2; // 0..1
        opacity = 0.25 + 0.65 * pulse; // 0.25..0.90
      } else {
        // Static: gentle gradient around the ring.
        opacity = 0.35 + 0.35 * (1 - i / dotCount);
      }

      canvas.drawCircle(
        Offset(dx, dy),
        dotRadius,
        Paint()..color = color.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_SpinnerPainter oldDelegate) =>
      t != oldDelegate.t ||
      color != oldDelegate.color ||
      dotCount != oldDelegate.dotCount;
}
