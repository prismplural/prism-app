import 'package:flutter/material.dart';

/// A standardized loading indicator for async states.
///
/// Replaces repeated `Center(child: CircularProgressIndicator())` patterns.
/// Use [PrismLoadingState.sliver] inside [CustomScrollView].
class PrismLoadingState extends StatelessWidget {
  const PrismLoadingState({super.key, this.color});

  /// A loading indicator wrapped in [SliverFillRemaining] for scroll views.
  const factory PrismLoadingState.sliver({Key? key, Color? color}) =
      _SliverLoadingState;

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Center(child: CircularProgressIndicator(color: color));
  }
}

class _SliverLoadingState extends PrismLoadingState {
  const _SliverLoadingState({super.key, super.color});

  @override
  Widget build(BuildContext context) {
    return SliverFillRemaining(
      child: Center(child: CircularProgressIndicator(color: color)),
    );
  }
}
