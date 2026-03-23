import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/models.dart';
import 'package:prism_plurality/features/settings/providers/sleep_settings_providers.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

/// Settings screen for sleep tracking configuration.
class SleepSettingsScreen extends ConsumerWidget {
  const SleepSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEnabled = ref.watch(sleepTrackingEnabledProvider);
    final defaultQuality = ref.watch(defaultSleepQualityProvider);

    return PrismPageScaffold(
      topBar: const PrismTopBar(title: 'Sleep Tracking', showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        children: [
          PrismSwitchRow(
            title: 'Sleep tracking enabled',
            subtitle:
              'Show sleep tracking controls on the fronting screen',
            value: isEnabled,
            onChanged: (value) {
              ref
                  .read(sleepTrackingEnabledProvider.notifier)
                  .toggle(value);
            },
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            title: const Text('Default quality'),
            subtitle: Text(defaultQuality.label),
            trailing: DropdownButton<SleepQuality>(
              value: defaultQuality,
              underline: const SizedBox.shrink(),
              items: SleepQuality.values
                  .map((q) => DropdownMenuItem(
                        value: q,
                        child: Text(q.label),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  ref
                      .read(defaultSleepQualityProvider.notifier)
                      .set(value);
                }
              },
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Sleep sessions help you track rest patterns alongside '
              'fronting sessions. You can start a sleep session from the '
              'moon icon on the fronting screen.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
