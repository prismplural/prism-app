import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_settings_row.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';

/// Settings subview for the Fronting feature.
class FrontingFeatureSettingsScreen extends ConsumerWidget {
  const FrontingFeatureSettingsScreen({super.key});

  static String _quickSwitchLabel(int seconds) {
    if (seconds == 0) return 'Off';
    if (seconds < 60) return '${seconds}s correction window';
    return '${seconds ~/ 60}m correction window';
  }

  static void _showQuickSwitchPicker(
    BuildContext context,
    WidgetRef ref,
    int current,
  ) {
    const options = [
      (0, 'Off'),
      (15, '15 seconds'),
      (30, '30 seconds'),
      (60, '1 minute'),
    ];
    PrismDialog.show<void>(
      context: context,
      title: 'Quick Switch Window',
      message: 'If you switch fronters within this window, it corrects '
          'the current session instead of creating a new one.',
      builder: (ctx) {
        return RadioGroup<int>(
          groupValue: current,
          onChanged: (value) {
            if (value == null) return;
            ref
                .read(settingsNotifierProvider.notifier)
                .updateQuickSwitchThreshold(value);
            Navigator.of(ctx).pop();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options
                .map(
                  (opt) => RadioListTile<int>(
                    contentPadding: EdgeInsets.zero,
                    value: opt.$1,
                    title: Text(opt.$2),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(systemSettingsProvider);
    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: const PrismTopBar(title: 'Fronting', showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: settingsAsync.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (settings) => ListView(
          padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Configure how fronting sessions work.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            PrismSection(
              title: 'Options',
              child: PrismSectionCard(
                padding: EdgeInsets.zero,
                child: PrismSettingsRow(
                  icon: Icons.speed,
                  iconColor: Colors.purple,
                  title: 'Quick Switch',
                  subtitle: _quickSwitchLabel(
                    settings.quickSwitchThresholdSeconds,
                  ),
                  onTap: () => _showQuickSwitchPicker(
                    context,
                    ref,
                    settings.quickSwitchThresholdSeconds,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
