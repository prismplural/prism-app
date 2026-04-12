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
  const PrismLoadingState({super.key, this.color});

  /// A loading indicator wrapped in [SliverFillRemaining] for scroll views.
  const factory PrismLoadingState.sliver({Key? key, Color? color}) =
      _SliverLoadingState;

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: PrismSpinner(
        color: color ?? Theme.of(context).colorScheme.primary,
        size: 52,
        dotCount: 8,
        duration: const Duration(milliseconds: 3000),
      ),
    );
  }
}

class _SliverLoadingState extends PrismLoadingState {
  const _SliverLoadingState({super.key, super.color});

  @override
  Widget build(BuildContext context) {
    return SliverFillRemaining(
      child: Center(
        child: PrismSpinner(
          color: color ?? Theme.of(context).colorScheme.primary,
          size: 52,
          dotCount: 8,
          duration: const Duration(milliseconds: 3000),
        ),
      ),
    );
  }
}
