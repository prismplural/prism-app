import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/system_settings.dart';
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

  static String _listViewModeLabel(
    AppLocalizations l10n,
    FrontingListViewMode mode,
  ) {
    switch (mode) {
      case FrontingListViewMode.combinedPeriods:
        return l10n.settingsFrontingListViewModeCombinedPeriods;
      case FrontingListViewMode.perMemberRows:
        return l10n.settingsFrontingListViewModePerMemberRows;
      case FrontingListViewMode.timeline:
        return l10n.settingsFrontingListViewModeTimeline;
    }
  }

  static String _listViewModeDescription(
    AppLocalizations l10n,
    FrontingListViewMode mode,
  ) {
    switch (mode) {
      case FrontingListViewMode.combinedPeriods:
        return l10n.settingsFrontingListViewModeCombinedPeriodsDescription;
      case FrontingListViewMode.perMemberRows:
        return l10n.settingsFrontingListViewModePerMemberRowsDescription;
      case FrontingListViewMode.timeline:
        return l10n.settingsFrontingListViewModeTimelineDescription;
    }
  }

  static String _addFrontBehaviorLabel(
    AppLocalizations l10n,
    FrontStartBehavior behavior,
  ) {
    switch (behavior) {
      case FrontStartBehavior.additive:
        return l10n.settingsAddFrontDefaultBehaviorAdditive;
      case FrontStartBehavior.replace:
        return l10n.settingsAddFrontDefaultBehaviorReplace;
    }
  }

  static String _addFrontBehaviorDescription(
    AppLocalizations l10n,
    FrontStartBehavior behavior,
  ) {
    switch (behavior) {
      case FrontStartBehavior.additive:
        return l10n.settingsAddFrontDefaultBehaviorAdditiveDescription;
      case FrontStartBehavior.replace:
        return l10n.settingsAddFrontDefaultBehaviorReplaceDescription;
    }
  }

  static String _quickFrontBehaviorLabel(
    AppLocalizations l10n,
    FrontStartBehavior behavior,
  ) {
    switch (behavior) {
      case FrontStartBehavior.additive:
        return l10n.settingsQuickFrontDefaultBehaviorAdditive;
      case FrontStartBehavior.replace:
        return l10n.settingsQuickFrontDefaultBehaviorReplace;
    }
  }

  static void _showListViewModePicker(
    BuildContext context,
    WidgetRef ref,
    FrontingListViewMode current,
  ) {
    PrismDialog.show<void>(
      context: context,
      title: context.l10n.settingsFrontingListViewModeLabel,
      builder: (ctx) {
        return RadioGroup<FrontingListViewMode>(
          groupValue: current,
          onChanged: (value) {
            if (value == null) return;
            ref
                .read(settingsNotifierProvider.notifier)
                .updateFrontingListViewMode(value);
            Navigator.of(ctx).pop();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: FrontingListViewMode.values
                .map(
                  (mode) => RadioListTile<FrontingListViewMode>(
                    contentPadding: EdgeInsets.zero,
                    value: mode,
                    title: Text(_listViewModeLabel(context.l10n, mode)),
                    subtitle: Text(
                      _listViewModeDescription(context.l10n, mode),
                    ),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }

  static void _showAddFrontBehaviorPicker(
    BuildContext context,
    WidgetRef ref,
    FrontStartBehavior current,
  ) {
    PrismDialog.show<void>(
      context: context,
      title: context.l10n.settingsAddFrontDefaultBehaviorLabel,
      builder: (ctx) {
        return RadioGroup<FrontStartBehavior>(
          groupValue: current,
          onChanged: (value) {
            if (value == null) return;
            ref
                .read(settingsNotifierProvider.notifier)
                .updateAddFrontDefaultBehavior(value);
            Navigator.of(ctx).pop();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: FrontStartBehavior.values
                .map(
                  (behavior) => RadioListTile<FrontStartBehavior>(
                    contentPadding: EdgeInsets.zero,
                    value: behavior,
                    title: Text(_addFrontBehaviorLabel(context.l10n, behavior)),
                    subtitle: Text(
                      _addFrontBehaviorDescription(context.l10n, behavior),
                    ),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }

  static void _showQuickFrontBehaviorPicker(
    BuildContext context,
    WidgetRef ref,
    FrontStartBehavior current,
  ) {
    PrismDialog.show<void>(
      context: context,
      title: context.l10n.settingsQuickFrontDefaultBehaviorLabel,
      builder: (ctx) {
        return RadioGroup<FrontStartBehavior>(
          groupValue: current,
          onChanged: (value) {
            if (value == null) return;
            ref
                .read(settingsNotifierProvider.notifier)
                .updateQuickFrontDefaultBehavior(value);
            Navigator.of(ctx).pop();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: FrontStartBehavior.values
                .map(
                  (behavior) => RadioListTile<FrontStartBehavior>(
                    contentPadding: EdgeInsets.zero,
                    value: behavior,
                    title: Text(
                      _quickFrontBehaviorLabel(context.l10n, behavior),
                    ),
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
    final listViewMode = ref.watch(frontingListViewModeProvider);
    final addFrontBehavior = ref.watch(addFrontDefaultBehaviorProvider);
    final quickFrontBehavior = ref.watch(quickFrontDefaultBehaviorProvider);
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
                    onChanged: (value) => ref
                        .read(settingsNotifierProvider.notifier)
                        .toggleQuickFront(value),
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
          PrismSection(
            title: context.l10n.settingsFrontingSessionDisplaySectionTitle,
            child: PrismGroupedSectionCard(
              child: Column(
                children: [
                  PrismSettingsRow(
                    icon: AppIcons.viewListRounded,
                    iconColor: Colors.purple,
                    title: context.l10n.settingsFrontingListViewModeLabel,
                    subtitle: _listViewModeLabel(context.l10n, listViewMode),
                    showChevron: true,
                    onTap: () =>
                        _showListViewModePicker(context, ref, listViewMode),
                  ),
                  PrismSettingsRow(
                    icon: AppIcons.addCircle,
                    iconColor: Colors.purple,
                    title:
                        context.l10n.settingsAddFrontDefaultBehaviorLabel,
                    subtitle: _addFrontBehaviorLabel(
                      context.l10n,
                      addFrontBehavior,
                    ),
                    showChevron: true,
                    onTap: () => _showAddFrontBehaviorPicker(
                      context,
                      ref,
                      addFrontBehavior,
                    ),
                  ),
                  PrismSettingsRow(
                    icon: AppIcons.flashOn,
                    iconColor: Colors.purple,
                    title:
                        context.l10n.settingsQuickFrontDefaultBehaviorLabel,
                    subtitle: _quickFrontBehaviorLabel(
                      context.l10n,
                      quickFrontBehavior,
                    ),
                    showChevron: true,
                    onTap: () => _showQuickFrontBehaviorPicker(
                      context,
                      ref,
                      quickFrontBehavior,
                    ),
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
