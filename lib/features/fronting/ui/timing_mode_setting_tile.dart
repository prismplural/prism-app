import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/fronting/validation/fronting_validation_config.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// A settings tile with a [SegmentedButton] for choosing the fronting timing
/// mode (Flexible / Strict).
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
            child: SegmentedButton<FrontingTimingMode>(
              segments: const [
                ButtonSegment(
                  value: FrontingTimingMode.flexible,
                  label: Text('Flexible'),
                  icon: Icon(AppIcons.tune, size: 18),
                ),
                ButtonSegment(
                  value: FrontingTimingMode.strict,
                  label: Text('Strict'),
                  icon: Icon(AppIcons.lockClock, size: 18),
                ),
              ],
              selected: {timingMode},
              onSelectionChanged: (values) {
                ref
                    .read(settingsNotifierProvider.notifier)
                    .updateTimingMode(values.first);
              },
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
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
