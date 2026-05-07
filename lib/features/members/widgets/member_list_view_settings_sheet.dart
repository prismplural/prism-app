import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/system_settings.dart';
import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/features/settings/providers/settings_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_segmented_control.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';

class MemberListViewSettingsSheet extends ConsumerWidget {
  const MemberListViewSettingsSheet({
    super.key,
    required this.scrollController,
  });

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final viewMode = ref.watch(membersListViewModeProvider);
    final groupedDefault = ref.watch(membersGroupedDefaultStateProvider);
    final folderVisibility = ref.watch(membersFolderMemberVisibilityProvider);
    final showFrontButtons = ref.watch(membersShowFrontButtonsProvider);
    final frontButtonBehavior = ref.watch(membersFrontButtonBehaviorProvider);

    return Column(
      children: [
        PrismSheetTopBar(title: l10n.memberListViewSettingsTitle),
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            children: [
              _SettingsSection(
                title: l10n.memberListViewModeLabel,
                description: l10n.memberListViewModeDescription,
                child: PrismSegmentedControl<MembersListViewMode>(
                  selected: viewMode,
                  onChanged: (mode) {
                    ref
                        .read(settingsNotifierProvider.notifier)
                        .updateMembersListViewMode(mode);
                  },
                  segments: [
                    PrismSegment(
                      value: MembersListViewMode.groupedSections,
                      label: l10n.memberListViewModeGroupedSections,
                    ),
                    PrismSegment(
                      value: MembersListViewMode.folders,
                      label: l10n.memberListViewModeFolders,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (viewMode == MembersListViewMode.groupedSections)
                _SettingsSection(
                  title: l10n.memberGroupedDefaultStateLabel,
                  description: l10n.memberGroupedDefaultStateDescription,
                  child: PrismSegmentedControl<MembersGroupedDefaultState>(
                    selected: groupedDefault,
                    onChanged: (state) {
                      ref
                          .read(settingsNotifierProvider.notifier)
                          .updateMembersGroupedDefaultState(state);
                      final collapsed = ref.read(
                        collapsedGroupsProvider.notifier,
                      );
                      switch (state) {
                        case MembersGroupedDefaultState.open:
                          collapsed.expandAll();
                        case MembersGroupedDefaultState.closed:
                          collapsed.collapseAll();
                      }
                    },
                    segments: [
                      PrismSegment(
                        value: MembersGroupedDefaultState.open,
                        label: l10n.memberGroupedDefaultStateOpen,
                      ),
                      PrismSegment(
                        value: MembersGroupedDefaultState.closed,
                        label: l10n.memberGroupedDefaultStateClosed,
                      ),
                    ],
                  ),
                )
              else
                _SettingsSection(
                  title: l10n.memberFolderVisibilityLabel,
                  description: l10n.memberFolderVisibilityDescription,
                  child: PrismSegmentedControl<MembersFolderMemberVisibility>(
                    selected: folderVisibility,
                    onChanged: (visibility) {
                      ref
                          .read(settingsNotifierProvider.notifier)
                          .updateMembersFolderMemberVisibility(visibility);
                    },
                    segments: [
                      PrismSegment(
                        value: MembersFolderMemberVisibility.allMembers,
                        label: l10n.memberFolderVisibilityAll,
                      ),
                      PrismSegment(
                        value: MembersFolderMemberVisibility.ungroupedOnly,
                        label: l10n.memberFolderVisibilityUngrouped,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              _SettingsSection(
                title: l10n.memberFrontButtonsLabel,
                description: l10n.memberFrontButtonsDescription,
                child: Column(
                  children: [
                    PrismSwitchRow(
                      title: l10n.memberFrontButtonsToggle,
                      subtitle: l10n.memberFrontButtonsToggleDescription,
                      value: showFrontButtons,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      onChanged: (value) {
                        ref
                            .read(settingsNotifierProvider.notifier)
                            .updateMembersShowFrontButtons(value);
                      },
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: showFrontButtons
                          ? Padding(
                              key: const ValueKey('member-front-behavior'),
                              padding: const EdgeInsets.only(top: 12),
                              child: _LabeledControl(
                                label: l10n.memberFrontButtonBehaviorLabel,
                                child:
                                    PrismSegmentedControl<FrontStartBehavior>(
                                      selected: frontButtonBehavior,
                                      onChanged: (behavior) {
                                        ref
                                            .read(
                                              settingsNotifierProvider.notifier,
                                            )
                                            .updateMembersFrontButtonBehavior(
                                              behavior,
                                            );
                                      },
                                      segments: [
                                        PrismSegment(
                                          value: FrontStartBehavior.additive,
                                          label:
                                              l10n.memberFrontButtonBehaviorAdd,
                                        ),
                                        PrismSegment(
                                          value: FrontStartBehavior.replace,
                                          label: l10n
                                              .memberFrontButtonBehaviorReplace,
                                        ),
                                      ],
                                    ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LabeledControl extends StatelessWidget {
  const _LabeledControl({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.child,
    this.description,
  });

  final String title;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        child,
        if (description != null) ...[
          const SizedBox(height: 8),
          Text(
            description!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
