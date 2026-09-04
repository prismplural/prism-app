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
      (15, _quickSwitchLabel(context, 15)),
      (30, _quickSwitchLabel(context, 30)),
      (60, _quickSwitchLabel(context, 60)),
    ];
    PrismDialog.show<void>(
      context: context,
      title: frontingTerms.quickCorrectionWindowTitle,
      message: context.l10n.featureFrontingQuickSwitchMessage(
        frontingTerms.activePluralLabel.toLowerCase(),
        frontingTerms.sessionSingularLower,
      ),
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
    AppLocalizations l10n,
    FrontingTermBundle frontingTerms,
    FrontingListViewMode mode,
  ) {
    switch (mode) {
      case FrontingListViewMode.combinedPeriods:
        return l10n.settingsFrontingListViewModeCombinedPeriodsDescription(
          frontingTerms.sessionPluralLower,
        );
      case FrontingListViewMode.perMemberRows:
        return l10n.settingsFrontingListViewModePerMemberRowsDescription;
      case FrontingListViewMode.timeline:
        return l10n.settingsFrontingListViewModeTimelineDescription;
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
    AppLocalizations l10n,
    FrontingTermBundle frontingTerms,
    FrontStartBehavior behavior,
  ) {
    switch (behavior) {
      case FrontStartBehavior.additive:
        return l10n.settingsAddFrontDefaultBehaviorAdditiveDescription(
          frontingTerms.sessionPluralLower,
        );
      case FrontStartBehavior.replace:
        return l10n.settingsAddFrontDefaultBehaviorReplaceDescription(
          frontingTerms.sessionPluralLower,
        );
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
                      _listViewModeDescription(
                        context.l10n,
                        frontingTerms,
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

  static void _showAddFrontBehaviorPicker(
    BuildContext context,
    WidgetRef ref,
    FrontStartBehavior current,
    FrontingTermBundle frontingTerms,
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
                    title: Text(
                      _addFrontBehaviorLabel(frontingTerms, behavior),
                    ),
                    subtitle: Text(
                      _addFrontBehaviorDescription(
                        context.l10n,
                        frontingTerms,
                        behavior,
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
        return l10n.settingsComposerDefaultMemberLatestFronterDescription;
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
    final frontingTerms = watchFrontingTerms(context, ref);
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
              context.l10n.featureFrontingDescription(
                frontingTerms.sessionPluralLower,
              ),
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
                    subtitle: context.l10n
                        .featureFrontingShowQuickFrontSubtitle(
                          frontingTerms.quickAction.toLowerCase(),
                          terms.pluralLower,
                        ),
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
            title: context.l10n.settingsFrontingSessionDisplaySectionTitle,
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
                    title: context.l10n.settingsAddFrontDefaultBehaviorLabel,
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
                    title: context.l10n.settingsQuickFrontDefaultBehaviorLabel,
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
                    title: context.l10n
                        .settingsAutoPromoteLongFrontingSessionsLabel(
                          frontingTerms.longRunningHeaderLabel,
                        ),
                    subtitle: context.l10n
                        .settingsAutoPromoteLongFrontingSessionsDescription(
                          frontingTerms.sessionPluralLower,
                          frontingTerms.alwaysActiveLabel,
                        ),
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
