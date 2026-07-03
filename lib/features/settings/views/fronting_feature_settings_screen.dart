import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/preferences/fronting_terms.dart';
import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/domain/preferences/composer_default_member.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
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
    if (seconds < 60) {
      return context.l10n.featureFrontingQuickSwitchSeconds(seconds);
    }
    return context.l10n.featureFrontingQuickSwitchMinutes(seconds ~/ 60);
  }

  static void _showQuickSwitchPicker(
    BuildContext context,
    WidgetRef ref,
    int current,
    FrontingTermBundle frontingTerms,
  ) {
    final options = [
      (0, context.l10n.featureFrontingQuickSwitchOff),
      (15, '15 seconds'),
      (30, '30 seconds'),
      (60, '1 minute'),
    ];
    PrismDialog.show<void>(
      context: context,
      title: frontingTerms.quickCorrectionWindowTitle,
      message: _quickSwitchMessage(frontingTerms),
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
    String memberTermLower,
  ) {
    switch (mode) {
      case FrontingListViewMode.combinedPeriods:
        return l10n.settingsFrontingListViewModeCombinedPeriods;
      case FrontingListViewMode.perMemberRows:
        return l10n.settingsFrontingListViewModePerMemberRows(memberTermLower);
      case FrontingListViewMode.timeline:
        return l10n.settingsFrontingListViewModeTimeline;
    }
  }

  static String _listViewModeDescription(
    FrontingTermBundle frontingTerms,
    FrontingListViewMode mode,
  ) {
    switch (mode) {
      case FrontingListViewMode.combinedPeriods:
        return 'Avatar stacks for each unique '
            '${frontingTerms.activeSingularLabel.toLowerCase()} group';
      case FrontingListViewMode.perMemberRows:
        return 'One row per '
            '${frontingTerms.activeSingularLabel.toLowerCase()} '
            '${frontingTerms.sessionSingular.toLowerCase()}, side-by-side';
      case FrontingListViewMode.timeline:
        return 'Bar chart view of ${frontingTerms.featureLower} over time';
    }
  }

  static String _addFrontBehaviorLabel(
    FrontingTermBundle frontingTerms,
    FrontStartBehavior behavior,
  ) {
    switch (behavior) {
      case FrontStartBehavior.additive:
        return frontingTerms.addAction;
      case FrontStartBehavior.replace:
        return frontingTerms.replaceCurrentAction;
    }
  }

  static String _addFrontBehaviorDescription(
    FrontingTermBundle frontingTerms,
    FrontStartBehavior behavior,
  ) {
    switch (behavior) {
      case FrontStartBehavior.additive:
        return 'New ${frontingTerms.sessionPlural.toLowerCase()} '
            'join existing ones';
      case FrontStartBehavior.replace:
        return 'End all current ${frontingTerms.sessionPlural.toLowerCase()} '
            'before starting new ones';
    }
  }

  static String _quickFrontBehaviorLabel(
    FrontingTermBundle frontingTerms,
    FrontStartBehavior behavior,
  ) {
    switch (behavior) {
      case FrontStartBehavior.additive:
        return frontingTerms.addAction;
      case FrontStartBehavior.replace:
        return frontingTerms.replaceCurrentAction;
    }
  }

  static void _showListViewModePicker(
    BuildContext context,
    WidgetRef ref,
    FrontingListViewMode current,
    String memberTermLower,
    FrontingTermBundle frontingTerms,
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
                    title: Text(
                      _listViewModeLabel(context.l10n, mode, memberTermLower),
                    ),
                    subtitle: Text(
                      _listViewModeDescription(frontingTerms, mode),
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
    FrontingTermBundle frontingTerms,
  ) {
    PrismDialog.show<void>(
      context: context,
      title: _addFrontBehaviorSettingLabel(frontingTerms),
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
                    title: Text(
                      _addFrontBehaviorLabel(frontingTerms, behavior),
                    ),
                    subtitle: Text(
                      _addFrontBehaviorDescription(frontingTerms, behavior),
                    ),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }

  static String _composerDefaultMemberLabel(
    FrontingTermBundle frontingTerms,
    AppLocalizations l10n,
    ComposerDefaultMember mode,
  ) {
    switch (mode) {
      case ComposerDefaultMember.latestFronter:
        return frontingTerms.latestActiveLabel;
      case ComposerDefaultMember.lastUsed:
        return l10n.settingsComposerDefaultMemberLastUsed;
      case ComposerDefaultMember.askEachTime:
        return l10n.settingsComposerDefaultMemberAskEachTime;
    }
  }

  static String _composerDefaultMemberDescription(
    FrontingTermBundle frontingTerms,
    AppLocalizations l10n,
    ComposerDefaultMember mode,
  ) {
    switch (mode) {
      case ComposerDefaultMember.latestFronter:
        return 'Open as the most recent '
            '${frontingTerms.activeSingularLabel.toLowerCase()}';
      case ComposerDefaultMember.lastUsed:
        return l10n.settingsComposerDefaultMemberLastUsedDescription;
      case ComposerDefaultMember.askEachTime:
        return l10n.settingsComposerDefaultMemberAskEachTimeDescription;
    }
  }

  static void _showComposerDefaultMemberPicker(
    BuildContext context,
    WidgetRef ref,
    ComposerDefaultMember current,
    FrontingTermBundle frontingTerms,
  ) {
    PrismDialog.show<void>(
      context: context,
      title: context.l10n.settingsComposerDefaultMemberLabel,
      builder: (ctx) {
        return RadioGroup<ComposerDefaultMember>(
          groupValue: current,
          onChanged: (value) {
            if (value == null) return;
            ref.read(composerDefaultMemberProvider.notifier).set(value);
            Navigator.of(ctx).pop();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: ComposerDefaultMember.values
                .map(
                  (mode) => RadioListTile<ComposerDefaultMember>(
                    contentPadding: EdgeInsets.zero,
                    value: mode,
                    title: Text(
                      _composerDefaultMemberLabel(
                        frontingTerms,
                        context.l10n,
                        mode,
                      ),
                    ),
                    subtitle: Text(
                      _composerDefaultMemberDescription(
                        frontingTerms,
                        context.l10n,
                        mode,
                      ),
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
    FrontingTermBundle frontingTerms,
  ) {
    PrismDialog.show<void>(
      context: context,
      title: _quickFrontBehaviorSettingLabel(frontingTerms),
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
                      _quickFrontBehaviorLabel(frontingTerms, behavior),
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
    final composerDefaultMember =
        ref.watch(composerDefaultMemberProvider).value ??
        ComposerDefaultMember.defaultValue;
    final autoPromoteLongFrontingSessions = ref.watch(
      autoPromoteLongFrontingSessionsProvider,
    );
    final terms = watchTerminology(context, ref);
    final frontingTerms = watchFrontingTerms(ref);
    final memberTermLower = terms.singularLower;
    final theme = Theme.of(context);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: frontingTerms.featureLabel,
        showBackButton: true,
      ),
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Text(
              'Configure how ${frontingTerms.sessionPlural.toLowerCase()} '
              'work.',
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
                    title: frontingTerms.quickAction,
                    subtitle:
                        'Show ${frontingTerms.quickAction.toLowerCase()} '
                        'tap-and-hold shortcuts for ${terms.pluralLower}',
                    value: showQuickFront,
                    onChanged: (value) => ref
                        .read(settingsNotifierProvider.notifier)
                        .toggleQuickFront(value),
                  ),
                  PrismSettingsRow(
                    icon: AppIcons.speed,
                    iconColor: Colors.purple,
                    title: frontingTerms.quickCorrectionLabel,
                    subtitle: _quickSwitchLabel(context, quickSwitchThreshold),
                    showChevron: true,
                    onTap: () => _showQuickSwitchPicker(
                      context,
                      ref,
                      quickSwitchThreshold,
                      frontingTerms,
                    ),
                  ),
                ],
              ),
            ),
          ),
          PrismSection(
            title:
                '${frontingTerms.sessionSingular} display & '
                '${frontingTerms.featureLower} behavior',
            child: PrismGroupedSectionCard(
              child: Column(
                children: [
                  PrismSettingsRow(
                    icon: AppIcons.viewListRounded,
                    iconColor: Colors.purple,
                    title: context.l10n.settingsFrontingListViewModeLabel,
                    subtitle: _listViewModeLabel(
                      context.l10n,
                      listViewMode,
                      memberTermLower,
                    ),
                    showChevron: true,
                    onTap: () => _showListViewModePicker(
                      context,
                      ref,
                      listViewMode,
                      memberTermLower,
                      frontingTerms,
                    ),
                  ),
                  PrismSettingsRow(
                    icon: AppIcons.addCircle,
                    iconColor: Colors.purple,
                    title: _addFrontBehaviorSettingLabel(frontingTerms),
                    subtitle: _addFrontBehaviorLabel(
                      frontingTerms,
                      addFrontBehavior,
                    ),
                    showChevron: true,
                    onTap: () => _showAddFrontBehaviorPicker(
                      context,
                      ref,
                      addFrontBehavior,
                      frontingTerms,
                    ),
                  ),
                  PrismSettingsRow(
                    icon: AppIcons.flashOn,
                    iconColor: Colors.purple,
                    title: _quickFrontBehaviorSettingLabel(frontingTerms),
                    subtitle: _quickFrontBehaviorLabel(
                      frontingTerms,
                      quickFrontBehavior,
                    ),
                    showChevron: true,
                    onTap: () => _showQuickFrontBehaviorPicker(
                      context,
                      ref,
                      quickFrontBehavior,
                      frontingTerms,
                    ),
                  ),
                  PrismSettingsRow(
                    icon: AppIcons.person,
                    iconColor: Colors.purple,
                    title: context.l10n.settingsComposerDefaultMemberLabel,
                    subtitle: _composerDefaultMemberLabel(
                      frontingTerms,
                      context.l10n,
                      composerDefaultMember,
                    ),
                    showChevron: true,
                    onTap: () => _showComposerDefaultMemberPicker(
                      context,
                      ref,
                      composerDefaultMember,
                      frontingTerms,
                    ),
                  ),
                  PrismSwitchRow(
                    icon: AppIcons.schedule,
                    iconColor: Colors.purple,
                    title:
                        'Show '
                        '${frontingTerms.longRunningHeaderLabel.toLowerCase()} '
                        'in header',
                    subtitle:
                        'After 7 days, show active '
                        '${frontingTerms.sessionPlural.toLowerCase()} in the '
                        'pinned header without marking them '
                        '${frontingTerms.alwaysActiveLabel} or hiding them '
                        'from history.',
                    value: autoPromoteLongFrontingSessions,
                    onChanged: (value) => ref
                        .read(settingsNotifierProvider.notifier)
                        .updateAutoPromoteLongFrontingSessions(value),
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

String _quickSwitchMessage(FrontingTermBundle frontingTerms) {
  return 'If you change ${frontingTerms.activePluralLabel.toLowerCase()} '
      'within this window, Prism corrects the current '
      '${frontingTerms.sessionSingular.toLowerCase()} instead of creating '
      'a new one.';
}

String _addFrontBehaviorSettingLabel(FrontingTermBundle frontingTerms) {
  return 'When adding a new ${frontingTerms.activeSingularLabel.toLowerCase()}';
}

String _quickFrontBehaviorSettingLabel(FrontingTermBundle frontingTerms) {
  return 'When using ${frontingTerms.quickAction.toLowerCase()}';
}
