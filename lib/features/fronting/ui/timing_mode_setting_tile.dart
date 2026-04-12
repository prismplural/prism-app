import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

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
      FrontingTimingMode.flexible => context.l10n.frontingTimingModeFlexibleSubtitle,
      FrontingTimingMode.strict => context.l10n.frontingTimingModeStrictSubtitle,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.frontingTimingModeTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: PrismSegmentedControl<FrontingTimingMode>(
              segments: [
                PrismSegment(
                  value: FrontingTimingMode.flexible,
                  label: context.l10n.frontingTimingModeFlexible,
                ),
                PrismSegment(
                  value: FrontingTimingMode.strict,
                  label: context.l10n.frontingTimingModeStrict,
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
