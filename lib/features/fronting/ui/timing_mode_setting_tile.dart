import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/fronting/validation/fronting_validation_config.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';

/// A settings tile for choosing the fronting timing mode (Flexible / Strict).
class TimingModeSettingTile extends ConsumerWidget {
  const TimingModeSettingTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final timingMode = ref.watch(timingModeProvider);

    final subtitle = switch (timingMode) {
      FrontingTimingMode.flexible =>
        'Small gaps (under 5 minutes) are allowed between sessions.',
      FrontingTimingMode.strict =>
        'Sessions must be continuous with no gaps in the timeline.',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Timing Mode',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: PrismSegmentedControl<FrontingTimingMode>(
              segments: [
                const PrismSegment(
                  value: FrontingTimingMode.flexible,
                  label: 'Flexible',
                ),
                const PrismSegment(
                  value: FrontingTimingMode.strict,
                  label: 'Strict',
                ),
              ],
              selected: timingMode,
              onChanged: (value) {
                ref
                    .read(settingsNotifierProvider.notifier)
                    .updateTimingMode(value);
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
