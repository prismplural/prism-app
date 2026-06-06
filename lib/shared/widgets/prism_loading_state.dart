import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:prism_plurality/shared/widgets/prism_spinner.dart';

/// A standardized loading indicator for async states.
///
/// Eight dots arranged in a ring with a sequential cosine pulse — the same
/// orbital language as [PrismSpinner] but scaled up for page-level contexts.
/// The 3 s cycle keeps it calm while the system works.
///
/// Use [PrismLoadingState.sliver] inside [CustomScrollView].
class PrismLoadingState extends StatelessWidget {
  const PrismLoadingState({super.key, this.color, this.size = 52});

  /// A loading indicator wrapped in [SliverFillRemaining] for scroll views.
  const factory PrismLoadingState.sliver({
    Key? key,
    Color? color,
    double size,
  }) = _SliverLoadingState;

  final Color? color;
  final double size;

  static const double _compactScale = 0.62;
  static const double _minimumAutoSize = 20;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          Center(child: _buildSpinner(context, _sizeFor(constraints))),
    );
  }

  Widget _buildSpinner(BuildContext context, double resolvedSize) {
    return PrismSpinner(
      color: color ?? Theme.of(context).colorScheme.primary,
      size: resolvedSize,
      dotCount: 8,
      duration: const Duration(milliseconds: 3000),
    );
  }

  double _sizeFor(BoxConstraints constraints) {
    final bounded = <double>[
      if (constraints.hasBoundedWidth) constraints.maxWidth,
      if (constraints.hasBoundedHeight) constraints.maxHeight,
    ].where((value) => value.isFinite && value > 0).toList();
    if (bounded.isEmpty) return size;

    final shortestSide = bounded.reduce(math.min);
    final minimum = math.min(size, _minimumAutoSize);
    final preferred = math.min(
      size,
      math.max(minimum, shortestSide * _compactScale),
    );
    return math.min(shortestSide, preferred);
  }
}

class _SliverLoadingState extends PrismLoadingState {
  const _SliverLoadingState({super.key, super.color, super.size = 52});

  @override
  Widget build(BuildContext context) {
    return SliverFillRemaining(
      child: LayoutBuilder(
        builder: (context, constraints) =>
            Center(child: _buildSpinner(context, _sizeFor(constraints))),
      ),
    );
  }
}
