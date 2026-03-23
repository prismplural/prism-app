import 'package:flutter/material.dart';

/// A standardized loading indicator for async states.
///
/// Replaces repeated `Center(child: CircularProgressIndicator())` patterns.
/// Use [PrismLoadingState.sliver] inside [CustomScrollView].
class PrismLoadingState extends StatelessWidget {
  const PrismLoadingState({super.key});

  /// A loading indicator wrapped in [SliverFillRemaining] for scroll views.
  const factory PrismLoadingState.sliver({Key? key}) = _SliverLoadingState;

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _SliverLoadingState extends PrismLoadingState {
  const _SliverLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return const SliverFillRemaining(
      child: Center(child: CircularProgressIndicator()),
    );
  }
}
