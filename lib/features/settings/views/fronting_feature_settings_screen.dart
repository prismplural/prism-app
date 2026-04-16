import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_grouped_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_section.dart';
import 'package:prism_plurality/shared/widgets/prism_settings_row.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// Settings subview for the Fronting feature.
class FrontingFeatureSettingsScreen extends ConsumerWidget {
  const FrontingFeatureSettingsScreen({super.key});

  static String _quickSwitchLabel(BuildContext context, int seconds) {
    if (seconds == 0) return context.l10n.featureFrontingQuickSwitchOff;
    if (seconds < 60) return context.l10n.featureFrontingQuickSwitchSeconds(seconds);
    return context.l10n.featureFrontingQuickSwitchMinutes(seconds ~/ 60);
  }

  static void _showQuickSwitchPicker(
    BuildContext context,
    WidgetRef ref,
    int current,
  ) {
    final options = [
      (0, context.l10n.featureFrontingQuickSwitchOff),
      (15, '15 seconds'),
      (30, '30 seconds'),
      (60, '1 minute'),
    ];
    PrismDialog.show<void>(
      context: context,
      title: context.l10n.featureFrontingQuickSwitchTitle,
      message: context.l10n.featureFrontingQuickSwitchMessage,
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
    final quickSwitchThreshold = ref.watch(quickSwitchThresholdProvider);
    final showQuickFront = ref.watch(showQuickFrontProvider);
    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: PrismTopBar(title: context.l10n.featureFrontingTitle, showBackButton: true),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Text(
              context.l10n.featureFrontingDescription,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          PrismSection(
            title: context.l10n.featureFrontingOptions,
            child: PrismGroupedSectionCard(
              child: Column(
                children: [
                  PrismSwitchRow(
                    icon: AppIcons.flashOn,
                    iconColor: Colors.purple,
                    title: context.l10n.featureFrontingShowQuickFront,
                    subtitle: context.l10n.featureFrontingShowQuickFrontSubtitle,
                    value: showQuickFront,
                    onChanged: (value) {
                      ref
                          .read(settingsNotifierProvider.notifier)
                          .toggleQuickFront(value);
                      if (!value) {
                        SemanticsService.sendAnnouncement(
                          View.of(context),
                          context.l10n.featureFrontingShowQuickFront,
                          Directionality.of(context),
                        );
                      }
                    },
                  ),
                  PrismSettingsRow(
                    icon: AppIcons.speed,
                    iconColor: Colors.purple,
                    title: context.l10n.featureFrontingQuickSwitch,
                    subtitle: _quickSwitchLabel(context, quickSwitchThreshold),
                    showChevron: true,
                    onTap: () => _showQuickSwitchPicker(context, ref, quickSwitchThreshold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
