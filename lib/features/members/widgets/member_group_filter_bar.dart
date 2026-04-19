import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/features/members/providers/member_groups_providers.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';

class MemberGroupFilterBar extends ConsumerWidget {
  const MemberGroupFilterBar({super.key, this.onChipTap});

  /// When non-null, chips invoke this callback (passing the group ID, `null`
  /// for "All", or `'__ungrouped__'`) instead of mutating
  /// [activeGroupFilterProvider]. In this mode chips don't render a selected
  /// state — they act as scroll-to-section navigation.
  final void Function(String? groupId)? onChipTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(allGroupsProvider).value ?? [];
    final counts = ref.watch(groupMemberCountsProvider);
    final activeFilter = ref.watch(activeGroupFilterProvider);
    final ungroupedExists = ref.watch(ungroupedMembersExistProvider);
    final l10n = context.l10n;
    final scrollMode = onChipTap != null;

    // Hide bar when there are no groups at all.
    if (groups.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 48,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Semantics(
          label: l10n.memberGroupFilterBarLabel,
          child: Row(
            children: [
              // "All" chip
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: PrismChip(
                  label: l10n.memberGroupFilterAll,
                  selected: scrollMode ? false : activeFilter == null,
                  onTap: () {
                    if (scrollMode) {
                      onChipTap!(null);
                    } else {
                      ref
                          .read(activeGroupFilterProvider.notifier)
                          .setFilter(null);
                    }
                  },
                ),
              ),
              // Group chips
              ...groups.map((group) {
                final count = counts[group.id] ?? 0;
                final isSelected =
                    scrollMode ? false : activeFilter == group.id;
                final groupColor = group.colorHex != null
                    ? AppColors.fromHex(group.colorHex!)
                    : null;
                final prefix = group.emoji != null ? '${group.emoji} ' : '';
                final labelText = '$prefix${group.name} \u2022 $count';
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Semantics(
                    label: '${group.name}, $count members, '
                        '${isSelected ? 'selected' : 'not selected'}',
                    excludeSemantics: true,
                    child: PrismChip(
                      label: labelText,
                      selected: isSelected,
                      selectedColor: groupColor,
                      onTap: () {
                        if (scrollMode) {
                          onChipTap!(group.id);
                        } else {
                          ref
                              .read(activeGroupFilterProvider.notifier)
                              .setFilter(isSelected ? null : group.id);
                        }
                      },
                    ),
                  ),
                );
              }),
              // "Ungrouped" chip — only shown when at least one ungrouped active member exists
              if (ungroupedExists)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: PrismChip(
                    label: l10n.memberGroupFilterUngrouped,
                    selected: scrollMode
                        ? false
                        : activeFilter == '__ungrouped__',
                    onTap: () {
                      if (scrollMode) {
                        onChipTap!('__ungrouped__');
                      } else {
                        ref
                            .read(activeGroupFilterProvider.notifier)
                            .setFilter(activeFilter == '__ungrouped__'
                                ? null
                                : '__ungrouped__');
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
